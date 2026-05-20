-- src/StarterPlayer/StarterPlayerScripts/TouchControls.client.lua
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService = game:GetService("GuiService")

local Events = require(ReplicatedStorage.Shared.Events)

if not UserInputService.TouchEnabled then
    -- desktop; bail
    return
end

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "TouchControls"
screenGui.IgnoreGuiInset = true
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

local function safeAreaInset()
    -- GuiService:GetSafeZoneOffsets() returns inset rect; bottom inset is what matters here
    local _, bottomInset = GuiService:GetSafeZoneOffsets():Wait()
    return bottomInset or 0
end

local function makeButton(name, anchorX, sizePx)
    local btn = Instance.new("TextButton")
    btn.Name = name
    btn.Text = name
    btn.Size = UDim2.fromOffset(sizePx, sizePx)
    btn.Position = UDim2.new(anchorX, 0, 1, -sizePx - 20) -- 20 + safe-area gap
    btn.AnchorPoint = Vector2.new(0, 0)
    btn.BackgroundTransparency = 0.4
    btn.TextSize = 18
    btn.Parent = screenGui
    return btn
end

local SIZE = 64 -- comfortably above the 44pt minimum
local leftBtn   = makeButton("←", 0.05, SIZE)
local rightBtn  = makeButton("→", 0.20, SIZE)
local rotateCcw = makeButton("Z", 0.65, SIZE)
local rotateCw  = makeButton("X", 0.80, SIZE)
local hardBtn   = makeButton("⬇", 0.95, SIZE)

leftBtn.Position   = UDim2.new(0.05, 0, 1, -SIZE - 20)
rightBtn.Position  = UDim2.new(0.05, SIZE + 10, 1, -SIZE - 20)
rotateCcw.Position = UDim2.new(1, -2 * SIZE - 80, 1, -SIZE - 20)
rotateCw.Position  = UDim2.new(1, -SIZE - 70, 1, -SIZE - 20)
hardBtn.Position   = UDim2.new(0.45, -SIZE / 2, 1, -SIZE - 20)

local function getRemote(name)
    return ReplicatedStorage:WaitForChild("Remotes"):WaitForChild(name)
end

local moveRemote     = getRemote(Events.Names.InputMove)
local rotateRemote   = getRemote(Events.Names.InputRotate)
local hardDropRemote = getRemote(Events.Names.InputHardDrop)

leftBtn.MouseButton1Click:Connect(function() moveRemote:FireServer({ direction = "left" }) end)
rightBtn.MouseButton1Click:Connect(function() moveRemote:FireServer({ direction = "right" }) end)
rotateCcw.MouseButton1Click:Connect(function() rotateRemote:FireServer({ direction = "ccw" }) end)
rotateCw.MouseButton1Click:Connect(function() rotateRemote:FireServer({ direction = "cw" }) end)
hardBtn.MouseButton1Click:Connect(function() hardDropRemote:FireServer({}) end)

print("TouchControls ready")
