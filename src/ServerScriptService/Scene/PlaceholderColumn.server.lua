-- Day 1 placeholder: build a single 6×14 play column in Workspace so
-- Sarah can see the play field in Studio before Day 3 wires up real rendering.
-- Pure visual scaffolding; no gameplay logic, no collisions.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UIConstants = require(ReplicatedStorage.Shared.UI.UIConstants)

local Constants
do
    local ok, mod = pcall(require, ReplicatedStorage.Shared.Logic.Constants)
    Constants = ok and mod or { BOARD_WIDTH = 6, BOARD_VISIBLE_HEIGHT = 12, BOARD_TOTAL_HEIGHT = 14 }
end

local CELL_STUDS = 1
local WIDTH = Constants.BOARD_WIDTH * CELL_STUDS
local HEIGHT = Constants.BOARD_TOTAL_HEIGHT * CELL_STUDS
local VISIBLE_HEIGHT = Constants.BOARD_VISIBLE_HEIGHT * CELL_STUDS
local WALL_THICKNESS = 0.2

local folder = Instance.new("Folder")
folder.Name = "BobaDropScene"
folder.Parent = workspace

local function makePart(name, size, position, color, transparency)
    local p = Instance.new("Part")
    p.Name = name
    p.Size = size
    p.Position = position
    p.Anchored = true
    p.CanCollide = false
    p.CanQuery = false
    p.CanTouch = false
    p.Material = Enum.Material.SmoothPlastic
    p.Color = color
    p.Transparency = transparency or 0
    p.Parent = folder
    return p
end

-- Floor (row 0 boundary)
makePart(
    "Floor",
    Vector3.new(WIDTH + WALL_THICKNESS * 2, WALL_THICKNESS, 1),
    Vector3.new(0, -WALL_THICKNESS / 2, 0),
    UIConstants.Colors.Background,
    0
)

-- Left + right walls
makePart(
    "WallLeft",
    Vector3.new(WALL_THICKNESS, HEIGHT, 1),
    Vector3.new(-(WIDTH / 2 + WALL_THICKNESS / 2), HEIGHT / 2, 0),
    UIConstants.Colors.Background,
    0
)
makePart(
    "WallRight",
    Vector3.new(WALL_THICKNESS, HEIGHT, 1),
    Vector3.new(WIDTH / 2 + WALL_THICKNESS / 2, HEIGHT / 2, 0),
    UIConstants.Colors.Background,
    0
)

-- Back panel (recessed) — faint frame so the column reads as a 3D well
makePart(
    "BackPanel",
    Vector3.new(WIDTH, HEIGHT, 0.1),
    Vector3.new(0, HEIGHT / 2, -0.55),
    UIConstants.Colors.Background,
    0.55
)

-- Danger-zone line at the top of the visible board (row 12)
makePart(
    "DangerLine",
    Vector3.new(WIDTH, 0.05, 1),
    Vector3.new(0, VISIBLE_HEIGHT, 0),
    UIConstants.Colors.GarbageWarning,
    0.4
)

print(("[Scene] Built BobaDropScene placeholder: %d-wide × %d-tall (visible %d)"):format(WIDTH, HEIGHT, VISIBLE_HEIGHT))
