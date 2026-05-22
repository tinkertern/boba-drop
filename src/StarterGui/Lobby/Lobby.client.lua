-- Lobby UI: queue pill only. The MainMenu screen owns PLAY / Themes /
-- Settings / How-to-play. This script is what the player sees during the
-- brief "matching" window between tapping PLAY and the server promoting
-- them into a match. UIStateController flips this ScreenGui's Enabled
-- based on GameState: enabled while "matching", disabled otherwise.
--
-- The pill slides up from below on entering "matching" and slides down
-- when the controller flips us off. Cancel fires LeaveQueue, which removes
-- the player from the server queue and flips GameState back to main_menu;
-- UIStateController catches that and swaps the screen. Search-again fires
-- EnterQueue and restarts the local timer; server-side enqueue is
-- idempotent so a double-fire can't pair a player against themselves.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local UIConstants = require(ReplicatedStorage.Shared.UI.UIConstants)
local Constants = require(ReplicatedStorage.Shared.Logic.Constants)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Defensive UI-SFX trigger. UISfx.client.lua publishes _G.BobaDropSfx with
-- click/confirm/back/error functions; client script execution order isn't
-- deterministic so we guard against it loading after this one.
local function sfx(kind)
    if _G.BobaDropSfx and _G.BobaDropSfx[kind] then _G.BobaDropSfx[kind]() end
end

-- Defensive lookup: the remote lives at ReplicatedStorage.Remotes.EnterQueue
-- (matches the convention used by InputHandler, BoardPlaceholder, etc).
-- If the engineer's server piece hasn't merged yet, log a warning and let
-- Search-again no-op rather than crashing.
local Remotes = ReplicatedStorage:WaitForChild("Remotes", 30)
local enterQueueRemote = Remotes and Remotes:WaitForChild("EnterQueue", 30)
local leaveQueueRemote = Remotes and Remotes:WaitForChild("LeaveQueue", 30)
if not enterQueueRemote then
    warn("[Lobby] Remotes.EnterQueue not found within 30s. Search-again will no-op.")
end
if not leaveQueueRemote then
    warn("[Lobby] Remotes.LeaveQueue not found within 30s. Cancel will fall back to a client-only pill flip.")
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "Lobby"
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = UIConstants.ZOrder.Tutorial
-- Global ZIndex so the queue pill's child labels can sit above the pearl
-- field deterministically. With the default Sibling behavior, the pearl
-- container's children were getting drawn over the queue pill's text in
-- the bundle that added the ambient pearls.
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Global
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

-- Cozy queue tips: rotated every 3 seconds while the player is matching so
-- the subtitle reads less like a dry stopwatch and more like a small coach
-- whispering mechanics. Elapsed seconds get appended after a middle-dot so
-- the wait progress is still visible at a glance.
local TIP_ROTATION = {
    "hold S or Down to soft drop",
    "chain colors for combo damage",
    "watch your danger row pulse",
    "warm-tan cancels, mint goes",
    "the cup that overflows first loses",
    "popping 4+ same color triggers a chain",
}
local TIP_INTERVAL_SECONDS = 3

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
statusBlock.ZIndex = 11
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
queueLabel.ZIndex = 12
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
subtitleLabel.ZIndex = 12
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
cancelBtn.ZIndex = 12
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
-- reset on each "matching" entry so re-queueing after a match is a clean
-- slate. `tipIndex` walks TIP_ROTATION while queueActive.
local queueStarted = 0
local queueActive = false
local queuePillVisible = false
local tipIndex = 1

local function setSearchAgainMode(subtitle)
    queueActive = false
    queueLabel.Text = "Queue canceled"
    subtitleLabel.Text = subtitle
    cancelBtn.Text = "Search again"
    cancelBtn.BackgroundColor3 = UIConstants.Colors.Peach
    cancelBtn.TextColor3 = UIConstants.Colors.TextDark
end

local function currentTip()
    if #TIP_ROTATION == 0 then return nil end
    return TIP_ROTATION[((tipIndex - 1) % #TIP_ROTATION) + 1]
end

local function formatSubtitle(elapsed)
    local tip = currentTip()
    if tip then
        return ("%s · %ds"):format(tip, elapsed)
    end
    return ("%ds"):format(elapsed)
end

local function startQueue()
    queueStarted = tick()
    queueActive = true
    tipIndex = 1
    queueLabel.Text = "Searching for opponent..."
    subtitleLabel.Text = formatSubtitle(0)
    cancelBtn.Text = "Cancel"
    cancelBtn.BackgroundColor3 = UIConstants.Colors.WarmCancel
    cancelBtn.TextColor3 = UIConstants.Colors.TextOnWarm
    task.spawn(function()
        while queueActive and queuePanel.Parent do
            local elapsed = math.floor(tick() - queueStarted)
            -- Advance the tip every TIP_INTERVAL_SECONDS ticks. elapsed == 0
            -- on the first pass keeps tipIndex at 1 so the player sees the
            -- opening tip for a full interval before rotation kicks in.
            if elapsed > 0 and elapsed % TIP_INTERVAL_SECONDS == 0 then
                tipIndex = tipIndex + 1
            end
            subtitleLabel.Text = formatSubtitle(elapsed)
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
    -- Two-mode button: while queueActive it's Cancel (back); after a timeout
    -- it relabels to "Search again" (confirm). Pick the SFX kind to match.
    if queueActive then
        sfx("back")
    else
        sfx("confirm")
    end
    squish(cancelScale)
    if queueActive then
        -- Server pops us from the queue and flips GameState back to
        -- main_menu; UIStateController then swaps to the MainMenu screen
        -- and onGameStateChanged below slides this pill out. Fallback to
        -- the old client-only pill flip if the remote is missing so the
        -- button never appears broken.
        if leaveQueueRemote then
            leaveQueueRemote:FireServer()
        else
            setSearchAgainMode("Tap Search again when you're ready.")
        end
    else
        -- Search-again: re-fire EnterQueue and restart the local timer.
        -- GameState is already "matching" so UIStateController won't flip
        -- the screen, the pill just rolls over to a fresh search. Server
        -- enqueue is idempotent so a duplicate fire is a safe no-op.
        if enterQueueRemote then
            enterQueueRemote:FireServer({})
        end
        startQueue()
    end
end)

--------------------------------------------------------------------------------
-- Pill halo: a wide soft cream blob sitting behind the queue pill that
-- breathes (alpha 0.85 to 0.70 and back) while matching. Anchors the eye to
-- the bottom of the screen where the pill is and signals "actively waiting"
-- without competing for focus. ZIndex 4 places it above the pearl field
-- (ZIndex 1) but below the queue pill (ZIndex 10).
--------------------------------------------------------------------------------

local pillHalo = Instance.new("Frame")
pillHalo.Name = "PillHalo"
pillHalo.AnchorPoint = Vector2.new(0.5, 1)
pillHalo.Size = UDim2.fromOffset(640, PILL_HEIGHT + 80)
pillHalo.Position = UDim2.new(0.5, 0, 1, -PILL_BOTTOM_OFFSET + 20)
pillHalo.BackgroundColor3 = UIConstants.Colors.Cream
pillHalo.BackgroundTransparency = 1
pillHalo.BorderSizePixel = 0
pillHalo.ZIndex = 4
pillHalo.Visible = false
pillHalo.Parent = screenGui

local pillHaloCorner = Instance.new("UICorner")
pillHaloCorner.CornerRadius = UDim.new(0, 80)
pillHaloCorner.Parent = pillHalo

local haloBreatheTween
local function startHaloBreathe()
    if haloBreatheTween and haloBreatheTween.PlaybackState == Enum.PlaybackState.Playing then
        return
    end
    pillHalo.Visible = true
    pillHalo.BackgroundTransparency = 0.85
    haloBreatheTween = TweenService:Create(
        pillHalo,
        TweenInfo.new(2.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
        { BackgroundTransparency = 0.70 }
    )
    haloBreatheTween:Play()
end

local function stopHaloBreathe()
    if haloBreatheTween then
        haloBreatheTween:Cancel()
        haloBreatheTween = nil
    end
    pillHalo.BackgroundTransparency = 1
    pillHalo.Visible = false
end

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
        startHaloBreathe()
    else
        if queuePillVisible then
            slideOut()
            queueActive = false
        end
        stopPearls()
        stopHaloBreathe()
    end
end

-- Apply once on load in case GameState is already "matching" when the
-- script runs.
onGameStateChanged()
player:GetAttributeChangedSignal("GameState"):Connect(onGameStateChanged)
