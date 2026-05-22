-- src/ServerScriptService/Main.server.lua
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local RoomManager = require(ServerScriptService.Networking.RoomManager)
local DisconnectHandler = require(ServerScriptService.Networking.DisconnectHandler)
local StateSync = require(ServerScriptService.Networking.StateSync)
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

Players.PlayerRemoving:Connect(function(player)
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

    if moveRemote then
        moveRemote.OnServerEvent:Connect(function(player, payload)
            payload = payload or {}
            if payload.direction ~= "left" and payload.direction ~= "right" then return end
            roomManager:applyInput(player, { type = "move", direction = payload.direction })
        end)
    end
    if rotateRemote then
        rotateRemote.OnServerEvent:Connect(function(player, payload)
            payload = payload or {}
            if payload.direction ~= "cw" and payload.direction ~= "ccw" then return end
            roomManager:applyInput(player, { type = "rotate", direction = payload.direction })
        end)
    end
    if softDropRemote then
        softDropRemote.OnServerEvent:Connect(function(player, payload)
            payload = payload or {}
            roomManager:setSoftDrop(player, payload.held == true)
        end)
    end
    if hardDropRemote then
        hardDropRemote.OnServerEvent:Connect(function(player, payload)
            roomManager:applyInput(player, { type = "hardDrop" })
        end)
    end
    if rematchRemote then
        rematchRemote.OnServerEvent:Connect(function(player, payload)
            roomManager:registerRematchVote(player, true)
        end)
    end
    if leaveRemote then
        leaveRemote.OnServerEvent:Connect(function(player, payload)
            roomManager:registerRematchVote(player, false)
        end)
    end
    if enterQueueRemote then
        enterQueueRemote.OnServerEvent:Connect(function(player)
            if roomManager:roomOf(player) then return end
            roomManager:enqueuePlayer(player)
        end)
    end
    if leaveQueueRemote then
        leaveQueueRemote.OnServerEvent:Connect(function(player)
            roomManager:leaveQueue(player)
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
                    if player and player.Parent then
                        room.gameState:applyInput(tostring(player.UserId), { type = "tick" })
                    end
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
            if held then
                local room = roomManager._playerRoom[userId]
                if room and room.phase == "playing" and room.gameState and room.gameState:phase() == "playing" then
                    room.gameState:applyInput(tostring(userId), { type = "tick" })
                end
            end
        end
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
            gs:forfeitRound(event.playerId, "afk")
        end)
    end)
    gs:subscribe("onPieceLocked", function(event)
        local player = findPlayerByUserId(event.playerId)
        if not player then return end
        disconnectHandler:clearAfkTimer(player)
    end)
end)

print("[Main.server] Boba Drop server ready")
