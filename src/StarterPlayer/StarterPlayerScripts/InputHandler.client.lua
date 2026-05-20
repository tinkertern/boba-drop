-- src/StarterPlayer/StarterPlayerScripts/InputHandler.client.lua
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
    elseif input.KeyCode == Enum.KeyCode.Z then
        rotateRemote:FireServer({ direction = "ccw" })
    elseif input.KeyCode == Enum.KeyCode.X then
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

print("InputHandler (keyboard) ready")
