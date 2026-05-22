-- Custom in-game mouse cursor: a tiny boba cup. Asset uploaded to
-- create.roblox.com 2026-05-22. Lives in StarterPlayerScripts so it
-- survives character respawns and runs once per session.
--
-- Roblox restores the default cursor when MouseIconEnabled is toggled
-- off (e.g. by some default game tools); we re-apply on enable to keep
-- the boba cup pinned.

local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

local CURSOR_ID = "rbxassetid://126148803408498"

local player = Players.LocalPlayer
local mouse = player:GetMouse()

mouse.Icon = CURSOR_ID
UserInputService.MouseIconEnabled = true

UserInputService:GetPropertyChangedSignal("MouseIconEnabled"):Connect(function()
    if UserInputService.MouseIconEnabled then
        mouse.Icon = CURSOR_ID
    end
end)
