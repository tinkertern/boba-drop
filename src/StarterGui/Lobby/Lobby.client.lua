-- Lobby UI: tutorial card + matchmaking queue panel + themes button.
-- Tutorial dismiss state lives on the server (DataStore); client reads
-- via player:GetAttribute("TutorialDismissed") and fires DismissTutorial
-- RemoteEvent to request the write. Queue UI is client-side elapsed
-- timer; the server-side RoomManager actually matches players. Themes
-- button opens the Shop modal via _G.BobaDropShop.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local UIConstants = require(ReplicatedStorage.Shared.UI.UIConstants)
local Constants = require(ReplicatedStorage.Shared.Logic.Constants)

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

-- Text lives in a wrapper so its UIPadding does not also shift the close
-- button — the X stays anchored to the card's actual top-right corner.
local textWrapper = Instance.new("Frame")
textWrapper.Name = "TextWrapper"
textWrapper.Size = UDim2.fromScale(1, 1)
textWrapper.BackgroundTransparency = 1
textWrapper.Parent = card

local textPadding = Instance.new("UIPadding")
textPadding.PaddingTop = UDim.new(0, 14)
textPadding.PaddingBottom = UDim.new(0, 14)
textPadding.PaddingLeft = UDim.new(0, 18)
textPadding.PaddingRight = UDim.new(0, 44) -- reserve space for close button
textPadding.Parent = textWrapper

-- Small color dots above the body text — telegraphs what pearls look
-- like before the player ever sees the board.
local dotRow = Instance.new("Frame")
dotRow.Name = "DotRow"
dotRow.Size = UDim2.fromOffset(78, 14)
dotRow.Position = UDim2.fromOffset(0, 0)
dotRow.BackgroundTransparency = 1
dotRow.Parent = textWrapper

local dotLayout = Instance.new("UIListLayout")
dotLayout.FillDirection = Enum.FillDirection.Horizontal
dotLayout.Padding = UDim.new(0, 6)
dotLayout.VerticalAlignment = Enum.VerticalAlignment.Center
dotLayout.Parent = dotRow

local function makeDot(color)
    local dot = Instance.new("Frame")
    dot.Size = UDim2.fromOffset(14, 14)
    dot.BackgroundColor3 = color
    dot.BorderSizePixel = 0
    dot.Parent = dotRow

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(1, 0)
    corner.Parent = dot

    local stroke = Instance.new("UIStroke")
    stroke.Color = UIConstants.Colors.StrokeWarm
    stroke.Thickness = 0.5
    stroke.Transparency = 0.4
    stroke.Parent = dot
end

makeDot(UIConstants.Colors.PearlBrown)
makeDot(UIConstants.Colors.PearlPink)
makeDot(UIConstants.Colors.PearlGreen)
makeDot(UIConstants.Colors.PearlWhite)

-- RichText body: key verbs are colored + bolded so the rules read with
-- some rhythm instead of as a wall of dark-brown text. "pop" / "Chain" /
-- "ice cubes" / "overflow" each take an accent color drawn from the
-- palette they actually represent in-game.
local label = Instance.new("TextLabel")
label.Size = UDim2.new(1, 0, 1, -20)
label.Position = UDim2.fromOffset(0, 20)
label.BackgroundTransparency = 1
label.TextColor3 = UIConstants.Colors.TextDark
label.TextWrapped = true
label.RichText = true
label.TextXAlignment = Enum.TextXAlignment.Left
label.TextYAlignment = Enum.TextYAlignment.Top
label.FontFace = UIConstants.Fonts.Tutorial
label.TextSize = UIConstants.TextSizes.Body
-- "pop" stays Coral (positive feedback). "overflow" uses the deeper
-- Warning hue (UIConstants.Colors.Warning = #C25C3F) so the lose-state
-- verb reads as worse than the celebratory pop verb.
label.Text = table.concat({
    "Match <b>4+</b> same-color pearls to <b><font color=\"rgb(255,138,124)\">pop</font></b>.",
    "<b><font color=\"rgb(255,175,195)\">Chain</font></b> pops send <b><font color=\"rgb(120,180,220)\">ice cubes</font></b> to your opponent.",
    "Don't <b><font color=\"rgb(194,92,63)\">overflow</font></b> your cup.",
}, "\n")
label.Parent = textWrapper

-- Direct child of card (not textWrapper) so the text-padding does not push
-- this off into the middle. Anchored to the card's actual top-right corner
-- with an 8px inset on both axes so the X sits flush in the corner.
local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.fromOffset(28, 28)
closeBtn.Position = UDim2.new(1, -8, 0, 8)
closeBtn.AnchorPoint = Vector2.new(1, 0)
closeBtn.Text = "×"
closeBtn.FontFace = UIConstants.Fonts.Display
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

-- Queue state (declared early so applyVisibility can see it).
-- queueActive = true while the timer is counting; flips to false after
-- cancel or timeout (the pill stays up but shows Search-again).
-- queuePillVisible = true while the pill is on-screen at all; the tutorial
-- card hides for the whole window the pill is up, not just while searching.
local queueStarted = tick()
local queueActive = true
local queuePillVisible = true

-- Debug override: when true, force the card visible regardless of the
-- DataStore-persisted dismiss attribute. Toggled by the corner "?" button
-- below. Remove the whole `Debug toggle` block (and the forceShow read in
-- applyVisibility) to retire this once we don't need it.
local forceShow = false

local function applyVisibility()
    -- forceShow is the explicit "I want to see the tutorial right now" signal
    -- from the ? button, and it has to win over the queue-pill auto-hide.
    -- Otherwise pressing ? while in the queue (i.e. basically always in the
    -- lobby) does nothing, because queuePillVisible would short-circuit first.
    if forceShow then
        card.Visible = true
        return
    end
    -- Tutorial card auto-hides while the queue pill is on-screen so the
    -- two cards never compete for attention. Re-shows once the pill slides
    -- away, unless the player has already dismissed the tutorial.
    if queuePillVisible then
        card.Visible = false
        return
    end
    card.Visible = not player:GetAttribute(ATTRIBUTE)
end

local function requestDismiss()
    squish(closeScale)
    forceShow = false
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

-- Queue pill: bottom-anchored, horizontal. Status text + subtitle on the
-- left, action button on the right. Slides up from below on start, slides
-- down on dismiss. Lives at the bottom so it doesn't fight the tutorial
-- card for the center of attention, and so the board (when present) reads
-- above it. Lobby ScreenGui keeps the default topbar inset, so a fixed
-- 24px bottom gap doubles as our safe-area buffer here.
local PILL_BOTTOM_OFFSET = 24
local PILL_HEIGHT = 92

local queuePanel = Instance.new("Frame")
queuePanel.Name = "Queue"
queuePanel.Size = UDim2.fromOffset(480, PILL_HEIGHT)
queuePanel.Position = UDim2.new(0.5, 0, 1, PILL_HEIGHT + 80) -- start off-screen below for slide-in
queuePanel.AnchorPoint = Vector2.new(0.5, 1)
queuePanel.BackgroundColor3 = UIConstants.Colors.Cream
queuePanel.BackgroundTransparency = 0
queuePanel.BorderSizePixel = 0
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

-- Status block on the left: title line + subtitle line (timer / hint).
-- Subtitle lives on its own line so the digit count growing from "9s" to
-- "10s" doesn't shift the title text horizontally.
local statusBlock = Instance.new("Frame")
statusBlock.Name = "Status"
statusBlock.Size = UDim2.new(1, -168, 1, 0) -- leave room for the 152-wide action button + padding
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

-- Subtitle wraps so the post-timeout copy ("No opponent yet...") can run
-- onto a second line if needed. Single-line "0s" / "4s" still sits at the
-- top of the slot because TextYAlignment is Top.
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

-- Slide animations. The pill's resting position is bottom-anchored with
-- a 24px gap (PILL_BOTTOM_OFFSET). It slides in from y = +200 below, and
-- slides back down to dismiss. Back/Out easing gives a slight overshoot
-- that feels game-y without being silly.
local PILL_RESTING_POSITION = UDim2.new(0.5, 0, 1, -PILL_BOTTOM_OFFSET)
local PILL_HIDDEN_POSITION = UDim2.new(0.5, 0, 1, 200)

local function slideIn()
    queuePanel.Position = PILL_HIDDEN_POSITION
    queuePanel.Visible = true
    queuePillVisible = true
    applyVisibility()
    TweenService:Create(
        queuePanel,
        UIConstants.tween(0.35, "UI"),
        { Position = PILL_RESTING_POSITION }
    ):Play()
end

-- slideOut is kept here for the eventual MatchFound / explicit-dismiss
-- handler. The Cancel button currently flips state in place rather than
-- dismissing, so this only runs when something else closes the queue.
local function slideOut()
    queuePillVisible = false
    applyVisibility()
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

-- Queue lifecycle: startQueue() drives the elapsed timer and flips
-- the cancel button into a Cancel / Search-again toggle, so the pill
-- always has an actionable button instead of an inert post-state.
local function setSearchAgainMode(subtitle)
    queueActive = false
    queueLabel.Text = "Queue canceled"
    subtitleLabel.Text = subtitle
    cancelBtn.Text = "Search again"
    cancelBtn.BackgroundColor3 = UIConstants.Colors.Peach
    cancelBtn.TextColor3 = UIConstants.Colors.TextDark
    applyVisibility()
end

local function startQueue()
    queueStarted = tick()
    queueActive = true
    queueLabel.Text = "Searching for opponent..."
    subtitleLabel.Text = "0s"
    cancelBtn.Text = "Cancel"
    cancelBtn.BackgroundColor3 = UIConstants.Colors.WarmCancel
    cancelBtn.TextColor3 = UIConstants.Colors.TextOnWarm
    applyVisibility()
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

slideIn()
startQueue()

cancelBtn.MouseButton1Click:Connect(function()
    squish(cancelScale)
    if queueActive then
        setSearchAgainMode("Tap Search again when you're ready.")
    else
        startQueue()
        -- TODO Day 4: fire a real RequeueRequest RemoteEvent if/when the server adds one.
    end
end)

-- Themes button: opens the Shop modal. Disabled (greyed) while the queue
-- is active so players can't accidentally buy mid-matchmaking.
local themesBtn = Instance.new("TextButton")
themesBtn.Name = "ThemesBtn"
themesBtn.Size = UDim2.fromOffset(132, 36)
themesBtn.Position = UDim2.new(1, -56, 0, 16)
themesBtn.AnchorPoint = Vector2.new(1, 0)
themesBtn.AutoButtonColor = false
themesBtn.BorderSizePixel = 0
themesBtn.BackgroundColor3 = UIConstants.Colors.Peach
themesBtn.TextColor3 = UIConstants.Colors.TextDark
themesBtn.FontFace = UIConstants.Fonts.Display
themesBtn.TextSize = UIConstants.TextSizes.HUDLabel
themesBtn.Text = "Themes"
themesBtn.Parent = screenGui

local themesCorner = Instance.new("UICorner")
themesCorner.CornerRadius = UIConstants.Corners.Button
themesCorner.Parent = themesBtn

local themesStroke = Instance.new("UIStroke")
themesStroke.Color = UIConstants.Colors.StrokeWarm
themesStroke.Thickness = 1.5
themesStroke.Transparency = 0.4
themesStroke.Parent = themesBtn

local themesScale = Instance.new("UIScale")
themesScale.Scale = 1
themesScale.Parent = themesBtn

-- Full color-swap between enabled (vibrant peach) and disabled (muted
-- cream) so the affordance is unambiguous, not just a transparency dim.
local function applyThemesEnabled()
    local enabled = not queueActive
    themesBtn.AutoButtonColor = enabled
    if enabled then
        themesBtn.BackgroundColor3 = UIConstants.Colors.Peach
        themesBtn.TextColor3 = UIConstants.Colors.TextDark
        themesBtn.BackgroundTransparency = 0
        themesBtn.TextTransparency = 0
        themesStroke.Color = UIConstants.Colors.StrokeWarm
        themesStroke.Transparency = 0.3
    else
        themesBtn.BackgroundColor3 = UIConstants.Colors.Cream
        themesBtn.TextColor3 = UIConstants.Colors.TextSoft
        themesBtn.BackgroundTransparency = 0.15
        themesBtn.TextTransparency = 0.2
        themesStroke.Color = UIConstants.Colors.StrokeSoft
        themesStroke.Transparency = 0.55
    end
end
applyThemesEnabled()

-- Poll queueActive once per second so the themes button updates after the
-- 60s timeout flips queueActive to false.
task.spawn(function()
    while themesBtn.Parent do
        applyThemesEnabled()
        task.wait(0.5)
    end
end)

themesBtn.MouseButton1Click:Connect(function()
    if queueActive then return end
    squish(themesScale)
    if _G.BobaDropShop then
        _G.BobaDropShop.open()
    end
end)

-- Settings (gear) button: sits to the left of the Themes button. Same
-- behavior pattern as Themes: full color-swap between enabled / disabled
-- while the queue is active so the affordance is unambiguous. Opens the
-- Settings modal via _G.BobaDropSettings.
local SETTINGS_WIDTH = 36
local THEMES_RIGHT_INSET = 56          -- existing themes button right inset
local THEMES_WIDTH = 132               -- matches themesBtn.Size above
local GAP = 8

local settingsBtn = Instance.new("TextButton")
settingsBtn.Name = "SettingsBtn"
settingsBtn.Size = UDim2.fromOffset(SETTINGS_WIDTH, 36)
settingsBtn.Position = UDim2.new(1, -(THEMES_RIGHT_INSET + THEMES_WIDTH + GAP), 0, 16)
settingsBtn.AnchorPoint = Vector2.new(1, 0)
settingsBtn.AutoButtonColor = false
settingsBtn.BorderSizePixel = 0
settingsBtn.BackgroundColor3 = UIConstants.Colors.Peach
settingsBtn.TextColor3 = UIConstants.Colors.TextDark
settingsBtn.FontFace = UIConstants.Fonts.Display
settingsBtn.TextSize = 20
-- Unicode gear glyph. FredokaOne doesn't ship symbol glyphs but Roblox
-- falls back through the system font for missing codepoints, so the gear
-- renders cleanly on every platform.
settingsBtn.Text = "\u{2699}"
settingsBtn.Parent = screenGui

local settingsCorner = Instance.new("UICorner")
settingsCorner.CornerRadius = UIConstants.Corners.Button
settingsCorner.Parent = settingsBtn

local settingsStroke = Instance.new("UIStroke")
settingsStroke.Color = UIConstants.Colors.StrokeWarm
settingsStroke.Thickness = 1.5
settingsStroke.Transparency = 0.4
settingsStroke.Parent = settingsBtn

local settingsScale = Instance.new("UIScale")
settingsScale.Scale = 1
settingsScale.Parent = settingsBtn

local function applySettingsEnabled()
    local enabled = not queueActive
    settingsBtn.AutoButtonColor = enabled
    if enabled then
        settingsBtn.BackgroundColor3 = UIConstants.Colors.Peach
        settingsBtn.TextColor3 = UIConstants.Colors.TextDark
        settingsBtn.BackgroundTransparency = 0
        settingsBtn.TextTransparency = 0
        settingsStroke.Color = UIConstants.Colors.StrokeWarm
        settingsStroke.Transparency = 0.3
    else
        settingsBtn.BackgroundColor3 = UIConstants.Colors.Cream
        settingsBtn.TextColor3 = UIConstants.Colors.TextSoft
        settingsBtn.BackgroundTransparency = 0.15
        settingsBtn.TextTransparency = 0.2
        settingsStroke.Color = UIConstants.Colors.StrokeSoft
        settingsStroke.Transparency = 0.55
    end
end
applySettingsEnabled()

-- GameState binding: the gear is only meaningful in lobby. Hide it (and
-- close the modal if it's open) the moment the player enters a match so
-- the in-match HUD stays uncluttered. The modal itself remains closeable
-- any time it's open even if state transitions mid-open.
local function refreshSettingsVisibility()
    local state = player:GetAttribute("GameState") or "lobby"
    settingsBtn.Visible = (state == "lobby")
    if state ~= "lobby" and _G.BobaDropSettings then
        _G.BobaDropSettings.close()
    end
end
refreshSettingsVisibility()
player:GetAttributeChangedSignal("GameState"):Connect(refreshSettingsVisibility)

-- Poll queueActive once per second so the gear updates after the 60s
-- timeout flips queueActive to false. Mirrors the Themes pattern.
task.spawn(function()
    while settingsBtn.Parent do
        applySettingsEnabled()
        task.wait(0.5)
    end
end)

settingsBtn.MouseButton1Click:Connect(function()
    if queueActive then return end
    squish(settingsScale)
    if _G.BobaDropSettings then
        _G.BobaDropSettings.open()
    end
end)

-- ── Debug toggle ────────────────────────────────────────────────────────
-- Tiny corner button to force-show the tutorial card during testing.
-- Safe to delete this whole block once the tutorial visuals are settled.
--
-- Open design question: should the ? button mute during queue the same
-- way the Themes button does? Themes mutes (good, no accidental buys mid-
-- queue). The ? is a debug affordance and stays full-color for now. See
-- Slack thread 1779258843 for the call.
local debugBtn = Instance.new("TextButton")
debugBtn.Name = "TutorialDebugToggle"
debugBtn.Size = UDim2.fromOffset(32, 32)
debugBtn.Position = UDim2.new(1, -16, 0, 16)
debugBtn.AnchorPoint = Vector2.new(1, 0)
debugBtn.AutoButtonColor = false
debugBtn.BorderSizePixel = 0
debugBtn.BackgroundColor3 = UIConstants.Colors.Cream
debugBtn.TextColor3 = UIConstants.Colors.TextDark
debugBtn.FontFace = UIConstants.Fonts.Display
debugBtn.TextSize = 18
debugBtn.Text = "?"
debugBtn.Parent = screenGui

local debugCorner = Instance.new("UICorner")
debugCorner.CornerRadius = UIConstants.Corners.Button
debugCorner.Parent = debugBtn

local debugStroke = Instance.new("UIStroke")
debugStroke.Color = UIConstants.Colors.StrokeWarm
debugStroke.Thickness = 1.5
debugStroke.Transparency = 0.4
debugStroke.Parent = debugBtn

local debugScale = Instance.new("UIScale")
debugScale.Scale = 1
debugScale.Parent = debugBtn

debugBtn.MouseButton1Click:Connect(function()
    squish(debugScale)
    forceShow = not forceShow
    applyVisibility()
end)
-- ─────────────────────────────────────────────────────────────────────────

screenGui.AncestryChanged:Connect(function(_, parent)
    if not parent then bobConn:Disconnect() end
end)
