-- Lobby UI: queue pill only. The MainMenu screen owns PLAY / Themes /
-- Settings / How-to-play. This script is what the player sees during the
-- brief "matching" window between tapping PLAY and the server promoting
-- them into a match. UIStateController flips this ScreenGui's Enabled
-- based on GameState: enabled while "matching", disabled otherwise.
--
-- The pill slides up from below on entering "matching" and slides down
-- when the controller flips us off. Cancel is a client-only state flip
-- for now (no LeaveQueue remote yet, known gap). Search-again fires
-- EnterQueue and restarts the local timer; the server treats it as a
-- fresh enqueue.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local UIConstants = require(ReplicatedStorage.Shared.UI.UIConstants)
local Constants = require(ReplicatedStorage.Shared.Logic.Constants)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Defensive lookup: the remote lives at ReplicatedStorage.Remotes.EnterQueue
-- (matches the convention used by InputHandler, BoardPlaceholder, etc).
-- If the engineer's server piece hasn't merged yet, log a warning and let
-- Search-again no-op rather than crashing.
local Remotes = ReplicatedStorage:WaitForChild("Remotes", 30)
local enterQueueRemote = Remotes and Remotes:WaitForChild("EnterQueue", 30)
if not enterQueueRemote then
    warn("[Lobby] Remotes.EnterQueue not found within 30s. Search-again will no-op.")
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "Lobby"
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = UIConstants.ZOrder.Tutorial
screenGui.Parent = playerGui

--------------------------------------------------------------------------------
-- Queue pill: bottom-anchored, horizontal. Status text + subtitle on the
-- left, action button on the right. Slides in when we enter "matching",
-- slides down when we leave. State (queueActive / queuePillVisible /
-- queueStarted) is re-initialized on each entry so re-queue after a match
-- starts fresh.
--------------------------------------------------------------------------------

local PILL_BOTTOM_OFFSET = 24
local PILL_HEIGHT = 92

local queuePanel = Instance.new("Frame")
queuePanel.Name = "Queue"
queuePanel.Size = UDim2.fromOffset(480, PILL_HEIGHT)
queuePanel.Position = UDim2.new(0.5, 0, 1, PILL_HEIGHT + 80)
queuePanel.AnchorPoint = Vector2.new(0.5, 1)
queuePanel.BackgroundColor3 = UIConstants.Colors.Cream
queuePanel.BackgroundTransparency = 0
queuePanel.BorderSizePixel = 0
queuePanel.Visible = false
queuePanel.Parent = screenGui

local queueCorner = Instance.new("UICorner")
queueCorner.CornerRadius = UIConstants.Corners.Card
queueCorner.Parent = queuePanel

local queueStroke = Instance.new("UIStroke")
queueStroke.Color = UIConstants.Colors.StrokeWarm
queueStroke.Thickness = 2
queueStroke.Transparency = 0.4
queueStroke.Parent = queuePanel

local queuePadding = Instance.new("UIPadding")
queuePadding.PaddingTop = UDim.new(0, 12)
queuePadding.PaddingBottom = UDim.new(0, 12)
queuePadding.PaddingLeft = UDim.new(0, 20)
queuePadding.PaddingRight = UDim.new(0, 16)
queuePadding.Parent = queuePanel

local statusBlock = Instance.new("Frame")
statusBlock.Name = "Status"
statusBlock.Size = UDim2.new(1, -168, 1, 0)
statusBlock.Position = UDim2.fromOffset(0, 0)
statusBlock.BackgroundTransparency = 1
statusBlock.Parent = queuePanel

local queueLabel = Instance.new("TextLabel")
queueLabel.Name = "Title"
queueLabel.Size = UDim2.new(1, 0, 0, 28)
queueLabel.Position = UDim2.fromOffset(0, 6)
queueLabel.BackgroundTransparency = 1
queueLabel.FontFace = UIConstants.Fonts.HUD
queueLabel.TextSize = UIConstants.TextSizes.Body
queueLabel.TextColor3 = UIConstants.Colors.TextDark
queueLabel.TextXAlignment = Enum.TextXAlignment.Left
queueLabel.TextYAlignment = Enum.TextYAlignment.Center
queueLabel.TextWrapped = false
queueLabel.Text = "Searching for opponent..."
queueLabel.Parent = statusBlock

local subtitleLabel = Instance.new("TextLabel")
subtitleLabel.Name = "Subtitle"
subtitleLabel.Size = UDim2.new(1, 0, 0, 32)
subtitleLabel.Position = UDim2.fromOffset(0, 36)
subtitleLabel.BackgroundTransparency = 1
subtitleLabel.FontFace = UIConstants.Fonts.Tutorial
subtitleLabel.TextSize = UIConstants.TextSizes.SmallButton
subtitleLabel.TextColor3 = UIConstants.Colors.TextSoft
subtitleLabel.TextXAlignment = Enum.TextXAlignment.Left
subtitleLabel.TextYAlignment = Enum.TextYAlignment.Top
subtitleLabel.TextWrapped = true
subtitleLabel.Text = "0s"
subtitleLabel.Parent = statusBlock

local cancelBtn = Instance.new("TextButton")
cancelBtn.Name = "CancelBtn"
cancelBtn.Size = UDim2.fromOffset(152, 48)
cancelBtn.Position = UDim2.new(1, 0, 0.5, 0)
cancelBtn.AnchorPoint = Vector2.new(1, 0.5)
cancelBtn.AutoButtonColor = false
cancelBtn.BorderSizePixel = 0
cancelBtn.BackgroundColor3 = UIConstants.Colors.WarmCancel
cancelBtn.TextColor3 = UIConstants.Colors.TextOnWarm
cancelBtn.FontFace = UIConstants.Fonts.Display
cancelBtn.TextSize = UIConstants.TextSizes.Body
cancelBtn.Text = "Cancel"
cancelBtn.Parent = queuePanel

local cancelCorner = Instance.new("UICorner")
cancelCorner.CornerRadius = UIConstants.Corners.Button
cancelCorner.Parent = cancelBtn

local cancelStroke = Instance.new("UIStroke")
cancelStroke.Color = UIConstants.Colors.StrokeWarm
cancelStroke.Thickness = 1.5
cancelStroke.Transparency = 0.3
cancelStroke.Parent = cancelBtn

local cancelScale = Instance.new("UIScale")
cancelScale.Scale = 1
cancelScale.Parent = cancelBtn

local function squish(target)
    target.Scale = UIConstants.Motion.ButtonPressScale
    TweenService:Create(
        target,
        UIConstants.tween(UIConstants.Durations.ButtonPress, "UI"),
        { Scale = 1 }
    ):Play()
end

local PILL_RESTING_POSITION = UDim2.new(0.5, 0, 1, -PILL_BOTTOM_OFFSET)
local PILL_HIDDEN_POSITION = UDim2.new(0.5, 0, 1, 200)

-- Queue state (declared before the lifecycle helpers reference them). All
-- three reset on each "matching" entry so re-queueing after a match is a
-- clean slate.
local queueStarted = 0
local queueActive = false
local queuePillVisible = false

local function setSearchAgainMode(subtitle)
    queueActive = false
    queueLabel.Text = "Queue canceled"
    subtitleLabel.Text = subtitle
    cancelBtn.Text = "Search again"
    cancelBtn.BackgroundColor3 = UIConstants.Colors.Peach
    cancelBtn.TextColor3 = UIConstants.Colors.TextDark
end

local function startQueue()
    queueStarted = tick()
    queueActive = true
    queueLabel.Text = "Searching for opponent..."
    subtitleLabel.Text = "0s"
    cancelBtn.Text = "Cancel"
    cancelBtn.BackgroundColor3 = UIConstants.Colors.WarmCancel
    cancelBtn.TextColor3 = UIConstants.Colors.TextOnWarm
    task.spawn(function()
        while queueActive and queuePanel.Parent do
            local elapsed = math.floor(tick() - queueStarted)
            subtitleLabel.Text = ("%ds"):format(elapsed)
            if elapsed >= Constants.QUEUE_TIMEOUT then
                setSearchAgainMode("No opponent yet. Try again or invite a friend.")
                break
            end
            task.wait(1)
        end
    end)
end

local function slideIn()
    queuePanel.Position = PILL_HIDDEN_POSITION
    queuePanel.Visible = true
    queuePillVisible = true
    TweenService:Create(
        queuePanel,
        UIConstants.tween(0.35, "UI"),
        { Position = PILL_RESTING_POSITION }
    ):Play()
end

local function slideOut()
    queuePillVisible = false
    local tween = TweenService:Create(
        queuePanel,
        UIConstants.tween(0.3, "UIIn"),
        { Position = PILL_HIDDEN_POSITION }
    )
    tween.Completed:Connect(function()
        queuePanel.Visible = false
    end)
    tween:Play()
end

cancelBtn.MouseButton1Click:Connect(function()
    squish(cancelScale)
    if queueActive then
        -- Client-only cancel for now. The server still has us enqueued; a
        -- real LeaveQueue remote is a Day 4 followup. setSearchAgainMode
        -- gates the local timer so we stop showing growing seconds.
        setSearchAgainMode("Tap Search again when you're ready.")
    else
        -- Search-again: re-fire EnterQueue and restart the local timer.
        -- GameState is already "matching" so UIStateController won't flip
        -- the screen, the pill just rolls over to a fresh search.
        if enterQueueRemote then
            enterQueueRemote:FireServer({})
        end
        startQueue()
    end
end)

--------------------------------------------------------------------------------
-- GameState binding: slide in on "matching", slide out otherwise. The
-- ScreenGui's Enabled flag is owned by UIStateController; this just drives
-- the pill animation + internal state reset within the visible window.
--------------------------------------------------------------------------------

local function onGameStateChanged()
    local state = player:GetAttribute("GameState")
    if state == "matching" then
        if not queuePillVisible then
            startQueue()
            slideIn()
        end
    else
        if queuePillVisible then
            slideOut()
            queueActive = false
        end
    end
end

-- Apply once on load in case GameState is already "matching" when the
-- script runs.
onGameStateChanged()
player:GetAttributeChangedSignal("GameState"):Connect(onGameStateChanged)
