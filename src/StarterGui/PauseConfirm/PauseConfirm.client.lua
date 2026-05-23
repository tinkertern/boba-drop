-- PauseConfirm: in-match modal to forfeit cleanly via LeaveMatch RemoteEvent.
--
-- ScreenGui stays Enabled at all times (simpler than threading another entry
-- through UIStateController). The small LEAVE button in the top-right is shown
-- only while GameState == "in_match". The modal frame stays Visible = false
-- until the player taps LEAVE, then slides up over a warm scrim.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local UIConstants = require(ReplicatedStorage.Shared.UI.UIConstants)
local Events = require(ReplicatedStorage.Shared.Events)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Defensive UI-SFX trigger. UISfx.client.lua publishes _G.BobaDropSfx with
-- click/confirm/back/error functions; client script execution order isn't
-- deterministic so we guard against it loading after this one.
local function sfx(kind)
    if _G.BobaDropSfx and _G.BobaDropSfx[kind] then _G.BobaDropSfx[kind]() end
end

--------------------------------------------------------------------------------
-- ScreenGui
--------------------------------------------------------------------------------

local screen = Instance.new("ScreenGui")
screen.Name = "PauseConfirm"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = true
-- Above MatchEnd (RoundBanner=80) and any HUD layer. UIConstants.ZOrder has no
-- Modal entry yet, so pick something higher than the highest existing layer
-- (BlockedFlash = 110) without editing UIConstants.
screen.DisplayOrder = 200
screen.Enabled = true
screen.Parent = playerGui

--------------------------------------------------------------------------------
-- Top-right LEAVE button (in-match only)
--------------------------------------------------------------------------------

local leaveCorner = Instance.new("TextButton")
leaveCorner.Name = "LeaveCornerBtn"
leaveCorner.AnchorPoint = Vector2.new(1, 0)
leaveCorner.Position = UDim2.new(1, -16, 0, 16)
leaveCorner.Size = UDim2.fromOffset(88, 44)
leaveCorner.AutoButtonColor = false
leaveCorner.BorderSizePixel = 0
-- Resting state uses Peach (warmer, less aggressive) so a glance at the
-- top-right pill doesn't read as a panic / "you're about to lose" state.
-- The destructive confirm button inside the modal still uses WarmCancel,
-- which keeps the "this is the final commitment" weight on the right
-- element. Coral / WarmCancel here read as too alarming during normal play.
leaveCorner.BackgroundColor3 = UIConstants.Colors.Peach
leaveCorner.TextColor3 = UIConstants.Colors.TextDark
leaveCorner.FontFace = UIConstants.Fonts.Display
leaveCorner.TextSize = UIConstants.TextSizes.SmallButton
leaveCorner.Text = "LEAVE"
leaveCorner.Visible = false
leaveCorner.Parent = screen

local leaveCornerRadius = Instance.new("UICorner")
leaveCornerRadius.CornerRadius = UIConstants.Corners.Button
leaveCornerRadius.Parent = leaveCorner

local leaveCornerStroke = Instance.new("UIStroke")
leaveCornerStroke.Color = UIConstants.Colors.StrokeWarm
leaveCornerStroke.Thickness = 2
leaveCornerStroke.Transparency = 0.5
leaveCornerStroke.Parent = leaveCorner

local leaveCornerScale = Instance.new("UIScale")
leaveCornerScale.Scale = 1
leaveCornerScale.Parent = leaveCorner

--------------------------------------------------------------------------------
-- Modal scrim + panel
--------------------------------------------------------------------------------

local scrim = Instance.new("Frame")
scrim.Name = "Scrim"
scrim.Size = UDim2.fromScale(1, 1)
scrim.BackgroundColor3 = UIConstants.Colors.WarmDark
scrim.BackgroundTransparency = 0.45 -- final visual at 0.55 opacity (1 - 0.45 alpha)
scrim.BorderSizePixel = 0
scrim.Visible = false
scrim.Parent = screen

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 1.2) -- starts off-screen below
panel.Size = UDim2.fromOffset(360, 200)
panel.BackgroundColor3 = UIConstants.Colors.Cream
panel.BorderSizePixel = 0
panel.Parent = scrim

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UIConstants.Corners.Panel
panelCorner.Parent = panel

local panelStroke = Instance.new("UIStroke")
panelStroke.Color = UIConstants.Colors.StrokeWarm
panelStroke.Thickness = 2
panelStroke.Transparency = 0.4
panelStroke.Parent = panel

local panelPadding = Instance.new("UIPadding")
panelPadding.PaddingTop = UDim.new(0, 20)
panelPadding.PaddingBottom = UDim.new(0, 20)
panelPadding.PaddingLeft = UDim.new(0, 20)
panelPadding.PaddingRight = UDim.new(0, 20)
panelPadding.Parent = panel

local title = Instance.new("TextLabel")
title.Name = "Title"
title.Size = UDim2.new(1, 0, 0, 32)
title.Position = UDim2.fromOffset(0, 0)
title.BackgroundTransparency = 1
title.FontFace = UIConstants.Fonts.Display
title.TextSize = 24
title.TextColor3 = UIConstants.Colors.TextDark
title.Text = "LEAVE MATCH?"
title.TextXAlignment = Enum.TextXAlignment.Center
title.Parent = panel

local body = Instance.new("TextLabel")
body.Name = "Body"
body.Size = UDim2.new(1, 0, 0, 24)
body.Position = UDim2.fromOffset(0, 40)
body.BackgroundTransparency = 1
body.FontFace = UIConstants.Fonts.HUD
body.TextSize = 14
body.TextColor3 = UIConstants.Colors.TextSoft
body.Text = "Your opponent will win by forfeit."
body.TextXAlignment = Enum.TextXAlignment.Center
body.TextWrapped = true
body.Parent = panel

--------------------------------------------------------------------------------
-- STAY / LEAVE buttons (side by side at bottom of panel)
--------------------------------------------------------------------------------

local function makeModalButton(name, text, bgColor, textColor, anchorRight)
    local btn = Instance.new("TextButton")
    btn.Name = name
    -- Buttons share the panel's inner width (320px after 20px padding both
    -- sides). Each is (320 - 12 gap) / 2 = 154px wide.
    btn.Size = UDim2.fromOffset(154, 52)
    if anchorRight then
        btn.AnchorPoint = Vector2.new(1, 1)
        btn.Position = UDim2.new(1, 0, 1, 0)
    else
        btn.AnchorPoint = Vector2.new(0, 1)
        btn.Position = UDim2.new(0, 0, 1, 0)
    end
    btn.AutoButtonColor = false
    btn.BorderSizePixel = 0
    btn.BackgroundColor3 = bgColor
    btn.TextColor3 = textColor
    btn.FontFace = UIConstants.Fonts.Display
    btn.TextSize = 22
    btn.Text = text
    btn.Parent = panel

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UIConstants.Corners.Button
    corner.Parent = btn

    local scale = Instance.new("UIScale")
    scale.Scale = 1
    scale.Parent = btn

    return btn, scale
end

local stayBtn, stayScale = makeModalButton(
    "StayBtn",
    "STAY",
    UIConstants.Colors.Mint,
    UIConstants.Colors.TextDark,
    false
)
local confirmLeaveBtn, confirmLeaveScale = makeModalButton(
    "LeaveBtn",
    "LEAVE",
    UIConstants.Colors.WarmCancel,
    UIConstants.Colors.TextOnWarm,
    true
)

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

local SLIDE_DURATION = 0.25

-- Copy adapts to MatchMode. Versus = forfeit warning, practice = run-abandon.
local function refreshCopy()
    local matchMode = player:GetAttribute("MatchMode")
    if matchMode == "practice" then
        title.Text = "LEAVE RUN?"
        body.Text = "Your progress this run will be lost."
    else
        title.Text = "LEAVE MATCH?"
        body.Text = "Your opponent will win by forfeit."
    end
end

local function openModal()
    refreshCopy()
    scrim.Visible = true
    panel.Position = UDim2.fromScale(0.5, 1.2)
    TweenService:Create(
        panel,
        UIConstants.tween(SLIDE_DURATION, "UI"),
        { Position = UDim2.fromScale(0.5, 0.5) }
    ):Play()
end

local function closeModal()
    local tween = TweenService:Create(
        panel,
        UIConstants.tween(SLIDE_DURATION, "UIIn"),
        { Position = UDim2.fromScale(0.5, 1.2) }
    )
    tween.Completed:Connect(function()
        scrim.Visible = false
    end)
    tween:Play()
end

--------------------------------------------------------------------------------
-- LEAVE button visibility follows GameState attribute
--------------------------------------------------------------------------------

local function refreshLeaveCornerVisibility()
    local state = player:GetAttribute("GameState")
    leaveCorner.Visible = (state == "in_match")
    -- Hide modal if we leave the in_match state (e.g. server forces match_end).
    if state ~= "in_match" and scrim.Visible then
        scrim.Visible = false
        panel.Position = UDim2.fromScale(0.5, 1.2)
    end
end

refreshLeaveCornerVisibility()
player:GetAttributeChangedSignal("GameState"):Connect(refreshLeaveCornerVisibility)

--------------------------------------------------------------------------------
-- Wire up remote + click handlers
--------------------------------------------------------------------------------

local remotes = ReplicatedStorage:WaitForChild("Remotes", 30)
if not remotes then return end

local leaveName = Events.Names.LeaveMatch
if not leaveName then return end

local leaveRemote = remotes:WaitForChild(leaveName, 30)
if not leaveRemote then return end

-- Optional: server gates on MatchMode == "practice" already, but we also
-- gate client-side so we don't FireServer on every versus pause-modal open.
local pauseRemote = remotes:WaitForChild("PauseRequest", 10)

local function requestPause(paused)
    if not pauseRemote then return end
    if player:GetAttribute("MatchMode") ~= "practice" then return end
    pauseRemote:FireServer({ paused = paused })
end

leaveCorner.MouseButton1Click:Connect(function()
    sfx("click")
    squish(leaveCornerScale)
    openModal()
    requestPause(true)
end)

stayBtn.MouseButton1Click:Connect(function()
    sfx("click")
    squish(stayScale)
    closeModal()
    requestPause(false)
end)

confirmLeaveBtn.MouseButton1Click:Connect(function()
    sfx("back")
    squish(confirmLeaveScale)
    -- LeaveMatch ends the run anyway, so no resume needed. Server clears
    -- the pause latch in _closeRoom.
    leaveRemote:FireServer({})
    closeModal()
end)
