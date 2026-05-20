-- Lobby tutorial card. Cozy cream + peach styling, idle bob to feel alive.
-- Dismiss state lives on the server (DataStore); client reads via
-- player:GetAttribute("TutorialDismissed") and fires DismissTutorial
-- RemoteEvent to request the write.
-- Day 3 will extend this file with queue UI + themes button.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local UIConstants = require(ReplicatedStorage.Shared.UI.UIConstants)

local ATTRIBUTE = "TutorialDismissed"

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local dismissRemote = ReplicatedStorage:WaitForChild("DismissTutorial")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "Lobby"
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = UIConstants.ZOrder.Tutorial
screenGui.Parent = playerGui

local card = Instance.new("Frame")
card.Name = "Tutorial"
card.Size = UDim2.fromOffset(340, 130)
card.Position = UDim2.fromScale(0.5, 0.22)
card.AnchorPoint = Vector2.new(0.5, 0.5)
card.BackgroundColor3 = UIConstants.Colors.Cream
card.BackgroundTransparency = 0
card.BorderSizePixel = 0
card.Parent = screenGui

local cardCorner = Instance.new("UICorner")
cardCorner.CornerRadius = UIConstants.Corners.Card
cardCorner.Parent = card

local cardStroke = Instance.new("UIStroke")
cardStroke.Color = UIConstants.Colors.StrokeWarm
cardStroke.Thickness = 2
cardStroke.Transparency = 0.4
cardStroke.Parent = card

local cardPadding = Instance.new("UIPadding")
cardPadding.PaddingTop = UDim.new(0, 14)
cardPadding.PaddingBottom = UDim.new(0, 14)
cardPadding.PaddingLeft = UDim.new(0, 18)
cardPadding.PaddingRight = UDim.new(0, 48) -- reserve space for close button
cardPadding.Parent = card

local label = Instance.new("TextLabel")
label.Size = UDim2.fromScale(1, 1)
label.BackgroundTransparency = 1
label.TextColor3 = UIConstants.Colors.TextDark
label.TextWrapped = true
label.TextXAlignment = Enum.TextXAlignment.Left
label.TextYAlignment = Enum.TextYAlignment.Top
label.Font = UIConstants.Fonts.Tutorial
label.TextSize = UIConstants.TextSizes.Body
label.Text = "Match 4+ same-color pearls to pop.\nChain pops send ice cubes to your opponent.\nDon't overflow your cup."
label.Parent = card

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.fromOffset(28, 28)
closeBtn.Position = UDim2.new(1, -34, 0, 6)
closeBtn.AnchorPoint = Vector2.new(0, 0)
closeBtn.Text = "×"
closeBtn.Font = UIConstants.Fonts.Display
closeBtn.TextSize = 22
closeBtn.TextColor3 = UIConstants.Colors.TextOnWarm
closeBtn.BackgroundColor3 = UIConstants.Colors.Peach
closeBtn.BorderSizePixel = 0
closeBtn.AutoButtonColor = false
closeBtn.Parent = card

local closeCorner = Instance.new("UICorner")
closeCorner.CornerRadius = UIConstants.Corners.Button
closeCorner.Parent = closeBtn

local closeScale = Instance.new("UIScale")
closeScale.Scale = 1
closeScale.Parent = closeBtn

local function squish(target)
    target.Scale = UIConstants.Motion.ButtonPressScale
    TweenService:Create(
        target,
        UIConstants.tween(UIConstants.Durations.ButtonPress, "UI"),
        { Scale = 1 }
    ):Play()
end

-- Idle bob so the card feels alive (2-4px float bob, period IdleFloatPeriod).
local basePosY = card.Position.Y.Scale
local baseOffsetY = card.Position.Y.Offset
local bobAmp = UIConstants.Motion.FloatBobPx
local startTime = os.clock()
local bobConn = RunService.RenderStepped:Connect(function()
    if not card.Visible then return end
    local t = (os.clock() - startTime) / UIConstants.Durations.IdleFloatPeriod
    local offset = math.sin(t * math.pi * 2) * bobAmp
    card.Position = UDim2.new(card.Position.X.Scale, card.Position.X.Offset, basePosY, baseOffsetY + offset)
end)

local function applyVisibility()
    card.Visible = not player:GetAttribute(ATTRIBUTE)
end

local function requestDismiss()
    squish(closeScale)
    card.Visible = false
    dismissRemote:FireServer()
end

applyVisibility()
player:GetAttributeChangedSignal(ATTRIBUTE):Connect(applyVisibility)

closeBtn.MouseButton1Click:Connect(requestDismiss)
card.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        requestDismiss()
    end
end)

screenGui.AncestryChanged:Connect(function(_, parent)
    if not parent then bobConn:Disconnect() end
end)
