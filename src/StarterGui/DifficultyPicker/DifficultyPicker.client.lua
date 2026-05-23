-- DifficultyPicker: modal that opens when MainMenu's SINGLE PLAYER button
-- is tapped. Lets the player choose an AI difficulty before entering the
-- queue. Shipped tiers (EASY + MEDIUM) fire EnterQueue with the picked
-- difficulty; HARD + PRO render as locked "Coming Soon" cards so the
-- future shape is visible.
--
-- Always-Enabled ScreenGui pattern (same as Shop / Settings / HowToPlay /
-- ThemesInventory). Internal Visible toggling on scrim + panel. Bounds-
-- checked scrim InputBegan for outside-the-panel close.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local UIConstants = require(ReplicatedStorage.Shared.UI.UIConstants)
local Events = require(ReplicatedStorage.Shared.Events)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local function sfx(kind)
    if _G.BobaDropSfx and _G.BobaDropSfx[kind] then _G.BobaDropSfx[kind]() end
end

local Remotes = ReplicatedStorage:WaitForChild("Remotes", 30)
local enterQueueRemote = Remotes and Remotes:FindFirstChild(Events.Names.EnterQueue)

--------------------------------------------------------------------------------
-- ScreenGui + scrim + panel shell
--------------------------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "DifficultyPicker"
gui.ResetOnSpawn = false
gui.DisplayOrder = UIConstants.ZOrder and (UIConstants.ZOrder.ShopOverlay or 50) + 2 or 52
-- IgnoreGuiInset = false so the scrim + panel sit inside the safe area
-- (below the Roblox topbar) on mobile. Previously IgnoreGuiInset=true
-- put the panel top at viewport_y=0, which the topbar (~36 px tall)
-- then obscured — clipping the "CHOOSE OPPONENT" title.
gui.IgnoreGuiInset = false
gui.Parent = playerGui

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

local PANEL_ONSCREEN = UDim2.fromScale(0.5, 0.5)
local PANEL_OFFSCREEN = UDim2.new(0.5, 0, 0.55, 0)

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.Active = true
-- Scale-based with min/max clamps so the 4-tier card stack fits inside a
-- landscape-mobile viewport (e.g. 844x390) without bleeding off the bottom.
-- MinSize keeps it readable on tiny viewports; MaxSize caps it at the prior
-- 440x460 ceiling for desktop / tablet.
panel.Size = UDim2.new(0.92, 0, 0.92, 0)
panel.Position = PANEL_OFFSCREEN
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.BackgroundColor3 = UIConstants.Colors.Cream
panel.BorderSizePixel = 0
panel.Visible = false
panel.Parent = gui

local panelSizeConstraint = Instance.new("UISizeConstraint")
panelSizeConstraint.MinSize = Vector2.new(320, 320)
panelSizeConstraint.MaxSize = Vector2.new(440, 460)
panelSizeConstraint.Parent = panel

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UIConstants.Corners.Panel
panelCorner.Parent = panel

local panelStroke = Instance.new("UIStroke")
panelStroke.Color = UIConstants.Colors.StrokeWarm
panelStroke.Thickness = 2
panelStroke.Transparency = 0.4
panelStroke.Parent = panel

-- Padding tightened from 24 to 16 vertical so the 4 cards + title fit when
-- the panel shrinks to its 320 min height on landscape mobile.
local panelPadding = Instance.new("UIPadding")
panelPadding.PaddingTop = UDim.new(0, 16)
panelPadding.PaddingBottom = UDim.new(0, 16)
panelPadding.PaddingLeft = UDim.new(0, 20)
panelPadding.PaddingRight = UDim.new(0, 20)
panelPadding.Parent = panel

--------------------------------------------------------------------------------
-- Title + close
--------------------------------------------------------------------------------

local title = Instance.new("TextLabel")
title.Name = "Title"
title.Size = UDim2.new(1, 0, 0, 30)
title.Position = UDim2.fromOffset(0, 0)
title.BackgroundTransparency = 1
title.FontFace = UIConstants.Fonts.Display
title.TextSize = 26
title.TextColor3 = UIConstants.Colors.TextDark
title.TextXAlignment = Enum.TextXAlignment.Center
title.Text = "CHOOSE OPPONENT"
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
-- Difficulty cards stacked vertically. Each card has a title row + a one-
-- line description. Live tiers (EASY, MEDIUM) get vibrant backgrounds and
-- a click handler; locked tiers (HARD, PRO) get cream backgrounds, muted
-- text, and a "Coming Soon" tag.
--------------------------------------------------------------------------------

-- CardWrap fills the panel below the title (30 title + 14 gap = 44 px). Cards
-- use Scale Y so 4 stacked tiers always fit regardless of viewport height —
-- on landscape mobile (panel ~320 tall) cards land at ~53 px, on desktop
-- (panel 460 tall) cards land at ~88 px. Without the Scale Y the 64-fixed
-- cards overflowed off the bottom of a compact panel.
local cardWrap = Instance.new("Frame")
cardWrap.Name = "CardWrap"
cardWrap.Size = UDim2.new(1, 0, 1, -44)
cardWrap.Position = UDim2.fromOffset(0, 44)
cardWrap.BackgroundTransparency = 1
cardWrap.Parent = panel

local cardLayout = Instance.new("UIListLayout")
cardLayout.FillDirection = Enum.FillDirection.Vertical
cardLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
cardLayout.VerticalAlignment = Enum.VerticalAlignment.Top
cardLayout.SortOrder = Enum.SortOrder.LayoutOrder
cardLayout.Padding = UDim.new(0, 8)
cardLayout.Parent = cardWrap

local TIERS = {
    { key = "easy",   name = "EASY",   desc = "casual random opponent",        bg = UIConstants.Colors.Mint,       textColor = UIConstants.Colors.TextDark,    locked = false },
    { key = "medium", name = "MEDIUM", desc = "plays safer, avoids overflow",  bg = UIConstants.Colors.Peach,      textColor = UIConstants.Colors.TextDark,    locked = false },
    { key = "hard",   name = "HARD",   desc = "hunts chains, reacts fast",     bg = UIConstants.Colors.Coral,      textColor = UIConstants.Colors.TextOnWarm,  locked = false },
    { key = "pro",    name = "PRO",    desc = "thinks ahead, builds setups",   bg = UIConstants.Colors.WarmDark,   textColor = UIConstants.Colors.TextOnWarm,  locked = false },
}

local panelOpen = false
local fireLatch = false

local function closePicker()
    if not panelOpen then return end
    panelOpen = false
    local tween = TweenService:Create(
        panel,
        UIConstants.tween(0.20, "UIIn"),
        { Position = PANEL_OFFSCREEN }
    )
    tween.Completed:Connect(function()
        if not panelOpen then
            scrim.Visible = false
            panel.Visible = false
            panel.Position = PANEL_ONSCREEN
        end
    end)
    tween:Play()
end

local function fireDifficulty(difficulty)
    if fireLatch then return end
    if not enterQueueRemote then
        warn("[DifficultyPicker] EnterQueue remote missing, ignoring tap")
        return
    end
    fireLatch = true
    enterQueueRemote:FireServer({ mode = "ai", difficulty = difficulty })
    closePicker()
end

local function buildCard(tier, layoutOrder)
    local card = Instance.new("TextButton")
    card.Name = tier.name .. "Card"
    -- Y Scale: 4 cards + 3*8 padding gaps = 24 px → each card claims
    -- (cardWrap_h - 24) / 4. Using 0.25 scale Y minus 6 offset gives
    -- 0.25*h - 6 each → total = 4*(0.25h - 6) + 24 = h. Fits exactly.
    card.Size = UDim2.new(1, -8, 0.25, -6)
    card.LayoutOrder = layoutOrder
    card.AutoButtonColor = false
    card.BorderSizePixel = 0
    card.BackgroundColor3 = tier.bg
    card.Text = ""
    card.Parent = cardWrap

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UIConstants.Corners.Button
    corner.Parent = card

    local stroke = Instance.new("UIStroke")
    stroke.Color = UIConstants.Colors.StrokeWarm
    stroke.Thickness = 1.5
    stroke.Transparency = tier.locked and 0.55 or 0.35
    stroke.Parent = card

    local nameLabel = Instance.new("TextLabel")
    nameLabel.Name = "Name"
    nameLabel.Size = UDim2.new(0.45, 0, 1, 0)
    nameLabel.Position = UDim2.fromOffset(16, 0)
    nameLabel.BackgroundTransparency = 1
    nameLabel.FontFace = UIConstants.Fonts.Display
    nameLabel.TextSize = 26
    nameLabel.TextColor3 = tier.textColor
    nameLabel.TextXAlignment = Enum.TextXAlignment.Left
    nameLabel.TextYAlignment = Enum.TextYAlignment.Center
    nameLabel.Text = tier.name
    nameLabel.Parent = card

    local descLabel = Instance.new("TextLabel")
    descLabel.Name = "Desc"
    descLabel.Size = UDim2.new(0.55, -16, 1, 0)
    descLabel.Position = UDim2.new(0.45, 0, 0, 0)
    descLabel.BackgroundTransparency = 1
    descLabel.FontFace = UIConstants.Fonts.Tutorial
    descLabel.TextSize = 13
    -- Use the tier's textColor for the desc too so it stays readable on dark
    -- backgrounds (PRO's WarmDark bg with hardcoded TextDark desc made the
    -- subtitle invisible — same dark brown on both layers). Locked tiers
    -- keep the muted TextSoft for the cream-on-cream "coming soon" look.
    descLabel.TextColor3 = tier.locked and UIConstants.Colors.TextSoft or tier.textColor
    descLabel.TextXAlignment = Enum.TextXAlignment.Right
    descLabel.TextYAlignment = Enum.TextYAlignment.Center
    descLabel.Text = tier.desc
    descLabel.TextWrapped = true
    descLabel.Parent = card

    local scaleObj = Instance.new("UIScale")
    scaleObj.Scale = 1
    scaleObj.Parent = card

    card.MouseButton1Click:Connect(function()
        if tier.locked then
            sfx("error")
            squish(scaleObj)
            return
        end
        sfx("confirm")
        squish(scaleObj)
        fireDifficulty(tier.key)
    end)

    return card
end

for i, tier in ipairs(TIERS) do
    buildCard(tier, i)
end

--------------------------------------------------------------------------------
-- Open / close / scrim bounds check
--------------------------------------------------------------------------------

local function openPicker()
    if panelOpen then return end
    local state = player:GetAttribute("GameState")
    if state ~= nil and state ~= "main_menu" then
        return
    end
    panelOpen = true
    fireLatch = false
    sfx("click")
    scrim.Visible = true
    panel.Visible = true
    panel.Position = PANEL_OFFSCREEN
    TweenService:Create(
        panel,
        UIConstants.tween(0.25, "UI"),
        { Position = PANEL_ONSCREEN }
    ):Play()
end

closeBtn.MouseButton1Click:Connect(function()
    sfx("back")
    squish(closeScale)
    closePicker()
end)

scrim.InputBegan:Connect(function(input)
    if input.UserInputType ~= Enum.UserInputType.MouseButton1
        and input.UserInputType ~= Enum.UserInputType.Touch then
        return
    end
    local pos = input.Position
    local rectPos = panel.AbsolutePosition
    local rectSize = panel.AbsoluteSize
    local inside = pos.X >= rectPos.X
        and pos.X <= rectPos.X + rectSize.X
        and pos.Y >= rectPos.Y
        and pos.Y <= rectPos.Y + rectSize.Y
    if not inside then
        sfx("back")
        closePicker()
    end
end)

-- If the player force-transitions out of main_menu while picker is open
-- (server-driven), snap it shut. Mirror ThemesInventory's pattern.
player:GetAttributeChangedSignal("GameState"):Connect(function()
    local state = player:GetAttribute("GameState")
    if state ~= "main_menu" and panelOpen then
        panelOpen = false
        scrim.Visible = false
        panel.Visible = false
        panel.Position = PANEL_ONSCREEN
    end
end)

_G.BobaDropDifficultyPicker = {
    open = openPicker,
    close = closePicker,
}
