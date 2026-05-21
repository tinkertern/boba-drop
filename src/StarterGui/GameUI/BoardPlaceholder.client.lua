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

-- Diagnostic helpers. Internal only: prints/warns go to the Studio Output
-- window so Sarah can paste them back when something looks off. Tag every
-- line with [BoardRenderer] so it's greppable.
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

local function countCells(cells)
    if type(cells) ~= "table" then return 0, 0 end
    local rowCount, cellCount = 0, 0
    for r = 1, BOARD_TOTAL_HEIGHT do
        local rowTable = rowLookup(cells, r)
        if rowTable ~= nil then
            rowCount += 1
            for c = 1, BOARD_WIDTH do
                if cellLookup(rowTable, c) then cellCount += 1 end
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
-- Two separate pools so a transient "active" overlay can never destroy the
-- "locked" pearl underneath it. Locked is the source of truth (server-side
-- snapshot); active is a per-frame overlay owned by ActivePieceUpdate.
local lockedPearls = {}
local activePearls = {}

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
    local key = posKey(row, col)
    local cell = cellsByPos[key]
    if not cell then return end
    if kind == "active" then
        -- Diagnostic: surface the conflict so we can confirm the fix is wired
        -- when Sarah retests the danger-row spawn case.
        if lockedPearls[key] then
            print(("[BoardRenderer] paintPearl conflict avoided: locked at (%d, %d) vs active at (%d, %d)"):format(row, col, row, col))
        end
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

local function clearActivePearls()
    for key, entry in pairs(activePearls) do
        if entry.pearl then entry.pearl:Destroy() end
        activePearls[key] = nil
    end
end

local function clearAll()
    for key, entry in pairs(lockedPearls) do
        if entry.pearl then entry.pearl:Destroy() end
        lockedPearls[key] = nil
    end
    for key, entry in pairs(activePearls) do
        if entry.pearl then entry.pearl:Destroy() end
        activePearls[key] = nil
    end
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

    local punchInfo = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    local punch = TweenService:Create(pearl, punchInfo, {
        Size = UDim2.fromScale(0.82 * 1.4, 0.82 * 1.4),
        BackgroundColor3 = UIConstants.Colors.PearlHighlight,
    })
    punch:Play()

    task.delay(0.08, function()
        if not pearl or not pearl.Parent then return end
        local shrinkInfo = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
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
    local base = 0.82
    local stretchInfo = TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    local squashInfo = TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
    local settleInfo = TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

    local stretch = TweenService:Create(pearl, stretchInfo, {
        Size = UDim2.fromScale(base * 0.92, base * 1.15),
    })
    stretch:Play()
    task.delay(0.06, function()
        if not pearl or not pearl.Parent then return end
        local squash = TweenService:Create(pearl, squashInfo, {
            Size = UDim2.fromScale(base * 1.05, base * 0.95),
        })
        squash:Play()
        task.delay(0.06, function()
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
        -- Animated destroy path. Each step's popped cells run the pop tween
        -- (scale punch, fade to white, shrink out) staggered by (i-1)*180ms,
        -- with sound pitch escalating per step. We still tally destroyPoppedCells
        -- semantics by counting what we hand off to animatePopThenDestroy.
        -- Reconcile + repaint waits until the final step's animation is well
        -- underway so the player sees pops before gravity settles.
        local totalDestroyed = 0
        local stepCount = 0
        local stepStagger = 0.18
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
                    end)
                end
            end
        end
        -- Wait for the final per-step animation to finish before settling
        -- gravity + repainting. Worst case: (stepCount * 180) + 220ms (the
        -- 220 covers the 80ms punch + 140ms shrink of the last step).
        task.spawn(function()
            local waitSeconds = (math.max(stepCount, 1) - 1) * stepStagger + 0.22
            task.wait(waitSeconds)
            local settledRemoved = 0
            if event.cells then
                settledRemoved = reconcileLockedToSnapshot(event.cells)
            end
            print(("[BoardRenderer] ChainCompleted destroyed %d popped cells across %d steps, settled %d more"):format(totalDestroyed, stepCount, settledRemoved))
            if event.cells then
                paintFromSnapshot(event.cells)
            end
        end)
        -- Chain HUD + score are handled by ChainCounter / ScoreDisplay scripts.
    end)
end

local roundEndRemote = Remotes:WaitForChild("RoundEnd", 10)
if roundEndRemote then
    roundEndRemote.OnClientEvent:Connect(function(event)
        print(("[BoardRenderer] RoundEnd received reason=%s winner=%s loser=%s"):format(
            fmtVal(event and event.reason),
            fmtVal(event and event.winner),
            fmtVal(event and event.loser)
        ))
        clearAll()
    end)
end

-- Stale-state safety net. If we enter in_match but no pearls show up within
-- 1.5s (no ActivePieceUpdate, no PieceLocked), warn so the lost-initial-spawn
-- race condition between RoomManager and StateSync is visible in Output. This
-- is a pure observation hook: it doesn't fix the race, just makes it loud.
local function snapshotHasAnyPearl()
    for _key, entry in pairs(lockedPearls) do
        if entry and entry.pearl then return true end
    end
    for _key, entry in pairs(activePearls) do
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
