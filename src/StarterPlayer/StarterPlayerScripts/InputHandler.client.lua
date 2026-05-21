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

-- Disable the default Roblox PlayerControls while in_match so WASD only routes
-- to the falling-block game (and doesn't walk the avatar in the background or
-- play footstep sounds). Re-enable on lobby/match_end so the player can move
-- around between matches if they want.
local player = Players.LocalPlayer
local controlsAvailable, Controls = pcall(function()
    local PlayerScripts = player:WaitForChild("PlayerScripts", 10)
    local PlayerModule = require(PlayerScripts:WaitForChild("PlayerModule", 10))
    return PlayerModule:GetControls()
end)

local function syncControlsForState()
    if not controlsAvailable or not Controls then return end
    local state = player:GetAttribute("GameState")
    if state == "in_match" then
        Controls:Disable()
    else
        Controls:Enable()
    end
end

player:GetAttributeChangedSignal("GameState"):Connect(syncControlsForState)
syncControlsForState()

print("InputHandler (keyboard) ready")
