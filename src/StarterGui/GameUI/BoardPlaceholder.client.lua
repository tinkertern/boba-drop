-- BoardRenderer (file still named BoardPlaceholder for Rojo continuity).
--
-- Renders the local player's board in response to server-fired events:
--   PieceLocked       : repaints locked pearls from the post-settle cells
--                       snapshot in the payload. Also clears any active
--                       overlay since the falling pair just became locked.
--   ActivePieceUpdate : paints the currently-falling pair at the pivot +
--                       partner-offset position. Active pearls are visually
--                       distinct from locked (heavier stroke).
--   ChainCompleted    : repaints from the post-chain cells snapshot, so any
--                       popped cells disappear and gravity-settled positions
--                       are reflected. Score / chain HUD are handled by their
--                       own scripts.
--   RoundEnd          : wipes the board for the next round.
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

-- Diagnostic helpers. Internal only: prints/warns go to the Studio Output
-- window so Sarah can paste them back when something looks off. Tag every
-- line with [BoardRenderer] so it's greppable.
local function countCells(cells)
    if type(cells) ~= "table" then return 0, 0 end
    local rowCount, cellCount = 0, 0
    for r = 1, BOARD_TOTAL_HEIGHT do
        local rowTable = cells[r]
        if rowTable ~= nil then
            rowCount += 1
            for c = 1, BOARD_WIDTH do
                if rowTable[c] then cellCount += 1 end
            end
        end
    end
    return rowCount, cellCount
end

local function fmtBool(v)
    if v == true then return "true" end
    if v == false then return "false" end
    return "nil"
end

local function fmtVal(v)
    if v == nil then return "nil" end
    return tostring(v)
end

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

-- Declarative repaint from a server-sent cells snapshot. cells is a 2D table
-- where cells[row][col] is either a color name ("Brown"/"Pink"/...) or nil.
-- Leaves active pearls alone (those are repainted by ActivePieceUpdate). Used
-- by PieceLocked and ChainCompleted, both of which carry the post-event grid.
local function paintFromSnapshot(cells)
    if type(cells) ~= "table" then return end
    for row = 1, BOARD_TOTAL_HEIGHT do
        local rowTable = cells[row]
        for col = 1, BOARD_WIDTH do
            local key = posKey(row, col)
            local existing = pearlByPos[key]
            local snapshotColor = rowTable and rowTable[col]
            if existing and existing.kind == "active" then
                -- active pearls are owned by ActivePieceUpdate; don't touch
            elseif snapshotColor then
                if existing and existing.pearl then existing.pearl:Destroy() end
                local pearl = buildPearl(cellsByPos[key], colorForServerName(snapshotColor), false)
                pearlByPos[key] = { pearl = pearl, kind = "locked" }
            else
                if existing and existing.pearl then existing.pearl:Destroy() end
                pearlByPos[key] = nil
            end
        end
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

local function isLocalEvent(event)
    if event == nil then return false end
    if event.isLocal ~= nil then return event.isLocal end
    return tostring(event.playerId) == localUserId
end

local pieceLockedRemote = Remotes:WaitForChild("PieceLocked", 10)
if pieceLockedRemote then
    pieceLockedRemote.OnClientEvent:Connect(function(event)
        local isLocal = isLocalEvent(event)
        local rowCount, cellCount = countCells(event and event.cells)
        print(("[BoardRenderer] PieceLocked received isLocal=%s cells=%s rows=%d filled=%d aRow=%s aCol=%s bRow=%s bCol=%s"):format(
            fmtBool(isLocal),
            (event and event.cells) and "Y" or "N",
            rowCount, cellCount,
            fmtVal(event and event.aRow), fmtVal(event and event.aCol),
            fmtVal(event and event.bRow), fmtVal(event and event.bCol)
        ))
        if not isLocal then return end
        -- The just-locked pair stops being "active". Clear any active overlay
        -- then repaint locked state from the post-settle snapshot.
        clearActivePearls()
        if event.cells then
            paintFromSnapshot(event.cells)
        else
            -- Pre-snapshot fallback: paint the two locked cells individually.
            paintPearl(event.aRow, event.aCol, event.a, "locked")
            paintPearl(event.bRow, event.bCol, event.b, "locked")
        end
    end)
end

local activePieceRemote = Remotes:WaitForChild("ActivePieceUpdate", 10)
if activePieceRemote then
    activePieceRemote.OnClientEvent:Connect(function(event)
        local isLocal = isLocalEvent(event)
        local aColor = event and event.colors and event.colors.a
        local bColor = event and event.colors and event.colors.b
        print(("[BoardRenderer] ActivePieceUpdate received isLocal=%s pivot=%s,%s ori=%s colors.a=%s colors.b=%s"):format(
            fmtBool(isLocal),
            fmtVal(event and event.pivotRow), fmtVal(event and event.pivotCol),
            fmtVal(event and event.orientation),
            fmtVal(aColor), fmtVal(bColor)
        ))
        if not isLocal then return end
        clearActivePearls()
        local pivotRow = event.pivotRow
        local pivotCol = event.pivotCol
        local orientation = event.orientation or 0
        if not pivotRow or not pivotCol then return end
        local dr, dc = partnerOffset(orientation)
        if aColor then paintPearl(pivotRow, pivotCol, aColor, "active") end
        if bColor then paintPearl(pivotRow + dr, pivotCol + dc, bColor, "active") end
    end)
end

local chainCompletedRemote = Remotes:WaitForChild("ChainCompleted", 10)
if chainCompletedRemote then
    chainCompletedRemote.OnClientEvent:Connect(function(event)
        local isLocal = isLocalEvent(event)
        local rowCount, cellCount = countCells(event and event.cells)
        print(("[BoardRenderer] ChainCompleted received isLocal=%s cells=%s rows=%d filled=%d chainLength=%s totalPopped=%s"):format(
            fmtBool(isLocal),
            (event and event.cells) and "Y" or "N",
            rowCount, cellCount,
            fmtVal(event and event.chainLength),
            fmtVal(event and event.totalPopped)
        ))
        if not isLocal then return end
        if event.cells then
            paintFromSnapshot(event.cells)
        end
        -- Chain HUD + score are handled by ChainCounter / ScoreDisplay scripts.
    end)
end

local roundEndRemote = Remotes:WaitForChild("RoundEnd", 10)
if roundEndRemote then
    roundEndRemote.OnClientEvent:Connect(function(event)
        print(("[BoardRenderer] RoundEnd received reason=%s winnerId=%s"):format(
            fmtVal(event and event.reason),
            fmtVal(event and event.winnerId)
        ))
        clearAll()
    end)
end

-- Stale-state safety net. If we enter in_match but no pearls show up within
-- 1.5s (no ActivePieceUpdate, no PieceLocked), warn so the lost-initial-spawn
-- race condition between RoomManager and StateSync is visible in Output. This
-- is a pure observation hook: it doesn't fix the race, just makes it loud.
local function snapshotHasAnyPearl()
    for _key, entry in pairs(pearlByPos) do
        if entry and entry.pearl then return true end
    end
    return false
end

local function watchInMatch()
    local enteredAt = os.clock()
    print(("[BoardRenderer] GameState -> in_match at t=%.2f userId=%s"):format(enteredAt, localUserId))
    task.delay(1.5, function()
        if player:GetAttribute("GameState") ~= "in_match" then return end
        if not snapshotHasAnyPearl() then
            warn("[BoardRenderer] In match for 1.5s but board is empty, likely missed initial spawn event")
        end
    end)
end

player:GetAttributeChangedSignal("GameState"):Connect(function()
    local state = player:GetAttribute("GameState")
    print(("[BoardRenderer] GameState changed -> %s"):format(fmtVal(state)))
    if state == "in_match" then
        watchInMatch()
    end
end)

if player:GetAttribute("GameState") == "in_match" then
    watchInMatch()
end
