-- Shop modal for Premium Themes Pack.
-- Hidden by default. Opens via _G.BobaDropShop.open() from the lobby
-- Themes button (Day 3) or from the post-match prompt (≤1×/session for
-- the losing player). Visual is final; opener wiring lands when the
-- lobby Themes button is added.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local TweenService = game:GetService("TweenService")

local UIConstants = require(ReplicatedStorage.Shared.UI.UIConstants)
local Themes = require(ReplicatedStorage.Shared.UI.Themes)
local Events = require(ReplicatedStorage.Shared.Events)

local PREMIUM_THEMES_ID = 1846258540

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Defensive UI-SFX trigger. UISfx.client.lua publishes _G.BobaDropSfx with
-- click/confirm/back/error functions; client script execution order isn't
-- deterministic so we guard against it loading after this one.
local function sfx(kind)
    if _G.BobaDropSfx and _G.BobaDropSfx[kind] then _G.BobaDropSfx[kind]() end
end

local gui = Instance.new("ScreenGui")
gui.Name = "Shop"
gui.ResetOnSpawn = false
gui.DisplayOrder = UIConstants.ZOrder.ShopOverlay
-- IgnoreGuiInset = false so the modal centers inside the safe area
-- (below the Roblox topbar) instead of bleeding the title up under it
-- on landscape mobile.
gui.IgnoreGuiInset = false
gui.Parent = playerGui

-- Scrim behind the modal so the lobby/match-end UI dims when the shop is
-- open. Uses WarmDark (the warm-brown wash) at 0.55 transparency so the
-- dim reads as a cozy tint rather than the muddy near-black a neutral
-- gray would give. Preserves contrast against the cream modal card.
-- Active=true on both scrim and modal so clicks don't fall through to
-- MainMenu PLAY etc. behind. Scrim click → close (handler below); modal
-- click is absorbed silently.
local scrim = Instance.new("Frame")
scrim.Name = "Scrim"
scrim.Active = true
scrim.Size = UDim2.fromScale(1, 1)
scrim.BackgroundColor3 = UIConstants.Colors.WarmDark
scrim.BackgroundTransparency = 0.55
scrim.BorderSizePixel = 0
scrim.Visible = false
scrim.Parent = gui

local modal = Instance.new("Frame")
modal.Name = "Modal"
modal.Active = true
-- Viewport-adaptive sizing so the "Buy for 99 R$" button at the bottom
-- doesn't clip off landscape phones. 92% × 85% with mobile/desktop clamp.
modal.Size = UDim2.new(0.92, 0, 0.85, 0)
modal.Position = UDim2.fromScale(0.5, 0.5)
modal.AnchorPoint = Vector2.new(0.5, 0.5)
modal.BackgroundColor3 = UIConstants.Colors.Cream
modal.BackgroundTransparency = 0
modal.BorderSizePixel = 0
modal.Visible = false
modal.Parent = gui

local modalSizeConstraint = Instance.new("UISizeConstraint")
modalSizeConstraint.MinSize = Vector2.new(300, 304)
modalSizeConstraint.MaxSize = Vector2.new(420, 460)
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
modalPadding.PaddingTop = UDim.new(0, 20)
modalPadding.PaddingBottom = UDim.new(0, 20)
modalPadding.PaddingLeft = UDim.new(0, 20)
modalPadding.PaddingRight = UDim.new(0, 20)
modalPadding.Parent = modal

-- Top-down UIListLayout so children flow naturally (title → body →
-- preview swatches → buttons) without fixed offsets that collide when
-- the modal hits its min height. Padding 10 between sections.
local modalLayout = Instance.new("UIListLayout")
modalLayout.FillDirection = Enum.FillDirection.Vertical
modalLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
modalLayout.VerticalAlignment = Enum.VerticalAlignment.Top
modalLayout.SortOrder = Enum.SortOrder.LayoutOrder
modalLayout.Padding = UDim.new(0, 10)
modalLayout.Parent = modal

local title = Instance.new("TextLabel")
title.Name = "Title"
title.LayoutOrder = 1
title.Size = UDim2.new(1, 0, 0, 36)
title.BackgroundTransparency = 1
title.FontFace = UIConstants.Fonts.Display
title.TextSize = UIConstants.TextSizes.Score
title.TextColor3 = UIConstants.Colors.TextDark
title.Text = "Premium Themes Pack"
title.Parent = modal

-- Soft warm-cream stroke gives the chunky FredokaOne title an extra hint
-- of weight without losing the cozy feel.
local titleStroke = Instance.new("UIStroke")
titleStroke.Color = UIConstants.Colors.StrokeWarm
titleStroke.Thickness = 2
titleStroke.Transparency = 0.35
titleStroke.Parent = title

-- RichText body: theme names colored to each theme's signature pearl
-- so the description scans as a tasting-menu instead of a uniform line.
-- "Gameplay-neutral" softened to TextSoft so the theme names lead the eye.
local body = Instance.new("TextLabel")
body.Name = "Body"
body.LayoutOrder = 2
body.Size = UDim2.new(1, 0, 0, 64)
body.BackgroundTransparency = 1
body.FontFace = UIConstants.Fonts.Tutorial
body.TextSize = UIConstants.TextSizes.Body
body.TextColor3 = UIConstants.Colors.TextDark
body.TextWrapped = true
body.RichText = true
body.TextXAlignment = Enum.TextXAlignment.Left
body.TextYAlignment = Enum.TextYAlignment.Top
body.Text = table.concat({
    "Three cosmetic cup themes:",
    "<b><font color=\"rgb(184,121,74)\">Brown Sugar Boba</font></b>, <b><font color=\"rgb(255,156,181)\">Strawberry Milk</font></b>, <b><font color=\"rgb(135,169,107)\">Matcha</font></b>.",
    "<font color=\"rgb(120,90,70)\"><i>Gameplay-neutral. Just for the vibes.</i></font>",
}, "\n")
body.Parent = modal

-- Theme preview swatches: three pearls in each theme's signature color.
-- 104 px tall (was 90) so the label band underneath the pearls has room
-- for "Brown Sugar Boba" to wrap to two lines without spilling out of
-- the cell.
local previewRow = Instance.new("Frame")
previewRow.Name = "PreviewRow"
previewRow.LayoutOrder = 3
previewRow.Size = UDim2.new(1, 0, 0, 96)
previewRow.BackgroundTransparency = 1
previewRow.Parent = modal

local previewLayout = Instance.new("UIListLayout")
previewLayout.FillDirection = Enum.FillDirection.Horizontal
previewLayout.Padding = UDim.new(0, 8)
previewLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
previewLayout.VerticalAlignment = Enum.VerticalAlignment.Center
previewLayout.SortOrder = Enum.SortOrder.LayoutOrder
previewLayout.Parent = previewRow

local function previewSwatch(theme, order)
    local cell = Instance.new("Frame")
    cell.Name = theme.name
    cell.Size = UDim2.new(1/3, -8, 1, 0)
    cell.BackgroundColor3 = theme.CupTint
    cell.BorderSizePixel = 0
    cell.LayoutOrder = order
    cell.Parent = previewRow

    local cellCorner = Instance.new("UICorner")
    cellCorner.CornerRadius = UIConstants.Corners.Card
    cellCorner.Parent = cell

    local cellStroke = Instance.new("UIStroke")
    cellStroke.Color = UIConstants.Colors.StrokeSoft
    cellStroke.Thickness = 1
    cellStroke.Transparency = 0.5
    cellStroke.Parent = cell

    local function pearl(color, posX, posY, size)
        local p = Instance.new("Frame")
        p.Size = UDim2.fromOffset(size, size)
        p.Position = UDim2.fromScale(posX, posY)
        p.AnchorPoint = Vector2.new(0.5, 0.5)
        p.BackgroundColor3 = color
        p.BorderSizePixel = 0
        p.Parent = cell

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UIConstants.Corners.Pearl
        corner.Parent = p

        -- Warm stroke so cream-coloured pearls stay visible against the
        -- cup-tint background of each swatch (cup tints can be near-cream).
        local pearlStroke = Instance.new("UIStroke")
        pearlStroke.Color = UIConstants.Colors.StrokeWarm
        pearlStroke.Thickness = 1.5
        pearlStroke.Transparency = 0.2
        pearlStroke.Parent = p

        local highlight = Instance.new("Frame")
        highlight.Size = UIConstants.Pearl.HighlightSize
        highlight.Position = UIConstants.Pearl.HighlightPosition
        highlight.AnchorPoint = UIConstants.Pearl.HighlightAnchor
        highlight.BackgroundColor3 = UIConstants.Colors.PearlHighlight
        highlight.BackgroundTransparency = UIConstants.Pearl.HighlightTransparency
        highlight.BorderSizePixel = 0
        highlight.Parent = p

        local highlightCorner = Instance.new("UICorner")
        highlightCorner.CornerRadius = UIConstants.Corners.Pearl
        highlightCorner.Parent = highlight
    end

    -- Pearl Y positions lifted (0.40 → 0.32, 0.60 → 0.50) so the taller
    -- label band underneath has clear room.
    pearl(theme.PearlBrown, 0.27, 0.32, 28)
    pearl(theme.PearlPink, 0.5, 0.5, 28)
    pearl(theme.PearlGreen, 0.73, 0.32, 28)

    -- All three label boxes share a 2-line minimum height + Top alignment
    -- so the labels align consistently across cards regardless of whether
    -- the name wraps. Previously "Matcha" centered in a 32px slot while
    -- "Brown Sugar Boba" filled it, making the cards bottom-align
    -- unevenly. Top alignment plants every name on the same baseline.
    local LABEL_LINE_HEIGHT = 16
    local LABEL_HEIGHT = LABEL_LINE_HEIGHT * 2
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -8, 0, LABEL_HEIGHT)
    label.Position = UDim2.new(0, 4, 1, -LABEL_HEIGHT - 4)
    label.BackgroundTransparency = 1
    label.FontFace = UIConstants.Fonts.HUD
    label.TextSize = UIConstants.TextSizes.HUDLabel
    label.TextColor3 = UIConstants.Colors.TextDark
    label.TextWrapped = true
    label.TextXAlignment = Enum.TextXAlignment.Center
    label.TextYAlignment = Enum.TextYAlignment.Top
    label.Text = theme.name
    label.Parent = cell

    -- Soft warm outline so the name reads as a chunky label on top of
    -- the cup-tint background instead of as flat text. Subtle on
    -- purpose — the swatch is the hero, not the label.
    local labelStroke = Instance.new("UIStroke")
    labelStroke.Color = UIConstants.Colors.StrokeWarm
    labelStroke.Thickness = 1
    labelStroke.Transparency = 0.55
    labelStroke.Parent = label
end

previewSwatch(Themes.BrownSugarBoba, 1)
previewSwatch(Themes.StrawberryMilk, 2)
previewSwatch(Themes.Matcha, 3)

-- Buy + close buttons live inside a buttonRow Frame so they flow with the
-- modal's UIListLayout (sits beneath the preview swatches). Each button
-- uses Scale X (48%) so they fit on landscape mobile without overlapping
-- the cards above.
local buttonRow = Instance.new("Frame")
buttonRow.Name = "ButtonRow"
buttonRow.LayoutOrder = 4
buttonRow.Size = UDim2.new(1, 0, 0, 52)
buttonRow.BackgroundTransparency = 1
buttonRow.Parent = modal

-- The Buy button uses Coral (the chain-gradient end color) as a primary
-- accent so it does not blend with the Brown Sugar swatch's peach
-- background in the preview row. Cream text + warm stroke for contrast.
local function makeBtn(name, text, opts)
    local btn = Instance.new("TextButton")
    btn.Name = name
    btn.Size = UDim2.new(0.48, 0, 1, 0)
    if opts.anchorX == 0 then
        btn.AnchorPoint = Vector2.new(0, 0)
        btn.Position = UDim2.new(0, 0, 0, 0)
    else
        btn.AnchorPoint = Vector2.new(1, 0)
        btn.Position = UDim2.new(1, 0, 0, 0)
    end
    btn.AutoButtonColor = false
    btn.BorderSizePixel = 0
    btn.BackgroundColor3 = opts.bg
    btn.TextColor3 = opts.text
    btn.FontFace = UIConstants.Fonts.Display
    btn.TextSize = UIConstants.TextSizes.Body
    btn.Text = text
    btn.Parent = buttonRow

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UIConstants.Corners.Button
    corner.Parent = btn

    if opts.stroke then
        local stroke = Instance.new("UIStroke")
        stroke.Color = opts.stroke
        stroke.Thickness = 2
        stroke.Transparency = 0.3
        stroke.Parent = btn
    end

    local scale = Instance.new("UIScale")
    scale.Scale = 1
    scale.Parent = btn

    return btn, scale
end

local buyBtn, buyScale = makeBtn("BuyBtn", "Buy for 99 R$", {
    bg = UIConstants.Colors.Coral,
    text = UIConstants.Colors.TextOnWarm,
    stroke = UIConstants.Colors.StrokeWarm,
    anchorX = 0,
})
local closeBtn, closeScale = makeBtn("CloseBtn", "Close", {
    bg = UIConstants.Colors.Mint,
    text = UIConstants.Colors.TextDark,
    anchorX = 1,
})

local function squish(target)
    target.Scale = UIConstants.Motion.ButtonPressScale
    TweenService:Create(
        target,
        UIConstants.tween(UIConstants.Durations.ButtonPress, "UI"),
        { Scale = 1 }
    ):Play()
end

local function setOpen(open)
    scrim.Visible = open
    modal.Visible = open
end

buyBtn.MouseButton1Click:Connect(function()
    sfx("confirm")
    squish(buyScale)
    MarketplaceService:PromptGamePassPurchase(player, PREMIUM_THEMES_ID)
end)

closeBtn.MouseButton1Click:Connect(function()
    sfx("back")
    squish(closeScale)
    setOpen(false)
end)

-- Tapping the scrim closes the modal, but only when the click landed
-- OUTSIDE the modal rect. modal.Active=true alone doesn't stop
-- scrim.InputBegan from firing for modal-internal clicks (Roblox bubbles
-- input through the hierarchy).
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

_G.BobaDropShop = {
    open = function() setOpen(true) end,
    close = function() setOpen(false) end,
}

-- Removed the auto-prompt-on-loss flow at Sarah's request 2026-05-20: the
-- Shop should only open via explicit user action (Themes button in lobby
-- or _G.BobaDropShop.open() from a script). The previous behavior surprised
-- the losing player by popping the shop modal 2s after match-end.
