-- Chain counter HUD. Celebratory bounce-in with peach→coral gradient.
-- Listens for ChainCompleted RemoteEvent (created Day 3); WaitForChild
-- with a 30s timeout to avoid the infinite-yield warning pre-Day-3.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local UIConstants = require(ReplicatedStorage.Shared.UI.UIConstants)
local Events = require(ReplicatedStorage.Shared.Events)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ChainCounter"
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = UIConstants.ZOrder.ChainCounter
screenGui.Parent = playerGui

local holder = Instance.new("Frame")
holder.Name = "Holder"
holder.Size = UDim2.fromOffset(360, 100)
holder.AnchorPoint = Vector2.new(0.5, 0.5)
holder.Position = UDim2.fromScale(0.5, 0.35)
holder.BackgroundTransparency = 1
holder.Visible = false
holder.Parent = screenGui

local label = Instance.new("TextLabel")
label.Name = "ChainLabel"
label.Size = UDim2.fromScale(1, 1)
label.AnchorPoint = Vector2.new(0.5, 0.5)
label.Position = UDim2.fromScale(0.5, 0.5)
label.BackgroundTransparency = 1
label.FontFace = UIConstants.Fonts.Display
label.TextSize = UIConstants.TextSizes.DisplayLarge
label.TextColor3 = UIConstants.Colors.TextOnWarm
label.TextStrokeColor3 = UIConstants.Colors.TextDark
label.TextStrokeTransparency = 0.6
label.Text = ""
label.Parent = holder

-- Peach → coral gradient on the text.
local gradient = Instance.new("UIGradient")
gradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, UIConstants.Colors.ChainGradientStart),
    ColorSequenceKeypoint.new(1, UIConstants.Colors.ChainGradientEnd),
})
gradient.Rotation = 90
gradient.Parent = label

local scale = Instance.new("UIScale")
scale.Scale = 0.4
scale.Parent = holder

local remotes = ReplicatedStorage:WaitForChild("Remotes", 30)
if not remotes then
    return
end
local chainRemote = remotes:WaitForChild(Events.Names.ChainCompleted, 30)
if not chainRemote then
    return
end

local hideTask = nil

local function bounceIn()
    scale.Scale = 0.4
    holder.Visible = true
    local tween = TweenService:Create(
        scale,
        UIConstants.tween(UIConstants.Durations.BounceIn, "UI"),
        { Scale = 1 }
    )
    tween:Play()
end

local function hide()
    holder.Visible = false
    scale.Scale = 0.4
end

chainRemote.OnClientEvent:Connect(function(payload)
    if not payload.isLocal then return end
    label.Text = "Chain x" .. payload.chainLength .. "!"
    bounceIn()
    if hideTask then task.cancel(hideTask) end
    hideTask = task.delay(UIConstants.Durations.ChainCounterPersist, function()
        hide()
        hideTask = nil
    end)
end)
