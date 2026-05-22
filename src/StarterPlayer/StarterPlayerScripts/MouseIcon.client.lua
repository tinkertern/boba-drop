-- State-aware mouse cursor. Four assets uploaded to create.roblox.com
-- 2026-05-22:
--   * DEFAULT          rests over non-clickable space
--   * DEFAULT_DOWN     default + mouse button held
--   * CLICKABLE        pointer over a GuiButton (TextButton or ImageButton)
--   * CLICKABLE_DOWN   clickable + mouse button held
--
-- Lives in StarterPlayerScripts so it survives respawn. Reactive: tracks
-- hover by listening to MouseEnter / MouseLeave on every GuiButton under
-- PlayerGui (current + future), plus a global MouseButton1 / Touch latch
-- for the held state. No polling.

local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

local CURSORS = {
    DEFAULT = "rbxassetid://105870042566386",
    DEFAULT_DOWN = "rbxassetid://115400978648073",
    CLICKABLE = "rbxassetid://127416938505898",
    CLICKABLE_DOWN = "rbxassetid://103874665217453",
}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mouse = player:GetMouse()

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
    mouse.Icon = CURSORS[key]
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

-- Window blur sometimes swallows InputEnded; reset the held latch so the
-- pressed-state cursor doesn't get stuck after alt-tabbing back in.
UserInputService.WindowFocusReleased:Connect(function()
    isDown = false
    refresh()
end)

refresh()
UserInputService.MouseIconEnabled = true

UserInputService:GetPropertyChangedSignal("MouseIconEnabled"):Connect(function()
    if UserInputService.MouseIconEnabled then
        refresh()
    end
end)
