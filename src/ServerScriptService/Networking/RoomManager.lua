-- src/ServerScriptService/Networking/RoomManager.lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local GameState = require(ReplicatedStorage.Shared.Logic.GameState)
local Constants = require(ReplicatedStorage.Shared.Logic.Constants)
local Events = require(ReplicatedStorage.Shared.Events)

local RoomManager = {}
RoomManager.__index = RoomManager

function RoomManager.new()
    local self = setmetatable({}, RoomManager)
    self._queue = {}      -- list of Player Instances waiting
    self._rooms = {}      -- list of { players = {p1, p2}, gameState = GameState, phase = "playing" | "postMatch" }
    self._playerRoom = {} -- playerId → room
    self._rematchVotes = {} -- room → { [playerId] = boolean }
    self._roomReadyListeners = {} -- fired with (room) AFTER GameState exists but BEFORE startRound
    self._softDropping = {} -- [userId] = true while the Down/S key is held; driven by softDropRemote
    self._paused = {} -- [userId] = true while the PauseConfirm modal is open; practice-only
    return self
end

-- Set the practice-mode pause latch for a player. Only honored when the player
-- is in a practice room — versus pause is a competitive grief vector (free
-- thinking time mid-match), so silently no-op there. The gravity tick + soft
-- drop loop + AFK timer in Main.server.lua all consult this latch via :isPaused.
function RoomManager:setPaused(player, paused)
    local room = self:roomOf(player)
    if not room or room.mode ~= "practice" then return end
    self._paused[player.UserId] = paused and true or nil
end

function RoomManager:isPaused(userId)
    return self._paused[userId] == true
end

function RoomManager:setSoftDrop(player, held)
    -- Server-side latch for "is this player currently holding soft drop?". The
    -- fast-tick loop in Main.server.lua reads this every GRAVITY_BASE/SOFT_DROP_MULT
    -- seconds and injects an extra tick if true, producing sustained 8x gravity
    -- instead of the previous "one row per keypress" behaviour.
    self._softDropping[player.UserId] = held and true or nil
end

function RoomManager:isSoftDropping(userId)
    return self._softDropping[userId] == true
end

function RoomManager:onRoomReady(fn)
    table.insert(self._roomReadyListeners, fn)
end

function RoomManager:_fireRoomReady(room)
    for _, fn in self._roomReadyListeners do
        fn(room)
    end
end

function RoomManager:enqueuePlayer(player)
    -- Idempotent: a double-fired EnterQueue (rapid PLAY taps, cancel→play
    -- without a server-side LeaveQueue, etc.) must not insert the same player
    -- twice — otherwise _tryMatchmake will pair the player against themself
    -- and produce a ghost-opponent room.
    for _, queued in self._queue do
        if queued == player then return end
    end
    table.insert(self._queue, player)
    player:SetAttribute("GameState", "matching")
    print("[RoomManager] enqueued " .. player.Name .. " (queue size " .. #self._queue .. ")")
    self:_tryMatchmake()
end

-- Practice mode entry: bypass the queue and spin up a 1-player room directly.
-- Idempotent against an already-in-room player so a double-fire of EnterQueue
-- {mode = "practice"} can't stack rooms (mirrors enqueuePlayer's guard).
function RoomManager:enterPractice(player)
    if self._playerRoom[player.UserId] then return end
    print("[RoomManager] " .. player.Name .. " entering practice (solo)")
    self:_startSoloRoom(player)
end

function RoomManager:leaveQueue(player)
    for i, queued in self._queue do
        if queued == player then
            table.remove(self._queue, i)
            print("[RoomManager] " .. player.Name .. " left queue (size " .. #self._queue .. ")")
            break
        end
    end
    if player.Parent then
        player:SetAttribute("GameState", "main_menu")
    end
end

function RoomManager:_tryMatchmake()
    -- Loop so that re-queuing a survivor after a partner-disconnect doesn't
    -- block a fresh pairing if there are 2+ still waiting.
    while #self._queue >= 2 do
        local p1 = table.remove(self._queue, 1)
        local p2 = table.remove(self._queue, 1)
        -- Race window: between enqueuePlayer and this firing, either player
        -- may have left the server. PlayerRemoving doesn't currently scrub
        -- the queue, so we get a Player Instance with no Parent. Skip pairing;
        -- re-queue the survivor at the front so they don't lose their slot.
        local p1Alive = p1.Parent ~= nil
        local p2Alive = p2.Parent ~= nil
        if p1Alive and p2Alive then
            self:_startRoom(p1, p2)
        elseif p1Alive then
            table.insert(self._queue, 1, p1)
            return
        elseif p2Alive then
            table.insert(self._queue, 1, p2)
            return
        end
        -- both gone → drop both, continue trying with the rest
    end
end

function RoomManager:_startRoom(p1, p2)
    local seed = math.random(1, 1000000)
    local gs = GameState.new({ players = { tostring(p1.UserId), tostring(p2.UserId) }, seed = seed })
    local room = { players = { p1, p2 }, gameState = gs, phase = "playing", mode = "versus" }
    table.insert(self._rooms, room)
    self._playerRoom[p1.UserId] = room
    self._playerRoom[p2.UserId] = room
    self._rematchVotes[room] = {}
    p1:SetAttribute("GameState", "in_match")
    p2:SetAttribute("GameState", "in_match")
    -- MatchMode tells client-side HUDs (UIStateController, OpponentBoard, MatchEnd)
    -- which variant to render. Cleared in _closeRoom.
    p1:SetAttribute("MatchMode", "versus")
    p2:SetAttribute("MatchMode", "versus")
    -- Wire subscribers (StateSync, etc.) BEFORE the countdown dispatch so the
    -- onRoundStartCountdown event reaches the clients. Also before startRound
    -- so the initial onPieceSpawned events aren't dropped.
    self:_fireRoomReady(room)
    self:_runCountdownThenStart(gs)
    print("[RoomManager] room started: " .. p1.Name .. " vs " .. p2.Name)
end

function RoomManager:_startSoloRoom(player)
    local seed = math.random(1, 1000000)
    local gs = GameState.new({ players = { tostring(player.UserId) }, seed = seed })
    local room = { players = { player }, gameState = gs, phase = "playing", mode = "practice" }
    table.insert(self._rooms, room)
    self._playerRoom[player.UserId] = room
    self._rematchVotes[room] = {}
    player:SetAttribute("GameState", "in_match")
    player:SetAttribute("MatchMode", "practice")
    -- Same ordering as versus: wire subscribers first so the countdown +
    -- initial piece spawn events reach the client.
    self:_fireRoomReady(room)
    self:_runCountdownThenStart(gs)
    print("[RoomManager] solo room started: " .. player.Name)
end

function RoomManager:_runCountdownThenStart(gs)
    -- Broadcast the countdown end timestamp, wait the configured duration,
    -- then spawn pieces. Both clients animate 3-2-1-GO against the timestamp.
    -- Input + gravity stay inert during the wait because no active piece exists.
    local startsAt = Workspace:GetServerTimeNow() + Constants.ROUND_START_COUNTDOWN
    gs:announceRoundStartCountdown(startsAt)
    task.wait(Constants.ROUND_START_COUNTDOWN)
    gs:startRound()
end

function RoomManager:roomOf(player)
    return self._playerRoom[player.UserId]
end

function RoomManager:applyInput(player, input)
    -- Generic input application. The actual input-to-piece-state translation
    -- happens inside the GameState's per-player Board, driven server-side.
    -- For Day 3 MVP, input fires a corresponding GameState method; details
    -- depend on whether the round is "playing" — drop inputs otherwise.
    local room = self:roomOf(player)
    if not room or room.phase ~= "playing" then return end
    -- The GameState exposes input hooks; we forward.
    if room.gameState.applyInput then
        room.gameState:applyInput(tostring(player.UserId), input)
    end
end

-- Mid-rematch-disconnect routing entry point. Called by DisconnectHandler.
function RoomManager:treatAsLeave(player)
    local room = self:roomOf(player)
    if not room or room.phase ~= "postMatch" then return false end
    -- Treat as Leave: end rematch flow, return both players to lobby
    print("[RoomManager] " .. player.Name .. " treated as Leave during rematch window")
    self:_closeRoom(room)
    return true
end

-- Single entry point for "the player tapped a LEAVE button." Handles both
-- the in-match Pause→Leave flow (forfeit the round, then close) and the
-- match-end Leave-instead-of-Rematch flow (decline the rematch, close).
-- Previously the LeaveMatch remote was wired directly to registerRematchVote
-- with accept=false, which silently early-returned during the playing phase
-- — so the in-match LEAVE button did nothing server-side. This unifies it.
function RoomManager:requestLeave(player)
    local room = self:roomOf(player)
    if not room then return end
    if room.phase == "playing" then
        -- Mid-match leave is a forfeit. Cascading through forfeitRound makes
        -- the opponent's MatchEnd panel show "opponent left" via reason; the
        -- _closeRoom call wipes the leaving player back to main_menu after
        -- the cascade so they don't get stuck on their own MatchEnd panel.
        --
        -- Practice mode has no opponent to forfeit to, and forfeitRound would
        -- assert on _otherPlayer. Skip straight to _closeRoom — the player
        -- explicitly chose to quit, so no match-end panel is needed.
        if room.mode ~= "practice" and room.gameState and room.gameState:phase() == "playing" then
            room.gameState:forfeitRound(tostring(player.UserId), "leave")
        end
        self:_closeRoom(room)
    elseif room.phase == "postMatch" then
        self:registerRematchVote(player, false)
    end
end

function RoomManager:registerRematchVote(player, accept)
    local room = self:roomOf(player)
    if not room or room.phase ~= "postMatch" then return end
    if accept then
        self._rematchVotes[room][player.UserId] = true
        -- Practice mode: only one player exists. A single accept-vote restarts
        -- the room immediately — no second-vote wait. Mirrors versus rematch
        -- otherwise (new seed, new GameState, re-wire, countdown + startRound).
        local soloRestart = (room.mode == "practice")
        local versusBothAccepted = (room.mode ~= "practice")
            and self._rematchVotes[room][room.players[1].UserId]
            and self._rematchVotes[room][room.players[2].UserId]
        if soloRestart or versusBothAccepted then
            print("[RoomManager] rematch accepted — restarting room (" .. room.mode .. ")")
            local seed = math.random(1, 1000000)
            local playerIds = {}
            for _, p in room.players do
                table.insert(playerIds, tostring(p.UserId))
            end
            room.gameState = GameState.new({ players = playerIds, seed = seed })
            room.phase = "playing"
            self._rematchVotes[room] = {}
            for _, p in room.players do
                if p and p.Parent then
                    p:SetAttribute("GameState", "in_match")
                    -- MatchMode is sticky across rematches: a practice rematch
                    -- stays practice, versus stays versus.
                    p:SetAttribute("MatchMode", room.mode)
                end
            end
            -- Re-wire the new GameState's subscribers before the countdown.
            self:_fireRoomReady(room)
            self:_runCountdownThenStart(room.gameState)
        end
    else
        -- Leave
        self:_closeRoom(room)
    end
end

function RoomManager:_closeRoom(room)
    for _, p in room.players do
        self._playerRoom[p.UserId] = nil
        self._softDropping[p.UserId] = nil
        self._paused[p.UserId] = nil
        if p.Parent then
            -- Match end / Leave returns the player to the main menu. No auto
            -- re-enqueue — re-entering the queue requires a fresh PLAY click
            -- (server-side: EnterQueue RemoteEvent).
            p:SetAttribute("GameState", "main_menu")
            -- Clear MatchMode so the next match's attribute write is observed
            -- as a fresh value by GetAttributeChangedSignal listeners.
            p:SetAttribute("MatchMode", nil)
        end
    end
    self._rematchVotes[room] = nil
    for i, r in self._rooms do
        if r == room then table.remove(self._rooms, i); break end
    end
    print("[RoomManager] room closed, players returned to main menu")
end

function RoomManager:onMatchEnd(room)
    -- Called by StateSync subscriber when GameState fires onMatchEnd
    room.phase = "postMatch"
    for _, p in room.players do
        if p and p.Parent then p:SetAttribute("GameState", "match_end") end
    end
    -- Match-end panel stays open indefinitely; room closes only on deliberate
    -- Leave / Rematch click or on player disconnect (handled by DisconnectHandler).
    -- (Previous behaviour auto-closed after REMATCH_WINDOW seconds.)
end

return RoomManager
