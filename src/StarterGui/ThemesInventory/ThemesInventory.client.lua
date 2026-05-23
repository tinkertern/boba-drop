-- ThemesInventory modal: 2x2 grid of theme cards (Default + the 3 Premium
-- themes). Each card shows the theme name, a 4-pearl swatch row, and a
-- state button: EQUIPPED (mint, disabled), EQUIP (peach, sets active theme),
-- or LOCKED (warm-cancel, opens the Shop). Hidden by default; opens via
-- _G.BobaDropThemes.open() from the MainMenu THEMES pill.
--
-- State plumbing:
--   * player attribute BobaDropOwnsPremiumThemes mirrors the server-side
--     GamePasses cache; refreshes when it flips (mid-session purchase).
--   * player attribute BobaDropActiveTheme is written client-side on equip
--     (session-only; DataStore persistence is v1.1).
--   * Visibility is gated by GameState == "main_menu" so trying to open the
--     inventory mid-match is a silent no-op.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local UIConstants = require(ReplicatedStorage.Shared.UI.UIConstants)
local Themes = require(ReplicatedStorage.Shared.UI.Themes)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Attributes
local OWNS_ATTR = "BobaDropOwnsPremiumThemes"
local ACTIVE_ATTR = "BobaDropActiveTheme"

-- Defensive UI-SFX trigger. UISfx.client.lua publishes _G.BobaDropSfx with
-- click/confirm/back/error functions; client script execution order isn't
-- deterministic so we guard against it loading after this one.
local function sfx(kind)
    if _G.BobaDropSfx and _G.BobaDropSfx[kind] then _G.BobaDropSfx[kind]() end
end

local function readOwns()
    return player:GetAttribute(OWNS_ATTR) == true
end

local function readActive()
    local v = player:GetAttribute(ACTIVE_ATTR)
    if typeof(v) ~= "string" or v == "" then return "Default" end
    return v
end

--------------------------------------------------------------------------------
-- ScreenGui + scrim + panel shell
--------------------------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "ThemesInventory"
gui.ResetOnSpawn = false
-- One above Settings (ShopOverlay + 1) so themes can sit on top of shop
-- and settings if any overlap occurs. In practice the inventory is the
-- only modal that opens from the THEMES pill.
gui.DisplayOrder = UIConstants.ZOrder.ShopOverlay + 2
-- IgnoreGuiInset = false so the modal centers inside the safe area
-- (below the Roblox topbar) on mobile.
gui.IgnoreGuiInset = false
gui.Parent = playerGui

-- Scrim and modal both Active=true so clicks don't pass through to MainMenu
-- buttons behind. The scrim InputBegan handler near the bottom does a bounds
-- check against the modal rect before closing, since Roblox bubbles input
-- through the hierarchy even when modal.Active=true.
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

-- Panel height is viewport-relative (viewport_height - 48px) clamped to a
-- comfortable range. On short viewports the inner ScrollingFrame takes
-- over so the grid stays reachable; on tall viewports the panel caps
-- out instead of growing into wasted whitespace.
local PANEL_ONSCREEN = UDim2.fromScale(0.5, 0.5)
local PANEL_OFFSCREEN = UDim2.new(0.5, 0, 0.55, 0)

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.Active = true
panel.Size = UDim2.new(0, 580, 1, -48)
panel.Position = PANEL_OFFSCREEN
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.BackgroundColor3 = UIConstants.Colors.Cream
panel.BorderSizePixel = 0
panel.Visible = false
panel.Parent = gui

local panelSize = Instance.new("UISizeConstraint")
panelSize.MinSize = Vector2.new(580, 320)
panelSize.MaxSize = Vector2.new(580, 560)
panelSize.Parent = panel

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UIConstants.Corners.Panel
panelCorner.Parent = panel

local panelStroke = Instance.new("UIStroke")
panelStroke.Color = UIConstants.Colors.StrokeWarm
panelStroke.Thickness = 2
panelStroke.Transparency = 0.4
panelStroke.Parent = panel

local panelPadding = Instance.new("UIPadding")
panelPadding.PaddingTop = UDim.new(0, 24)
panelPadding.PaddingBottom = UDim.new(0, 24)
panelPadding.PaddingLeft = UDim.new(0, 24)
panelPadding.PaddingRight = UDim.new(0, 24)
panelPadding.Parent = panel

--------------------------------------------------------------------------------
-- Title + close (X)
-- Both are parented directly to the panel, NOT to the grid wrapper. The grid
-- wrapper holds ONLY card cells so UIGridLayout doesn't slot the title as a
-- grid item (a footgun from prior bugs).
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
title.Text = "MY THEMES"
title.Parent = panel

local closeBtn = Instance.new("TextButton")
closeBtn.Name = "Close"
closeBtn.Size = UDim2.fromOffset(36, 36)
closeBtn.Position = UDim2.new(1, -8, 0, 8)
closeBtn.AnchorPoint = Vector2.new(1, 0)
closeBtn.Text = "\u{00D7}"
closeBtn.FontFace = UIConstants.Fonts.Display
closeBtn.TextSize = 26
closeBtn.TextColor3 = UIConstants.Colors.TextOnWarm
closeBtn.BackgroundColor3 = UIConstants.Colors.WarmCancel
closeBtn.BorderSizePixel = 0
closeBtn.AutoButtonColor = false
closeBtn.Parent = panel

local closeCorner = Instance.new("UICorner")
closeCorner.CornerRadius = UIConstants.Corners.Button
closeCorner.Parent = closeBtn

local closeScale = Instance.new("UIScale")
closeScale.Scale = 1
closeScale.Parent = closeBtn

local function squish(scaleObj)
    scaleObj.Scale = UIConstants.Motion.ButtonPressScale
    TweenService:Create(
        scaleObj,
        UIConstants.tween(UIConstants.Durations.ButtonPress, "UI"),
        { Scale = 1 }
    ):Play()
end

--------------------------------------------------------------------------------
-- Grid wrapper: holds the 4 card cells only. Title + close sit OUTSIDE it so
-- the UIGridLayout does not slot them as grid items.
--------------------------------------------------------------------------------

-- ScrollingFrame holds the 2x2 card grid. Cells are fixed-offset so they
-- don't shrink with the panel; CanvasSize tracks the grid's content size
-- so the scrollbar appears only when the panel is too short for all cards.
local gridWrap = Instance.new("ScrollingFrame")
gridWrap.Name = "GridWrap"
gridWrap.Size = UDim2.new(1, 0, 1, -56)
gridWrap.Position = UDim2.fromOffset(0, 56)
gridWrap.BackgroundTransparency = 1
gridWrap.BorderSizePixel = 0
gridWrap.ScrollBarThickness = 6
gridWrap.ScrollBarImageColor3 = UIConstants.Colors.StrokeWarm
gridWrap.ScrollingDirection = Enum.ScrollingDirection.Y
gridWrap.CanvasSize = UDim2.fromOffset(0, 0)
gridWrap.ClipsDescendants = true
gridWrap.Parent = panel

local grid = Instance.new("UIGridLayout")
grid.Name = "Grid"
grid.CellSize = UDim2.fromOffset(250, 210)
grid.CellPadding = UDim2.fromOffset(16, 16)
grid.FillDirection = Enum.FillDirection.Horizontal
grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
grid.VerticalAlignment = Enum.VerticalAlignment.Top
grid.SortOrder = Enum.SortOrder.LayoutOrder
grid.StartCorner = Enum.StartCorner.TopLeft
grid.Parent = gridWrap

-- Inset the scroll content slightly so card UIStrokes (which render half
-- outside the card bounds) don't get cropped by the ScrollingFrame's
-- ClipsDescendants. 4px on each side is enough to clear a 1.5px stroke.
local gridPadding = Instance.new("UIPadding")
gridPadding.PaddingTop = UDim.new(0, 4)
gridPadding.PaddingBottom = UDim.new(0, 4)
gridPadding.PaddingLeft = UDim.new(0, 4)
gridPadding.PaddingRight = UDim.new(0, 4)
gridPadding.Parent = gridWrap

grid:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    gridWrap.CanvasSize = UDim2.fromOffset(0, grid.AbsoluteContentSize.Y + 8)
end)

--------------------------------------------------------------------------------
-- Card factory. Each card has:
--   - Theme name (top, colored by theme.PearlBrown for character)
--   - 4-pearl swatch row (Brown, Pink, Green, White)
--   - State button (EQUIPPED / EQUIP / LOCKED), bottom of the card
-- The state button's handler is rebuilt every refresh() since which state
-- a given card is in can flip between equip <-> equipped on a click.
--------------------------------------------------------------------------------

local cards = {}  -- themeKey -> { card, nameLabel, pearls = {f1..f4}, button, buttonLabel, buttonScale }

local function buildCard(themeKey, layoutOrder)
    local theme = Themes.byKey(themeKey)

    local card = Instance.new("Frame")
    card.Name = themeKey .. "Card"
    card.BackgroundColor3 = UIConstants.Colors.Cream
    card.BorderSizePixel = 0
    card.LayoutOrder = layoutOrder
    card.Parent = gridWrap

    local cardCorner = Instance.new("UICorner")
    cardCorner.CornerRadius = UIConstants.Corners.Card
    cardCorner.Parent = card

    local cardStroke = Instance.new("UIStroke")
    cardStroke.Color = UIConstants.Colors.StrokeWarm
    cardStroke.Thickness = 1.5
    cardStroke.Transparency = 0.45
    cardStroke.Parent = card

    -- Subtle theme-tinted background overlay so each card carries a hint of
    -- its theme's flavor without overwhelming the swatches. Sits behind the
    -- card children at the same UICorner radius.
    local tint = Instance.new("Frame")
    tint.Name = "Tint"
    tint.Size = UDim2.fromScale(1, 1)
    tint.BackgroundColor3 = theme.CupTint
    tint.BackgroundTransparency = 0.65
    tint.BorderSizePixel = 0
    tint.ZIndex = 0
    tint.Parent = card

    local tintCorner = Instance.new("UICorner")
    tintCorner.CornerRadius = UIConstants.Corners.Card
    tintCorner.Parent = tint

    --
    -- Name label
    --
    local nameLabel = Instance.new("TextLabel")
    nameLabel.Name = "Name"
    nameLabel.Size = UDim2.new(1, -16, 0, 28)
    nameLabel.Position = UDim2.fromOffset(8, 10)
    nameLabel.BackgroundTransparency = 1
    nameLabel.FontFace = UIConstants.Fonts.Display
    nameLabel.TextSize = 20
    nameLabel.TextColor3 = theme.PearlBrown
    nameLabel.TextXAlignment = Enum.TextXAlignment.Center
    nameLabel.TextYAlignment = Enum.TextYAlignment.Center
    nameLabel.TextWrapped = true
    nameLabel.Text = theme.name
    nameLabel.ZIndex = 2
    nameLabel.Parent = card

    local nameStroke = Instance.new("UIStroke")
    nameStroke.Color = UIConstants.Colors.StrokeWarm
    nameStroke.Thickness = 1
    nameStroke.Transparency = 0.6
    nameStroke.Parent = nameLabel

    --
    -- Pearl swatch row (4 pearls). Wraps a Frame whose ONLY children are the
    -- 4 pearls plus a UIListLayout. No grid here so we can freely add a
    -- UIListLayout without sibling-slot issues.
    --
    local pearlRow = Instance.new("Frame")
    pearlRow.Name = "PearlRow"
    pearlRow.Size = UDim2.new(1, -16, 0, 32)
    pearlRow.Position = UDim2.fromOffset(8, 48)
    pearlRow.BackgroundTransparency = 1
    pearlRow.ZIndex = 2
    pearlRow.Parent = card

    local pearlLayout = Instance.new("UIListLayout")
    pearlLayout.FillDirection = Enum.FillDirection.Horizontal
    pearlLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    pearlLayout.VerticalAlignment = Enum.VerticalAlignment.Center
    pearlLayout.Padding = UDim.new(0, 10)
    pearlLayout.SortOrder = Enum.SortOrder.LayoutOrder
    pearlLayout.Parent = pearlRow

    local function makePearl(color, order)
        local p = Instance.new("Frame")
        p.Name = "Pearl" .. tostring(order)
        p.Size = UDim2.fromOffset(28, 28)
        p.BackgroundColor3 = color
        p.BorderSizePixel = 0
        p.LayoutOrder = order
        p.ZIndex = 2
        p.Parent = pearlRow

        local pCorner = Instance.new("UICorner")
        pCorner.CornerRadius = UIConstants.Corners.Pearl
        pCorner.Parent = p

        local pStroke = Instance.new("UIStroke")
        pStroke.Color = UIConstants.Colors.StrokeWarm
        pStroke.Thickness = 1.5
        pStroke.Transparency = 0.3
        pStroke.Parent = p

        local hi = Instance.new("Frame")
        hi.Name = "Highlight"
        hi.Size = UIConstants.Pearl.HighlightSize
        hi.Position = UIConstants.Pearl.HighlightPosition
        hi.AnchorPoint = UIConstants.Pearl.HighlightAnchor
        hi.BackgroundColor3 = UIConstants.Colors.PearlHighlight
        hi.BackgroundTransparency = UIConstants.Pearl.HighlightTransparency
        hi.BorderSizePixel = 0
        hi.ZIndex = 3
        hi.Parent = p

        local hiCorner = Instance.new("UICorner")
        hiCorner.CornerRadius = UIConstants.Corners.Pearl
        hiCorner.Parent = hi

        return p
    end

    local pearls = {
        makePearl(theme.PearlBrown, 1),
        makePearl(theme.PearlPink, 2),
        makePearl(theme.PearlGreen, 3),
        makePearl(theme.PearlWhite, 4),
    }

    --
    -- State button. Position + size fixed; text/color set by refresh().
    --
    local button = Instance.new("TextButton")
    button.Name = "StateButton"
    button.Size = UDim2.new(1, -32, 0, 42)
    button.Position = UDim2.new(0.5, 0, 1, -16)
    button.AnchorPoint = Vector2.new(0.5, 1)
    button.AutoButtonColor = false
    button.BorderSizePixel = 0
    button.FontFace = UIConstants.Fonts.Display
    button.TextSize = 18
    button.Text = ""
    button.ZIndex = 2
    button.Parent = card

    local btnCorner = Instance.new("UICorner")
    btnCorner.CornerRadius = UIConstants.Corners.Button
    btnCorner.Parent = button

    local btnStroke = Instance.new("UIStroke")
    btnStroke.Color = UIConstants.Colors.StrokeWarm
    btnStroke.Thickness = 1.5
    btnStroke.Transparency = 0.4
    btnStroke.Parent = button

    local btnScale = Instance.new("UIScale")
    btnScale.Scale = 1
    btnScale.Parent = button

    cards[themeKey] = {
        card = card,
        nameLabel = nameLabel,
        pearls = pearls,
        button = button,
        buttonScale = btnScale,
        clickConn = nil,
        themeKey = themeKey,
    }
end

for index, themeKey in ipairs(Themes.ORDER) do
    buildCard(themeKey, index)
end

--------------------------------------------------------------------------------
-- refresh(): paint each card's state button based on current ownership +
-- active theme. Rewires the click handler each pass so a freshly-equipped
-- card doesn't keep firing the old equip handler.
--------------------------------------------------------------------------------

local function refresh()
    local owns = readOwns()
    local active = readActive()
    for themeKey, entry in pairs(cards) do
        local theme = Themes.byKey(themeKey)
        local isActive = (active == themeKey)
        local isUnlocked = (not theme.locked) or owns

        -- Tear down the prior click connection. Rebuilding fresh per refresh
        -- means each state has a single coherent click handler.
        if entry.clickConn then
            entry.clickConn:Disconnect()
            entry.clickConn = nil
        end

        if isActive then
            entry.button.Text = "EQUIPPED"
            entry.button.BackgroundColor3 = UIConstants.Colors.Mint
            entry.button.TextColor3 = UIConstants.Colors.TextDark
            entry.clickConn = entry.button.MouseButton1Click:Connect(function()
                -- Idle SFX so the tap still gives feedback even though the
                -- state doesn't change.
                sfx("click")
                squish(entry.buttonScale)
            end)
        elseif isUnlocked then
            entry.button.Text = "EQUIP"
            entry.button.BackgroundColor3 = UIConstants.Colors.Peach
            entry.button.TextColor3 = UIConstants.Colors.TextDark
            entry.clickConn = entry.button.MouseButton1Click:Connect(function()
                sfx("confirm")
                squish(entry.buttonScale)
                player:SetAttribute(ACTIVE_ATTR, themeKey)
                -- The attribute changed signal below will trigger refresh().
            end)
        else
            -- Locked premium theme. The shop pill on MainMenu is the unlock
            -- path; the locked card here is informational only. Click still
            -- gives audible feedback so it doesn't feel dead.
            entry.button.Text = "\u{1F512} LOCKED"
            entry.button.BackgroundColor3 = UIConstants.Colors.WarmCancel
            entry.button.TextColor3 = UIConstants.Colors.TextOnWarm
            entry.clickConn = entry.button.MouseButton1Click:Connect(function()
                sfx("click")
                squish(entry.buttonScale)
            end)
        end
    end
end

refresh()

-- Repaint when ownership flips (mid-session purchase) or when the active
-- theme changes (equip click, or any future server-side write).
player:GetAttributeChangedSignal(OWNS_ATTR):Connect(refresh)
player:GetAttributeChangedSignal(ACTIVE_ATTR):Connect(refresh)

--------------------------------------------------------------------------------
-- Open / close. Tween panel slide-in from 0.55 vertical to 0.5; close
-- tweens back down and hides scrim after. Mirrors HowToPlay's pattern.
-- GameState gating: silently no-op if the player tries to open mid-match.
--------------------------------------------------------------------------------

local OPEN_DURATION = 0.25
local CLOSE_DURATION = 0.20
local isOpen = false

local function openInventory()
    if isOpen then return end
    local state = player:GetAttribute("GameState")
    if state ~= nil and state ~= "main_menu" then
        return
    end
    isOpen = true
    refresh()
    sfx("click")
    scrim.Visible = true
    panel.Visible = true
    panel.Position = PANEL_OFFSCREEN
    TweenService:Create(
        panel,
        UIConstants.tween(OPEN_DURATION, "UI"),
        { Position = PANEL_ONSCREEN }
    ):Play()
end

local function closeInventory()
    if not isOpen then return end
    isOpen = false
    local tween = TweenService:Create(
        panel,
        UIConstants.tween(CLOSE_DURATION, "UIIn"),
        { Position = PANEL_OFFSCREEN }
    )
    tween.Completed:Connect(function()
        if not isOpen then
            scrim.Visible = false
            panel.Visible = false
            panel.Position = PANEL_ONSCREEN
        end
    end)
    tween:Play()
end

-- Belt-and-suspenders: if GameState flips off main_menu while the inventory
-- is open, snap it shut. The MainMenu pill already gates opens so this only
-- catches edge transitions (e.g. server force-transition).
player:GetAttributeChangedSignal("GameState"):Connect(function()
    local state = player:GetAttribute("GameState")
    if state ~= "main_menu" and isOpen then
        isOpen = false
        scrim.Visible = false
        panel.Visible = false
        panel.Position = PANEL_ONSCREEN
    end
end)

closeBtn.MouseButton1Click:Connect(function()
    sfx("back")
    squish(closeScale)
    closeInventory()
end)

-- Scrim click closes only when the click landed OUTSIDE the panel rect.
-- panel.Active=true alone does NOT stop scrim.InputBegan from firing for
-- panel-internal clicks; Roblox bubbles input through the hierarchy.
scrim.InputBegan:Connect(function(input)
    if input.UserInputType ~= Enum.UserInputType.MouseButton1
        and input.UserInputType ~= Enum.UserInputType.Touch then
        return
    end
    local pos = input.Position
    local rectPos = panel.AbsolutePosition
    local rectSize = panel.AbsoluteSize
    local insideModal = pos.X >= rectPos.X
        and pos.X <= rectPos.X + rectSize.X
        and pos.Y >= rectPos.Y
        and pos.Y <= rectPos.Y + rectSize.Y
    if not insideModal then
        sfx("back")
        closeInventory()
    end
end)

_G.BobaDropThemes = {
    open = openInventory,
    close = closeInventory,
}
