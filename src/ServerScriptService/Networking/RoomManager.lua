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
    return self
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
    table.insert(self._queue, player)
    player:SetAttribute("GameState", "matching")
    print("[RoomManager] enqueued " .. player.Name .. " (queue size " .. #self._queue .. ")")
    self:_tryMatchmake()
end

function RoomManager:_tryMatchmake()
    if #self._queue >= 2 then
        local p1 = table.remove(self._queue, 1)
        local p2 = table.remove(self._queue, 1)
        self:_startRoom(p1, p2)
    end
end

function RoomManager:_startRoom(p1, p2)
    local seed = math.random(1, 1000000)
    local gs = GameState.new({ players = { tostring(p1.UserId), tostring(p2.UserId) }, seed = seed })
    local room = { players = { p1, p2 }, gameState = gs, phase = "playing" }
    table.insert(self._rooms, room)
    self._playerRoom[p1.UserId] = room
    self._playerRoom[p2.UserId] = room
    self._rematchVotes[room] = {}
    p1:SetAttribute("GameState", "in_match")
    p2:SetAttribute("GameState", "in_match")
    -- Wire subscribers (StateSync, etc.) BEFORE the countdown dispatch so the
    -- onRoundStartCountdown event reaches the clients. Also before startRound
    -- so the initial onPieceSpawned events aren't dropped.
    self:_fireRoomReady(room)
    self:_runCountdownThenStart(gs)
    print("[RoomManager] room started: " .. p1.Name .. " vs " .. p2.Name)
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

function RoomManager:registerRematchVote(player, accept)
    local room = self:roomOf(player)
    if not room or room.phase ~= "postMatch" then return end
    if accept then
        self._rematchVotes[room][player.UserId] = true
        if self._rematchVotes[room][room.players[1].UserId] and self._rematchVotes[room][room.players[2].UserId] then
            -- Both accepted — start new match
            print("[RoomManager] rematch accepted — restarting room")
            local seed = math.random(1, 1000000)
            room.gameState = GameState.new({
                players = { tostring(room.players[1].UserId), tostring(room.players[2].UserId) },
                seed = seed,
            })
            room.phase = "playing"
            self._rematchVotes[room] = {}
            for _, p in room.players do
                if p and p.Parent then p:SetAttribute("GameState", "in_match") end
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
        if p.Parent then
            -- Surface "lobby" first so Producer's UIStateController can show the
            -- lobby panel; the immediate re-queue below transitions us to
            -- "matching" on the next tick.
            p:SetAttribute("GameState", "lobby")
            table.insert(self._queue, p)
            p:SetAttribute("GameState", "matching")
        end
    end
    self._rematchVotes[room] = nil
    for i, r in self._rooms do
        if r == room then table.remove(self._rooms, i); break end
    end
    print("[RoomManager] room closed, players re-queued where possible")
    self:_tryMatchmake()
end

function RoomManager:onMatchEnd(room)
    -- Called by StateSync subscriber when GameState fires onMatchEnd
    room.phase = "postMatch"
    for _, p in room.players do
        if p and p.Parent then p:SetAttribute("GameState", "match_end") end
    end
    -- 15s rematch window started by client; server cleans up after timeout
    task.delay(Constants.REMATCH_WINDOW, function()
        if room.phase == "postMatch" then
            print("[RoomManager] rematch window expired — closing room")
            self:_closeRoom(room)
        end
    end)
end

return RoomManager
