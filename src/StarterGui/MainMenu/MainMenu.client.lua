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

-- Defensive UI-SFX trigger. UISfx.client.lua publishes _G.BobaDropSfx with
-- click/confirm/back/error functions; client script execution order isn't
-- deterministic so we guard against it loading after this one.
local function sfx(kind)
    if _G.BobaDropSfx and _G.BobaDropSfx[kind] then _G.BobaDropSfx[kind]() end
end

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

-- PearlWhite removed: it blends with the peach-toned backdrop and reads as
-- nothing in the drift. Three high-contrast variants left so every pearl in
-- the field is visible.
local pearlColors = {
    UIConstants.Colors.PearlBrown,
    UIConstants.Colors.PearlPink,
    UIConstants.Colors.PearlGreen,
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
-- Hero stack: wraps the BOBA DROP wordmark + the PLAY / PRACTICE / SINGLE
-- PLAYER button group in a single centered vertical layout. Without this
-- wrapper the title (Scale-positioned at y=0.18) and the PlayGroup (Scale-
-- positioned at y=0.5) drift toward each other on short viewports and
-- collide. The wrapper anchors at the viewport center, uses AutomaticSize.Y
-- to fit its children, and keeps a fixed 50px gap between title and CTAs
-- regardless of viewport height.
--------------------------------------------------------------------------------

local heroStack = Instance.new("Frame")
heroStack.Name = "HeroStack"
heroStack.Size = UDim2.fromOffset(520, 0)
heroStack.AutomaticSize = Enum.AutomaticSize.Y
-- Top-anchored at a fixed 40px offset (not Scale-based) so the title
-- sits in a predictable place regardless of viewport height. Center
-- anchoring pushed the title to mid-screen; even 8% Scale was reading
-- too low on Sarah's playtest. Fixed offset locks the wordmark to the
-- top region and lets the button group land cleanly above the pill row.
heroStack.Position = UDim2.new(0.5, 0, 0, 40)
heroStack.AnchorPoint = Vector2.new(0.5, 0)
heroStack.BackgroundTransparency = 1
heroStack.ZIndex = 5
heroStack.Parent = screenGui

local heroLayout = Instance.new("UIListLayout")
heroLayout.FillDirection = Enum.FillDirection.Vertical
heroLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
heroLayout.VerticalAlignment = Enum.VerticalAlignment.Top
heroLayout.SortOrder = Enum.SortOrder.LayoutOrder
heroLayout.Padding = UDim.new(0, 50)
heroLayout.Parent = heroStack

--------------------------------------------------------------------------------
-- Title wordmark "BOBA DROP". Display font, large, with a soft drop shadow
-- and a 2s idle scale pulse so it never reads as static. Position is owned
-- by HeroStack's UIListLayout (LayoutOrder=1).
--------------------------------------------------------------------------------

local titleContainer = Instance.new("Frame")
titleContainer.Name = "Title"
titleContainer.Size = UDim2.fromOffset(520, 92)
titleContainer.AnchorPoint = Vector2.new(0.5, 0)
titleContainer.BackgroundTransparency = 1
titleContainer.LayoutOrder = 1
titleContainer.ZIndex = 5
titleContainer.Parent = heroStack

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
-- Player greeting: small frame top-left with the player's headshot circle
-- and a "Welcome back," + DisplayName text block. Drifts in from above on
-- first render so the menu feels like it's assembling itself for this
-- specific player. Sits above the pearl ambience (ZIndex 5) but below the
-- title pulse and CTA stack (ZIndex 10).
--------------------------------------------------------------------------------

local greetingFrame = Instance.new("Frame")
greetingFrame.Name = "Greeting"
greetingFrame.AnchorPoint = Vector2.new(0, 0)
greetingFrame.Position = UDim2.fromOffset(20, -60) -- starts above the screen, tweens down to clear Roblox's top-bar chrome
greetingFrame.Size = UDim2.fromOffset(200, 56)
greetingFrame.BackgroundTransparency = 1
greetingFrame.ZIndex = 5
greetingFrame.Parent = screenGui

-- Headshot circle on the left. 48x48 with Cream fill as a loading-state
-- background so a slow thumbnail fetch doesn't render as a blank hole.
local headshot = Instance.new("ImageLabel")
headshot.Name = "Headshot"
headshot.AnchorPoint = Vector2.new(0, 0.5)
headshot.Position = UDim2.new(0, 0, 0.5, 0)
headshot.Size = UDim2.fromOffset(48, 48)
headshot.BackgroundColor3 = UIConstants.Colors.Cream
headshot.BackgroundTransparency = 0
headshot.BorderSizePixel = 0
headshot.ScaleType = Enum.ScaleType.Crop
headshot.Image = ""
headshot.ZIndex = 6
headshot.Parent = greetingFrame

local headshotCorner = Instance.new("UICorner")
headshotCorner.CornerRadius = UIConstants.Corners.Pearl
headshotCorner.Parent = headshot

-- Thumbnail fetch can throw if Roblox auth is offline or the avatar isn't
-- resolvable. Wrap in pcall and fall back to a solid PearlPink fill so the
-- corner still reads as a player chip and not a broken image.
local ok, thumbnailUrl = pcall(function()
    return Players:GetUserThumbnailAsync(
        player.UserId,
        Enum.ThumbnailType.HeadShot,
        Enum.ThumbnailSize.Size48x48
    )
end)
if ok and thumbnailUrl and thumbnailUrl ~= "" then
    headshot.Image = thumbnailUrl
else
    -- Solid pearl fallback. Drop the cream background, swap in PearlPink so
    -- the chip still feels intentional, and leave Image empty.
    headshot.BackgroundColor3 = UIConstants.Colors.PearlPink
end

-- Text block on the right of the headshot. Two stacked lines: a small soft
-- "Welcome back," and the DisplayName below it. If DisplayName equals Name
-- we still show just one name line (the spec calls for one name line either
-- way), so this branch only changes which string we pass to the label.
local textBlock = Instance.new("Frame")
textBlock.Name = "TextBlock"
textBlock.AnchorPoint = Vector2.new(0, 0.5)
textBlock.Position = UDim2.new(0, 56, 0.5, 0) -- 48px headshot + 8px gap
textBlock.Size = UDim2.fromOffset(144, 48)
textBlock.BackgroundTransparency = 1
textBlock.ZIndex = 6
textBlock.Parent = greetingFrame

local welcomeLabel = Instance.new("TextLabel")
welcomeLabel.Name = "Welcome"
welcomeLabel.AnchorPoint = Vector2.new(0, 0)
welcomeLabel.Position = UDim2.fromOffset(0, 2)
welcomeLabel.Size = UDim2.new(1, 0, 0, 18)
welcomeLabel.BackgroundTransparency = 1
welcomeLabel.Text = "Welcome back,"
welcomeLabel.FontFace = UIConstants.Fonts.Tutorial
welcomeLabel.TextSize = 14
welcomeLabel.TextColor3 = UIConstants.Colors.TextSoft
welcomeLabel.TextXAlignment = Enum.TextXAlignment.Left
welcomeLabel.TextYAlignment = Enum.TextYAlignment.Center
welcomeLabel.ZIndex = 6
welcomeLabel.Parent = textBlock

local nameLabel = Instance.new("TextLabel")
nameLabel.Name = "DisplayName"
nameLabel.AnchorPoint = Vector2.new(0, 0)
nameLabel.Position = UDim2.fromOffset(0, 22)
nameLabel.Size = UDim2.new(1, 0, 0, 22)
nameLabel.BackgroundTransparency = 1
-- DisplayName preferred. When it happens to equal Name, we still render it
-- once (the spec is explicit: one name line either way).
nameLabel.Text = player.DisplayName
nameLabel.FontFace = UIConstants.Fonts.Display
nameLabel.TextSize = 18
nameLabel.TextColor3 = UIConstants.Colors.TextDark
nameLabel.TextXAlignment = Enum.TextXAlignment.Left
nameLabel.TextYAlignment = Enum.TextYAlignment.Center
nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
nameLabel.ZIndex = 6
nameLabel.Parent = textBlock

-- Drift in from above. Matches the menu's Back/Out motion grammar (the
-- title pulse and pill buttons use the same easing family via
-- UIConstants.Easing.UI).
local greetingDriftIn = TweenService:Create(
    greetingFrame,
    UIConstants.tween(0.5, "UI"),
    { Position = UDim2.fromOffset(20, 44) }
)
greetingDriftIn:Play()

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

-- Three play buttons (PLAY versus / PRACTICE solo / SINGLE PLAYER vs AI)
-- are vertically stacked as a button group inside HeroStack. The outer
-- HeroStack layout handles the gap from the title above; this group's
-- own UIListLayout handles the 14px gap between the 3 buttons. PLAY is
-- the visually loudest as the primary multiplayer CTA; PRACTICE and
-- SINGLE PLAYER are equal-weight secondary alternatives below.
local playGroup = Instance.new("Frame")
playGroup.Name = "PlayGroup"
playGroup.Size = UDim2.fromOffset(260, 232)
playGroup.AnchorPoint = Vector2.new(0.5, 0)
playGroup.BackgroundTransparency = 1
playGroup.LayoutOrder = 2
playGroup.ZIndex = 10
playGroup.Parent = heroStack

local playGroupLayout = Instance.new("UIListLayout")
playGroupLayout.FillDirection = Enum.FillDirection.Vertical
playGroupLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
playGroupLayout.VerticalAlignment = Enum.VerticalAlignment.Center
playGroupLayout.SortOrder = Enum.SortOrder.LayoutOrder
playGroupLayout.Padding = UDim.new(0, 14)
playGroupLayout.Parent = playGroup

-- Factory for the secondary CTAs so PRACTICE and SINGLE PLAYER share the
-- same shape without copy-paste.
local function makeModeBtn(name, label, layoutOrder, isPrimary)
    local btn = Instance.new("TextButton")
    btn.Name = name
    btn.Size = isPrimary and UDim2.fromOffset(260, 80) or UDim2.fromOffset(220, 52)
    btn.LayoutOrder = layoutOrder
    btn.AutoButtonColor = false
    btn.BorderSizePixel = 0
    btn.BackgroundColor3 = isPrimary and UIConstants.Colors.Mint or UIConstants.Colors.Cream
    btn.TextColor3 = UIConstants.Colors.TextDark
    btn.FontFace = UIConstants.Fonts.Display
    btn.TextSize = isPrimary and 40 or 22
    btn.Text = label
    btn.ZIndex = 10
    btn.Parent = playGroup

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UIConstants.Corners.Button
    corner.Parent = btn

    local stroke = Instance.new("UIStroke")
    stroke.Color = UIConstants.Colors.StrokeWarm
    stroke.Thickness = isPrimary and 2 or 1.5
    stroke.Transparency = 0.35
    stroke.Parent = btn

    local scaleObj = Instance.new("UIScale")
    scaleObj.Scale = 1
    scaleObj.Parent = btn

    return btn, scaleObj
end

local playBtn, playScale = makeModeBtn("PlayBtn", "PLAY", 1, true)
local practiceBtn, practiceScale = makeModeBtn("PracticeBtn", "PRACTICE", 2, false)
local singlePlayerBtn, singlePlayerScale = makeModeBtn("SinglePlayerBtn", "SINGLE PLAYER", 3, false)

-- Shared firing logic: each button latches its own bool to prevent
-- double-fire, and any one button firing locks the rest until the
-- GameState transition clears the latches. Avoids race where a player
-- taps PLAY then quickly hits PRACTICE before the server transition
-- pulls the menu away.
local playFired = false
local practiceFired = false
local singlePlayerFired = false

local function anyFired()
    return playFired or practiceFired or singlePlayerFired
end

local function disableBtn(btn)
    btn.AutoButtonColor = false
    btn.Active = false
end

playBtn.MouseButton1Click:Connect(function()
    if anyFired() then return end
    sfx("confirm")
    squish(playScale)
    if not enterQueueRemote then
        warn("[MainMenu] EnterQueue remote missing, PLAY no-op")
        return
    end
    playFired = true
    disableBtn(playBtn)
    enterQueueRemote:FireServer({ mode = "versus" })
end)

practiceBtn.MouseButton1Click:Connect(function()
    if anyFired() then return end
    sfx("confirm")
    squish(practiceScale)
    if not enterQueueRemote then
        warn("[MainMenu] EnterQueue remote missing, PRACTICE no-op")
        return
    end
    practiceFired = true
    disableBtn(practiceBtn)
    enterQueueRemote:FireServer({ mode = "practice" })
end)

singlePlayerBtn.MouseButton1Click:Connect(function()
    if anyFired() then return end
    sfx("click")
    squish(singlePlayerScale)
    -- SINGLE PLAYER opens the difficulty picker, which fires EnterQueue
    -- itself once the player taps a tier. Latch stays unfired so the
    -- player can close the picker and tap another mode button without
    -- the menu being locked.
    if _G.BobaDropDifficultyPicker and _G.BobaDropDifficultyPicker.open then
        _G.BobaDropDifficultyPicker.open()
    else
        warn("[MainMenu] DifficultyPicker not ready, falling back to easy")
        if enterQueueRemote then
            singlePlayerFired = true
            disableBtn(singlePlayerBtn)
            enterQueueRemote:FireServer({ mode = "ai", difficulty = "easy" })
        end
    end
end)

-- Reset on returning to the menu (match end -> main_menu). The ScreenGui
-- persists across the in_match window (ResetOnSpawn = false), so the
-- fired latches and Active flags need an explicit reset.
player:GetAttributeChangedSignal("GameState"):Connect(function()
    local state = player:GetAttribute("GameState")
    if state == "main_menu" then
        playFired = false
        practiceFired = false
        singlePlayerFired = false
        playBtn.Active = true
        practiceBtn.Active = true
        singlePlayerBtn.Active = true
    end
end)

--------------------------------------------------------------------------------
-- Secondary pill row: Themes / gear / How-to-play. Horizontal UIListLayout
-- centered below PLAY. Each pill uses the same press-feedback pattern as
-- the existing buttons in Lobby and Settings.
--------------------------------------------------------------------------------

local pillRow = Instance.new("Frame")
pillRow.Name = "PillRow"
pillRow.Size = UDim2.fromOffset(534, 44) -- 4 * 120 + 3 * 18 padding (SHOP added)
-- Bottom-anchored with a 32px floor so the pill row never collides with
-- the PLAY/PRACTICE pair, regardless of viewport height. The play group
-- sits at viewport center; gear of room from the pill row scales with
-- viewport rather than disappearing on short displays.
pillRow.Position = UDim2.new(0.5, 0, 1, -32)
pillRow.AnchorPoint = Vector2.new(0.5, 1)
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
    -- Cream background instead of Peach so the pill silhouette pops against
    -- the peach-toned gradient backdrop. Peach-on-peach was reading as text
    -- floating on nothing in Sarah's 2026-05-21 screenshot.
    btn.BackgroundColor3 = UIConstants.Colors.Cream
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
        sfx("click")
        squish(scaleObj)
        onActivate()
    end)

    return btn
end

makePill("ThemesBtn", "THEMES", UIConstants.TextSizes.Body, 1, function()
    -- THEMES opens the inventory of owned + locked themes. The Shop pill
    -- alongside is the unlock path; locked cards no longer route to it.
    if _G.BobaDropThemes and _G.BobaDropThemes.open then
        _G.BobaDropThemes.open()
    end
end)

makePill("ShopBtn", "SHOP", UIConstants.TextSizes.Body, 2, function()
    if _G.BobaDropShop and _G.BobaDropShop.open then
        _G.BobaDropShop.open()
    end
end)

makePill("SettingsBtn", "\u{2699}", 24, 3, function()
    if _G.BobaDropSettings and _G.BobaDropSettings.open then
        _G.BobaDropSettings.open()
    end
end)

makePill("HowToBtn", "?", 28, 4, function()
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
