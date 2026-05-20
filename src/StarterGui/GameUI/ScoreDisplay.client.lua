-- Day 1 scaffold: in-game score HUD.
-- Server is authoritative on score: Day 3 will extend ChainCompleted with
-- `scoreAdded` (computed via Scoring.compute on the server). Client just
-- accumulates that and resets on RoundEnd. Until Day 3, scoreAdded is
-- absent and the HUD stays at 0.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UIConstants = require(ReplicatedStorage.Shared.UI.UIConstants)
local Events = require(ReplicatedStorage.Shared.Events)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ScoreDisplay"
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = UIConstants.ZOrder.ChainCounter - 1
screenGui.Parent = playerGui

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.Size = UDim2.fromOffset(160, 56)
panel.Position = UDim2.fromOffset(16, 16)
panel.BackgroundColor3 = UIConstants.Colors.Background
panel.BackgroundTransparency = 0.35
panel.BorderSizePixel = 0
panel.Parent = screenGui

local labelTitle = Instance.new("TextLabel")
labelTitle.Name = "Title"
labelTitle.Size = UDim2.new(1, -16, 0, 18)
labelTitle.Position = UDim2.fromOffset(8, 4)
labelTitle.BackgroundTransparency = 1
labelTitle.Font = UIConstants.Fonts.HUD
labelTitle.TextSize = 14
labelTitle.TextColor3 = Color3.fromRGB(220, 220, 230)
labelTitle.TextXAlignment = Enum.TextXAlignment.Left
labelTitle.Text = "SCORE"
labelTitle.Parent = panel

local labelValue = Instance.new("TextLabel")
labelValue.Name = "Value"
labelValue.Size = UDim2.new(1, -16, 0, 28)
labelValue.Position = UDim2.fromOffset(8, 22)
labelValue.BackgroundTransparency = 1
labelValue.Font = UIConstants.Fonts.Score
labelValue.TextSize = 26
labelValue.TextColor3 = Color3.new(1, 1, 1)
labelValue.TextXAlignment = Enum.TextXAlignment.Left
labelValue.Text = "0"
labelValue.Parent = panel

local score = 0
local function render()
    labelValue.Text = tostring(score)
end

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local chainRemote = remotes:WaitForChild(Events.Names.ChainCompleted)
local roundEndRemote = remotes:WaitForChild(Events.Names.RoundEnd)

chainRemote.OnClientEvent:Connect(function(payload)
    if not payload.isLocal then return end
    score += payload.scoreAdded or 0
    render()
end)

roundEndRemote.OnClientEvent:Connect(function()
    score = 0
    render()
end)
