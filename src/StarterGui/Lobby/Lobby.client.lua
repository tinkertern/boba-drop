-- Day 1: tutorial card with DataStore-persisted dismiss.
-- Day 3 will extend this file with queue UI + themes button.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")

local UIConstants = require(ReplicatedStorage.Shared.UI.UIConstants)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

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

local ds = DataStoreService:GetDataStore("BobaDrop_TutorialDismissed")
local key = "u" .. tostring(player.UserId)

local function dismiss()
    card.Visible = false
    pcall(function() ds:SetAsync(key, true) end)
end

local dismissed = false
pcall(function()
    dismissed = ds:GetAsync(key) == true
end)
if dismissed then
    card.Visible = false
end

closeBtn.MouseButton1Click:Connect(dismiss)
card.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        dismiss()
    end
end)
