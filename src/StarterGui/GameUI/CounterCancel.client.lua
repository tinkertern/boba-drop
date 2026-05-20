-- "BLOCKED!" visual for counter-cancel. Rendered in a different screen
-- region from the chain counter (left side, not center) so simultaneous
-- events don't visually collide. Per art direction the tone is worry,
-- not panic — soft blue text, peach backdrop pill, bounce-in.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local UIConstants = require(ReplicatedStorage.Shared.UI.UIConstants)
local Events = require(ReplicatedStorage.Shared.Events)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local gui = Instance.new("ScreenGui")
gui.Name = "CounterCancel"
gui.ResetOnSpawn = false
gui.DisplayOrder = UIConstants.ZOrder.BlockedFlash
gui.Parent = playerGui

local holder = Instance.new("Frame")
holder.Name = "Holder"
holder.Size = UDim2.fromOffset(240, 72)
holder.Position = UDim2.fromScale(0.18, 0.5)
holder.AnchorPoint = Vector2.new(0.5, 0.5)
holder.BackgroundColor3 = UIConstants.Colors.Peach
holder.BackgroundTransparency = 0.1
holder.BorderSizePixel = 0
holder.Visible = false
holder.Parent = gui

local holderCorner = Instance.new("UICorner")
holderCorner.CornerRadius = UIConstants.Corners.Pill
holderCorner.Parent = holder

local holderStroke = Instance.new("UIStroke")
holderStroke.Color = UIConstants.Colors.StrokeWarm
holderStroke.Thickness = 2
holderStroke.Transparency = 0.45
holderStroke.Parent = holder

local label = Instance.new("TextLabel")
label.Name = "BlockedLabel"
label.Size = UDim2.fromScale(1, 1)
label.BackgroundTransparency = 1
label.FontFace = UIConstants.Fonts.Display
label.TextSize = UIConstants.TextSizes.Score
label.TextColor3 = UIConstants.Colors.Blocked
label.TextStrokeColor3 = UIConstants.Colors.TextDark
label.TextStrokeTransparency = 0.55
label.Text = "BLOCKED!"
label.Parent = holder

local scale = Instance.new("UIScale")
scale.Scale = 0.5
scale.Parent = holder

local hideTask = nil

local function showBlocked()
    scale.Scale = 0.5
    holder.Visible = true
    TweenService:Create(
        scale,
        UIConstants.tween(UIConstants.Durations.BounceIn, "UI"),
        { Scale = 1 }
    ):Play()
    if hideTask then task.cancel(hideTask) end
    hideTask = task.delay(UIConstants.Durations.BlockedFlash, function()
        holder.Visible = false
        scale.Scale = 0.5
        hideTask = nil
    end)
end

task.spawn(function()
    local remotes = ReplicatedStorage:WaitForChild("Remotes", 30)
    if not remotes then return end
    local appliedName = Events.Names.GarbageApplied
    if not appliedName then return end
    local appliedRemote = remotes:WaitForChild(appliedName, 30)
    if not appliedRemote then return end

    appliedRemote.OnClientEvent:Connect(function(event)
        if tostring(event.playerId) ~= tostring(player.UserId) then return end
        if (event.canceledByCounter or 0) <= 0 then return end
        showBlocked()
    end)
end)
