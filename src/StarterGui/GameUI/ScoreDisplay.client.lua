-- In-game score HUD — cream pill, rounded, warm-dark text.
-- Server is authoritative on score: Day 3 ChainCompleted carries `scoreAdded`
-- (computed via Scoring.compute on the server). Client just accumulates that
-- and resets on RoundEnd. Until Day 3 the HUD stays at 0.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local UIConstants = require(ReplicatedStorage.Shared.UI.UIConstants)
local Events = require(ReplicatedStorage.Shared.Events)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ScoreDisplay"
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = UIConstants.ZOrder.ChainCounter - 1
-- IgnoreGuiInset so we own the full screen — landscape mobile only has ~390
-- vertical px to spend and the 36px topbar inset was pushing SCORE down into
-- the playable area.
screenGui.IgnoreGuiInset = true
screenGui.Parent = playerGui

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.Size = UDim2.fromOffset(168, 60)
panel.Position = UDim2.fromOffset(16, 12)
panel.BackgroundColor3 = UIConstants.Colors.Cream
panel.BackgroundTransparency = 0
panel.BorderSizePixel = 0
panel.Parent = screenGui

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UIConstants.Corners.Card
panelCorner.Parent = panel

local panelStroke = Instance.new("UIStroke")
panelStroke.Color = UIConstants.Colors.StrokeWarm
panelStroke.Thickness = 2
panelStroke.Transparency = 0.55
panelStroke.Parent = panel

local labelTitle = Instance.new("TextLabel")
labelTitle.Name = "Title"
labelTitle.Size = UDim2.new(1, -20, 0, 16)
labelTitle.Position = UDim2.fromOffset(12, 5)
labelTitle.BackgroundTransparency = 1
labelTitle.FontFace = UIConstants.Fonts.HUD
labelTitle.TextSize = UIConstants.TextSizes.HUDLabel
labelTitle.TextColor3 = UIConstants.Colors.TextSoft
labelTitle.TextXAlignment = Enum.TextXAlignment.Left
labelTitle.Text = "SCORE"
labelTitle.Parent = panel

local labelValue = Instance.new("TextLabel")
labelValue.Name = "Value"
labelValue.Size = UDim2.new(1, -20, 0, 32)
labelValue.Position = UDim2.fromOffset(12, 22)
labelValue.BackgroundTransparency = 1
labelValue.FontFace = UIConstants.Fonts.Display
labelValue.TextSize = UIConstants.TextSizes.Score
labelValue.TextColor3 = UIConstants.Colors.TextDark
labelValue.TextXAlignment = Enum.TextXAlignment.Left
labelValue.Text = "0"
labelValue.Parent = panel

local valueScale = Instance.new("UIScale")
valueScale.Scale = 1
valueScale.Parent = labelValue

local COUNT_UP_DURATION = 0.6 -- seconds, Quad/Out easing applied via RenderStepped

local score = 0 -- authoritative target score
local displayedScore = 0 -- currently rendered number
local tweenStartScore = 0
local tweenStartTime = 0
local tweenActive = false
local tweenConn = nil

local function setText(n)
    labelValue.Text = tostring(n)
end

local function bounce()
    valueScale.Scale = 1.15
    TweenService:Create(
        valueScale,
        UIConstants.tween(UIConstants.Durations.BounceIn, "UI"),
        { Scale = 1 }
    ):Play()
end

local function stopTween()
    if tweenConn then
        tweenConn:Disconnect()
        tweenConn = nil
    end
    tweenActive = false
end

local function startCountUp()
    stopTween()
    tweenStartScore = displayedScore
    tweenStartTime = os.clock()
    tweenActive = true
    tweenConn = RunService.RenderStepped:Connect(function()
        local t = (os.clock() - tweenStartTime) / COUNT_UP_DURATION
        if t >= 1 then
            displayedScore = score
            setText(displayedScore)
            stopTween()
            return
        end
        -- Quad/Out: 1 - (1 - t)^2
        local eased = 1 - (1 - t) * (1 - t)
        displayedScore = math.floor(tweenStartScore + (score - tweenStartScore) * eased + 0.5)
        setText(displayedScore)
    end)
end

local function render(snap)
    if snap then
        stopTween()
        displayedScore = score
        setText(displayedScore)
        return
    end
    bounce()
    startCountUp()
end

local remotes = ReplicatedStorage:WaitForChild("Remotes", 30)
if not remotes then
    return
end
local chainRemote = remotes:WaitForChild(Events.Names.ChainCompleted, 30)
local roundEndRemote = remotes:WaitForChild(Events.Names.RoundEnd, 30)
if not (chainRemote and roundEndRemote) then
    return
end

chainRemote.OnClientEvent:Connect(function(payload)
    if not payload.isLocal then return end
    score += payload.scoreAdded or 0
    render()
end)

roundEndRemote.OnClientEvent:Connect(function()
    score = 0
    render(true) -- snap on reset; no tween from N back to 0
end)
