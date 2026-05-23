-- Settings modal: music volume, sound fx volume, music on/off toggle.
-- Triggered by the lobby gear icon (top-right, left of the Themes button).
-- Only visible in lobby GameState; the gear hides + the modal closes when
-- the player enters a match. Persistence is per-session via LocalPlayer
-- attributes (BobaDropMusicVolume, BobaDropSoundFxVolume, BobaDropMusicEnabled).
-- AmbientLoop already listens for BobaDropMusicVolume and BobaDropMusicEnabled
-- so changes here take effect without any extra wiring.
--
-- v1.1 stretch (intentionally cut): high-contrast pearls toggle. The hook
-- point is the components list below; add a new row there when ready.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local UIConstants = require(ReplicatedStorage.Shared.UI.UIConstants)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Defensive UI-SFX trigger. UISfx.client.lua publishes _G.BobaDropSfx with
-- click/confirm/back/error functions; client script execution order isn't
-- deterministic so we guard against it loading after this one.
local function sfx(kind)
    if _G.BobaDropSfx and _G.BobaDropSfx[kind] then _G.BobaDropSfx[kind]() end
end

-- Attribute names match what AmbientLoop / future SFX listeners read.
local MUSIC_VOLUME_ATTR = "BobaDropMusicVolume"
local SFX_VOLUME_ATTR = "BobaDropSoundFxVolume"
local MUSIC_ENABLED_ATTR = "BobaDropMusicEnabled"

-- Defaults from spec: music 50, sfx 70, music enabled. Stored as 0-1 floats
-- on the player so AmbientLoop's clampVolume() reads them directly.
local DEFAULT_MUSIC = 0.5
local DEFAULT_SFX = 0.7
local DEFAULT_MUSIC_ENABLED = true

local function readMusic()
    local v = player:GetAttribute(MUSIC_VOLUME_ATTR)
    if typeof(v) ~= "number" then return DEFAULT_MUSIC end
    if v < 0 then return 0 end
    if v > 1 then return 1 end
    return v
end

local function readSfx()
    local v = player:GetAttribute(SFX_VOLUME_ATTR)
    if typeof(v) ~= "number" then return DEFAULT_SFX end
    if v < 0 then return 0 end
    if v > 1 then return 1 end
    return v
end

local function readMusicEnabled()
    local v = player:GetAttribute(MUSIC_ENABLED_ATTR)
    if typeof(v) ~= "boolean" then return DEFAULT_MUSIC_ENABLED end
    return v
end

-- Seed defaults on first load so AmbientLoop sees sane starting volumes
-- even before the player ever opens the panel.
if player:GetAttribute(MUSIC_VOLUME_ATTR) == nil then
    player:SetAttribute(MUSIC_VOLUME_ATTR, DEFAULT_MUSIC)
end
if player:GetAttribute(SFX_VOLUME_ATTR) == nil then
    player:SetAttribute(SFX_VOLUME_ATTR, DEFAULT_SFX)
end
if player:GetAttribute(MUSIC_ENABLED_ATTR) == nil then
    player:SetAttribute(MUSIC_ENABLED_ATTR, DEFAULT_MUSIC_ENABLED)
end

--------------------------------------------------------------------------------
-- ScreenGui + scrim + modal shell
--------------------------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "Settings"
gui.ResetOnSpawn = false
-- One above ShopOverlay so Settings can sit on top of an open Shop if both
-- ever overlap. In practice they're mutually exclusive in lobby flow.
gui.DisplayOrder = UIConstants.ZOrder.ShopOverlay + 1
-- IgnoreGuiInset = false so the modal centers inside the safe area
-- (below the Roblox topbar) on mobile.
gui.IgnoreGuiInset = false
gui.Parent = playerGui

-- Scrim and modal both Active=true so clicks don't pass through to MainMenu
-- buttons (PLAY etc.) sitting behind. The scrim InputBegan handler at the
-- bottom of this file relies on Active=true to fire on a Frame click.
local scrim = Instance.new("Frame")
scrim.Name = "Scrim"
scrim.Active = true
scrim.Size = UDim2.fromScale(1, 1)
-- Scrim is fully transparent — Sarah didn't want the dark wash behind
-- modals. Frame stays Active=true to capture outside-modal clicks for
-- close-via-InputBegan.
scrim.BackgroundTransparency = 1
scrim.BorderSizePixel = 0
scrim.Visible = false
scrim.Parent = gui

local modal = Instance.new("Frame")
modal.Name = "Modal"
modal.Active = true
-- Viewport-adaptive sizing: 92% wide × 85% tall, clamped between mobile-
-- friendly minimum and desktop-friendly maximum. Fixed 480×420 was
-- overflowing landscape phones (~750×414) so the bottom toggle got
-- clipped. Mirrors the pattern ThemesInventory.client.lua uses.
modal.Size = UDim2.new(0.92, 0, 0.85, 0)
modal.Position = UDim2.fromScale(0.5, 0.5)
modal.AnchorPoint = Vector2.new(0.5, 0.5)
modal.BackgroundColor3 = UIConstants.Colors.Cream
modal.BorderSizePixel = 0
modal.Visible = false
modal.Parent = gui

local modalSizeConstraint = Instance.new("UISizeConstraint")
modalSizeConstraint.MinSize = Vector2.new(280, 260)
modalSizeConstraint.MaxSize = Vector2.new(480, 420)
modalSizeConstraint.Parent = modal

local modalCorner = Instance.new("UICorner")
modalCorner.CornerRadius = UIConstants.Corners.Panel
modalCorner.Parent = modal

local modalStroke = Instance.new("UIStroke")
modalStroke.Color = UIConstants.Colors.StrokeWarm
modalStroke.Thickness = 2
modalStroke.Transparency = 0.4
modalStroke.Parent = modal

local modalPadding = Instance.new("UIPadding")
modalPadding.PaddingTop = UDim.new(0, 24)
modalPadding.PaddingBottom = UDim.new(0, 20)
modalPadding.PaddingLeft = UDim.new(0, 28)
modalPadding.PaddingRight = UDim.new(0, 28)
modalPadding.Parent = modal

--------------------------------------------------------------------------------
-- Title
--------------------------------------------------------------------------------

local title = Instance.new("TextLabel")
title.Name = "Title"
title.Size = UDim2.new(1, 0, 0, 40)
title.Position = UDim2.fromOffset(0, 0)
title.BackgroundTransparency = 1
title.FontFace = UIConstants.Fonts.Display
title.TextSize = 32
title.TextColor3 = UIConstants.Colors.TextDark
title.TextXAlignment = Enum.TextXAlignment.Center
title.TextYAlignment = Enum.TextYAlignment.Center
title.Text = "SETTINGS"
title.Parent = modal

--------------------------------------------------------------------------------
-- Close (X) top-right
--------------------------------------------------------------------------------

local closeBtn = Instance.new("TextButton")
closeBtn.Name = "Close"
closeBtn.Size = UDim2.fromOffset(36, 36)
closeBtn.Position = UDim2.new(1, -8, 0, 8)
closeBtn.AnchorPoint = Vector2.new(1, 0)
closeBtn.Text = "×"
closeBtn.FontFace = UIConstants.Fonts.Display
closeBtn.TextSize = 26
closeBtn.TextColor3 = UIConstants.Colors.TextOnWarm
closeBtn.BackgroundColor3 = UIConstants.Colors.WarmCancel
closeBtn.BorderSizePixel = 0
closeBtn.AutoButtonColor = false
closeBtn.Parent = modal

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

--------------------------------------------------------------------------------
-- Slider widget (drag-to-set)
--   - Track: full-width pill, soft cream surface
--   - Fill: peach pill that grows from the left as the value rises
--   - Thumb: round mint dot anchored to the right edge of the fill
--   - Drag from anywhere on the track. Tap-to-jump also works.
--
-- value is reported as 0-1; the label shows 0-100% so it reads like a
-- normal volume slider.
--------------------------------------------------------------------------------

local function makeSlider(parent, opts)
    local row = Instance.new("Frame")
    row.Name = opts.name .. "Row"
    row.Size = UDim2.new(1, 0, 0, 64)
    row.Position = UDim2.fromOffset(0, opts.y)
    row.BackgroundTransparency = 1
    row.Parent = parent

    local label = Instance.new("TextLabel")
    label.Name = "Label"
    label.Size = UDim2.new(1, -60, 0, 22)
    label.Position = UDim2.fromOffset(0, 0)
    label.BackgroundTransparency = 1
    label.FontFace = UIConstants.Fonts.HUD
    label.TextSize = UIConstants.TextSizes.Body
    label.TextColor3 = UIConstants.Colors.TextDark
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextYAlignment = Enum.TextYAlignment.Center
    label.Text = opts.label
    label.Parent = row

    local pct = Instance.new("TextLabel")
    pct.Name = "Percent"
    pct.Size = UDim2.fromOffset(56, 22)
    pct.Position = UDim2.new(1, 0, 0, 0)
    pct.AnchorPoint = Vector2.new(1, 0)
    pct.BackgroundTransparency = 1
    pct.FontFace = UIConstants.Fonts.HUD
    pct.TextSize = UIConstants.TextSizes.Body
    pct.TextColor3 = UIConstants.Colors.TextSoft
    pct.TextXAlignment = Enum.TextXAlignment.Right
    pct.TextYAlignment = Enum.TextYAlignment.Center
    pct.Text = "0%"
    pct.Parent = row

    local track = Instance.new("Frame")
    track.Name = "Track"
    track.Size = UDim2.new(1, 0, 0, 18)
    track.Position = UDim2.fromOffset(0, 36)
    track.BackgroundColor3 = UIConstants.Colors.Backdrop
    track.BorderSizePixel = 0
    track.Parent = row

    local trackCorner = Instance.new("UICorner")
    trackCorner.CornerRadius = UIConstants.Corners.Pill
    trackCorner.Parent = track

    local trackStroke = Instance.new("UIStroke")
    trackStroke.Color = UIConstants.Colors.StrokeSoft
    trackStroke.Thickness = 1
    trackStroke.Transparency = 0.4
    trackStroke.Parent = track

    local fill = Instance.new("Frame")
    fill.Name = "Fill"
    fill.Size = UDim2.fromScale(0, 1)
    fill.Position = UDim2.fromScale(0, 0)
    fill.BackgroundColor3 = UIConstants.Colors.Peach
    fill.BorderSizePixel = 0
    fill.Parent = track

    local fillCorner = Instance.new("UICorner")
    fillCorner.CornerRadius = UIConstants.Corners.Pill
    fillCorner.Parent = fill

    local thumb = Instance.new("Frame")
    thumb.Name = "Thumb"
    thumb.Size = UDim2.fromOffset(26, 26)
    thumb.Position = UDim2.fromScale(0, 0.5)
    thumb.AnchorPoint = Vector2.new(0.5, 0.5)
    thumb.BackgroundColor3 = UIConstants.Colors.Mint
    thumb.BorderSizePixel = 0
    thumb.ZIndex = 2
    thumb.Parent = track

    local thumbCorner = Instance.new("UICorner")
    thumbCorner.CornerRadius = UDim.new(1, 0)
    thumbCorner.Parent = thumb

    local thumbStroke = Instance.new("UIStroke")
    thumbStroke.Color = UIConstants.Colors.StrokeWarm
    thumbStroke.Thickness = 1.5
    thumbStroke.Transparency = 0.3
    thumbStroke.Parent = thumb

    local function apply(v)
        if v < 0 then v = 0 end
        if v > 1 then v = 1 end
        fill.Size = UDim2.new(v, 0, 1, 0)
        thumb.Position = UDim2.new(v, 0, 0.5, 0)
        pct.Text = ("%d%%"):format(math.floor(v * 100 + 0.5))
    end

    local dragging = false

    local function valueFromInput(input)
        local absPos = track.AbsolutePosition.X
        local absSize = track.AbsoluteSize.X
        if absSize <= 0 then return 0 end
        local x = input.Position.X - absPos
        local v = x / absSize
        if v < 0 then v = 0 end
        if v > 1 then v = 1 end
        return v
    end

    track.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            local v = valueFromInput(input)
            apply(v)
            opts.onChange(v)
        end
    end)

    -- Listen globally for drag motion so the slider keeps tracking even when
    -- the cursor leaves the track bounds during a drag.
    UserInputService.InputChanged:Connect(function(input)
        if not dragging then return end
        if input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch then
            local v = valueFromInput(input)
            apply(v)
            opts.onChange(v)
        end
    end)

    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)

    apply(opts.initial)

    return { apply = apply }
end

--------------------------------------------------------------------------------
-- Toggle switch widget (two-state mint / soft-gray pill, horizontal tween)
--------------------------------------------------------------------------------

local function makeToggle(parent, opts)
    local row = Instance.new("Frame")
    row.Name = opts.name .. "Row"
    row.Size = UDim2.new(1, 0, 0, 40)
    row.Position = UDim2.fromOffset(0, opts.y)
    row.BackgroundTransparency = 1
    row.Parent = parent

    local label = Instance.new("TextLabel")
    label.Name = "Label"
    label.Size = UDim2.new(1, -80, 1, 0)
    label.Position = UDim2.fromOffset(0, 0)
    label.BackgroundTransparency = 1
    label.FontFace = UIConstants.Fonts.HUD
    label.TextSize = UIConstants.TextSizes.Body
    label.TextColor3 = UIConstants.Colors.TextDark
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextYAlignment = Enum.TextYAlignment.Center
    label.Text = opts.label
    label.Parent = row

    local btn = Instance.new("TextButton")
    btn.Name = "Switch"
    btn.Size = UDim2.fromOffset(56, 30)
    btn.Position = UDim2.new(1, 0, 0.5, 0)
    btn.AnchorPoint = Vector2.new(1, 0.5)
    btn.AutoButtonColor = false
    btn.BorderSizePixel = 0
    btn.Text = ""
    btn.BackgroundColor3 = UIConstants.Colors.Mint
    btn.Parent = row

    local btnCorner = Instance.new("UICorner")
    btnCorner.CornerRadius = UIConstants.Corners.Pill
    btnCorner.Parent = btn

    local btnStroke = Instance.new("UIStroke")
    btnStroke.Color = UIConstants.Colors.StrokeWarm
    btnStroke.Thickness = 1.5
    btnStroke.Transparency = 0.3
    btnStroke.Parent = btn

    local knob = Instance.new("Frame")
    knob.Name = "Knob"
    knob.Size = UDim2.fromOffset(24, 24)
    knob.Position = UDim2.new(1, -3, 0.5, 0)
    knob.AnchorPoint = Vector2.new(1, 0.5)
    knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    knob.BorderSizePixel = 0
    knob.Parent = btn

    local knobCorner = Instance.new("UICorner")
    knobCorner.CornerRadius = UDim.new(1, 0)
    knobCorner.Parent = knob

    -- Soft-gray off-state. StrokeSoft is the closest existing token; using it
    -- directly as a surface keeps the palette tidy without adding a token.
    local OFF_COLOR = UIConstants.Colors.StrokeSoft

    local function apply(on, animate)
        local targetBg = on and UIConstants.Colors.Mint or OFF_COLOR
        local targetKnob = on
            and UDim2.new(1, -3, 0.5, 0)
            or UDim2.new(0, 3, 0.5, 0)
        local targetAnchor = on and Vector2.new(1, 0.5) or Vector2.new(0, 0.5)
        if animate then
            TweenService:Create(
                btn,
                TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                { BackgroundColor3 = targetBg }
            ):Play()
            knob.AnchorPoint = targetAnchor
            TweenService:Create(
                knob,
                TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                { Position = targetKnob }
            ):Play()
        else
            btn.BackgroundColor3 = targetBg
            knob.AnchorPoint = targetAnchor
            knob.Position = targetKnob
        end
    end

    btn.MouseButton1Click:Connect(function()
        sfx("click")
        local nextValue = not opts.read()
        apply(nextValue, true)
        opts.onChange(nextValue)
    end)

    apply(opts.initial, false)

    return { apply = apply }
end

--------------------------------------------------------------------------------
-- Component layout: title (top), three rows. Credits removed 2026-05-21.
-- Modal interior height after padding is 420 - 24 - 20 = 376.
--   y =  0  title (40 high)
--   y = 64  music volume slider (64 high)
--   y = 140 sfx volume slider     (64 high)
--   y = 216 music toggle          (40 high)
--------------------------------------------------------------------------------

local musicSlider = makeSlider(modal, {
    name = "MusicVolume",
    label = "MUSIC VOLUME",
    y = 64,
    initial = readMusic(),
    onChange = function(v)
        player:SetAttribute(MUSIC_VOLUME_ATTR, v)
    end,
})

local sfxSlider = makeSlider(modal, {
    name = "SfxVolume",
    label = "SOUND FX",
    y = 140,
    initial = readSfx(),
    onChange = function(v)
        player:SetAttribute(SFX_VOLUME_ATTR, v)
    end,
})

local musicToggle = makeToggle(modal, {
    name = "MusicEnabled",
    label = "PLAY MUSIC",
    y = 216,
    initial = readMusicEnabled(),
    read = readMusicEnabled,
    onChange = function(on)
        player:SetAttribute(MUSIC_ENABLED_ATTR, on)
    end,
})

-- Credits line removed 2026-05-21 to match the MainMenu credit drop
-- (commit 443ee80). The Settings modal ends at the music toggle row;
-- bottom padding from modalPadding (20px) is the visual breathing room.

--------------------------------------------------------------------------------
-- Reflect external attribute changes (e.g. if some other system writes the
-- attribute) back into the UI so the panel never goes stale.
--------------------------------------------------------------------------------

player:GetAttributeChangedSignal(MUSIC_VOLUME_ATTR):Connect(function()
    musicSlider.apply(readMusic())
end)
player:GetAttributeChangedSignal(SFX_VOLUME_ATTR):Connect(function()
    sfxSlider.apply(readSfx())
end)
player:GetAttributeChangedSignal(MUSIC_ENABLED_ATTR):Connect(function()
    musicToggle.apply(readMusicEnabled(), true)
end)

--------------------------------------------------------------------------------
-- Open / close. setOpen flips scrim + modal visibility together.
-- Exposed on _G.BobaDropSettings so Lobby.client.lua can open it without
-- needing to RequireChild a sibling ScreenGui.
--------------------------------------------------------------------------------

local function setOpen(open)
    scrim.Visible = open
    modal.Visible = open
end

closeBtn.MouseButton1Click:Connect(function()
    sfx("back")
    squish(closeScale)
    setOpen(false)
end)

-- Close on scrim click only when the click landed OUTSIDE the modal rect.
-- modal.Active=true alone doesn't stop scrim.InputBegan from firing for
-- modal-internal clicks (Roblox bubbles input through the hierarchy).
scrim.InputBegan:Connect(function(input)
    if input.UserInputType ~= Enum.UserInputType.MouseButton1
        and input.UserInputType ~= Enum.UserInputType.Touch then
        return
    end
    local pos = input.Position
    local rectPos = modal.AbsolutePosition
    local rectSize = modal.AbsoluteSize
    local insideModal = pos.X >= rectPos.X
        and pos.X <= rectPos.X + rectSize.X
        and pos.Y >= rectPos.Y
        and pos.Y <= rectPos.Y + rectSize.Y
    if not insideModal then
        setOpen(false)
    end
end)

_G.BobaDropSettings = {
    open = function() setOpen(true) end,
    close = function() setOpen(false) end,
}
