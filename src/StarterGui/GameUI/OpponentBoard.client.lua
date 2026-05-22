-- OpponentBoard: read-only mirror of opponent's cup to the right of your own.
-- Subscribes to the same PieceLocked / ChainCompleted RemoteEvents the main
-- BoardPlaceholder uses, but filters for isLocal == false. Renders into a
-- separate ScreenGui so the two boards live independently.
--
-- Deliberately stripped vs the main board:
--   * No active overlay (we only paint locked + chain pops from snapshots)
--   * No pop/lock animations (snapshot diff is the visual)
--   * No glossy highlight dot on pearls (mini board, less noise)
--   * Lighter danger row (their lose-state isn't your problem at a glance)
--
-- Snapshots are dense 6x14 (Engineer fix 393b098) so we can trust them for
-- both additive paint and destructive reconcile.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIConstants = require(ReplicatedStorage.Shared.UI.UIConstants)

local BOARD_WIDTH = 6
local BOARD_VISIBLE_HEIGHT = 12
local BOARD_TOTAL_HEIGHT = 14
local DANGER_ROW = BOARD_VISIBLE_HEIGHT

local CELL_TONE_A = Color3.fromRGB(252, 240, 220)
local CELL_TONE_B = Color3.fromRGB(245, 230, 208)

--------------------------------------------------------------------------------
-- Snapshot lookup helpers
--
-- Roblox RemoteEvent marshalling converts sparse integer-keyed tables into
-- dictionaries with string keys. snap[r] = {[3]="Pink"} arrives as
-- snap[r] = {["3"]="Pink"}. Always fall back to the string-key form.
--------------------------------------------------------------------------------

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

--------------------------------------------------------------------------------
-- Color mapping
--
-- Same shape as the main board's colorForServerName. Garbage maps to IceBase
-- so the in-cup garbage block reads as the same pastel ice as the main board.
--
-- TODO v1.1: opponent's theme is not broadcast yet, so opponent pearls render
-- with the Default palette (which is identical to UIConstants.Colors.Pearl*).
-- When opponent theme broadcast lands, swap this to Themes.byKey(opponentKey)
-- where opponentKey is piped from a server attribute set on the opponent
-- player. For now, the local player's equipped theme does NOT affect the
-- opponent's cup, which is what we want anyway (their cup is THEIR theme).
--------------------------------------------------------------------------------

local function colorForServerName(name)
    if name == "Brown" then return UIConstants.Colors.PearlBrown
    elseif name == "Pink" then return UIConstants.Colors.PearlPink
    elseif name == "Green" then return UIConstants.Colors.PearlGreen
    elseif name == "White" then return UIConstants.Colors.PearlWhite
    elseif name == "Garbage" then return UIConstants.Colors.GarbageBlock or UIConstants.Colors.IceBase
    end
    return UIConstants.Colors.PearlWhite
end

--------------------------------------------------------------------------------
-- ScreenGui scaffolding
--------------------------------------------------------------------------------

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "OpponentBoard"
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = UIConstants.ZOrder.Board
screenGui.IgnoreGuiInset = true
-- Initial state is hidden; the GameState attribute handler at the bottom of
-- this file is the only thing that turns it on.
screenGui.Enabled = false
screenGui.Parent = playerGui

-- Small "OPPONENT" label sitting just above the mini cup. Anchored top-center
-- Parented to screenGui (NOT the container) so UIGridLayout inside the
-- container doesn't treat the label as a 7th grid child. When we
-- previously re-parented the label INTO the container to anchor it to the
-- cup edge, the grid laid it out as the bottom-left slot (LayoutOrder 0),
-- pushing every cell one position forward and creating a staircase across
-- columns in Sarah's 2026-05-22 playtest.
--
-- The aspect lock keeps the container's height at Scale 0.65 of the
-- viewport, so its TOP edge is always at Scale Y = 0.175 (center 0.5
-- minus half-height 0.325). Positioning the label at Scale Y = 0.165
-- with AnchorPoint(0.5, 1) parks its bottom edge 0.01 scale units above
-- the cup top, a constant 8 to 14 pixel gap across viewport heights.
local label = Instance.new("TextLabel")
label.Name = "OpponentLabel"
label.AnchorPoint = Vector2.new(0.5, 1)
label.Position = UDim2.fromScale(0.78, 0.165)
label.Size = UDim2.fromOffset(120, 18)
label.BackgroundTransparency = 1
label.FontFace = UIConstants.Fonts.HUD
label.TextSize = UIConstants.TextSizes.HUDLabel
-- TextOnWarm reads cleanly against the in-match milk-tea brown backdrop
-- the label sits on; the previous TextSoft brown blended into the wash.
label.TextColor3 = UIConstants.Colors.TextOnWarm
label.TextXAlignment = Enum.TextXAlignment.Center
label.TextYAlignment = Enum.TextYAlignment.Center
label.Text = "OPPONENT"
label.Parent = screenGui

local container = Instance.new("Frame")
container.Name = "OpponentBoardFrame"
container.AnchorPoint = Vector2.new(0.5, 0.5)
container.Position = UDim2.fromScale(0.78, 0.5)
container.Size = UDim2.fromScale(0.18, 0.65)
container.BackgroundColor3 = UIConstants.Colors.Cream
container.BackgroundTransparency = 0
container.BorderSizePixel = 0
-- ClipsDescendants masks the Scale-based CellSize + UIPadding interaction:
-- 14 cells at container_height/14 each fits the container exactly, so the
-- 6px UIPadding offset pushes the bottom of the grid 6px PAST the cup's
-- cream background. Aspect-locking the cup shrank the overflow's relative
-- size, making the "cells below the cup" stripe visible in Sarah's
-- 2026-05-21 playtest. Clipping to the container hides the overflow.
container.ClipsDescendants = true
container.Parent = screenGui

-- Lock the mini cup to the same 6:14 aspect as the main board so the cells
-- inside (sized 1/6 width by 1/14 height of the container via UIGridLayout)
-- stay square on every viewport. Without this, ultrawide and tall-portrait
-- screens render non-square cells and the pearls clip to oblong UICorners.
local aspect = Instance.new("UIAspectRatioConstraint")
aspect.AspectRatio = BOARD_WIDTH / BOARD_TOTAL_HEIGHT
aspect.DominantAxis = Enum.DominantAxis.Height
aspect.Parent = container

-- (Previous parent-into-container re-anchor reverted: that approach put
-- the label inside the UIGridLayout, where it became the bottom-left slot
-- and staircased every grid cell over by one. Label now stays parented to
-- screenGui above, aspect-stable thanks to the height-locked container.)

local containerCorner = Instance.new("UICorner")
containerCorner.CornerRadius = UIConstants.Corners.Card
containerCorner.Parent = container

local containerStroke = Instance.new("UIStroke")
containerStroke.Color = UIConstants.Colors.StrokeWarm
containerStroke.Thickness = 1.5
containerStroke.Transparency = 0.55
containerStroke.Parent = container

local aspect = Instance.new("UIAspectRatioConstraint")
aspect.AspectRatio = BOARD_WIDTH / BOARD_TOTAL_HEIGHT
aspect.DominantAxis = Enum.DominantAxis.Height
aspect.Parent = container

local padding = Instance.new("UIPadding")
padding.PaddingTop = UDim.new(0, 6)
padding.PaddingBottom = UDim.new(0, 6)
padding.PaddingLeft = UDim.new(0, 6)
padding.PaddingRight = UDim.new(0, 6)
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

--------------------------------------------------------------------------------
-- Cell grid build
--------------------------------------------------------------------------------

local cellsByPos = {}
local lockedPearls = {}

local function posKey(row, col)
    return row .. "_" .. col
end

local function layoutOrderFor(row, col)
    return (row - 1) * BOARD_WIDTH + col
end

local function makeCell(row, col, isDanger)
    local cell = Instance.new("Frame")
    cell.Name = ("Cell_%d_%d"):format(row, col)
    if isDanger then
        -- Subtler danger tint than the main board. Their lose state isn't the
        -- player's focus; we want it readable but not screaming.
        cell.BackgroundColor3 = UIConstants.Colors.GarbageWarning
        cell.BackgroundTransparency = 0.7
    else
        cell.BackgroundColor3 = (row % 2 == 0) and CELL_TONE_A or CELL_TONE_B
        cell.BackgroundTransparency = 0.4
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
    stroke.Transparency = 0.35
    stroke.Parent = cell

    cellsByPos[posKey(row, col)] = cell
    return cell
end

for row = 1, BOARD_TOTAL_HEIGHT do
    for col = 1, BOARD_WIDTH do
        makeCell(row, col, row == DANGER_ROW)
    end
end

--------------------------------------------------------------------------------
-- Pearl pool + paint helpers
--
-- Mini pearls are ~60% the visual weight of the main board's 0.82 scale. Skip
-- the glossy highlight dot: at this size it reads as a smudge, not a sheen.
--------------------------------------------------------------------------------

local PEARL_SCALE = UDim2.fromScale(0.78, 0.78)

local function buildPearl(parent, color)
    local p = Instance.new("Frame")
    p.Name = "LockedPearl"
    p.Size = PEARL_SCALE
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
    pearlStroke.Thickness = 1
    pearlStroke.Transparency = 0.5
    pearlStroke.Parent = p

    return p
end

-- Additive paint from a dense 6x14 snapshot. Doesn't destroy missing entries;
-- that's destroyPoppedCells / reconcile's job.
local function paintFromSnapshot(cells)
    if type(cells) ~= "table" then return end
    for row = 1, BOARD_TOTAL_HEIGHT do
        local rowTable = rowLookup(cells, row)
        for col = 1, BOARD_WIDTH do
            local snapshotColor = cellLookup(rowTable, col)
            if snapshotColor then
                local key = posKey(row, col)
                local existing = lockedPearls[key]
                if existing and existing.pearl then existing.pearl:Destroy() end
                local pearl = buildPearl(cellsByPos[key], colorForServerName(snapshotColor))
                lockedPearls[key] = { pearl = pearl }
            end
        end
    end
end

-- Destructive reconcile: any locked pearl absent from the snapshot is wiped.
-- Safe because snapshots are dense (false in empty cells, not nil).
local function reconcileLockedToSnapshot(cells)
    if type(cells) ~= "table" then return end
    for key, entry in pairs(lockedPearls) do
        local r, c = key:match("(%d+)_(%d+)")
        r, c = tonumber(r), tonumber(c)
        if r and c then
            local rowTable = rowLookup(cells, r)
            local snapshotColor = cellLookup(rowTable, c)
            if not snapshotColor then
                if entry.pearl then entry.pearl:Destroy() end
                lockedPearls[key] = nil
            end
        end
    end
end

-- Drop pearls listed in a step's cellsPopped. Used for ChainCompleted so pops
-- disappear before the reconcile + repaint pass runs.
local function destroyPoppedCells(cellsPopped)
    if type(cellsPopped) ~= "table" then return end
    for _, entry in ipairs(cellsPopped) do
        if type(entry) == "table" then
            local r = entry.row or entry[1]
            local c = entry.col or entry[2]
            if type(r) == "number" and type(c) == "number" then
                local key = posKey(r, c)
                local existing = lockedPearls[key]
                if existing and existing.pearl then existing.pearl:Destroy() end
                lockedPearls[key] = nil
            end
        end
    end
end

local function clearAll()
    for key, entry in pairs(lockedPearls) do
        if entry.pearl then entry.pearl:Destroy() end
        lockedPearls[key] = nil
    end
end

--------------------------------------------------------------------------------
-- RemoteEvent subscriptions (isLocal == false only)
--------------------------------------------------------------------------------

local Remotes = ReplicatedStorage:WaitForChild("Remotes", 30)
if not Remotes then
    warn("[OpponentBoard] Remotes folder missing; mini-mirror will stay static")
    return
end

local pieceLockedRemote = Remotes:WaitForChild("PieceLocked", 10)
if pieceLockedRemote then
    pieceLockedRemote.OnClientEvent:Connect(function(event)
        if not event then return end
        if event.isLocal ~= false then return end
        if event.cells then
            reconcileLockedToSnapshot(event.cells)
            paintFromSnapshot(event.cells)
        end
    end)
end

local chainCompletedRemote = Remotes:WaitForChild("ChainCompleted", 10)
if chainCompletedRemote then
    chainCompletedRemote.OnClientEvent:Connect(function(event)
        if not event then return end
        if event.isLocal ~= false then return end
        if type(event.steps) == "table" then
            for _, step in ipairs(event.steps) do
                if type(step) == "table" and type(step.cellsPopped) == "table" then
                    destroyPoppedCells(step.cellsPopped)
                end
            end
        end
        if event.cells then
            reconcileLockedToSnapshot(event.cells)
            paintFromSnapshot(event.cells)
        end
    end)
end

local roundEndRemote = Remotes:WaitForChild("RoundEnd", 10)
if roundEndRemote then
    roundEndRemote.OnClientEvent:Connect(function()
        clearAll()
    end)
end

--------------------------------------------------------------------------------
-- GameState attribute visibility binding
--
-- Mirrors NextPiecePreview's pattern: visible only during "in_match".
--------------------------------------------------------------------------------

local function updateVisibility()
    local state = player:GetAttribute("GameState")
    screenGui.Enabled = (state == "in_match")
end

player:GetAttributeChangedSignal("GameState"):Connect(updateVisibility)
updateVisibility()
