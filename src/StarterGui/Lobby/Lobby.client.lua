-- Day 1: tutorial card. Dismiss state lives on the server (DataStore);
-- client reads it via Player attribute "TutorialDismissed" and requests a
-- dismiss by firing the DismissTutorial RemoteEvent.
-- Day 3 will extend this file with queue UI + themes button.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

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
card.Size = UDim2.fromOffset(320, 110)
card.Position = UDim2.fromScale(0.5, 0.20)
card.AnchorPoint = Vector2.new(0.5, 0.5)
card.BackgroundColor3 = UIConstants.Colors.Background
card.BackgroundTransparency = 0.2
card.Parent = screenGui

local label = Instance.new("TextLabel")
label.Size = UDim2.new(1, -32, 1, -16)
label.Position = UDim2.fromOffset(16, 8)
label.BackgroundTransparency = 1
label.TextColor3 = Color3.new(1, 1, 1)
label.TextWrapped = true
label.Font = UIConstants.Fonts.Tutorial
label.TextSize = 16
label.Text = "Match 4+ same-color pearls to pop.\nChain pops send ice cubes to your opponent.\nDon't overflow your cup."
label.Parent = card

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.fromOffset(24, 24)
closeBtn.Position = UDim2.new(1, -28, 0, 4)
closeBtn.Text = "X"
closeBtn.BackgroundTransparency = 0.4
closeBtn.Parent = card

local function applyVisibility()
    card.Visible = not player:GetAttribute(ATTRIBUTE)
end

local function requestDismiss()
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
