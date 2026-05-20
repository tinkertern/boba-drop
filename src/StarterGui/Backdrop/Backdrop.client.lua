-- Full-screen warm-buttercream backdrop ScreenGui at z-order 0. Covers
-- Roblox's default sky + baseplate grid + any SpawnLocation pad so the
-- warm void reads as the game's actual background. Uses Colors.Backdrop
-- (one step warmer than Colors.Cream) so cream cards / panels / buttons
-- read as elevated surfaces against it instead of blending in.

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
fill.BackgroundColor3 = UIConstants.Colors.Backdrop
fill.BackgroundTransparency = 0
fill.BorderSizePixel = 0
fill.Parent = screenGui
