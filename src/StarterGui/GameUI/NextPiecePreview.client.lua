-- NextPiecePreview: top-left HUD showing the next 2 upcoming pieces, sitting
-- under the score pill. Was previously top-right but it overlapped the LEAVE
-- pill in that corner, per Sarah's note 2026-05-20.
-- Subscribes to NextPieceQueueUpdate (server fires on every _spawnPiece).
-- queue[1] = next piece, queue[2] = the one after. Currently-active piece
-- is NOT in the queue.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local UIConstants = require(ReplicatedStorage.Shared.UI.UIConstants)
local Themes = require(ReplicatedStorage.Shared.UI.Themes)
local Events = require(ReplicatedStorage.Shared.Events)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local localUserId = tostring(player.UserId)

--------------------------------------------------------------------------------
-- Color mapping (inlined, intentionally not shared with BoardPlaceholder)
--------------------------------------------------------------------------------

-- Active palette is read on every paint. The preview repaints when the
-- player equips a different theme (handler near the bottom of this file).
local function activePalette()
    return Themes.byKey(player:GetAttribute("BobaDropActiveTheme") or "Default")
end

local function colorForServerName(name)
    local palette = activePalette()
    if name == "Brown" then return palette.PearlBrown
    elseif name == "Pink" then return palette.PearlPink
    elseif name == "Green" then return palette.PearlGreen
    elseif name == "White" then return palette.PearlWhite
    end
    return palette.PearlWhite
end

--------------------------------------------------------------------------------
-- ScreenGui scaffolding
--------------------------------------------------------------------------------

-- Layout sits flush below the score pill: score is at (20, 20) size (176, 64),
-- so NEXT lives at (20, 100) with width matching the score (176) and height
-- big enough for a header + two side-by-side mini cards. Mounts off-screen-left.
-- 16px gap below score gives breathing room and matches the look of the gap
-- between Lobby's tutorial card and its CTA.
local CONTAINER_SIZE = UDim2.fromOffset(176, 96)
local ONSCREEN_POS = UDim2.new(0, 20, 0, 100)
local OFFSCREEN_POS = UDim2.new(0, -200, 0, 100)
local SLOT_SIZE = UDim2.fromOffset(56, 68)
local PEARL_SIZE = UDim2.fromOffset(24, 24)

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "NextPiecePreview"
screenGui.ResetOnSpawn = false
-- IgnoreGuiInset = false so this layer uses the same offset origin as the
-- score pill (ScoreDisplay defaults to false). Mismatched inset was making
-- NEXT visually overlap SCORE in Studio playtests even though their Y
-- positions had a gap.
screenGui.IgnoreGuiInset = false
screenGui.DisplayOrder = UIConstants.ZOrder.HUD or 100
screenGui.Enabled = false
screenGui.Parent = playerGui

local container = Instance.new("Frame")
container.Name = "Container"
container.AnchorPoint = Vector2.new(0, 0)
container.Position = OFFSCREEN_POS
container.Size = CONTAINER_SIZE
container.BackgroundColor3 = UIConstants.Colors.Cream
container.BackgroundTransparency = 0
container.BorderSizePixel = 0
container.Parent = screenGui

local containerCorner = Instance.new("UICorner")
containerCorner.CornerRadius = UIConstants.Corners.Card
containerCorner.Parent = container

local containerStroke = Instance.new("UIStroke")
containerStroke.Color = UIConstants.Colors.StrokeWarm
containerStroke.Thickness = 2
containerStroke.Transparency = 0.5
containerStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
containerStroke.Parent = container

local containerPadding = Instance.new("UIPadding")
containerPadding.PaddingTop = UDim.new(0, 6)
containerPadding.PaddingBottom = UDim.new(0, 6)
containerPadding.PaddingLeft = UDim.new(0, 6)
containerPadding.PaddingRight = UDim.new(0, 6)
containerPadding.Parent = container

-- Container layout: header on top, then a horizontal row of slot cards below.
local listLayout = Instance.new("UIListLayout")
listLayout.FillDirection = Enum.FillDirection.Vertical
listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
listLayout.VerticalAlignment = Enum.VerticalAlignment.Top
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Padding = UDim.new(0, 4)
listLayout.Parent = container

local header = Instance.new("TextLabel")
header.Name = "Header"
header.LayoutOrder = 1
header.Size = UDim2.new(1, 0, 0, 14)
header.BackgroundTransparency = 1
header.Text = "NEXT"
header.FontFace = UIConstants.Fonts.HUD
header.TextSize = 10
header.TextColor3 = UIConstants.Colors.TextSoft
header.TextXAlignment = Enum.TextXAlignment.Center
header.TextYAlignment = Enum.TextYAlignment.Center
header.Parent = container

-- Slot row: holds slot1 + slot2 side by side beneath the header.
local slotRow = Instance.new("Frame")
slotRow.Name = "SlotRow"
slotRow.LayoutOrder = 2
slotRow.Size = UDim2.new(1, 0, 0, SLOT_SIZE.Y.Offset)
slotRow.BackgroundTransparency = 1
slotRow.Parent = container

local slotRowLayout = Instance.new("UIListLayout")
slotRowLayout.FillDirection = Enum.FillDirection.Horizontal
slotRowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
slotRowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
slotRowLayout.SortOrder = Enum.SortOrder.LayoutOrder
slotRowLayout.Padding = UDim.new(0, 8)
slotRowLayout.Parent = slotRow

--------------------------------------------------------------------------------
-- Slot builders
--------------------------------------------------------------------------------

local function makeSlot(layoutOrder)
    local slot = Instance.new("Frame")
    slot.Name = "Slot" .. layoutOrder
    slot.LayoutOrder = layoutOrder
    slot.Size = SLOT_SIZE
    slot.BackgroundColor3 = UIConstants.Colors.Cream
    slot.BackgroundTransparency = 0.35
    slot.BorderSizePixel = 0
    slot.Visible = false
    slot.Parent = slotRow

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UIConstants.Corners.Card
    corner.Parent = slot

    local stroke = Instance.new("UIStroke")
    stroke.Color = UIConstants.Colors.StrokeSoft
    stroke.Thickness = 1
    stroke.Transparency = 0.4
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Parent = slot

    return slot
end

local slot1 = makeSlot(1)
local slot2 = makeSlot(2)

local function clearSlot(slot)
    for _, child in ipairs(slot:GetChildren()) do
        if child:IsA("Frame") and child.Name:match("^Pearl") then
            child:Destroy()
        end
    end
end

local function buildPearl(parent, color, isPivot)
    local pearl = Instance.new("Frame")
    pearl.Name = isPivot and "PearlPivot" or "PearlPartner"
    pearl.AnchorPoint = Vector2.new(0.5, 0.5)
    pearl.Size = PEARL_SIZE
    pearl.BackgroundColor3 = color
    pearl.BackgroundTransparency = 1 -- fade in
    pearl.BorderSizePixel = 0
    -- Partner sits on top, pivot on the bottom. Spawn orientation 0:
    -- pivot below, partner above.
    if isPivot then
        pearl.Position = UDim2.new(0.5, 0, 0.70, 0)
    else
        pearl.Position = UDim2.new(0.5, 0, 0.30, 0)
    end
    pearl.Parent = parent

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UIConstants.Corners.Pearl
    corner.Parent = pearl

    -- Stroke gives mini-pearls definition against the cream slot background,
    -- specifically so the white pearl reads instead of blending in.
    local stroke = Instance.new("UIStroke")
    stroke.Color = UIConstants.Colors.StrokeWarm
    stroke.Thickness = 1.5
    stroke.Transparency = 0.35
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Parent = pearl

    -- Subtle glossy highlight
    local highlight = Instance.new("Frame")
    highlight.Name = "Highlight"
    highlight.AnchorPoint = UIConstants.Pearl.HighlightAnchor
    highlight.Position = UIConstants.Pearl.HighlightPosition
    highlight.Size = UIConstants.Pearl.HighlightSize
    highlight.BackgroundColor3 = UIConstants.Colors.PearlHighlight
    highlight.BackgroundTransparency = 1 -- fade in with parent
    highlight.BorderSizePixel = 0
    highlight.Parent = pearl

    local hCorner = Instance.new("UICorner")
    hCorner.CornerRadius = UIConstants.Corners.Pearl
    hCorner.Parent = highlight

    return pearl, highlight
end

local function buildMiniPair(slotFrame, pieceData)
    -- pieceData = { a = "Brown", b = "Pink" } where a = pivot, b = partner.
    clearSlot(slotFrame)
    if not pieceData or not pieceData.a or not pieceData.b then
        slotFrame.Visible = false
        return
    end
    slotFrame.Visible = true

    local pivot, pivotHi = buildPearl(slotFrame, colorForServerName(pieceData.a), true)
    local partner, partnerHi = buildPearl(slotFrame, colorForServerName(pieceData.b), false)

    -- Fade from 0.3 → 1.0 alpha (i.e. transparency 0.7 → 0) over 200ms.
    local info = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    for _, p in ipairs({ pivot, partner }) do
        p.BackgroundTransparency = 0.7
        TweenService:Create(p, info, { BackgroundTransparency = 0 }):Play()
    end
    -- Highlights fade to their spec transparency (0.6) from fully transparent.
    for _, h in ipairs({ pivotHi, partnerHi }) do
        h.BackgroundTransparency = 1
        TweenService:Create(h, info, { BackgroundTransparency = UIConstants.Pearl.HighlightTransparency }):Play()
    end
end

-- Cached queue so a mid-match theme change can repaint the preview without
-- waiting for the next NextPieceQueueUpdate.
local lastQueue = nil

local function applyQueue(queue)
    lastQueue = queue
    local first = queue and queue[1]
    local second = queue and queue[2]
    buildMiniPair(slot1, first)
    buildMiniPair(slot2, second)
end

-- Repaint preview pearls when the player equips a different theme.
player:GetAttributeChangedSignal("BobaDropActiveTheme"):Connect(function()
    if lastQueue then
        applyQueue(lastQueue)
    end
end)

--------------------------------------------------------------------------------
-- Remote subscription
--------------------------------------------------------------------------------

local Remotes = ReplicatedStorage:WaitForChild("Remotes", 30)
local nextPieceRemote
if Remotes then
    local remoteName = (Events.Names and Events.Names.NextPieceQueueUpdate) or "NextPieceQueueUpdate"
    nextPieceRemote = Remotes:WaitForChild(remoteName, 30)
end

if nextPieceRemote then
    nextPieceRemote.OnClientEvent:Connect(function(event)
        if not event then return end
        local isLocal = event.isLocal
        if isLocal == nil then
            isLocal = (tostring(event.playerId) == localUserId)
        end
        if not isLocal then return end
        applyQueue(event.queue or {})
    end)
end

--------------------------------------------------------------------------------
-- Visibility (GameState attribute, self-managed)
--------------------------------------------------------------------------------

local hasMounted = false

local function playSlideIn()
    if hasMounted then return end
    hasMounted = true
    container.Position = OFFSCREEN_POS
    local info = UIConstants.tween(0.3, "UI")
    TweenService:Create(container, info, { Position = ONSCREEN_POS }):Play()
end

local function updateVisibility()
    local state = player:GetAttribute("GameState")
    local shouldShow = (state == "in_match")
    screenGui.Enabled = shouldShow
    if shouldShow then
        playSlideIn()
    else
        -- Reset so the slide-in plays fresh on the next match.
        hasMounted = false
        container.Position = OFFSCREEN_POS
    end
end

player:GetAttributeChangedSignal("GameState"):Connect(updateVisibility)
updateVisibility()
