-- Full-screen warm backdrop ScreenGui at z-order 0. Covers Roblox's default
-- sky + baseplate grid + any SpawnLocation pad so the warm void reads as
-- the game's actual background. A UIGradient on the fill frame swaps color
-- stops per GameState so each phase has its own atmosphere:
--   main_menu / match_end : Backdrop top to Peach bottom   (warm sunset)
--   matching              : Peach    top to Backdrop bottom (inverted, "different state")
--   in_match              : flat milk-tea brown wash       (lights dim, pearls pop)
--
-- BackgroundColor3 stays white so UIGradient renders its true colors
-- without tint multiplication.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIConstants = require(ReplicatedStorage.Shared.UI.UIConstants)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "Backdrop"
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = UIConstants.ZOrder.Background
screenGui.IgnoreGuiInset = true
screenGui.Parent = playerGui

local fill = Instance.new("Frame")
fill.Name = "Fill"
fill.Size = UDim2.fromScale(1, 1)
fill.BackgroundColor3 = Color3.new(1, 1, 1)
fill.BackgroundTransparency = 0
fill.BorderSizePixel = 0
fill.Parent = screenGui

local gradient = Instance.new("UIGradient")
gradient.Name = "StateGradient"
gradient.Rotation = 90 -- top to bottom
gradient.Parent = fill

-- Milk-tea brown: a 65/35 blend of WarmDark and Backdrop. Picked by hand
-- rather than computed inline so the value is greppable when the in-match
-- tone needs tuning. Reads as "coffee with cream" against the colorful
-- pearls and danger-row pulse during play.
local MILK_TEA_BROWN = Color3.fromRGB(122, 94, 72)

-- Top stop bumped from Backdrop to Cream (paler) so the cream-to-peach
-- gradient is legible top-to-bottom instead of reading as flat peach.
-- Sarah's 2026-05-21 screenshot showed the original Backdrop-to-Peach as
-- nearly indistinguishable from a flat fill.
local SEQ_MAIN_MENU = ColorSequence.new({
    ColorSequenceKeypoint.new(0, UIConstants.Colors.Cream),
    ColorSequenceKeypoint.new(1, UIConstants.Colors.Peach),
})
local SEQ_MATCHING = ColorSequence.new({
    ColorSequenceKeypoint.new(0, UIConstants.Colors.Peach),
    ColorSequenceKeypoint.new(1, UIConstants.Colors.Cream),
})
local SEQ_IN_MATCH = ColorSequence.new({
    ColorSequenceKeypoint.new(0, MILK_TEA_BROWN),
    ColorSequenceKeypoint.new(1, MILK_TEA_BROWN),
})

local function applyState(state)
    if state == "matching" then
        gradient.Color = SEQ_MATCHING
    elseif state == "in_match" then
        gradient.Color = SEQ_IN_MATCH
    else
        -- main_menu, match_end, nil, or any unknown state: default cozy.
        gradient.Color = SEQ_MAIN_MENU
    end
end

applyState(player:GetAttribute("GameState"))
player:GetAttributeChangedSignal("GameState"):Connect(function()
    applyState(player:GetAttribute("GameState"))
end)
