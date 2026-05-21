-- NextPiecePreview: top-right HUD showing the next 2 upcoming pieces.
-- Subscribes to NextPieceQueueUpdate (server fires on every _spawnPiece).
-- queue[1] = next piece, queue[2] = the one after. Currently-active piece
-- is NOT in the queue.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local UIConstants = require(ReplicatedStorage.Shared.UI.UIConstants)
local Events = require(ReplicatedStorage.Shared.Events)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local localUserId = tostring(player.UserId)

--------------------------------------------------------------------------------
-- Color mapping (inlined, intentionally not shared with BoardPlaceholder)
--------------------------------------------------------------------------------

local function colorForServerName(name)
    if name == "Brown" then return UIConstants.Colors.PearlBrown
    elseif name == "Pink" then return UIConstants.Colors.PearlPink
    elseif name == "Green" then return UIConstants.Colors.PearlGreen
    elseif name == "White" then return UIConstants.Colors.PearlWhite
    end
    return UIConstants.Colors.PearlWhite
end

--------------------------------------------------------------------------------
-- ScreenGui scaffolding
--------------------------------------------------------------------------------

local CONTAINER_SIZE = UDim2.fromOffset(72, 168)
local ONSCREEN_POS = UDim2.new(1, -16, 0, 16)
local OFFSCREEN_POS = UDim2.new(1, 16, 0, 16)
local SLOT_SIZE = UDim2.fromOffset(56, 68)
local PEARL_SIZE = UDim2.fromOffset(24, 24)

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "NextPiecePreview"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = UIConstants.ZOrder.HUD or 100
screenGui.Enabled = false
screenGui.Parent = playerGui

local container = Instance.new("Frame")
container.Name = "Container"
container.AnchorPoint = Vector2.new(1, 0)
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

--------------------------------------------------------------------------------
-- Slot builders
--------------------------------------------------------------------------------

local function makeSlot(layoutOrder)
    local slot = Instance.new("Frame")
    slot.Name = "Slot" .. layoutOrder
    slot.LayoutOrder = layoutOrder + 1 -- header is 1
    slot.Size = SLOT_SIZE
    slot.BackgroundColor3 = UIConstants.Colors.Cream
    slot.BackgroundTransparency = 0.35
    slot.BorderSizePixel = 0
    slot.Visible = false
    slot.Parent = container

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

local function applyQueue(queue)
    local first = queue and queue[1]
    local second = queue and queue[2]
    buildMiniPair(slot1, first)
    buildMiniPair(slot2, second)
end

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
