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
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

-- Placeholder Roblox library asset for pop/lock SFX. Same source id for both;
-- chain pops pitch up per step, lock plays at lower pitch. Swap to a custom
-- upload later if Sarah wants a curated set.
local POP_SOUND_ID = "rbxassetid://6732690176"

local UIConstants = require(ReplicatedStorage.Shared.UI.UIConstants)

local BOARD_WIDTH = 6
local BOARD_VISIBLE_HEIGHT = 12
local BOARD_TOTAL_HEIGHT = 14
local DANGER_ROW = BOARD_VISIBLE_HEIGHT

-- Roblox RemoteEvent marshalling converts sparse-keyed tables to dictionaries
-- with string keys. snap[r] = {[3]="Pink"} on the server arrives as
-- snap[r] = {["3"]="Pink"} on the client. Direct integer lookup misses it.
-- Always try the string-key fallback when looking up a snapshot cell.
local function cellLookup(rowTable, c)
    if rowTable == nil then return nil end
    local v = rowTable[c]
    if v ~= nil then return v end
    return rowTable[tostring(c)]
end

local function rowLookup(cells, r)
    if cells == nil then return nil end
    local v = cells[r]
    if v ~= nil then return v end
    return cells[tostring(r)]
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
-- Two separate pools so a transient "active" overlay can never destroy the
-- "locked" pearl underneath it. Locked is the source of truth (server-side
-- snapshot); active is a per-frame overlay owned by ActivePieceUpdate.
-- ghostPearls is a third pool, drop-target outline tied to the active piece;
-- rebuilt fresh on every ActivePieceUpdate, never destructive of lockedPearls.
local lockedPearls = {}
local activePearls = {}
local ghostPearls = {}
local dangerRowCells = {}

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
        -- Starts barely-visible; pulse driver raises transparency dynamically
        -- as the player's stack approaches the danger threshold (A8).
        cell.BackgroundTransparency = 0.85
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
        local cell = makeCell(row, col, row == DANGER_ROW)
        if row == DANGER_ROW then
            table.insert(dangerRowCells, cell)
        end
    end
end

-- Static baseline transparency for danger row cells; the dynamic pulse
-- (A8) overrides this each frame when the player's stack approaches the
-- danger threshold. Stored so we can restore exactly on board clear.
local DANGER_BASELINE_TRANSPARENCY = 0.85

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
    local key = posKey(row, col)
    local cell = cellsByPos[key]
    if not cell then return end
    if kind == "active" then
        local existingActive = activePearls[key]
        if existingActive and existingActive.pearl then existingActive.pearl:Destroy() end
        local pearl = buildPearl(cell, colorForServerName(serverColorName), true)
        activePearls[key] = { pearl = pearl, kind = "active" }
    else
        local existingLocked = lockedPearls[key]
        if existingLocked and existingLocked.pearl then existingLocked.pearl:Destroy() end
        local pearl = buildPearl(cell, colorForServerName(serverColorName), false)
        lockedPearls[key] = { pearl = pearl, kind = "locked" }
    end
end

local function clearPearl(row, col)
    local key = posKey(row, col)
    local existingLocked = lockedPearls[key]
    if existingLocked and existingLocked.pearl then existingLocked.pearl:Destroy() end
    lockedPearls[key] = nil
    local existingActive = activePearls[key]
    if existingActive and existingActive.pearl then existingActive.pearl:Destroy() end
    activePearls[key] = nil
end

-- Tracks the currently-falling pair as a single coherent object across
-- ActivePieceUpdate events. When colors match the previous tick, we tween the
-- existing Frames between cell positions (A4: smooth fall). When colors differ,
-- the piece is new and we destroy + rebuild. Cleared by clearActivePearls.
--
-- aPearl / bPearl are parented to `container` (not to the cell) so we can
-- tween Position smoothly without reparent thrash. Cells remain the layout
-- anchors; we compute their absolute pixel center on demand.
local activePieceState = {
    aPearl = nil,
    bPearl = nil,
    aColor = nil,
    bColor = nil,
    pivotRow = nil,
    pivotCol = nil,
    orientation = nil,
}

local function clearActivePearls()
    if activePieceState.aPearl then
        activePieceState.aPearl:Destroy()
        activePieceState.aPearl = nil
    end
    if activePieceState.bPearl then
        activePieceState.bPearl:Destroy()
        activePieceState.bPearl = nil
    end
    activePieceState.aColor = nil
    activePieceState.bColor = nil
    activePieceState.pivotRow = nil
    activePieceState.pivotCol = nil
    activePieceState.orientation = nil
    -- Also drain the legacy activePearls pool in case any cell-parented active
    -- pearls were left from the pre-A4 flow.
    for key, entry in pairs(activePearls) do
        if entry.pearl then entry.pearl:Destroy() end
        activePearls[key] = nil
    end
end

local function clearGhostPearls()
    for i, pearl in ipairs(ghostPearls) do
        if pearl then pearl:Destroy() end
        ghostPearls[i] = nil
    end
end

local function clearAll()
    for key, entry in pairs(lockedPearls) do
        if entry.pearl then entry.pearl:Destroy() end
        lockedPearls[key] = nil
    end
    clearActivePearls()
    clearGhostPearls()
end

-- Declarative repaint from a server-sent cells snapshot. cells is a 2D table
-- where cells[row][col] is either a color name ("Brown"/"Pink"/...) or nil.
-- Touches only the locked pool. The active overlay is owned by
-- ActivePieceUpdate and is left alone here. Used by PieceLocked and
-- ChainCompleted, both of which carry the post-event grid.
--
-- ADDITIVE ONLY. Roblox RemoteEvent serialization truncates mixed-sparse Lua
-- tables: a row like {[1]="Brown",[3]="Pink"} has #t==1 so it gets marshalled
-- as the JSON array ["Brown"], silently dropping [3]="Pink" on the wire. If we
-- destroyed cells absent from the incoming snapshot, locked pearls in
-- non-contiguous columns would disappear on every subsequent lock. So this
-- function only paints/updates cells the snapshot explicitly contains.
-- Destruction is the caller's job: ChainCompleted uses event.steps[i].cellsPopped,
-- RoundEnd uses clearAll(). PieceLocked never destroys via this path.
local function paintFromSnapshot(cells)
    if type(cells) ~= "table" then return end
    for row = 1, BOARD_TOTAL_HEIGHT do
        local rowTable = rowLookup(cells, row)
        for col = 1, BOARD_WIDTH do
            local snapshotColor = cellLookup(rowTable, col)
            if snapshotColor then
                local key = posKey(row, col)
                local existingLocked = lockedPearls[key]
                if existingLocked and existingLocked.pearl then existingLocked.pearl:Destroy() end
                local pearl = buildPearl(cellsByPos[key], colorForServerName(snapshotColor), false)
                lockedPearls[key] = { pearl = pearl, kind = "locked" }
            end
        end
    end
end

-- Reconcile current locked pearls against a post-chain snapshot. Used by
-- ChainCompleted to reflect gravity settle: surviving pearls that moved to
-- new rows have their old positions cleared so they no longer hang in mid-air.
-- Safe to use destructively here because the snapshot is dense (false in empty
-- cells, server-side fix 393b098) so we won't drop entries to truncation.
-- PieceLocked still uses additive paint because there's no gravity moment.
local function reconcileLockedToSnapshot(cells)
    if type(cells) ~= "table" then return 0 end
    local removed = 0
    for key, entry in pairs(lockedPearls) do
        local r, c = key:match("(%d+)_(%d+)")
        r, c = tonumber(r), tonumber(c)
        if r and c then
            local rowTable = rowLookup(cells, r)
            local snapshotColor = cellLookup(rowTable, c)
            if not snapshotColor then
                if entry.pearl then entry.pearl:Destroy() end
                lockedPearls[key] = nil
                removed += 1
            end
        end
    end
    return removed
end

-- Explicit destruction path for chain pops. Server's ChainCompleted payload
-- carries per-step cellsPopped (list of {row, col, color}) since commit 44e7003.
-- Iterating these and clearing locked pearls at each coordinate is robust to
-- the snapshot truncation issue, because the popped coordinates are sent as a
-- list (not a sparse 2D table) so Roblox marshalling preserves them.
local function destroyPoppedCells(cellsPopped)
    if type(cellsPopped) ~= "table" then return 0 end
    local destroyed = 0
    for _, entry in ipairs(cellsPopped) do
        if type(entry) == "table" then
            local r = entry.row or entry[1]
            local c = entry.col or entry[2]
            if type(r) == "number" and type(c) == "number" then
                local key = posKey(r, c)
                local existingLocked = lockedPearls[key]
                if existingLocked and existingLocked.pearl then existingLocked.pearl:Destroy() end
                if lockedPearls[key] ~= nil then
                    destroyed += 1
                    lockedPearls[key] = nil
                end
            end
        end
    end
    return destroyed
end

-- Animated single-cell pop. Detaches the pearl from the lockedPearls pool so
-- subsequent paints / reconciles don't trip over it, then runs:
--   1) scale punch 1.0 -> 1.4 over 80ms (Quad/Out)
--   2) color tween toward PearlHighlight (white) over the same 80ms
--   3) shrink to 0 + fade transparency to 1 over 140ms (Quad/In)
-- After 220ms the pearl is destroyed. Per-cell Sound parented to the pearl so
-- it cleans up when the pearl is destroyed; pitch escalates per chain step.
local function animatePopThenDestroy(row, col, stepIndex)
    local key = posKey(row, col)
    local entry = lockedPearls[key]
    if not entry or not entry.pearl then return end
    local pearl = entry.pearl
    -- Detach so reconcile / additive paint won't double-destroy or repaint over it.
    lockedPearls[key] = nil

    -- Per-pearl Sound. Parent to pearl so destruction cleans it up if Ended
    -- never fires (e.g., asset load failure).
    local sound = Instance.new("Sound")
    sound.SoundId = POP_SOUND_ID
    sound.Volume = 0.6
    sound.PlaybackSpeed = 1.0 + (stepIndex - 1) * 0.1
    sound.Parent = pearl
    sound.Ended:Connect(function()
        sound:Destroy()
    end)
    sound:Play()

    -- Slowed 2.5x from original (0.08 punch, 0.14 shrink, 0.18 stagger) so the
    -- pop reads clearly at a low frame-rate screen recording. Total per-pearl
    -- animation is now 0.20 + 0.35 = 0.55s; per-step stagger lives in the
    -- ChainCompleted handler.
    local punchInfo = TweenInfo.new(0.20, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    local punch = TweenService:Create(pearl, punchInfo, {
        Size = UDim2.fromScale(0.82 * 1.4, 0.82 * 1.4),
        BackgroundColor3 = UIConstants.Colors.PearlHighlight,
    })
    punch:Play()

    task.delay(0.20, function()
        if not pearl or not pearl.Parent then return end
        local shrinkInfo = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
        local shrink = TweenService:Create(pearl, shrinkInfo, {
            Size = UDim2.fromScale(0, 0),
            BackgroundTransparency = 1,
        })
        shrink:Play()
        shrink.Completed:Connect(function()
            if pearl then pearl:Destroy() end
        end)
    end)
end

-- Squish-bounce on a freshly-locked pearl. Reads the locked entry at (row, col)
-- and tweens its Size through a Y-stretch, X-stretch, settle sequence. Cheap
-- to call: if no pearl is there (shouldn't happen post-paintFromSnapshot but
-- guarded anyway), bails silently.
local function animateLockSquish(row, col)
    local key = posKey(row, col)
    local entry = lockedPearls[key]
    if not entry or not entry.pearl then return end
    local pearl = entry.pearl
    -- Slowed 2.5x from original 0.06 each to 0.15 each so the squish reads at
    -- low-fps screen recordings. Total bounce is now 0.45s (was 0.18s).
    local base = 0.82
    local stretchInfo = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    local squashInfo = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
    local settleInfo = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

    local stretch = TweenService:Create(pearl, stretchInfo, {
        Size = UDim2.fromScale(base * 0.92, base * 1.15),
    })
    stretch:Play()
    task.delay(0.15, function()
        if not pearl or not pearl.Parent then return end
        local squash = TweenService:Create(pearl, squashInfo, {
            Size = UDim2.fromScale(base * 1.05, base * 0.95),
        })
        squash:Play()
        task.delay(0.15, function()
            if not pearl or not pearl.Parent then return end
            local settle = TweenService:Create(pearl, settleInfo, {
                Size = UDim2.fromScale(base, base),
            })
            settle:Play()
        end)
    end)
end

-- One-shot lock SFX. Lower pitch than pop, slightly quieter. Parented to the
-- screenGui briefly, self-destructs on Ended.
local function playLockSound()
    local sound = Instance.new("Sound")
    sound.SoundId = POP_SOUND_ID
    sound.Volume = 0.4
    sound.PlaybackSpeed = 0.7
    sound.Parent = screenGui
    sound.Ended:Connect(function()
        sound:Destroy()
    end)
    sound:Play()
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

--------------------------------------------------------------------------------
-- A4 helpers: container-relative pearl positioning + tween
--------------------------------------------------------------------------------

-- Cells are children of `container` arranged by UIGridLayout. To tween an
-- active pearl between cells, we parent it directly to `container` and place
-- it with pixel offsets computed from the target cell's AbsolutePosition.
-- AnchorPoint (0.5, 0.5) means Position points at the cell center.
--
-- Defensive against pre-layout AbsoluteSize=zero (can happen on the very first
-- ActivePieceUpdate if the grid hasn't been measured yet): wait one frame and
-- retry up to 5 times before giving up.
local function cellCenterOffset(row, col)
    local cell = cellsByPos[posKey(row, col)]
    if not cell then return nil end
    local cellSize = cell.AbsoluteSize
    local attempts = 0
    while (cellSize.X <= 0 or cellSize.Y <= 0) and attempts < 5 do
        RunService.RenderStepped:Wait()
        cellSize = cell.AbsoluteSize
        attempts += 1
    end
    if cellSize.X <= 0 or cellSize.Y <= 0 then return nil end
    local cellPos = cell.AbsolutePosition
    local containerPos = container.AbsolutePosition
    local centerX = (cellPos.X - containerPos.X) + cellSize.X * 0.5
    local centerY = (cellPos.Y - containerPos.Y) + cellSize.Y * 0.5
    return UDim2.fromOffset(centerX, centerY), cellSize
end

-- Build an active pearl parented to `container` at the given cell's center.
-- Mirrors buildPearl shape/styling but uses pixel offsets so we can tween
-- Position smoothly across cell boundaries.
local function buildActivePearlAtCell(row, col, color)
    local centerOffset, cellSize = cellCenterOffset(row, col)
    if not centerOffset then return nil end
    local p = Instance.new("Frame")
    p.Name = "ActivePearl"
    p.AnchorPoint = Vector2.new(0.5, 0.5)
    p.Position = centerOffset
    p.Size = UDim2.fromOffset(cellSize.X * 0.82, cellSize.Y * 0.82)
    p.BackgroundColor3 = color
    p.BorderSizePixel = 0
    p.ZIndex = 5
    p.Parent = container

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UIConstants.Corners.Pearl
    corner.Parent = p

    local pearlStroke = Instance.new("UIStroke")
    pearlStroke.Color = UIConstants.Colors.StrokeWarm
    pearlStroke.Thickness = 1.5
    pearlStroke.Transparency = 0.25
    pearlStroke.Parent = p

    local highlight = Instance.new("Frame")
    highlight.Name = "Highlight"
    highlight.Size = UIConstants.Pearl.HighlightSize
    highlight.Position = UIConstants.Pearl.HighlightPosition
    highlight.AnchorPoint = UIConstants.Pearl.HighlightAnchor
    highlight.BackgroundColor3 = UIConstants.Colors.PearlHighlight
    highlight.BackgroundTransparency = UIConstants.Pearl.HighlightTransparency
    highlight.BorderSizePixel = 0
    highlight.ZIndex = 6
    highlight.Parent = p

    local highlightCorner = Instance.new("UICorner")
    highlightCorner.CornerRadius = UIConstants.Corners.Pearl
    highlightCorner.Parent = highlight

    return p
end

-- Move an existing active pearl to a new cell. Snap if duration <= 0, else
-- tween Position with the given TweenInfo. Size is updated to match the new
-- cell's pixel size (matters if the screen resized between events; rare).
local function moveActivePearlToCell(pearl, row, col, tweenInfo)
    if not pearl then return end
    local centerOffset, cellSize = cellCenterOffset(row, col)
    if not centerOffset then return end
    local targetSize = UDim2.fromOffset(cellSize.X * 0.82, cellSize.Y * 0.82)
    if not tweenInfo then
        pearl.Position = centerOffset
        pearl.Size = targetSize
        return
    end
    local tween = TweenService:Create(pearl, tweenInfo, {
        Position = centerOffset,
        Size = targetSize,
    })
    tween:Play()
end

-- Classify the motion between the previous and new active-piece state so we
-- can pick the right tween timing (or snap on hard drop).
-- Returns: TweenInfo or nil. nil means "snap, no tween" (hard drop case).
local function classifyActiveTween(prevPivotRow, prevPivotCol, prevOri, newPivotRow, newPivotCol, newOri)
    local rowDelta = newPivotRow - prevPivotRow
    local colDelta = newPivotCol - prevPivotCol
    local oriChanged = (newOri ~= prevOri)
    if rowDelta <= -2 then
        -- Hard drop: instant snap, the slam should feel discrete.
        return nil
    end
    if oriChanged then
        return TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    end
    if rowDelta == -1 and colDelta == 0 then
        -- Gravity tick fall.
        return TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    end
    if rowDelta == 0 and (colDelta == 1 or colDelta == -1) then
        -- Player lateral move.
        return TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    end
    -- Fallback: any other small delta gets the gravity-tick feel.
    return TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
end

--------------------------------------------------------------------------------
-- A5 helpers: drop ghost outline
--------------------------------------------------------------------------------

-- Returns true if the given (row, col) is occupied by a locked pearl or sits
-- below the cup floor. Used by the ghost ray-trace to find the landing row.
local function isCellBlocked(row, col)
    if row < 1 then return true end
    if col < 1 or col > BOARD_WIDTH then return true end
    return lockedPearls[posKey(row, col)] ~= nil
end

-- Trace the active pair downward as a rigid body. Both pivot and partner must
-- find empty cells simultaneously. Returns landingPivotRow such that the
-- partner sits at landingPivotRow + dr. nil means no valid landing (already
-- at or below cup floor).
local function traceLanding(pivotRow, pivotCol, dr, dc)
    local partnerCol = pivotCol + dc
    -- Walk downward from current position. Find the lowest pivotRow such that
    -- both (pivotRow, pivotCol) and (pivotRow + dr, partnerCol) are empty AND
    -- the cell directly below the lower of the two pearls would be blocked
    -- (or we are at row 1). We do this by walking down while still legal.
    local row = pivotRow
    while row >= 1 do
        local nextRow = row - 1
        local nextPivotBlocked = isCellBlocked(nextRow, pivotCol)
        local nextPartnerBlocked = isCellBlocked(nextRow + dr, partnerCol)
        -- If either pearl can't move down one more step, current `row` is the
        -- landing row.
        if nextPivotBlocked or nextPartnerBlocked then
            return row
        end
        row = nextRow
    end
    return 1
end

-- Build a single ghost pearl: an outline-only ring in the pearl's color so
-- the landing position reads clearly against the cream cup floor without
-- ever being mistaken for a real (filled) pearl. Solid stroke at thickness
-- 3 gives enough weight to be legible against the new milk-tea backdrop;
-- BackgroundTransparency=1 keeps the cell visible inside the outline.
local function buildGhostPearl(row, col, color)
    local cell = cellsByPos[posKey(row, col)]
    if not cell then return nil end
    local p = Instance.new("Frame")
    p.Name = "GhostPearl"
    p.Size = UDim2.fromScale(0.82, 0.82)
    p.Position = UDim2.fromScale(0.5, 0.5)
    p.AnchorPoint = Vector2.new(0.5, 0.5)
    p.BackgroundColor3 = color
    p.BackgroundTransparency = 1
    p.BorderSizePixel = 0
    p.ZIndex = 2
    p.Parent = cell

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UIConstants.Corners.Pearl
    corner.Parent = p

    local stroke = Instance.new("UIStroke")
    stroke.Color = color
    stroke.Thickness = 3
    stroke.Transparency = 0.15
    stroke.Parent = p
    return p
end

-- Repaint the ghost from the current active piece state. Cheap; clears the
-- previous pair and paints two fresh ghost pearls. Skipped only when the
-- piece already sits at its landing row (outline would just hug the active
-- pearl). The row-1-floor skip was removed at Sarah's request 2026-05-20:
-- showing the ghost at the floor is still informative as you slide the piece
-- across an empty cup floor.
local function paintGhost(pivotRow, pivotCol, orientation, aColor, bColor)
    clearGhostPearls()
    if not pivotRow or not pivotCol then return end
    local dr, dc = partnerOffset(orientation)
    local landingPivotRow = traceLanding(pivotRow, pivotCol, dr, dc)
    if not landingPivotRow or landingPivotRow == pivotRow then return end
    local partnerRow = landingPivotRow + dr
    local partnerCol = pivotCol + dc
    if aColor then
        local g = buildGhostPearl(landingPivotRow, pivotCol, colorForServerName(aColor))
        if g then table.insert(ghostPearls, g) end
    end
    if bColor then
        local g = buildGhostPearl(partnerRow, partnerCol, colorForServerName(bColor))
        if g then table.insert(ghostPearls, g) end
    end
end

--------------------------------------------------------------------------------
-- A8 helpers: danger row dynamic pulse
--------------------------------------------------------------------------------

-- Pulse driver state. Only one RenderStepped connection at a time; the
-- generation counter lets us cheaply cancel previous pulses without holding
-- onto signal connections.
local dangerPulseConnection = nil
local dangerPulseGeneration = 0
local DANGER_COLOR = UIConstants.Colors.GarbageWarning

local function setDangerRowStatic(transparency)
    for _, cell in ipairs(dangerRowCells) do
        cell.BackgroundTransparency = transparency
    end
end

local function stopDangerPulse()
    dangerPulseGeneration += 1
    if dangerPulseConnection then
        dangerPulseConnection:Disconnect()
        dangerPulseConnection = nil
    end
end

-- Drive the danger row cells with a sine pulse around the given baseline
-- transparency. Amplitude swings BackgroundTransparency by +/- 0.15 so it
-- visibly breathes without strobing.
local function startDangerPulse(baseTransparency, period)
    stopDangerPulse()
    local gen = dangerPulseGeneration
    local startClock = os.clock()
    dangerPulseConnection = RunService.RenderStepped:Connect(function()
        if gen ~= dangerPulseGeneration then return end
        local elapsed = os.clock() - startClock
        local phase = (elapsed / period) * math.pi * 2
        local pulse = math.sin(phase) * 0.15
        local t = math.clamp(baseTransparency + pulse, 0, 1)
        for _, cell in ipairs(dangerRowCells) do
            cell.BackgroundColor3 = DANGER_COLOR
            cell.BackgroundTransparency = t
        end
    end)
end

-- Find the highest occupied row across all columns in the locked pool.
-- Returns 0 when the board is empty.
local function highestOccupiedRow()
    local highest = 0
    for key, _entry in pairs(lockedPearls) do
        local r = tonumber(key:match("^(%d+)"))
        if r and r > highest then highest = r end
    end
    return highest
end

-- Recompute the danger row visualization from the current locked-pearl state.
-- Called after every paintFromSnapshot, and reset to static on RoundEnd.
local function updateDangerRow()
    local highest = highestOccupiedRow()
    if highest <= 9 then
        stopDangerPulse()
        setDangerRowStatic(DANGER_BASELINE_TRANSPARENCY)
    elseif highest == 10 then
        startDangerPulse(0.65, 2.0)
    elseif highest == 11 then
        startDangerPulse(0.4, 1.2)
    else
        -- 12 or above (overflow territory).
        startDangerPulse(0.15, 0.6)
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
        if not isLocal then return end
        -- The just-locked pair stops being "active". Clear any active overlay
        -- then repaint locked state from the post-settle snapshot. Ghost also
        -- goes away; the next ActivePieceUpdate (new piece) will repaint it.
        clearActivePearls()
        clearGhostPearls()
        if event.cells then
            -- Reconcile first so any locked pearl now absent from the snapshot
            -- (e.g., a garbage-applied gravitySettle moved cells) is destroyed
            -- before we additively repaint. Engineer's dense snapshot fix
            -- (393b098) makes the snapshot reliable enough to trust for this.
            -- Without this step, partner pearls that gravity-settled into a
            -- different column would visually float at their pre-settle row.
            reconcileLockedToSnapshot(event.cells)
            paintFromSnapshot(event.cells)
        else
            -- Pre-snapshot fallback: paint the two locked cells individually.
            paintPearl(event.aRow, event.aCol, event.a, "locked")
            paintPearl(event.bRow, event.bCol, event.b, "locked")
        end
        -- Lock feedback: squish both freshly-locked pearls and play one tick.
        -- Coexists with any subsequent chain pop on the same pearls; we don't
        -- try to gate this against ChainCompleted because overlap is fine.
        if type(event.aRow) == "number" and type(event.aCol) == "number" then
            animateLockSquish(event.aRow, event.aCol)
        end
        if type(event.bRow) == "number" and type(event.bCol) == "number" then
            animateLockSquish(event.bRow, event.bCol)
        end
        playLockSound()

        -- A8: re-evaluate danger row pulse against the new locked-pearl stack.
        updateDangerRow()
    end)
end

local activePieceRemote = Remotes:WaitForChild("ActivePieceUpdate", 10)
if activePieceRemote then
    activePieceRemote.OnClientEvent:Connect(function(event)
        local isLocal = isLocalEvent(event)
        local aColor = event and event.colors and event.colors.a
        local bColor = event and event.colors and event.colors.b
        if not isLocal then return end
        local pivotRow = event.pivotRow
        local pivotCol = event.pivotCol
        local orientation = event.orientation or 0
        if not pivotRow or not pivotCol then
            clearActivePearls()
            clearGhostPearls()
            return
        end
        local dr, dc = partnerOffset(orientation)

        -- Revert from A4 smooth-fall (container-parented pixel-offset) back to
        -- cell-parented active pearls via paintPearl. The reparent approach was
        -- positioning pearls outside the visible cup on Sarah's playtest, making
        -- the active piece appear invisible. Cell-parenting is rock-solid and
        -- handles dpi/aspect ratio changes for free; we lose the smooth fall
        -- tween but keep the game playable. Smooth fall can be re-attempted in
        -- v1.1 via a cleaner approach (e.g., transient ghost frame that lerps
        -- under the active pearl while it teleports on tick).
        clearActivePearls()
        if aColor then paintPearl(pivotRow, pivotCol, aColor, "active") end
        if bColor then paintPearl(pivotRow + dr, pivotCol + dc, bColor, "active") end
        activePieceState.pivotRow = pivotRow
        activePieceState.pivotCol = pivotCol
        activePieceState.orientation = orientation
        activePieceState.aColor = aColor
        activePieceState.bColor = bColor

        -- A5: redraw the drop-ghost outline based on the new active position.
        paintGhost(pivotRow, pivotCol, orientation, aColor, bColor)
    end)
end

local chainCompletedRemote = Remotes:WaitForChild("ChainCompleted", 10)
if chainCompletedRemote then
    chainCompletedRemote.OnClientEvent:Connect(function(event)
        local isLocal = isLocalEvent(event)
        if not isLocal then return end
        -- Animated destroy path. Each step's popped cells run the pop tween
        -- (scale punch, fade to white, shrink out) staggered by (i-1)*180ms,
        -- with sound pitch escalating per step. We still tally destroyPoppedCells
        -- semantics by counting what we hand off to animatePopThenDestroy.
        -- Reconcile + repaint waits until the final step's animation is well
        -- underway so the player sees pops before gravity settles.
        local totalDestroyed = 0
        local stepCount = 0
        -- Slowed 2.5x from original 0.18s so multi-step chains read clearly at
        -- low-fps captures. Per-step gap is now 0.45s; a 3-chain takes about 1.35s
        -- of stagger plus 0.55s pop tail.
        local stepStagger = 0.45
        if type(event.steps) == "table" then
            for i, step in ipairs(event.steps) do
                if type(step) == "table" then
                    stepCount += 1
                    local cellsPopped = step.cellsPopped
                    if type(cellsPopped) == "table" then
                        for _, popEntry in ipairs(cellsPopped) do
                            if type(popEntry) == "table" then
                                local r = popEntry.row or popEntry[1]
                                local c = popEntry.col or popEntry[2]
                                if type(r) == "number" and type(c) == "number" and lockedPearls[posKey(r, c)] then
                                    totalDestroyed += 1
                                end
                            end
                        end
                    end
                    -- Garbage neighbour-clear: Engineer 0f55c5d added
                    -- step.garbageCleared listing ice cubes that were cleared
                    -- as a side-effect of adjacent color pops. Reuse the same
                    -- pop animation so they shatter on the same per-step beat
                    -- as the colors that broke them.
                    local garbageCleared = step.garbageCleared
                    if type(garbageCleared) == "table" then
                        for _, gcEntry in ipairs(garbageCleared) do
                            if type(gcEntry) == "table" then
                                local r = gcEntry.row or gcEntry[1]
                                local c = gcEntry.col or gcEntry[2]
                                if type(r) == "number" and type(c) == "number" and lockedPearls[posKey(r, c)] then
                                    totalDestroyed += 1
                                end
                            end
                        end
                    end
                    -- Spawn per step so staggered timing doesn't block the main thread.
                    task.spawn(function()
                        if i > 1 then
                            task.wait((i - 1) * stepStagger)
                        end
                        if type(cellsPopped) == "table" then
                            for _, popEntry in ipairs(cellsPopped) do
                                if type(popEntry) == "table" then
                                    local r = popEntry.row or popEntry[1]
                                    local c = popEntry.col or popEntry[2]
                                    if type(r) == "number" and type(c) == "number" then
                                        animatePopThenDestroy(r, c, i)
                                    end
                                end
                            end
                        end
                        if type(garbageCleared) == "table" then
                            for _, gcEntry in ipairs(garbageCleared) do
                                if type(gcEntry) == "table" then
                                    local r = gcEntry.row or gcEntry[1]
                                    local c = gcEntry.col or gcEntry[2]
                                    if type(r) == "number" and type(c) == "number" then
                                        animatePopThenDestroy(r, c, i)
                                    end
                                end
                            end
                        end
                    end)
                end
            end
        end
        -- Wait for the final per-step animation to finish before settling
        -- gravity + repainting. Worst case: (stepCount * 180) + 220ms (the
        -- 220 covers the 80ms punch + 140ms shrink of the last step).
        task.spawn(function()
            -- 0.55s tail = punch 0.20s + shrink 0.35s of the final step.
            local waitSeconds = (math.max(stepCount, 1) - 1) * stepStagger + 0.55
            task.wait(waitSeconds)
            local settledRemoved = 0
            if event.cells then
                settledRemoved = reconcileLockedToSnapshot(event.cells)
            end
            if event.cells then
                paintFromSnapshot(event.cells)
            end
            -- A8: chains can either spike the stack (rare; garbage incoming)
            -- or relieve it (typical). Recompute pulse against the settled
            -- locked-pearl state.
            updateDangerRow()
        end)
        -- Chain HUD + score are handled by ChainCounter / ScoreDisplay scripts.
    end)
end

-- Garbage fall animation. Each entry in cellsDropped is a final {row, col}
-- where the server placed a "Garbage" cell. We spawn a transient screen-level
-- ice pearl at the top of the column, tween its Position down to the target
-- cell's center, then on completion swap to a real cell-parented locked pearl
-- via paintPearl. Parented to a dedicated overlay ScreenGui so the transient
-- floats freely above the cup container (avoids the UIPadding-on-container
-- gotcha that broke the earlier smooth-fall attempt).
local garbageOverlay = Instance.new("ScreenGui")
garbageOverlay.Name = "BoardGarbageOverlay"
garbageOverlay.ResetOnSpawn = false
garbageOverlay.IgnoreGuiInset = true
garbageOverlay.DisplayOrder = UIConstants.ZOrder.Board + 1
garbageOverlay.Parent = playerGui

local function animateGarbageFall(cellsDropped)
    if type(cellsDropped) ~= "table" then return end
    for _, entry in ipairs(cellsDropped) do
        if type(entry) == "table" then
            local targetRow = entry.row or entry[1]
            local targetCol = entry.col or entry[2]
            if type(targetRow) == "number" and type(targetCol) == "number" then
                local topCell = cellsByPos[posKey(BOARD_TOTAL_HEIGHT, targetCol)]
                local targetCell = cellsByPos[posKey(targetRow, targetCol)]
                if topCell and targetCell then
                    local topCellPos = topCell.AbsolutePosition
                    local topCellSize = topCell.AbsoluteSize
                    local targetCellPos = targetCell.AbsolutePosition
                    local startX = topCellPos.X + topCellSize.X * 0.5
                    local startY = topCellPos.Y + topCellSize.Y * 0.5
                    local endX = targetCellPos.X + topCellSize.X * 0.5
                    local endY = targetCellPos.Y + topCellSize.Y * 0.5

                    local fallingPearl = Instance.new("Frame")
                    fallingPearl.Name = "FallingGarbage"
                    fallingPearl.AnchorPoint = Vector2.new(0.5, 0.5)
                    fallingPearl.Position = UDim2.fromOffset(startX, startY)
                    fallingPearl.Size = UDim2.fromOffset(topCellSize.X * 0.82, topCellSize.Y * 0.82)
                    fallingPearl.BackgroundColor3 = colorForServerName("Garbage")
                    fallingPearl.BorderSizePixel = 0
                    fallingPearl.Parent = garbageOverlay

                    local corner = Instance.new("UICorner")
                    corner.CornerRadius = UIConstants.Corners.Pearl
                    corner.Parent = fallingPearl

                    local stroke = Instance.new("UIStroke")
                    stroke.Color = UIConstants.Colors.StrokeWarm
                    stroke.Thickness = 1.5
                    stroke.Transparency = 0.45
                    stroke.Parent = fallingPearl

                    -- Tween duration scales with distance so all cubes land at
                    -- roughly the same gravity-like acceleration feel.
                    local distance = math.max(1, BOARD_TOTAL_HEIGHT - targetRow)
                    local duration = 0.20 + distance * 0.05
                    local info = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
                    local tween = TweenService:Create(fallingPearl, info, {
                        Position = UDim2.fromOffset(endX, endY),
                    })
                    tween:Play()
                    tween.Completed:Connect(function()
                        if fallingPearl then fallingPearl:Destroy() end
                        paintPearl(targetRow, targetCol, "Garbage", "locked")
                        updateDangerRow()
                    end)
                end
            end
        end
    end
end

local garbageAppliedRemote = Remotes:WaitForChild("GarbageApplied", 10)
if garbageAppliedRemote then
    garbageAppliedRemote.OnClientEvent:Connect(function(event)
        if not event then return end
        local isLocal = tostring(event.playerId) == localUserId
        if not isLocal then return end
        animateGarbageFall(event.cellsDropped)
    end)
end

local roundEndRemote = Remotes:WaitForChild("RoundEnd", 10)
if roundEndRemote then
    roundEndRemote.OnClientEvent:Connect(function(event)
        clearAll()
        -- A8: reset danger row to its quiet baseline; the board is empty so
        -- there's no overflow risk to telegraph.
        stopDangerPulse()
        setDangerRowStatic(DANGER_BASELINE_TRANSPARENCY)
    end)
end

