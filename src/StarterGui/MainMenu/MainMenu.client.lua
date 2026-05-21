-- Main menu: the player's landing screen before they tap PLAY. Hero
-- wordmark + PLAY CTA + secondary pill row (Themes / Settings / How to
-- Play) + drifting pearl ambience. ScreenGui visibility is owned by
-- UIStateController based on the GameState attribute, this script only
-- builds and animates.
--
-- Lifecycle:
--   GameState == "main_menu"  -> MainMenu enabled, Lobby disabled
--   GameState == "matching"   -> MainMenu disabled, Lobby (queue pill) enabled
--   in_match / match_end       -> both disabled
--
-- PLAY click fires Remotes.EnterQueue. The server flips GameState to
-- "matching", UIStateController swaps the screens. Defensive WaitForChild
-- with a timeout so a stale client doesn't crash if the engineer's server
-- piece lands after this one.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local UIConstants = require(ReplicatedStorage.Shared.UI.UIConstants)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Defensive lookup. The remote lives at ReplicatedStorage.Remotes.EnterQueue
-- (matches the convention used by InputHandler, BoardPlaceholder, etc).
-- If the engineer's server piece hasn't merged yet, log a warning and let
-- PLAY no-op instead of crashing.
local Remotes = ReplicatedStorage:WaitForChild("Remotes", 30)
local enterQueueRemote = Remotes and Remotes:WaitForChild("EnterQueue", 30)
if not enterQueueRemote then
    warn("[MainMenu] Remotes.EnterQueue not found within 30s. PLAY will no-op until the server piece lands.")
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "MainMenu"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = false
screenGui.DisplayOrder = UIConstants.ZOrder.MainMenu
screenGui.Parent = playerGui

--------------------------------------------------------------------------------
-- Pearl ambience: 8 pearls drifting upward at low transparency. Spawned
-- behind everything via low ZIndex. Each pearl has its own duration so the
-- field never falls into a synchronized rhythm.
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

local function driftPearl(pearl, durationSeconds)
    -- Tween from below the screen (y = 1.1) up past the top (y = -0.15).
    -- TweenService can't loop forever so we chain via Completed.
    local startX = math.random(5, 95) / 100
    pearl.Position = UDim2.new(startX, 0, 1.1, 0)
    local tween = TweenService:Create(
        pearl,
        TweenInfo.new(durationSeconds, Enum.EasingStyle.Linear, Enum.EasingDirection.Out),
        { Position = UDim2.new(startX, 0, -0.15, 0) }
    )
    tween.Completed:Connect(function()
        if pearl.Parent then
            driftPearl(pearl, math.random(12, 18))
        end
    end)
    tween:Play()
end

for i = 1, PEARL_COUNT do
    local pearl = Instance.new("Frame")
    pearl.Name = "Pearl" .. i
    pearl.Size = UDim2.fromOffset(PEARL_SIZE, PEARL_SIZE)
    pearl.AnchorPoint = Vector2.new(0.5, 0.5)
    pearl.BackgroundColor3 = pearlColors[((i - 1) % #pearlColors) + 1]
    pearl.BackgroundTransparency = PEARL_TRANSPARENCY
    pearl.BorderSizePixel = 0
    pearl.ZIndex = 1
    pearl.Parent = pearlContainer

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UIConstants.Corners.Pearl
    corner.Parent = pearl

    -- Subtle highlight to keep the glossy-pearl visual language consistent.
    local highlight = Instance.new("Frame")
    highlight.Size = UIConstants.Pearl.HighlightSize
    highlight.AnchorPoint = UIConstants.Pearl.HighlightAnchor
    highlight.Position = UIConstants.Pearl.HighlightPosition
    highlight.BackgroundColor3 = UIConstants.Colors.PearlHighlight
    highlight.BackgroundTransparency = UIConstants.Pearl.HighlightTransparency + 0.2 -- extra-soft on ambient pearls
    highlight.BorderSizePixel = 0
    highlight.ZIndex = 2
    highlight.Parent = pearl
    local highlightCorner = Instance.new("UICorner")
    highlightCorner.CornerRadius = UIConstants.Corners.Pearl
    highlightCorner.Parent = highlight

    -- Stagger initial positions so the field doesn't all spawn at the bottom
    -- at the same instant. We do this by starting the tween from a random
    -- mid-air position and letting it drift up the remaining distance.
    local initialY = math.random(20, 110) / 100 -- 0.20 to 1.10
    pearl.Position = UDim2.new(math.random(5, 95) / 100, 0, initialY, 0)
    local remainingFraction = (initialY + 0.15) / 1.25
    local fullDuration = math.random(12, 18)
    local tween = TweenService:Create(
        pearl,
        TweenInfo.new(fullDuration * remainingFraction, Enum.EasingStyle.Linear, Enum.EasingDirection.Out),
        { Position = UDim2.new(pearl.Position.X.Scale, 0, -0.15, 0) }
    )
    tween.Completed:Connect(function()
        if pearl.Parent then
            driftPearl(pearl, math.random(12, 18))
        end
    end)
    tween:Play()
end

--------------------------------------------------------------------------------
-- Title wordmark "BOBA DROP". Display font, large, top-center with a
-- soft drop shadow and a 2s idle scale pulse so it never reads as static.
--------------------------------------------------------------------------------

local titleContainer = Instance.new("Frame")
titleContainer.Name = "Title"
titleContainer.Size = UDim2.fromOffset(520, 92)
titleContainer.Position = UDim2.fromScale(0.5, 0.18)
titleContainer.AnchorPoint = Vector2.new(0.5, 0.5)
titleContainer.BackgroundTransparency = 1
titleContainer.ZIndex = 5
titleContainer.Parent = screenGui

local titleScale = Instance.new("UIScale")
titleScale.Scale = 1
titleScale.Parent = titleContainer

-- Drop shadow: duplicated label offset +2px in WarmDark for cozy depth.
local titleShadow = Instance.new("TextLabel")
titleShadow.Name = "Shadow"
titleShadow.Size = UDim2.fromScale(1, 1)
titleShadow.Position = UDim2.fromOffset(2, 3)
titleShadow.BackgroundTransparency = 1
titleShadow.Text = "BOBA DROP"
titleShadow.FontFace = UIConstants.Fonts.Display
titleShadow.TextScaled = true
titleShadow.TextColor3 = UIConstants.Colors.WarmDark
titleShadow.TextTransparency = 0.65
titleShadow.ZIndex = 4
titleShadow.Parent = titleContainer

local titleLabel = Instance.new("TextLabel")
titleLabel.Name = "Wordmark"
titleLabel.Size = UDim2.fromScale(1, 1)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "BOBA DROP"
titleLabel.FontFace = UIConstants.Fonts.Display
titleLabel.TextScaled = true
titleLabel.TextColor3 = UIConstants.Colors.Coral
titleLabel.ZIndex = 6
titleLabel.Parent = titleContainer

local titleSizeConstraint = Instance.new("UITextSizeConstraint")
titleSizeConstraint.MaxTextSize = UIConstants.TextSizes.DisplayLarge
titleSizeConstraint.MinTextSize = 36
titleSizeConstraint.Parent = titleLabel

local shadowSizeConstraint = Instance.new("UITextSizeConstraint")
shadowSizeConstraint.MaxTextSize = UIConstants.TextSizes.DisplayLarge
shadowSizeConstraint.MinTextSize = 36
shadowSizeConstraint.Parent = titleShadow

-- Idle pulse: scale 1.0 <-> 1.03 over 2s, Sine InOut. Chained tweens so the
-- pulse is continuous and the easing is symmetric.
local TITLE_PULSE_PERIOD = 2.0
local pulseUp = TweenService:Create(
    titleScale,
    TweenInfo.new(TITLE_PULSE_PERIOD / 2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
    { Scale = 1.03 }
)
local pulseDown = TweenService:Create(
    titleScale,
    TweenInfo.new(TITLE_PULSE_PERIOD / 2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
    { Scale = 1.0 }
)
local pulseActive = true
pulseUp.Completed:Connect(function(state)
    if pulseActive and state == Enum.PlaybackState.Completed then
        pulseDown:Play()
    end
end)
pulseDown.Completed:Connect(function(state)
    if pulseActive and state == Enum.PlaybackState.Completed then
        pulseUp:Play()
    end
end)
pulseUp:Play()

--------------------------------------------------------------------------------
-- PLAY button: hero CTA. Mint background, warm stroke, big display text.
-- Press feedback: UIScale squish, then immediately disable so a fast tapper
-- can't double-fire EnterQueue. UIStateController will hide the whole
-- ScreenGui once the server flips state to "matching".
--------------------------------------------------------------------------------

local function squish(scaleObj)
    scaleObj.Scale = UIConstants.Motion.ButtonPressScale
    TweenService:Create(
        scaleObj,
        UIConstants.tween(UIConstants.Durations.ButtonPress, "UI"),
        { Scale = 1 }
    ):Play()
end

local playBtn = Instance.new("TextButton")
playBtn.Name = "PlayBtn"
playBtn.Size = UDim2.fromOffset(260, 88)
playBtn.Position = UDim2.fromScale(0.5, 0.5)
playBtn.AnchorPoint = Vector2.new(0.5, 0.5)
playBtn.AutoButtonColor = false
playBtn.BorderSizePixel = 0
playBtn.BackgroundColor3 = UIConstants.Colors.Mint
playBtn.TextColor3 = UIConstants.Colors.TextDark
playBtn.FontFace = UIConstants.Fonts.Display
playBtn.TextSize = 40
playBtn.Text = "PLAY"
playBtn.ZIndex = 10
playBtn.Parent = screenGui

local playCorner = Instance.new("UICorner")
playCorner.CornerRadius = UIConstants.Corners.Button
playCorner.Parent = playBtn

local playStroke = Instance.new("UIStroke")
playStroke.Color = UIConstants.Colors.StrokeWarm
playStroke.Thickness = 2
playStroke.Transparency = 0.35
playStroke.Parent = playBtn

local playScale = Instance.new("UIScale")
playScale.Scale = 1
playScale.Parent = playBtn

local playFired = false
playBtn.MouseButton1Click:Connect(function()
    if playFired then return end
    squish(playScale)
    if not enterQueueRemote then
        warn("[MainMenu] EnterQueue remote missing, PLAY no-op")
        return
    end
    playFired = true
    -- Disable interaction immediately so a fast double-tap can't fire twice
    -- before the server transition swaps screens. The screen as a whole goes
    -- away when GameState flips to "matching".
    playBtn.AutoButtonColor = false
    playBtn.Active = false
    enterQueueRemote:FireServer({})
end)

-- Reset on returning to the menu (match end -> main_menu). The ScreenGui
-- persists across the in_match window (ResetOnSpawn = false), so the
-- playFired latch and Active flag need an explicit reset.
player:GetAttributeChangedSignal("GameState"):Connect(function()
    local state = player:GetAttribute("GameState")
    if state == "main_menu" then
        playFired = false
        playBtn.Active = true
    end
end)

--------------------------------------------------------------------------------
-- Secondary pill row: Themes / gear / How-to-play. Horizontal UIListLayout
-- centered below PLAY. Each pill uses the same press-feedback pattern as
-- the existing buttons in Lobby and Settings.
--------------------------------------------------------------------------------

local pillRow = Instance.new("Frame")
pillRow.Name = "PillRow"
pillRow.Size = UDim2.fromOffset(396, 44) -- 3 * 120 + 2 * 18 padding
pillRow.Position = UDim2.fromScale(0.5, 0.8)
pillRow.AnchorPoint = Vector2.new(0.5, 0.5)
pillRow.BackgroundTransparency = 1
pillRow.ZIndex = 10
pillRow.Parent = screenGui

local pillLayout = Instance.new("UIListLayout")
pillLayout.FillDirection = Enum.FillDirection.Horizontal
pillLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
pillLayout.VerticalAlignment = Enum.VerticalAlignment.Center
pillLayout.Padding = UDim.new(0, 18)
pillLayout.Parent = pillRow

local function makePill(name, text, textSize, layoutOrder, onActivate)
    local btn = Instance.new("TextButton")
    btn.Name = name
    btn.Size = UDim2.fromOffset(120, 44)
    btn.AutoButtonColor = false
    btn.BorderSizePixel = 0
    btn.BackgroundColor3 = UIConstants.Colors.Peach
    btn.TextColor3 = UIConstants.Colors.TextDark
    btn.FontFace = UIConstants.Fonts.Display
    btn.TextSize = textSize
    btn.Text = text
    btn.LayoutOrder = layoutOrder
    btn.ZIndex = 10
    btn.Parent = pillRow

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UIConstants.Corners.Button
    corner.Parent = btn

    local stroke = Instance.new("UIStroke")
    stroke.Color = UIConstants.Colors.StrokeWarm
    stroke.Thickness = 1.5
    stroke.Transparency = 0.35
    stroke.Parent = btn

    local scaleObj = Instance.new("UIScale")
    scaleObj.Scale = 1
    scaleObj.Parent = btn

    btn.MouseButton1Click:Connect(function()
        squish(scaleObj)
        onActivate()
    end)

    return btn
end

makePill("ThemesBtn", "THEMES", UIConstants.TextSizes.Body, 1, function()
    if _G.BobaDropShop and _G.BobaDropShop.open then
        _G.BobaDropShop.open()
    end
end)

makePill("SettingsBtn", "\u{2699}", 24, 2, function()
    if _G.BobaDropSettings and _G.BobaDropSettings.open then
        _G.BobaDropSettings.open()
    end
end)

makePill("HowToBtn", "?", 28, 3, function()
    if _G.BobaDropHowToPlay and _G.BobaDropHowToPlay.open then
        _G.BobaDropHowToPlay.open()
    end
end)

--------------------------------------------------------------------------------
-- Cleanup: stop the pulse when the ScreenGui is destroyed (rare, but the
-- chained tweens otherwise leak). RunService isn't used here so there's
-- nothing else to disconnect.
--------------------------------------------------------------------------------

screenGui.AncestryChanged:Connect(function(_, parent)
    if not parent then
        pulseActive = false
        pulseUp:Cancel()
        pulseDown:Cancel()
    end
end)
