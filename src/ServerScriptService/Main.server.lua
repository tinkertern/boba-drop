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
    roomManager:enqueuePlayer(player)
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
            roomManager:applyInput(player, { type = "softDrop", held = payload.held == true })
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
else
    warn("[Main.server] Remotes folder missing — input routing disabled")
end

-- ----- Gravity tick driver (Day 4) -----
-- Drives a per-room, per-player tick that nudges each active piece down by one
-- row at GRAVITY_BASE seconds. Pieces lock when they can't fall further.
task.spawn(function()
    while true do
        task.wait(Constants.GRAVITY_BASE)
        for _, room in roomManager._rooms do
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

print("[Main.server] Boba Drop server ready")
