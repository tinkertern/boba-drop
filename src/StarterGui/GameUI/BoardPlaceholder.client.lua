-- BoardRenderer (file still named BoardPlaceholder for Rojo continuity).
--
-- Renders the local player's board in response to server-fired events:
--   PieceLocked       : paints the two pearls of a just-locked piece
--   ActivePieceUpdate : paints the currently-falling pair (Engineer wiring in
--                       parallel; subscribed defensively so this script works
--                       before and after that event lands)
--   ChainCompleted    : TODO needs a board-snapshot payload to repaint
--                       declaratively after pops + gravity settle. Until then,
--                       the next PieceLocked event will overwrite stale cells
--                       where new pieces land.
--   RoundEnd          : wipes the board for the next round
--
-- The board is 6 columns wide x 14 rows tall (12 visible + 2 danger). Game
-- coordinates: row 1 is the cup floor, row 14 is the cup ceiling. The original
-- placeholder rendered this inverted (row 1 visually at the top); fixed below
-- so falling pieces actually appear to fall.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIConstants = require(ReplicatedStorage.Shared.UI.UIConstants)

local BOARD_WIDTH = 6
local BOARD_VISIBLE_HEIGHT = 12
local BOARD_TOTAL_HEIGHT = 14
local DANGER_ROW = BOARD_VISIBLE_HEIGHT

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local localUserId = tostring(player.UserId)

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "BoardPlaceholder"
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = UIConstants.ZOrder.Board
screenGui.IgnoreGuiInset = true
screenGui.Parent = playerGui

local container = Instance.new("Frame")
container.Name = "BoardFrame"
container.AnchorPoint = Vector2.new(0.5, 0.5)
container.Position = UDim2.fromScale(0.5, 0.5)
container.Size = UDim2.fromScale(0.45, 0.85)
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
containerStroke.Parent = container

local aspect = Instance.new("UIAspectRatioConstraint")
aspect.AspectRatio = BOARD_WIDTH / BOARD_TOTAL_HEIGHT
aspect.DominantAxis = Enum.DominantAxis.Height
aspect.Parent = container

local padding = Instance.new("UIPadding")
padding.PaddingTop = UDim.new(0, 12)
padding.PaddingBottom = UDim.new(0, 12)
padding.PaddingLeft = UDim.new(0, 12)
padding.PaddingRight = UDim.new(0, 12)
padding.Parent = container

local grid = Instance.new("UIGridLayout")
grid.Name = "Grid"
grid.CellSize = UDim2.fromScale(1 / BOARD_WIDTH, 1 / BOARD_TOTAL_HEIGHT)
grid.CellPadding = UDim2.new(0, 0, 0, 0)
grid.FillDirection = Enum.FillDirection.Horizontal
grid.HorizontalAlignment = Enum.HorizontalAlignment.Left
grid.VerticalAlignment = Enum.VerticalAlignment.Top
grid.SortOrder = Enum.SortOrder.LayoutOrder
grid.StartCorner = Enum.StartCorner.BottomLeft
grid.Parent = container

local CELL_TONE_A = Color3.fromRGB(252, 240, 220)
local CELL_TONE_B = Color3.fromRGB(245, 230, 208)

-- LayoutOrder formula: with StartCorner.BottomLeft, lower LayoutOrder sits at
-- the visual bottom. Game row 1 (cup floor) maps to LayoutOrder col..col+5,
-- game row 14 (cup ceiling) maps to LayoutOrder 79..84. Pieces fall from top
-- to bottom visually, matching the cup metaphor.
local function layoutOrderFor(row, col)
    return (row - 1) * BOARD_WIDTH + col
end

local cellsByPos = {}
local pearlByPos = {}

local function posKey(row, col)
    return row .. "_" .. col
end

local function colorForServerName(name)
    -- Server sends "Brown" / "Pink" / "Green" / "White" / "Garbage". Map to
    -- the UIConstants palette tokens.
    if name == "Brown" then return UIConstants.Colors.PearlBrown
    elseif name == "Pink" then return UIConstants.Colors.PearlPink
    elseif name == "Green" then return UIConstants.Colors.PearlGreen
    elseif name == "White" then return UIConstants.Colors.PearlWhite
    elseif name == "Garbage" then return UIConstants.Colors.GarbageBlock or UIConstants.Colors.PearlWhite
    end
    return UIConstants.Colors.PearlWhite
end

local function makeCell(row, col, isDanger)
    local cell = Instance.new("Frame")
    cell.Name = ("Cell_%d_%d"):format(row, col)
    if isDanger then
        cell.BackgroundColor3 = UIConstants.Colors.GarbageWarning
        cell.BackgroundTransparency = 0.45
    else
        cell.BackgroundColor3 = (row % 2 == 0) and CELL_TONE_A or CELL_TONE_B
        cell.BackgroundTransparency = 0.35
    end
    cell.BorderSizePixel = 0
    cell.LayoutOrder = layoutOrderFor(row, col)
    cell.Parent = container

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UIConstants.Corners.Cell
    corner.Parent = cell

    local stroke = Instance.new("UIStroke")
    stroke.Thickness = 1
    stroke.Color = UIConstants.Colors.StrokeSoft
    stroke.Transparency = 0.25
    stroke.Parent = cell

    cellsByPos[posKey(row, col)] = cell
    return cell
end

for row = 1, BOARD_TOTAL_HEIGHT do
    for col = 1, BOARD_WIDTH do
        makeCell(row, col, row == DANGER_ROW)
    end
end

local function buildPearl(parent, color, isActive)
    local p = Instance.new("Frame")
    p.Name = isActive and "ActivePearl" or "LockedPearl"
    p.Size = UDim2.fromScale(0.82, 0.82)
    p.Position = UDim2.fromScale(0.5, 0.5)
    p.AnchorPoint = Vector2.new(0.5, 0.5)
    p.BackgroundColor3 = color
    p.BorderSizePixel = 0
    p.Parent = parent

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UIConstants.Corners.Pearl
    corner.Parent = p

    local pearlStroke = Instance.new("UIStroke")
    pearlStroke.Color = UIConstants.Colors.StrokeWarm
    -- Active pearls get a slightly heavier stroke so the player can tell which
    -- piece is currently controllable vs already locked.
    pearlStroke.Thickness = isActive and 1.5 or 1
    pearlStroke.Transparency = isActive and 0.25 or 0.45
    pearlStroke.Parent = p

    local highlight = Instance.new("Frame")
    highlight.Name = "Highlight"
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

    return p
end

local function paintPearl(row, col, serverColorName, kind)
    if row < 1 or row > BOARD_TOTAL_HEIGHT or col < 1 or col > BOARD_WIDTH then
        return
    end
    local cell = cellsByPos[posKey(row, col)]
    if not cell then return end
    local existing = pearlByPos[posKey(row, col)]
    if existing and existing.pearl then existing.pearl:Destroy() end
    local pearl = buildPearl(cell, colorForServerName(serverColorName), kind == "active")
    pearlByPos[posKey(row, col)] = { pearl = pearl, kind = kind }
end

local function clearPearl(row, col)
    local key = posKey(row, col)
    local existing = pearlByPos[key]
    if existing and existing.pearl then existing.pearl:Destroy() end
    pearlByPos[key] = nil
end

local function clearActivePearls()
    for key, entry in pairs(pearlByPos) do
        if entry.kind == "active" then
            if entry.pearl then entry.pearl:Destroy() end
            pearlByPos[key] = nil
        end
    end
end

local function clearAll()
    for key, entry in pairs(pearlByPos) do
        if entry.pearl then entry.pearl:Destroy() end
        pearlByPos[key] = nil
    end
end

-- Partner-offset mirrors GameState.partnerOffset so the client can paint both
-- pearls of an active piece from {anchorRow, anchorCol, orientation, colors}.
-- 0: partner above (dr=+1, dc=0), 1: partner right (0,+1), 2: below (-1,0),
-- 3: left (0,-1).
local function partnerOffset(orientation)
    if orientation == 0 then return 1, 0
    elseif orientation == 1 then return 0, 1
    elseif orientation == 2 then return -1, 0
    else return 0, -1
    end
end

local Remotes = ReplicatedStorage:WaitForChild("Remotes", 30)
if not Remotes then
    warn("[BoardRenderer] Remotes folder missing; renderer will stay static")
    return
end

local pieceLockedRemote = Remotes:WaitForChild("PieceLocked", 10)
if pieceLockedRemote then
    pieceLockedRemote.OnClientEvent:Connect(function(event)
        if tostring(event.playerId) ~= localUserId then return end
        clearPearl(event.aRow, event.aCol)
        clearPearl(event.bRow, event.bCol)
        paintPearl(event.aRow, event.aCol, event.a, "locked")
        paintPearl(event.bRow, event.bCol, event.b, "locked")
    end)
end

-- ActivePieceUpdate is being added by Engineer in parallel. Hook defensively
-- so this script works both before and after that remote ships.
local function tryHookActivePiece()
    local remote = Remotes:FindFirstChild("ActivePieceUpdate")
    if not remote then return end
    remote.OnClientEvent:Connect(function(event)
        if tostring(event.playerId) ~= localUserId then return end
        clearActivePearls()
        local anchorRow = event.position and event.position.anchorRow or event.anchorRow
        local anchorCol = event.position and event.position.anchorCol or event.anchorCol
        local orientation = event.orientation or 0
        if not anchorRow or not anchorCol then return end
        local dr, dc = partnerOffset(orientation)
        local aColor = (event.colors and event.colors.pearlA) or event.a
        local bColor = (event.colors and event.colors.pearlB) or event.b
        if aColor then paintPearl(anchorRow, anchorCol, aColor, "active") end
        if bColor then paintPearl(anchorRow + dr, anchorCol + dc, bColor, "active") end
    end)
end
tryHookActivePiece()
Remotes.ChildAdded:Connect(function(child)
    if child.Name == "ActivePieceUpdate" then tryHookActivePiece() end
end)

local roundEndRemote = Remotes:WaitForChild("RoundEnd", 10)
if roundEndRemote then
    roundEndRemote.OnClientEvent:Connect(function(_event)
        clearAll()
    end)
end

-- TODO: ChainCompleted needs a popped-cells list or a board snapshot in its
-- payload to repaint declaratively after pops + gravity settle. Pending the
-- contract update from Engineer. Until then, chains leave their pre-pop pearls
-- visible; subsequent PieceLocked events overwrite the cells where new pieces
-- land, but mid-chain pops will linger as ghost pearls. The score + chain HUD
-- reflect the chain landing even though the board renderer is stale.
