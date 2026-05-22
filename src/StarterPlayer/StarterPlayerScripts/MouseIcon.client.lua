-- State-aware mouse cursor. Four assets uploaded to create.roblox.com
-- 2026-05-22:
--   * DEFAULT          rests over non-clickable space
--   * DEFAULT_DOWN     default + mouse button held
--   * CLICKABLE        pointer over a GuiButton (TextButton or ImageButton)
--   * CLICKABLE_DOWN   clickable + mouse button held
--
-- Renders as a custom ImageLabel that follows the system mouse so the
-- pixel size is independent of the asset's upload resolution. Hover is
-- detected by querying PlayerGui:GetGuiObjectsAtPosition on each frame
-- because parenting our own ImageLabel on top of every other ScreenGui
-- makes MouseEnter on buttons unreliable (the cursor ImageLabel sits in
-- front of them at the cursor point and breaks per-object hover events
-- even with Active = false).

local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local CURSOR_SIZE = 64
local CURSORS = {
    DEFAULT = "rbxassetid://105870042566386",
    DEFAULT_DOWN = "rbxassetid://115400978648073",
    CLICKABLE = "rbxassetid://127416938505898",
    CLICKABLE_DOWN = "rbxassetid://103874665217453",
}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mouse = player:GetMouse()

UserInputService.MouseIconEnabled = false

-- IgnoreGuiInset = false aligns the ScreenGui's coordinate space with the
-- below-topbar coords that Mouse.X / Mouse.Y and GetGuiObjectsAtPosition
-- already use. With inset = true the cursor visual rendered 36px above
-- the hardware position, so hover hit-testing missed buttons the user
-- thought they were over.
local gui = Instance.new("ScreenGui")
gui.Name = "CustomCursor"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.DisplayOrder = 1000
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local img = Instance.new("ImageLabel")
img.Name = "Cursor"
img.AnchorPoint = Vector2.new(0, 0)
img.Size = UDim2.fromOffset(CURSOR_SIZE, CURSOR_SIZE)
img.Image = CURSORS.DEFAULT
img.BackgroundTransparency = 1
img.Active = false
img.Parent = gui

local isDown = false
local isOverClickable = false

local function refresh()
    local key
    if isOverClickable then
        key = isDown and "CLICKABLE_DOWN" or "CLICKABLE"
    else
        key = isDown and "DEFAULT_DOWN" or "DEFAULT"
    end
    img.Image = CURSORS[key]
end

local function hoveringClickable(x, y)
    local objects = playerGui:GetGuiObjectsAtPosition(x, y)
    for _, obj in ipairs(objects) do
        if obj:IsA("GuiButton") and obj.Active and obj.Visible then
            return true
        end
    end
    return false
end

local function isClickInput(input)
    return input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch
end

UserInputService.InputBegan:Connect(function(input)
    if isClickInput(input) then
        isDown = true
        refresh()
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if isClickInput(input) then
        isDown = false
        refresh()
    end
end)

UserInputService.WindowFocusReleased:Connect(function()
    isDown = false
    refresh()
end)

RunService.RenderStepped:Connect(function()
    local x, y = mouse.X, mouse.Y
    img.Position = UDim2.fromOffset(x, y)

    local hovering = hoveringClickable(x, y)
    if hovering ~= isOverClickable then
        isOverClickable = hovering
        refresh()
    end
end)

refresh()
