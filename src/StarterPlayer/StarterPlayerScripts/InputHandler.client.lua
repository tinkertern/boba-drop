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
-- in the camera's binding list.
--
-- BindAction with default priority lost a race against the camera: when
-- PlayerModule loads its camera scripts (typically after CharacterAdded,
-- i.e. after this script runs), they BindAction the arrow keys at the
-- same default priority and land on top of our binding in the CAS stack.
-- Same-priority ties go to the most recent binder, so the camera ate the
-- arrows again. Fix: BindActionAtPriority with High (3000) so we win
-- regardless of load order.

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

local HIGH_PRIORITY = Enum.ContextActionPriority.High.Value
ContextActionService:BindActionAtPriority("BobaDropMoveLeft",  moveLeft,  false, HIGH_PRIORITY, Enum.KeyCode.Left,  Enum.KeyCode.A)
ContextActionService:BindActionAtPriority("BobaDropMoveRight", moveRight, false, HIGH_PRIORITY, Enum.KeyCode.Right, Enum.KeyCode.D)
ContextActionService:BindActionAtPriority("BobaDropRotate",    rotate,    false, HIGH_PRIORITY, Enum.KeyCode.Up,    Enum.KeyCode.W)
ContextActionService:BindActionAtPriority("BobaDropSoftDrop",  softDrop,  false, HIGH_PRIORITY, Enum.KeyCode.Down,  Enum.KeyCode.S)
ContextActionService:BindActionAtPriority("BobaDropHardDrop",  hardDrop,  false, HIGH_PRIORITY, Enum.KeyCode.Space)

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
