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
-- Pearl ambience (ported from MainMenu): 8 pearls drifting upward at low
-- transparency, behind everything via ZIndex = 1. Same look and language as
-- the main menu so the wait state feels like a quieter continuation, not a
-- blank cream void. Pearls are created once and only animated while the
-- player is in the "matching" state (Lobby ScreenGui is also Enabled only
-- during matching, so this just keeps CPU clean when off-screen).
--------------------------------------------------------------------------------

local PEARL_COUNT = 8
local PEARL_SIZE = 36
local PEARL_TRANSPARENCY = 0.7

local pearlColors = {
    UIConstants.Colors.PearlBrown,
    UIConstants.Colors.PearlPink,
    UIConstants.Colors.PearlGreen,
    UIConstants.Colors.PearlWhite,
}

local pearlContainer = Instance.new("Frame")
pearlContainer.Name = "PearlField"
pearlContainer.Size = UDim2.fromScale(1, 1)
pearlContainer.BackgroundTransparency = 1
pearlContainer.ZIndex = 1
pearlContainer.Parent = screenGui

local pearls = {}
local pearlActiveTweens = {}
local pearlsRunning = false

local function buildPearl(index)
    local pearl = Instance.new("Frame")
    pearl.Name = "Pearl" .. index
    pearl.Size = UDim2.fromOffset(PEARL_SIZE, PEARL_SIZE)
    pearl.AnchorPoint = Vector2.new(0.5, 0.5)
    pearl.BackgroundColor3 = pearlColors[((index - 1) % #pearlColors) + 1]
    pearl.BackgroundTransparency = PEARL_TRANSPARENCY
    pearl.BorderSizePixel = 0
    pearl.ZIndex = 1
    pearl.Parent = pearlContainer

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UIConstants.Corners.Pearl
    corner.Parent = pearl

    local highlight = Instance.new("Frame")
    highlight.Size = UIConstants.Pearl.HighlightSize
    highlight.AnchorPoint = UIConstants.Pearl.HighlightAnchor
    highlight.Position = UIConstants.Pearl.HighlightPosition
    highlight.BackgroundColor3 = UIConstants.Colors.PearlHighlight
    highlight.BackgroundTransparency = UIConstants.Pearl.HighlightTransparency + 0.2
    highlight.BorderSizePixel = 0
    highlight.ZIndex = 2
    highlight.Parent = pearl
    local highlightCorner = Instance.new("UICorner")
    highlightCorner.CornerRadius = UIConstants.Corners.Pearl
    highlightCorner.Parent = highlight

    return pearl
end

local function driftPearl(pearl, durationSeconds)
    if not pearlsRunning then return end
    local startX = math.random(5, 95) / 100
    pearl.Position = UDim2.new(startX, 0, 1.1, 0)
    local tween = TweenService:Create(
        pearl,
        TweenInfo.new(durationSeconds, Enum.EasingStyle.Linear, Enum.EasingDirection.Out),
        { Position = UDim2.new(startX, 0, -0.15, 0) }
    )
    pearlActiveTweens[pearl] = tween
    tween.Completed:Connect(function(state)
        pearlActiveTweens[pearl] = nil
        if pearlsRunning and pearl.Parent and state == Enum.PlaybackState.Completed then
            driftPearl(pearl, math.random(12, 18))
        end
    end)
    tween:Play()
end

for i = 1, PEARL_COUNT do
    pearls[i] = buildPearl(i)
end

local function startPearls()
    if pearlsRunning then return end
    pearlsRunning = true
    for i, pearl in ipairs(pearls) do
        -- Stagger initial positions so the field doesn't all spawn at the
        -- bottom at the same instant. Mid-air start tweens for a fractional
        -- duration, then driftPearl chains the full-duration loop.
        local initialY = math.random(20, 110) / 100
        pearl.Position = UDim2.new(math.random(5, 95) / 100, 0, initialY, 0)
        local remainingFraction = (initialY + 0.15) / 1.25
        local fullDuration = math.random(12, 18)
        local tween = TweenService:Create(
            pearl,
            TweenInfo.new(fullDuration * remainingFraction, Enum.EasingStyle.Linear, Enum.EasingDirection.Out),
            { Position = UDim2.new(pearl.Position.X.Scale, 0, -0.15, 0) }
        )
        pearlActiveTweens[pearl] = tween
        tween.Completed:Connect(function(state)
            pearlActiveTweens[pearl] = nil
            if pearlsRunning and pearl.Parent and state == Enum.PlaybackState.Completed then
                driftPearl(pearl, math.random(12, 18))
            end
        end)
        tween:Play()
        -- Tiny stagger between starts so they don't share an exact frame.
        if i % 2 == 0 then task.wait() end
    end
end

local function stopPearls()
    pearlsRunning = false
    for pearl, tween in pairs(pearlActiveTweens) do
        tween:Cancel()
        pearlActiveTweens[pearl] = nil
    end
    -- Reseat below the screen so when matching resumes they don't pop into
    -- view at stale positions before the staggered re-spawn.
    for _, pearl in ipairs(pearls) do
        pearl.Position = UDim2.new(math.random(5, 95) / 100, 0, 1.1, 0)
    end
end

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
queuePanel.ZIndex = 10 -- sits above the pearl field (ZIndex 1)
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
        startPearls()
    else
        if queuePillVisible then
            slideOut()
            queueActive = false
        end
        stopPearls()
    end
end

-- Apply once on load in case GameState is already "matching" when the
-- script runs.
onGameStateChanged()
player:GetAttributeChangedSignal("GameState"):Connect(onGameStateChanged)
