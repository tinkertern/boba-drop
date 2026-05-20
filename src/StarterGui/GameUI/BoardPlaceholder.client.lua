-- Day 1 placeholder: 2D play-column grid styled per the cozy/bubbly art direction.
-- A 6-wide x 14-tall cell grid centered on screen, aspect-locked so it renders
-- consistently on desktop and mobile. The 12th row is marked as the danger line
-- in a soft coral. Pure visual scaffold — Day 3 rendering will replace the empty
-- cells with glossy pearls.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIConstants = require(ReplicatedStorage.Shared.UI.UIConstants)

local BOARD_WIDTH = 6
local BOARD_VISIBLE_HEIGHT = 12
local BOARD_TOTAL_HEIGHT = 14
local DANGER_ROW = BOARD_VISIBLE_HEIGHT

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

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

-- Two cell tones alternated per row so the grid reads against the cream
-- container backdrop. Stronger stroke for cell edges so each cell is visible.
local CELL_TONE_A = Color3.fromRGB(252, 240, 220)
local CELL_TONE_B = Color3.fromRGB(245, 230, 208)

-- Preview pearls placed during the lobby-state placeholder so the empty
-- board reads as a game-in-progress rather than dead space. Replaced
-- wholesale once Day 4's real renderer takes over.
local PREVIEW_PEARLS = {
    { row = 1, col = 1, color = "PearlBrown" },
    { row = 1, col = 2, color = "PearlPink" },
    { row = 1, col = 4, color = "PearlGreen" },
    { row = 1, col = 5, color = "PearlPink" },
    { row = 2, col = 1, color = "PearlPink" },
    { row = 2, col = 4, color = "PearlBrown" },
    { row = 2, col = 5, color = "PearlBrown" },
    { row = 3, col = 4, color = "PearlGreen" },
    { row = 3, col = 5, color = "PearlWhite" },
}

local function addPreviewPearl(cell, colorKey)
    local p = Instance.new("Frame")
    p.Name = "PreviewPearl"
    p.Size = UDim2.fromScale(0.82, 0.82)
    p.Position = UDim2.fromScale(0.5, 0.5)
    p.AnchorPoint = Vector2.new(0.5, 0.5)
    p.BackgroundColor3 = UIConstants.Colors[colorKey]
    p.BorderSizePixel = 0
    p.Parent = cell

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UIConstants.Corners.Pearl
    corner.Parent = p

    local pearlStroke = Instance.new("UIStroke")
    pearlStroke.Color = UIConstants.Colors.StrokeWarm
    pearlStroke.Thickness = 1
    pearlStroke.Transparency = 0.45
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
end

local previewByPos = {}
for _, entry in PREVIEW_PEARLS do
    previewByPos[entry.row .. "_" .. entry.col] = entry.color
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
    cell.LayoutOrder = (BOARD_TOTAL_HEIGHT - row) * BOARD_WIDTH + col
    cell.Parent = container

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UIConstants.Corners.Cell
    corner.Parent = cell

    local stroke = Instance.new("UIStroke")
    stroke.Thickness = 1
    stroke.Color = UIConstants.Colors.StrokeSoft
    stroke.Transparency = 0.25
    stroke.Parent = cell

    local previewKey = previewByPos[row .. "_" .. col]
    if previewKey and not isDanger then
        addPreviewPearl(cell, previewKey)
    end
end

for row = 1, BOARD_TOTAL_HEIGHT do
    for col = 1, BOARD_WIDTH do
        makeCell(row, col, row == DANGER_ROW)
    end
end
