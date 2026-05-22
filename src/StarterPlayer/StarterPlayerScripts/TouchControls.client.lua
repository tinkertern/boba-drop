-- src/StarterPlayer/StarterPlayerScripts/TouchControls.client.lua
-- Mobile / touch input panel. Mirrors the keyboard scheme:
--   ←  →            soft  rot  hard
-- Movement on the left (one thumb), drops + rotate on the right (other thumb).
-- Soft drop is a HELD button — pressing fires { held = true }, releasing fires
-- { held = false }. The server-side soft-drop driver (Main.server.lua) injects
-- ticks while held, matching the desktop Down/S behaviour.
--
-- Layout uses a manual bottom safe-area inset (34px) to clear the iPhone home-
-- bar gesture region. The old code called GuiService:GetSafeZoneOffsets() which
-- doesn't exist on the GuiService API; that whole branch was dead.

local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Events = require(ReplicatedStorage.Shared.Events)

if not UserInputService.TouchEnabled then
    -- desktop; bail
    return
end

local Remotes = ReplicatedStorage:WaitForChild("Remotes", 30)
if not Remotes then
    warn("TouchControls: Remotes folder absent (expected pre-Day-3); idle")
    return
end

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "TouchControls"
screenGui.IgnoreGuiInset = true
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = 5 -- above gameplay, below modals
screenGui.Parent = playerGui

local SIZE = 64               -- comfortably above the 44pt tap-target minimum
local PAD = 14                -- gap between adjacent buttons
local EDGE = 16               -- gap from the screen edge
local BOTTOM_SAFE = 34        -- iPhone home-bar gesture inset
local BOTTOM_GAP = 20         -- breathing room above the safe-area band
local BOTTOM_OFFSET = -BOTTOM_SAFE - BOTTOM_GAP

local function makeButton(name, label)
    local btn = Instance.new("TextButton")
    btn.Name = name
    btn.Text = label
    btn.Size = UDim2.fromOffset(SIZE, SIZE)
    btn.BackgroundTransparency = 0.4
    btn.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.TextSize = 26
    btn.Font = Enum.Font.GothamBold
    btn.AutoButtonColor = true
    btn.Parent = screenGui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 12)
    corner.Parent = btn

    return btn
end

-- Left cluster (movement) — anchored bottom-left
local leftBtn  = makeButton("Left",  "←")
local rightBtn = makeButton("Right", "→")
leftBtn.AnchorPoint  = Vector2.new(0, 1)
rightBtn.AnchorPoint = Vector2.new(0, 1)
leftBtn.Position  = UDim2.new(0, EDGE,              1, BOTTOM_OFFSET)
rightBtn.Position = UDim2.new(0, EDGE + SIZE + PAD, 1, BOTTOM_OFFSET)

-- Right cluster (soft / rotate / hard) — anchored bottom-right
local softBtn = makeButton("Soft", "▼")
local rotBtn  = makeButton("Rot",  "↻")
local hardBtn = makeButton("Hard", "⤓")
softBtn.AnchorPoint = Vector2.new(1, 1)
rotBtn.AnchorPoint  = Vector2.new(1, 1)
hardBtn.AnchorPoint = Vector2.new(1, 1)
hardBtn.Position = UDim2.new(1, -EDGE,                          1, BOTTOM_OFFSET)
rotBtn.Position  = UDim2.new(1, -EDGE - (SIZE + PAD),           1, BOTTOM_OFFSET)
softBtn.Position = UDim2.new(1, -EDGE - 2 * (SIZE + PAD),       1, BOTTOM_OFFSET)

local moveRemote     = Remotes:WaitForChild(Events.Names.InputMove, 30)
local rotateRemote   = Remotes:WaitForChild(Events.Names.InputRotate, 30)
local hardDropRemote = Remotes:WaitForChild(Events.Names.InputHardDrop, 30)
local softDropRemote = Remotes:WaitForChild(Events.Names.InputSoftDrop, 30)

leftBtn.MouseButton1Click:Connect(function() moveRemote:FireServer({ direction = "left" }) end)
rightBtn.MouseButton1Click:Connect(function() moveRemote:FireServer({ direction = "right" }) end)
rotBtn.MouseButton1Click:Connect(function() rotateRemote:FireServer({ direction = "cw" }) end)
hardBtn.MouseButton1Click:Connect(function() hardDropRemote:FireServer({}) end)

-- Soft drop is HELD: InputBegan on press → held=true, InputEnded on release →
-- held=false. Roblox keeps tracking the touch even if the finger drifts off the
-- button bounds, so InputEnded reliably fires for the matching down-press.
local function isPressInput(input)
    return input.UserInputType == Enum.UserInputType.Touch
        or input.UserInputType == Enum.UserInputType.MouseButton1
end

softBtn.InputBegan:Connect(function(input)
    if isPressInput(input) then softDropRemote:FireServer({ held = true }) end
end)
softBtn.InputEnded:Connect(function(input)
    if isPressInput(input) then softDropRemote:FireServer({ held = false }) end
end)

print("TouchControls ready")
