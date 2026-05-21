-- src/StarterPlayer/StarterPlayerScripts/InputHandler.client.lua
-- Tetris-style keyboard bindings: arrows + WASD for movement, Up/W rotate one
-- direction only, Down/S soft drop, Space hard drop. Z and X removed at Sarah's
-- request 2026-05-20.
-- Also disables Roblox's default PlayerControls while in_match so WASD doesn't
-- also walk the player's avatar around (and trigger footstep sounds) in the
-- background.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Events = require(ReplicatedStorage.Shared.Events)

local Remotes = ReplicatedStorage:WaitForChild("Remotes", 30)
if not Remotes then
    warn("InputHandler: Remotes folder absent (expected pre-Day-3); idle")
    return
end

local moveRemote = Remotes:WaitForChild(Events.Names.InputMove, 30)
local rotateRemote = Remotes:WaitForChild(Events.Names.InputRotate, 30)
local softDropRemote = Remotes:WaitForChild(Events.Names.InputSoftDrop, 30)
local hardDropRemote = Remotes:WaitForChild(Events.Names.InputHardDrop, 30)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == Enum.KeyCode.Left or input.KeyCode == Enum.KeyCode.A then
        moveRemote:FireServer({ direction = "left" })
    elseif input.KeyCode == Enum.KeyCode.Right or input.KeyCode == Enum.KeyCode.D then
        moveRemote:FireServer({ direction = "right" })
    elseif input.KeyCode == Enum.KeyCode.Up or input.KeyCode == Enum.KeyCode.W then
        -- Single rotation direction (clockwise), Tetris convention.
        rotateRemote:FireServer({ direction = "cw" })
    elseif input.KeyCode == Enum.KeyCode.Down or input.KeyCode == Enum.KeyCode.S then
        softDropRemote:FireServer({ held = true })
    elseif input.KeyCode == Enum.KeyCode.Space then
        hardDropRemote:FireServer({})
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.KeyCode == Enum.KeyCode.Down or input.KeyCode == Enum.KeyCode.S then
        softDropRemote:FireServer({ held = false })
    end
end)

-- Disable Roblox's default PlayerControls permanently. Boba Drop is a 2D UI
-- experience; the avatar exists in Workspace but is never visible or relevant.
-- Disabling controls prevents WASD from walking the avatar in the background
-- and silences the footstep audio. Wrapped in a pcall in case PlayerModule
-- isn't available in some run configurations.
--
-- Deferred until CharacterAdded so PlayerControls:Disable doesn't internally
-- call Player:Move with no character, which logs "Player:Move called, but
-- player currently has no character" on Studio start.
local player = Players.LocalPlayer

local function disablePlayerControls()
    pcall(function()
        local PlayerScripts = player:WaitForChild("PlayerScripts", 10)
        local PlayerModule = require(PlayerScripts:WaitForChild("PlayerModule", 10))
        PlayerModule:GetControls():Disable()
    end)
end

if player.Character then
    disablePlayerControls()
else
    player.CharacterAdded:Connect(disablePlayerControls)
end

print("InputHandler (keyboard) ready")
