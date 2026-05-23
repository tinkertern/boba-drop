-- src/ServerScriptService/Main.server.lua
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local RoomManager = require(ServerScriptService.Networking.RoomManager)
local DisconnectHandler = require(ServerScriptService.Networking.DisconnectHandler)
local StateSync = require(ServerScriptService.Networking.StateSync)
local AiOpponent = require(ServerScriptService.Networking.AiOpponent)
local GamePasses = require(ServerScriptService.Monetization.GamePasses)
local Constants = require(ReplicatedStorage.Shared.Logic.Constants)

print("[Main.server] Boba Drop server starting...")

local roomManager = RoomManager.new()
local disconnectHandler = DisconnectHandler.new(roomManager)
local stateSync = StateSync.new(roomManager)
local gamePasses = GamePasses.new()

Players.PlayerAdded:Connect(function(player)
    player:SetAttribute("GameState", "main_menu")
end)

-- ----- Per-player per-remote rate limiter -----
-- Token-bucket guard on every input/lifecycle remote. Legitimate keyboard auto-
-- repeat is ~30Hz; rates below are sized to comfortably pass real play and reject
-- only obvious spam. Rejection is silent — the gameplay layer never sees the
-- excess inputs, so a misbehaving client just sees their inputs ignored.
--
-- Tokens refill continuously at `perSecond`. Bucket caps at `burst` so a key
-- that's been idle doesn't accumulate infinite credit. State is keyed by UserId
-- and cleared on PlayerRemoving.
local rateBuckets = {} -- [userId] = { [eventName] = { tokens, lastRefill } }

local function checkRate(player, eventName, perSecond, burst)
    local userId = player.UserId
    local userBuckets = rateBuckets[userId]
    if not userBuckets then
        userBuckets = {}
        rateBuckets[userId] = userBuckets
    end
    local now = os.clock()
    local bucket = userBuckets[eventName]
    if not bucket then
        userBuckets[eventName] = { tokens = burst - 1, lastRefill = now }
        return true
    end
    bucket.tokens = math.min(burst, bucket.tokens + (now - bucket.lastRefill) * perSecond)
    bucket.lastRefill = now
    if bucket.tokens >= 1 then
        bucket.tokens -= 1
        return true
    end
    return false
end

Players.PlayerRemoving:Connect(function(player)
    rateBuckets[player.UserId] = nil
    disconnectHandler:onPlayerLeaving(player)
end)

-- ----- Input routing (Day 4) -----
local Remotes = ReplicatedStorage:WaitForChild("Remotes", 30)
if Remotes then
    local moveRemote = Remotes:WaitForChild("InputMove", 30)
    local rotateRemote = Remotes:WaitForChild("InputRotate", 30)
    local softDropRemote = Remotes:WaitForChild("InputSoftDrop", 30)
    local hardDropRemote = Remotes:WaitForChild("InputHardDrop", 30)
    local rematchRemote = Remotes:WaitForChild("RematchRequest", 30)
    local leaveRemote = Remotes:WaitForChild("LeaveMatch", 30)
    local enterQueueRemote = Remotes:WaitForChild("EnterQueue", 30)
    local leaveQueueRemote = Remotes:WaitForChild("LeaveQueue", 30)
    local pauseRemote = Remotes:WaitForChild("PauseRequest", 30)

    if moveRemote then
        moveRemote.OnServerEvent:Connect(function(player, payload)
            if not checkRate(player, "move", 25, 8) then return end
            payload = payload or {}
            if payload.direction ~= "left" and payload.direction ~= "right" then return end
            roomManager:applyInput(player, { type = "move", direction = payload.direction })
        end)
    end
    if rotateRemote then
        rotateRemote.OnServerEvent:Connect(function(player, payload)
            if not checkRate(player, "rotate", 25, 5) then return end
            payload = payload or {}
            if payload.direction ~= "cw" and payload.direction ~= "ccw" then return end
            roomManager:applyInput(player, { type = "rotate", direction = payload.direction })
        end)
    end
    if softDropRemote then
        softDropRemote.OnServerEvent:Connect(function(player, payload)
            -- Toggles only, not per-row drop — generous limit covers rapid taps.
            if not checkRate(player, "softDrop", 15, 5) then return end
            payload = payload or {}
            roomManager:setSoftDrop(player, payload.held == true)
        end)
    end
    if hardDropRemote then
        hardDropRemote.OnServerEvent:Connect(function(player, payload)
            if not checkRate(player, "hardDrop", 10, 3) then return end
            roomManager:applyInput(player, { type = "hardDrop" })
        end)
    end
    if rematchRemote then
        rematchRemote.OnServerEvent:Connect(function(player, payload)
            if not checkRate(player, "rematch", 2, 3) then return end
            roomManager:registerRematchVote(player, true)
        end)
    end
    if leaveRemote then
        leaveRemote.OnServerEvent:Connect(function(player, payload)
            if not checkRate(player, "leaveMatch", 2, 3) then return end
            -- Both in-match (PauseConfirm) and match-end (Leave-instead-of-
            -- Rematch) fire this remote. RoomManager:requestLeave routes by
            -- room.phase so each path does the right thing.
            roomManager:requestLeave(player)
        end)
    end
    if enterQueueRemote then
        enterQueueRemote.OnServerEvent:Connect(function(player, payload)
            if not checkRate(player, "enterQueue", 3, 5) then return end
            if roomManager:roomOf(player) then return end
            -- Payload defaults to versus for back-compat with old clients that
            -- fire `:FireServer()` with no args. Any unrecognized value also
            -- falls through to versus (server doesn't trust client strings).
            payload = (type(payload) == "table") and payload or {}
            if payload.mode == "practice" then
                roomManager:enterPractice(player)
            elseif payload.mode == "ai" then
                -- Difficulty defaults to easy on unknown / falsy. RoomManager
                -- re-validates so a malicious client can't smuggle a tier we
                -- haven't tuned yet.
                roomManager:enterAi(player, payload.difficulty)
            else
                roomManager:enqueuePlayer(player)
            end
        end)
    end
    if leaveQueueRemote then
        leaveQueueRemote.OnServerEvent:Connect(function(player)
            if not checkRate(player, "leaveQueue", 3, 5) then return end
            roomManager:leaveQueue(player)
        end)
    end
    if pauseRemote then
        pauseRemote.OnServerEvent:Connect(function(player, payload)
            -- Practice-only pause. RoomManager:setPaused gates on room.mode so
            -- versus requests silently no-op; that's our anti-grief guarantee
            -- (no free thinking time in 1v1). On pause=true we also cancel any
            -- pending AFK timer for the player — they're explicitly engaged with
            -- the UI, not idle. No re-arm on unpause; next piece spawn will
            -- start a fresh timer through the existing onPieceSpawned hook.
            if not checkRate(player, "pause", 5, 5) then return end
            payload = (type(payload) == "table") and payload or {}
            local paused = payload.paused == true
            roomManager:setPaused(player, paused)
            if paused and roomManager:isPaused(player.UserId) then
                disconnectHandler:clearAfkTimer(player)
            end
        end)
    end
else
    warn("[Main.server] Remotes folder missing — input routing disabled")
end

-- ----- Gravity tick driver (Day 4) -----
-- Drives a per-room, per-player tick that nudges each active piece down by one
-- row at GRAVITY_BASE seconds. Pieces lock when they can't fall further.
--
-- Snapshot _rooms each tick: _closeRoom (triggered by Leave, disconnect, or
-- match-end → Leave) does table.remove on _rooms, which mid-iteration would
-- cause the next room to be skipped. Today none of the close paths fire
-- mid-tick (no yields inside this loop body), but the foot-gun is real if
-- any future subscriber yields. table.clone is cheap; defense-in-depth.
task.spawn(function()
    while true do
        task.wait(Constants.GRAVITY_BASE)
        for _, room in table.clone(roomManager._rooms) do
            if room.phase == "playing" and room.gameState and room.gameState:phase() == "playing" then
                for _, player in room.players do
                    -- Skip paused players (practice-only; setPaused gates on
                    -- mode == "practice", so a versus player's :isPaused is
                    -- always false even if a malicious client fires the remote).
                    if player and player.Parent and not roomManager:isPaused(player.UserId) then
                        room.gameState:applyInput(tostring(player.UserId), { type = "tick" })
                    end
                end
                -- AI bot has no Player Instance, so it's not in room.players.
                -- Tick its piece in lockstep with the real player so gravity
                -- still pulls it down — without this, the bot's piece would
                -- only descend when the AI decision loop issued a hardDrop,
                -- breaking the "piece never reaches lock" failsafe.
                if room.aiBot then
                    room.gameState:applyInput(room.aiBot.userId, { type = "tick" })
                end
            end
        end
    end
end)

-- ----- Soft drop driver -----
-- While a player holds Down/S, the client fires softDropRemote with held=true,
-- which sets the server-side _softDropping latch. This loop reads that latch at
-- GRAVITY_BASE/SOFT_DROP_MULT cadence and injects an extra tick into the player's
-- GameState — producing sustained ~8x gravity for as long as the key is held.
-- InputEnded fires held=false → latch clears → loop stops injecting.
task.spawn(function()
    local interval = Constants.GRAVITY_BASE / Constants.SOFT_DROP_MULT
    while true do
        task.wait(interval)
        for userId, held in table.clone(roomManager._softDropping) do
            if held and not roomManager:isPaused(userId) then
                local room = roomManager._playerRoom[userId]
                if room and room.phase == "playing" and room.gameState and room.gameState:phase() == "playing" then
                    room.gameState:applyInput(tostring(userId), { type = "tick" })
                end
            end
        end
    end
end)

-- ----- Queue timeout sweeper -----
-- A player solo-queueing for versus shouldn't sit in matchmaking forever when
-- no second player joins (the v1 ship will have a small concurrent userbase,
-- so this WILL happen). Every 5s, scan the queue for players older than
-- QUEUE_TIMEOUT_SEC and flip them back to main_menu. Roblox's UI bindings on
-- the GameState attribute will return them to the menu automatically; a
-- proper toast remote can ship in v1.1 (Producer's lane).
local QUEUE_TIMEOUT_SEC = 60
task.spawn(function()
    while true do
        task.wait(5)
        roomManager:scanQueueTimeouts(QUEUE_TIMEOUT_SEC)
    end
end)

-- ----- AFK piece timer -----
-- Per-piece grief / inattention guard. When a piece spawns for a player, start
-- an AFK_PIECE_TIMEOUT countdown; clearing on lock. If it fires, forfeit the
-- round for that player with reason "afk". Without this, a player who walks
-- away mid-piece stalls the opponent indefinitely (gravity does still tick
-- their piece in theory, but they can hard-stall by never letting the piece
-- reach a locked state if no gravity is configured).
--
-- Subscribed via onRoomReady so the wiring lands BEFORE the first piece spawn,
-- same pattern StateSync uses.
local function findPlayerByUserId(userIdStr)
    for _, p in Players:GetPlayers() do
        if tostring(p.UserId) == userIdStr then return p end
    end
    return nil
end

roomManager:onRoomReady(function(room)
    local gs = room.gameState
    gs:subscribe("onPieceSpawned", function(event)
        local player = findPlayerByUserId(event.playerId)
        if not player then return end
        disconnectHandler:startAfkTimer(player, function()
            -- Re-check phase: a piece could have locked / round could have ended
            -- between the timeout firing and this callback running.
            if room.gameState ~= gs then return end
            if gs:phase() ~= "playing" then return end
            if gs:isSolo() then
                -- Practice AFK: end the run with the same dispatch shape as a
                -- topout. No opponent exists to forfeit to.
                gs:_endPracticeOnTopout(event.playerId)
            else
                gs:forfeitRound(event.playerId, "afk")
            end
        end)
    end)
    gs:subscribe("onPieceLocked", function(event)
        local player = findPlayerByUserId(event.playerId)
        if not player then return end
        disconnectHandler:clearAfkTimer(player)
    end)
end)

-- ----- AI decision loop -----
-- Server-authoritative bot inputs. Subscribes to onPieceSpawned on every AI
-- room's GameState and, when the spawn is for the bot, hands off to AiOpponent
-- for per-difficulty policy + input dispatch. Spawn-driven (not timer-driven)
-- so it naturally handles every piece: initial round spawn, post-lock spawns,
-- post-chain spawns, and post-garbage spawns all trigger the same path.
--
-- Tier behaviour lives in AiOpponent — see src/ServerScriptService/Networking/
-- AiOpponent.lua. This subscriber is intentionally a 4-liner so adding new
-- tiers doesn't require touching Main.server.
roomManager:onRoomReady(function(room)
    if not room.aiBot then return end
    local gs = room.gameState
    local botId = room.aiBot.userId
    gs:subscribe("onPieceSpawned", function(event)
        if event.playerId ~= botId then return end
        -- Run the decision sequence in a spawned task so subscribers aren't
        -- blocked by AiOpponent.decide's task.wait calls.
        task.spawn(function()
            AiOpponent.decide(gs, room, event)
        end)
    end)
end)

-- ----- Graceful shutdown -----
-- Roblox calls BindToClose when the server is being torn down (deploy push,
-- idle reap, soft shutdown). It blocks termination for up to 30s, giving
-- pending FireClient packets time to flush — chains, garbage, etc. fired in
-- the last frame would otherwise be dropped mid-flight. We don't fire MatchEnd
-- here: the client's MatchEnd panel infers winner/loser from scores and would
-- show a confusing "YOU WIN" / "YOU LOSE" right before the server vanished.
-- Standard Roblox "server shutting down" overlay is the better UX. v1.1 can
-- add a custom toast remote if Producer wants something fancier.
--
-- Studio playtests don't trigger BindToClose, so this is live-only behaviour.
game:BindToClose(function()
    local roomCount = #roomManager._rooms
    if roomCount == 0 then return end
    warn("[Main.server] Shutdown: " .. roomCount .. " active room(s); waiting 3s for replication flush")
    task.wait(3)
end)

print("[Main.server] Boba Drop server ready")
