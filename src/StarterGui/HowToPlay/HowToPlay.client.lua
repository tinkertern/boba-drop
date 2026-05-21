-- HowToPlay: in-game ? overlay teaching controls + chain mechanics.
--
-- A small "?" pill sits above the LEAVE corner button while
-- GameState == "in_match". Tapping it slides a modal panel up from below
-- with controls (keyboard + touch), the goal, and three tips. GOT IT
-- pill closes the modal. The "?" pulses gently so first-time players
-- notice it without it becoming visual noise during play.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIConstants = require(ReplicatedStorage.Shared.UI.UIConstants)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

--------------------------------------------------------------------------------
-- ScreenGui (always Enabled; visibility gated per element)
--------------------------------------------------------------------------------

local screen = Instance.new("ScreenGui")
screen.Name = "HowToPlay"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = true
-- Sit above BlockedFlash, but below PauseConfirm (200). 130 keeps it
-- above HUD layers while letting the LEAVE-confirm modal cover us if
-- both happened to be visible at the same time.
screen.DisplayOrder = UIConstants.ZOrder.BlockedFlash + 20
screen.Enabled = true
screen.Parent = playerGui

--------------------------------------------------------------------------------
-- "?" pill: top-right, 80px LEFT of the LEAVE pill
--------------------------------------------------------------------------------

local questionBtn = Instance.new("TextButton")
questionBtn.Name = "QuestionBtn"
questionBtn.AnchorPoint = Vector2.new(1, 0)
-- LEAVE pill sits at (1, -16, 0, 16) ~88w. We want to sit clearly LEFT
-- of it; (1, -100, 0, 20) leaves a ~12px gap and aligns the visual baseline.
questionBtn.Position = UDim2.new(1, -100, 0, 20)
questionBtn.Size = UDim2.fromOffset(36, 36)
questionBtn.AutoButtonColor = false
questionBtn.BorderSizePixel = 0
questionBtn.BackgroundColor3 = UIConstants.Colors.Cream
questionBtn.TextColor3 = UIConstants.Colors.TextDark
questionBtn.FontFace = UIConstants.Fonts.Display
questionBtn.TextSize = 20
questionBtn.Text = "?"
questionBtn.Visible = false
questionBtn.Parent = screen

local questionCorner = Instance.new("UICorner")
questionCorner.CornerRadius = UIConstants.Corners.Pearl
questionCorner.Parent = questionBtn

local questionStroke = Instance.new("UIStroke")
questionStroke.Color = UIConstants.Colors.StrokeWarm
questionStroke.Thickness = 2
questionStroke.Transparency = 0.5
questionStroke.Parent = questionBtn

local questionScale = Instance.new("UIScale")
questionScale.Scale = 1
questionScale.Parent = questionBtn

--------------------------------------------------------------------------------
-- Modal scrim + panel
--------------------------------------------------------------------------------

local scrim = Instance.new("Frame")
scrim.Name = "Scrim"
scrim.Size = UDim2.fromScale(1, 1)
scrim.BackgroundColor3 = UIConstants.Colors.WarmDark
scrim.BackgroundTransparency = 0.45 -- visual @ 0.55 opacity per spec
scrim.BorderSizePixel = 0
scrim.Visible = false
scrim.Parent = screen

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 1.2) -- starts off-screen below
panel.Size = UDim2.fromOffset(520, 600)
panel.BackgroundColor3 = UIConstants.Colors.Cream
panel.BorderSizePixel = 0
panel.Parent = scrim

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UIConstants.Corners.Panel
panelCorner.Parent = panel

local panelStroke = Instance.new("UIStroke")
panelStroke.Color = UIConstants.Colors.StrokeWarm
panelStroke.Thickness = 2
panelStroke.Transparency = 0.5
panelStroke.Parent = panel

local panelPadding = Instance.new("UIPadding")
panelPadding.PaddingTop = UDim.new(0, 22)
panelPadding.PaddingBottom = UDim.new(0, 22)
panelPadding.PaddingLeft = UDim.new(0, 24)
panelPadding.PaddingRight = UDim.new(0, 24)
panelPadding.Parent = panel

-- Vertical stack list so sections flow top-to-bottom without manual Y math
local panelList = Instance.new("UIListLayout")
panelList.FillDirection = Enum.FillDirection.Vertical
panelList.SortOrder = Enum.SortOrder.LayoutOrder
panelList.HorizontalAlignment = Enum.HorizontalAlignment.Center
panelList.Padding = UDim.new(0, 14)
panelList.Parent = panel

--------------------------------------------------------------------------------
-- Section helpers
--------------------------------------------------------------------------------

local function makeTitle(layoutOrder)
    local title = Instance.new("TextLabel")
    title.Name = "Title"
    title.LayoutOrder = layoutOrder
    title.Size = UDim2.new(1, 0, 0, 36)
    title.BackgroundTransparency = 1
    title.FontFace = UIConstants.Fonts.Display
    title.TextSize = 32
    title.TextColor3 = UIConstants.Colors.TextDark
    title.Text = "HOW TO PLAY"
    title.TextXAlignment = Enum.TextXAlignment.Center
    title.Parent = panel
    return title
end

local function makeHeading(layoutOrder, text)
    local heading = Instance.new("TextLabel")
    heading.Name = text .. "Heading"
    heading.LayoutOrder = layoutOrder
    heading.Size = UDim2.new(1, 0, 0, 22)
    heading.BackgroundTransparency = 1
    heading.FontFace = UIConstants.Fonts.Display
    heading.TextSize = 18
    heading.TextColor3 = UIConstants.Colors.TextDark
    heading.Text = text
    heading.TextXAlignment = Enum.TextXAlignment.Left
    heading.Parent = panel
    return heading
end

local function makeBodyLine(parent, layoutOrder, richText)
    local label = Instance.new("TextLabel")
    label.Name = "BodyLine" .. tostring(layoutOrder)
    label.LayoutOrder = layoutOrder
    label.Size = UDim2.new(1, 0, 0, 20)
    label.BackgroundTransparency = 1
    label.FontFace = UIConstants.Fonts.HUD
    label.TextSize = 14
    label.TextColor3 = UIConstants.Colors.TextDark
    label.RichText = true
    label.Text = richText
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextYAlignment = Enum.TextYAlignment.Top
    label.TextWrapped = true
    label.Parent = parent
    return label
end

--------------------------------------------------------------------------------
-- 1. Title
--------------------------------------------------------------------------------

makeTitle(1)

--------------------------------------------------------------------------------
-- 2. CONTROLS section (heading + two-column row)
--------------------------------------------------------------------------------

makeHeading(2, "CONTROLS")

local controlsRow = Instance.new("Frame")
controlsRow.Name = "ControlsRow"
controlsRow.LayoutOrder = 3
controlsRow.Size = UDim2.new(1, 0, 0, 140)
controlsRow.BackgroundTransparency = 1
controlsRow.Parent = panel

local controlsRowList = Instance.new("UIListLayout")
controlsRowList.FillDirection = Enum.FillDirection.Horizontal
controlsRowList.SortOrder = Enum.SortOrder.LayoutOrder
controlsRowList.HorizontalAlignment = Enum.HorizontalAlignment.Center
controlsRowList.VerticalAlignment = Enum.VerticalAlignment.Top
controlsRowList.Padding = UDim.new(0, 16)
controlsRowList.Parent = controlsRow

local function makeControlColumn(layoutOrder, columnTitle, lines)
    local col = Instance.new("Frame")
    col.Name = columnTitle .. "Column"
    col.LayoutOrder = layoutOrder
    -- Each column ~half panel inner width minus row padding
    col.Size = UDim2.new(0.5, -8, 1, 0)
    col.BackgroundTransparency = 1
    col.Parent = controlsRow

    local colList = Instance.new("UIListLayout")
    colList.FillDirection = Enum.FillDirection.Vertical
    colList.SortOrder = Enum.SortOrder.LayoutOrder
    colList.HorizontalAlignment = Enum.HorizontalAlignment.Left
    colList.Padding = UDim.new(0, 6)
    colList.Parent = col

    local sub = Instance.new("TextLabel")
    sub.Name = "SubHeading"
    sub.LayoutOrder = 1
    sub.Size = UDim2.new(1, 0, 0, 18)
    sub.BackgroundTransparency = 1
    sub.FontFace = UIConstants.Fonts.HUD
    sub.TextSize = 14
    sub.TextColor3 = UIConstants.Colors.TextSoft
    sub.Text = columnTitle
    sub.TextXAlignment = Enum.TextXAlignment.Left
    sub.Parent = col

    for i, lineText in ipairs(lines) do
        makeBodyLine(col, i + 1, lineText)
    end

    return col
end

makeControlColumn(1, "KEYBOARD", {
    "<b>&#8592; &#8594;</b>  move left/right",
    "<b>Z</b>  rotate counter-clockwise",
    "<b>X</b>  rotate clockwise",
    "<b>&#8595;</b>  soft drop (hold)",
    "<b>Space</b>  hard drop",
})

makeControlColumn(2, "TOUCH", {
    "drag piece to move",
    "tap piece to rotate",
    "swipe down to hard drop",
})

--------------------------------------------------------------------------------
-- 3. GOAL section
--------------------------------------------------------------------------------

makeHeading(4, "GOAL")

local goalBlock = Instance.new("Frame")
goalBlock.Name = "GoalBlock"
goalBlock.LayoutOrder = 5
goalBlock.Size = UDim2.new(1, 0, 0, 80)
goalBlock.BackgroundTransparency = 1
goalBlock.Parent = panel

local goalList = Instance.new("UIListLayout")
goalList.FillDirection = Enum.FillDirection.Vertical
goalList.SortOrder = Enum.SortOrder.LayoutOrder
goalList.HorizontalAlignment = Enum.HorizontalAlignment.Left
goalList.Padding = UDim.new(0, 4)
goalList.Parent = goalBlock

local function rgbHex(c)
    return string.format("#%02X%02X%02X", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end

local coralHex = rgbHex(UIConstants.Colors.Coral)
local pinkHex = rgbHex(UIConstants.Colors.PearlPink)
local iceHex = rgbHex(UIConstants.Colors.IceBase)
local warnHex = rgbHex(UIConstants.Colors.Warning)

makeBodyLine(goalBlock, 1,
    'Match <b>4 same-color pearls</b> to <b><font color="' .. coralHex .. '">pop</font></b> them.')
makeBodyLine(goalBlock, 2,
    'Pop <b><font color="' .. pinkHex .. '">chains</font></b> (cascading pops) to send <b><font color="' .. iceHex .. '">ice cubes</font></b> to your opponent.')
makeBodyLine(goalBlock, 3,
    'First cup to <b><font color="' .. warnHex .. '">overflow</font></b> loses.')

--------------------------------------------------------------------------------
-- 4. TIPS section
--------------------------------------------------------------------------------

makeHeading(6, "TIPS")

local tipsBlock = Instance.new("Frame")
tipsBlock.Name = "TipsBlock"
tipsBlock.LayoutOrder = 7
tipsBlock.Size = UDim2.new(1, 0, 0, 80)
tipsBlock.BackgroundTransparency = 1
tipsBlock.Parent = panel

local tipsList = Instance.new("UIListLayout")
tipsList.FillDirection = Enum.FillDirection.Vertical
tipsList.SortOrder = Enum.SortOrder.LayoutOrder
tipsList.HorizontalAlignment = Enum.HorizontalAlignment.Left
tipsList.Padding = UDim.new(0, 4)
tipsList.Parent = tipsBlock

makeBodyLine(tipsBlock, 1, "&#8226;  <b>Stack same colors</b> in vertical columns for easy 4-pops.")
makeBodyLine(tipsBlock, 2, "&#8226;  <b>Chain reactions</b> score more and send more garbage.")
makeBodyLine(tipsBlock, 3, "&#8226;  <b>Watch your danger row</b>. When it pulses fast, you're close to losing.")

--------------------------------------------------------------------------------
-- 5. GOT IT close button (full width pill at bottom)
--------------------------------------------------------------------------------

local closeBtn = Instance.new("TextButton")
closeBtn.Name = "GotItBtn"
closeBtn.LayoutOrder = 8
closeBtn.Size = UDim2.new(1, 0, 0, 52)
closeBtn.AutoButtonColor = false
closeBtn.BorderSizePixel = 0
closeBtn.BackgroundColor3 = UIConstants.Colors.Mint
closeBtn.TextColor3 = UIConstants.Colors.TextDark
closeBtn.FontFace = UIConstants.Fonts.Display
closeBtn.TextSize = 22
closeBtn.Text = "GOT IT"
closeBtn.Parent = panel

local closeCorner = Instance.new("UICorner")
closeCorner.CornerRadius = UIConstants.Corners.Button
closeCorner.Parent = closeBtn

local closeStroke = Instance.new("UIStroke")
closeStroke.Color = UIConstants.Colors.StrokeWarm
closeStroke.Thickness = 2
closeStroke.Transparency = 0.5
closeStroke.Parent = closeBtn

local closeScale = Instance.new("UIScale")
closeScale.Scale = 1
closeScale.Parent = closeBtn

--------------------------------------------------------------------------------
-- Motion helpers
--------------------------------------------------------------------------------

local function squish(scaleObj)
    scaleObj.Scale = UIConstants.Motion.ButtonPressScale
    TweenService:Create(
        scaleObj,
        UIConstants.tween(UIConstants.Durations.ButtonPress, "UI"),
        { Scale = 1 }
    ):Play()
end

local OPEN_DURATION = 0.35
local CLOSE_DURATION = 0.25
local isOpen = false

local function openModal()
    if isOpen then return end
    isOpen = true
    scrim.Visible = true
    panel.Visible = true
    panel.Position = UDim2.fromScale(0.5, 1.2)
    TweenService:Create(
        panel,
        UIConstants.tween(OPEN_DURATION, "UI"),
        { Position = UDim2.fromScale(0.5, 0.5) }
    ):Play()
end

local function closeModal()
    if not isOpen then return end
    isOpen = false
    local tween = TweenService:Create(
        panel,
        UIConstants.tween(CLOSE_DURATION, "UIIn"),
        { Position = UDim2.fromScale(0.5, 1.2) }
    )
    tween.Completed:Connect(function()
        -- Re-check in case we re-opened mid-tween
        if not isOpen then
            scrim.Visible = false
        end
    end)
    tween:Play()
end

--------------------------------------------------------------------------------
-- "?" pulse: subtle 1.0 -> 1.05 -> 1.0 sine over 4s, loops while visible
--------------------------------------------------------------------------------

local PULSE_PERIOD = 4
local pulseUp = TweenService:Create(
    questionScale,
    TweenInfo.new(PULSE_PERIOD / 2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
    { Scale = 1.05 }
)
local pulseDown = TweenService:Create(
    questionScale,
    TweenInfo.new(PULSE_PERIOD / 2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
    { Scale = 1.0 }
)

local pulseActive = false
local function startPulse()
    if pulseActive then return end
    pulseActive = true
    pulseUp:Play()
end

local function stopPulse()
    pulseActive = false
    pulseUp:Cancel()
    pulseDown:Cancel()
    questionScale.Scale = 1
end

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

--------------------------------------------------------------------------------
-- GameState binding: "?" only visible in_match
--------------------------------------------------------------------------------

local function refreshVisibility()
    local state = player:GetAttribute("GameState")
    local inMatch = (state == "in_match")
    questionBtn.Visible = inMatch
    if inMatch then
        startPulse()
    else
        stopPulse()
        -- If we left the match while modal was open, snap it closed silently.
        if isOpen then
            isOpen = false
            scrim.Visible = false
            panel.Position = UDim2.fromScale(0.5, 1.2)
        end
    end
end

refreshVisibility()
player:GetAttributeChangedSignal("GameState"):Connect(refreshVisibility)

--------------------------------------------------------------------------------
-- Click handlers
--------------------------------------------------------------------------------

questionBtn.MouseButton1Click:Connect(function()
    squish(questionScale)
    openModal()
end)

closeBtn.MouseButton1Click:Connect(function()
    squish(closeScale)
    closeModal()
end)

-- Exposed on _G.BobaDropHowToPlay so the MainMenu can surface the same modal
-- from its "?" pill. The in-match "?" button still drives openModal directly;
-- this is a parallel entry point, not a replacement.
_G.BobaDropHowToPlay = {
    open = openModal,
    close = closeModal,
}
