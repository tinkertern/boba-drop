-- Day 1 placeholder: 2D play-column grid.
-- A 6-wide x 14-tall cell grid centered on screen, aspect-locked so it
-- renders consistently on desktop and mobile. The 12th row is marked as
-- the danger line. Pure visual scaffold — Day 3 rendering will replace
-- the empty cells with piece sprites.

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

-- Container that locks aspect ratio so the board is the same shape on every device.
local container = Instance.new("Frame")
container.Name = "BoardFrame"
container.AnchorPoint = Vector2.new(0.5, 0.5)
container.Position = UDim2.fromScale(0.5, 0.5)
container.Size = UDim2.fromScale(0.45, 0.85)
container.BackgroundColor3 = UIConstants.Colors.Background
container.BackgroundTransparency = 0.15
container.BorderSizePixel = 0
container.Parent = screenGui

local aspect = Instance.new("UIAspectRatioConstraint")
aspect.AspectRatio = BOARD_WIDTH / BOARD_TOTAL_HEIGHT
aspect.DominantAxis = Enum.DominantAxis.Height
aspect.Parent = container

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

local function makeCell(row, col, isDanger)
    local cell = Instance.new("Frame")
    cell.Name = ("Cell_%d_%d"):format(row, col)
    cell.BackgroundColor3 = isDanger and UIConstants.Colors.GarbageWarning or UIConstants.Colors.Background
    cell.BackgroundTransparency = isDanger and 0.6 or 0.9
    cell.BorderSizePixel = 0
    cell.LayoutOrder = (BOARD_TOTAL_HEIGHT - row) * BOARD_WIDTH + col
    cell.Parent = container

    local stroke = Instance.new("UIStroke")
    stroke.Thickness = 1
    stroke.Color = Color3.fromRGB(60, 60, 75)
    stroke.Transparency = 0.6
    stroke.Parent = cell
end

for row = 1, BOARD_TOTAL_HEIGHT do
    for col = 1, BOARD_WIDTH do
        makeCell(row, col, row == DANGER_ROW)
    end
end
