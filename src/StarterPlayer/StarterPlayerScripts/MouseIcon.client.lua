-- State-aware mouse cursor. Four assets uploaded to create.roblox.com
-- 2026-05-22:
--   * DEFAULT          rests over non-clickable space
--   * DEFAULT_DOWN     default + mouse button held
--   * CLICKABLE        pointer over a GuiButton (TextButton or ImageButton)
--   * CLICKABLE_DOWN   clickable + mouse button held
--
-- Roblox's native Mouse.Icon renders the asset at its uploaded resolution,
-- which blew the cursor up to ~300px when Sarah's uploads were high-res.
-- We hide the OS cursor and render our own ImageLabel that follows the
-- mouse at a fixed size. One frame of lag, but pixel-perfect sizing and
-- no need to re-upload the assets at thumbnail resolution.

local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local CURSOR_SIZE = 32
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

local gui = Instance.new("ScreenGui")
gui.Name = "CustomCursor"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 2147483647
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
local hoverSet = {}

local function isClickableNow(btn)
    if not btn or not btn.Parent then return false end
    if not btn.Active then return false end
    if not btn.Visible then return false end
    return true
end

local function anyHoverClickable()
    for btn in pairs(hoverSet) do
        if isClickableNow(btn) then
            return true
        end
    end
    return false
end

local function refresh()
    local hovering = anyHoverClickable()
    local key
    if hovering then
        key = isDown and "CLICKABLE_DOWN" or "CLICKABLE"
    else
        key = isDown and "DEFAULT_DOWN" or "DEFAULT"
    end
    img.Image = CURSORS[key]
end

local function bindButton(btn)
    if not btn:IsA("GuiButton") then return end
    btn.MouseEnter:Connect(function()
        hoverSet[btn] = true
        refresh()
    end)
    btn.MouseLeave:Connect(function()
        hoverSet[btn] = nil
        refresh()
    end)
    btn.AncestryChanged:Connect(function(_, parent)
        if not parent and hoverSet[btn] then
            hoverSet[btn] = nil
            refresh()
        end
    end)
end

for _, descendant in ipairs(playerGui:GetDescendants()) do
    bindButton(descendant)
end
playerGui.DescendantAdded:Connect(bindButton)

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
    img.Position = UDim2.fromOffset(mouse.X, mouse.Y)
end)

refresh()
