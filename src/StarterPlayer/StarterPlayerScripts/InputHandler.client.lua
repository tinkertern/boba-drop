-- src/StarterPlayer/StarterPlayerScripts/InputHandler.client.lua
-- Tetris-style keyboard bindings: arrows + WASD for movement, Up/W rotate one
-- direction only, Down/S soft drop, Space hard drop. Z and X removed at Sarah's
-- request 2026-05-20.
-- Also disables Roblox's default PlayerControls while in_match so WASD doesn't
-- also walk the player's avatar around (and trigger footstep sounds) in the
-- background.
--
-- Bindings go through ContextActionService rather than UserInputService.
-- The default Roblox camera scripts bind Left/Right arrows via CAS for
-- camera orbit (and sink them), which was eating those arrows before
-- UIS:InputBegan would fire — WASD passed through because they were not
-- in the camera's binding list. Registering our own CAS bindings with
-- Sink overrides the camera bindings at the same priority, so all five
-- action keys reach the remotes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")

local Events = require(ReplicatedStorage.Shared.Events)

GuiService.GuiNavigationEnabled = false

local Remotes = ReplicatedStorage:WaitForChild("Remotes", 30)
if not Remotes then
    warn("InputHandler: Remotes folder absent (expected pre-Day-3); idle")
    return
end

local moveRemote = Remotes:WaitForChild(Events.Names.InputMove, 30)
local rotateRemote = Remotes:WaitForChild(Events.Names.InputRotate, 30)
local softDropRemote = Remotes:WaitForChild(Events.Names.InputSoftDrop, 30)
local hardDropRemote = Remotes:WaitForChild(Events.Names.InputHardDrop, 30)

local function moveLeft(_, inputState)
    if inputState == Enum.UserInputState.Begin then
        moveRemote:FireServer({ direction = "left" })
    end
    return Enum.ContextActionResult.Sink
end

local function moveRight(_, inputState)
    if inputState == Enum.UserInputState.Begin then
        moveRemote:FireServer({ direction = "right" })
    end
    return Enum.ContextActionResult.Sink
end

local function rotate(_, inputState)
    if inputState == Enum.UserInputState.Begin then
        rotateRemote:FireServer({ direction = "cw" })
    end
    return Enum.ContextActionResult.Sink
end

local function softDrop(_, inputState)
    if inputState == Enum.UserInputState.Begin then
        softDropRemote:FireServer({ held = true })
    elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
        softDropRemote:FireServer({ held = false })
    end
    return Enum.ContextActionResult.Sink
end

local function hardDrop(_, inputState)
    if inputState == Enum.UserInputState.Begin then
        hardDropRemote:FireServer({})
    end
    return Enum.ContextActionResult.Sink
end

ContextActionService:BindAction("BobaDropMoveLeft",  moveLeft,  false, Enum.KeyCode.Left,  Enum.KeyCode.A)
ContextActionService:BindAction("BobaDropMoveRight", moveRight, false, Enum.KeyCode.Right, Enum.KeyCode.D)
ContextActionService:BindAction("BobaDropRotate",    rotate,    false, Enum.KeyCode.Up,    Enum.KeyCode.W)
ContextActionService:BindAction("BobaDropSoftDrop",  softDrop,  false, Enum.KeyCode.Down,  Enum.KeyCode.S)
ContextActionService:BindAction("BobaDropHardDrop",  hardDrop,  false, Enum.KeyCode.Space)

-- Disable Roblox's default PlayerControls permanently. Boba Drop is a 2D UI
-- experience; the avatar exists in Workspace but is never visible or relevant.
-- Disabling controls prevents WASD from walking the avatar in the background
-- and silences the footstep audio. Wrapped in a pcall in case PlayerModule
-- isn't available in some run configurations.
--
-- Deferred until CharacterAdded so PlayerControls:Disable doesn't internally
-- call Player:Move with no character, which logs "Player:Move called, but
-- player currently has no character" on Studio start.
local player = Players.LocalPlayer

local function disablePlayerControls()
    pcall(function()
        local PlayerScripts = player:WaitForChild("PlayerScripts", 10)
        local PlayerModule = require(PlayerScripts:WaitForChild("PlayerModule", 10))
        PlayerModule:GetControls():Disable()
    end)
end

if player.Character then
    disablePlayerControls()
else
    player.CharacterAdded:Connect(disablePlayerControls)
end

print("InputHandler (keyboard) ready")
