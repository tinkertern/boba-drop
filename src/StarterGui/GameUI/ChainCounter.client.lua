local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UIConstants = require(ReplicatedStorage.Shared.UI.UIConstants)
local Events = require(ReplicatedStorage.Shared.Events)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ChainCounter"
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = UIConstants.ZOrder.ChainCounter
screenGui.Parent = playerGui

local label = Instance.new("TextLabel")
label.Name = "ChainLabel"
label.Size = UDim2.fromOffset(300, 80)
label.AnchorPoint = Vector2.new(0.5, 0.5)
label.Position = UDim2.fromScale(0.5, 0.35)
label.BackgroundTransparency = 1
label.Font = UIConstants.Fonts.HUD
label.TextSize = 48
label.TextColor3 = UIConstants.Colors.ChainCounterText
label.TextStrokeTransparency = 0.4
label.Text = ""
label.Visible = false
label.Parent = screenGui

-- ChainCompleted RemoteEvent is created in Day 3 networking work.
-- WaitForChild blocks safely until then.
local chainRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild(Events.Names.ChainCompleted)

local hideTask = nil
chainRemote.OnClientEvent:Connect(function(payload)
    if not payload.isLocal then return end
    label.Text = "Chain x" .. payload.chainLength .. "!"
    label.Visible = true
    if hideTask then task.cancel(hideTask) end
    hideTask = task.delay(UIConstants.Durations.ChainCounterPersist, function()
        label.Visible = false
        hideTask = nil
    end)
end)
