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

local gui = Instance.new("ScreenGui")
gui.Name = "Shop"
gui.ResetOnSpawn = false
gui.DisplayOrder = UIConstants.ZOrder.ShopOverlay
gui.IgnoreGuiInset = true
gui.Parent = playerGui

-- Scrim behind the modal so the lobby/match-end UI dims when the shop is open.
local scrim = Instance.new("Frame")
scrim.Name = "Scrim"
scrim.Size = UDim2.fromScale(1, 1)
scrim.BackgroundColor3 = UIConstants.Colors.TextDark
scrim.BackgroundTransparency = 0.55
scrim.BorderSizePixel = 0
scrim.Visible = false
scrim.Parent = gui

local modal = Instance.new("Frame")
modal.Name = "Modal"
modal.Size = UDim2.fromOffset(420, 460)
modal.Position = UDim2.fromScale(0.5, 0.5)
modal.AnchorPoint = Vector2.new(0.5, 0.5)
modal.BackgroundColor3 = UIConstants.Colors.Cream
modal.BackgroundTransparency = 0
modal.BorderSizePixel = 0
modal.Visible = false
modal.Parent = gui

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
modalPadding.PaddingBottom = UDim.new(0, 24)
modalPadding.PaddingLeft = UDim.new(0, 24)
modalPadding.PaddingRight = UDim.new(0, 24)
modalPadding.Parent = modal

local title = Instance.new("TextLabel")
title.Name = "Title"
title.Size = UDim2.new(1, 0, 0, 40)
title.BackgroundTransparency = 1
title.FontFace = UIConstants.Fonts.Display
title.TextSize = UIConstants.TextSizes.Score
title.TextColor3 = UIConstants.Colors.TextDark
title.Text = "Premium Themes Pack"
title.Parent = modal

local body = Instance.new("TextLabel")
body.Name = "Body"
body.Size = UDim2.new(1, 0, 0, 100)
body.Position = UDim2.fromOffset(0, 52)
body.BackgroundTransparency = 1
body.FontFace = UIConstants.Fonts.Tutorial
body.TextSize = UIConstants.TextSizes.Body
body.TextColor3 = UIConstants.Colors.TextDark
body.TextWrapped = true
body.TextXAlignment = Enum.TextXAlignment.Left
body.TextYAlignment = Enum.TextYAlignment.Top
body.Text = "Three cosmetic cup themes:\nBrown Sugar Boba, Strawberry Milk, Matcha.\nGameplay-neutral. Just for the vibes."
body.Parent = modal

-- Theme preview swatches: three pearls in each theme's signature color.
local previewRow = Instance.new("Frame")
previewRow.Name = "PreviewRow"
previewRow.Size = UDim2.new(1, 0, 0, 90)
previewRow.Position = UDim2.fromOffset(0, 160)
previewRow.BackgroundTransparency = 1
previewRow.Parent = modal

local previewLayout = Instance.new("UIListLayout")
previewLayout.FillDirection = Enum.FillDirection.Horizontal
previewLayout.Padding = UDim.new(0, 14)
previewLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
previewLayout.VerticalAlignment = Enum.VerticalAlignment.Center
previewLayout.SortOrder = Enum.SortOrder.LayoutOrder
previewLayout.Parent = previewRow

local function previewSwatch(theme, order)
    local cell = Instance.new("Frame")
    cell.Name = theme.name
    cell.Size = UDim2.fromOffset(110, 90)
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

    pearl(theme.PearlBrown, 0.27, 0.4, 28)
    pearl(theme.PearlPink, 0.5, 0.6, 28)
    pearl(theme.PearlGreen, 0.73, 0.4, 28)

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -8, 0, 18)
    label.Position = UDim2.new(0, 4, 1, -22)
    label.BackgroundTransparency = 1
    label.FontFace = UIConstants.Fonts.HUD
    label.TextSize = UIConstants.TextSizes.HUDLabel
    label.TextColor3 = UIConstants.Colors.TextDark
    label.Text = theme.name
    label.Parent = cell
end

previewSwatch(Themes.BrownSugarBoba, 1)
previewSwatch(Themes.StrawberryMilk, 2)
previewSwatch(Themes.Matcha, 3)

-- Buy + close buttons
local function makeBtn(name, text, bg, anchorX, layoutOrder)
    local btn = Instance.new("TextButton")
    btn.Name = name
    btn.Size = UDim2.fromOffset(170, 52)
    btn.Position = UDim2.new(anchorX, anchorX == 0 and 0 or -170, 1, -52)
    btn.AutoButtonColor = false
    btn.BorderSizePixel = 0
    btn.BackgroundColor3 = bg
    btn.TextColor3 = UIConstants.Colors.TextDark
    btn.FontFace = UIConstants.Fonts.Display
    btn.TextSize = UIConstants.TextSizes.Body
    btn.Text = text
    btn.Parent = modal

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UIConstants.Corners.Button
    corner.Parent = btn

    local scale = Instance.new("UIScale")
    scale.Scale = 1
    scale.Parent = btn

    return btn, scale
end

local buyBtn, buyScale = makeBtn("BuyBtn", "Buy for 99 R$", UIConstants.Colors.Peach, 0)
local closeBtn, closeScale = makeBtn("CloseBtn", "Close", UIConstants.Colors.Mint, 1)

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
    squish(buyScale)
    MarketplaceService:PromptGamePassPurchase(player, PREMIUM_THEMES_ID)
end)

closeBtn.MouseButton1Click:Connect(function()
    squish(closeScale)
    setOpen(false)
end)

-- Tapping the scrim closes the modal too.
scrim.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        setOpen(false)
    end
end)

_G.BobaDropShop = {
    open = function() setOpen(true) end,
    close = function() setOpen(false) end,
}

-- Post-match prompt for the losing player, max 1x per session.
local promptShownThisSession = false
task.spawn(function()
    local remotes = ReplicatedStorage:WaitForChild("Remotes", 30)
    if not remotes then return end
    local matchEndName = Events.Names.MatchEnd
    if not matchEndName then return end
    local matchEndRemote = remotes:WaitForChild(matchEndName, 30)
    if not matchEndRemote then return end

    matchEndRemote.OnClientEvent:Connect(function(event)
        local isLoser = tostring(event.winner) ~= tostring(player.UserId)
        if isLoser and not promptShownThisSession then
            promptShownThisSession = true
            task.wait(2)  -- let the match-end animation breathe
            setOpen(true)
        end
    end)
end)
