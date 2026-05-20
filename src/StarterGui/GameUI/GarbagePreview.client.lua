-- GarbagePreview: row of incoming ice cubes above the player's cup.
-- Cube look per art direction: pastel-blue rounded squares with a small
-- frost-crystal highlight. Pulse the row when garbage is queued so the
-- "drop is coming" feels like worry, not panic.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local UIConstants = require(ReplicatedStorage.Shared.UI.UIConstants)
local Events = require(ReplicatedStorage.Shared.Events)

local CUBE_SIZE = 22
local CUBE_PADDING = 4
local MAX_VISIBLE_CUBES = 12

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local gui = Instance.new("ScreenGui")
gui.Name = "GarbagePreview"
gui.ResetOnSpawn = false
gui.DisplayOrder = UIConstants.ZOrder.GarbageWarning
gui.Parent = playerGui

local row = Instance.new("Frame")
row.Name = "Row"
row.Size = UDim2.fromOffset(MAX_VISIBLE_CUBES * (CUBE_SIZE + CUBE_PADDING), CUBE_SIZE + 4)
row.Position = UDim2.fromScale(0.5, 0.08)
row.AnchorPoint = Vector2.new(0.5, 0.5)
row.BackgroundTransparency = 1
row.Parent = gui

local function makeCube(layoutOrder)
    local cube = Instance.new("Frame")
    cube.Name = "Cube"
    cube.Size = UDim2.fromOffset(CUBE_SIZE, CUBE_SIZE)
    cube.LayoutOrder = layoutOrder
    cube.BackgroundColor3 = UIConstants.Colors.IceBase
    cube.BorderSizePixel = 0
    cube.Parent = row

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 5)
    corner.Parent = cube

    local stroke = Instance.new("UIStroke")
    stroke.Color = UIConstants.Colors.IceFrost
    stroke.Thickness = 1
    stroke.Transparency = 0.3
    stroke.Parent = cube

    local frost = Instance.new("Frame")
    frost.Name = "Frost"
    frost.Size = UDim2.fromOffset(8, 5)
    frost.Position = UDim2.fromScale(0.28, 0.28)
    frost.AnchorPoint = Vector2.new(0.5, 0.5)
    frost.BackgroundColor3 = UIConstants.Colors.IceFrost
    frost.BackgroundTransparency = 0.1
    frost.BorderSizePixel = 0
    frost.Parent = cube

    local frostCorner = Instance.new("UICorner")
    frostCorner.CornerRadius = UDim.new(1, 0)
    frostCorner.Parent = frost

    return cube
end

local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Horizontal
layout.Padding = UDim.new(0, CUBE_PADDING)
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.VerticalAlignment = Enum.VerticalAlignment.Center
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = row

local overflowLabel = nil
local function clearRow()
    for _, child in row:GetChildren() do
        if child:IsA("Frame") or child:IsA("TextLabel") then
            child:Destroy()
        end
    end
    overflowLabel = nil
end

local function drawCubes(cubes)
    clearRow()
    -- Re-parent layout after clear (layout itself was cleared since it's a child).
    layout.Parent = row
    local visible = math.min(cubes, MAX_VISIBLE_CUBES)
    for i = 1, visible do
        makeCube(i)
    end
    if cubes > MAX_VISIBLE_CUBES then
        overflowLabel = Instance.new("TextLabel")
        overflowLabel.LayoutOrder = MAX_VISIBLE_CUBES + 1
        overflowLabel.Size = UDim2.fromOffset(40, CUBE_SIZE)
        overflowLabel.BackgroundTransparency = 1
        overflowLabel.FontFace = UIConstants.Fonts.Display
        overflowLabel.TextSize = UIConstants.TextSizes.HUDLabel
        overflowLabel.TextColor3 = UIConstants.Colors.TextDark
        overflowLabel.Text = ("+%d"):format(cubes - MAX_VISIBLE_CUBES)
        overflowLabel.Parent = row
    end
end

local pulseConn = nil
local function startPulse()
    if pulseConn then return end
    local startedAt = os.clock()
    pulseConn = RunService.RenderStepped:Connect(function()
        local t = os.clock() - startedAt
        local pulse = (math.sin(t * 6) + 1) * 0.5
        for _, child in row:GetChildren() do
            if child:IsA("Frame") then
                child.BackgroundTransparency = 0.1 + (1 - pulse) * 0.45
            end
        end
    end)
end

local function stopPulse()
    if pulseConn then
        pulseConn:Disconnect()
        pulseConn = nil
    end
end

task.spawn(function()
    local remotes = ReplicatedStorage:WaitForChild("Remotes", 30)
    if not remotes then return end
    local incomingName = Events.Names.GarbageIncoming
    local appliedName = Events.Names.GarbageApplied
    if not (incomingName and appliedName) then return end
    local incomingRemote = remotes:WaitForChild(incomingName, 30)
    local appliedRemote = remotes:WaitForChild(appliedName, 30)
    if not (incomingRemote and appliedRemote) then return end

    incomingRemote.OnClientEvent:Connect(function(event)
        if tostring(event.playerId) ~= tostring(player.UserId) then return end
        drawCubes(event.cubes or 0)
        startPulse()
    end)

    appliedRemote.OnClientEvent:Connect(function(event)
        if tostring(event.playerId) ~= tostring(player.UserId) then return end
        clearRow()
        stopPulse()
    end)
end)

gui.AncestryChanged:Connect(function(_, parent)
    if not parent then stopPulse() end
end)
