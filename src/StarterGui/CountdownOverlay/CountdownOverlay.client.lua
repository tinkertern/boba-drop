-- CountdownOverlay: 3-2-1-GO! shown when entering in_match. Gives players a
-- beat to orient before pieces start falling. Pairs with a server-side delay
-- on first piece spawn (Engineer); without that delay, pieces may fall during
-- the count which is a known acceptable visual compromise.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local UIConstants = require(ReplicatedStorage.Shared.UI.UIConstants)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local POP_ASSET = "rbxassetid://6732690176"
local SMALL_SIZE = 144
local GO_SIZE = 200
local SMALL_DUR = 0.20
local GO_DUR = 0.35
local GO_FADE_DUR = 0.50
local STROKE_THICKNESS = 4

--------------------------------------------------------------------------------
-- Build ScreenGui (once, reused per match)
--------------------------------------------------------------------------------

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "CountdownOverlay"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = UIConstants.ZOrder.BlockedFlash + 50  -- 160
screenGui.Enabled = false
screenGui.Parent = playerGui

local scrim = Instance.new("Frame")
scrim.Name = "Scrim"
scrim.Size = UDim2.fromScale(1, 1)
scrim.Position = UDim2.fromScale(0, 0)
scrim.BackgroundColor3 = UIConstants.Colors.WarmDark
scrim.BackgroundTransparency = 0.7
scrim.BorderSizePixel = 0
scrim.Parent = screenGui

local label = Instance.new("TextLabel")
label.Name = "CountLabel"
label.Size = UDim2.fromOffset(600, 300)
label.AnchorPoint = Vector2.new(0.5, 0.5)
label.Position = UDim2.fromScale(0.5, 0.5)
label.BackgroundTransparency = 1
label.FontFace = UIConstants.Fonts.Display
label.TextSize = SMALL_SIZE
label.TextColor3 = UIConstants.Colors.TextDark
label.TextTransparency = 1
label.Text = ""
label.Parent = scrim

local stroke = Instance.new("UIStroke")
stroke.Color = UIConstants.Colors.TextOnWarm
stroke.Thickness = STROKE_THICKNESS
stroke.Transparency = 0
stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
stroke.Parent = label

local gradient = Instance.new("UIGradient")
gradient.Enabled = false
gradient.Rotation = 90
gradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, UIConstants.Colors.ChainGradientStart),
    ColorSequenceKeypoint.new(1, UIConstants.Colors.ChainGradientEnd),
})
gradient.Parent = label

local scaler = Instance.new("UIScale")
scaler.Scale = 1
scaler.Parent = label

--------------------------------------------------------------------------------
-- Sequence state (interruptible)
--------------------------------------------------------------------------------

local running = false
local cancelToken = 0
local activeTweens = {}

local function clearTweens()
    for _, t in ipairs(activeTweens) do
        pcall(function() t:Cancel() end)
    end
    activeTweens = {}
end

local function trackTween(t)
    table.insert(activeTweens, t)
    return t
end

local function playPop(speed)
    local s = Instance.new("Sound")
    s.SoundId = POP_ASSET
    s.Volume = 0.7
    s.PlaybackSpeed = speed
    s.Parent = SoundService
    s.Ended:Connect(function()
        s:Destroy()
    end)
    s:Play()
end

local function popInTween(duration)
    return TweenInfo.new(duration, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
end

local function fadeTween(duration)
    return TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
end

-- Configure the label for a 3/2/1 step (no gradient, dark text).
local function configureSmall(text)
    label.Text = text
    label.TextSize = SMALL_SIZE
    label.TextColor3 = UIConstants.Colors.TextDark
    gradient.Enabled = false
end

-- Configure the label for GO! (gradient text, larger size).
local function configureGo()
    label.Text = "GO!"
    label.TextSize = GO_SIZE
    label.TextColor3 = UIConstants.Colors.TextOnWarm  -- base under gradient
    gradient.Enabled = true
end

-- Scale-in + fade-in. startScale shrinks to 1.0 over duration.
local function popIn(startScale, duration)
    scaler.Scale = startScale
    label.TextTransparency = 0  -- snap on; the pop is carried by scale
    stroke.Transparency = 0
    local tw = TweenService:Create(scaler, popInTween(duration), { Scale = 1 })
    trackTween(tw)
    tw:Play()
end

-- Fade label + stroke out together.
local function fadeOut(duration)
    local tA = TweenService:Create(label, fadeTween(duration), { TextTransparency = 1 })
    local tB = TweenService:Create(stroke, fadeTween(duration), { Transparency = 1 })
    trackTween(tA); trackTween(tB)
    tA:Play(); tB:Play()
end

local function hide()
    clearTweens()
    screenGui.Enabled = false
    label.Text = ""
    label.TextTransparency = 1
    stroke.Transparency = 1
    scaler.Scale = 1
    gradient.Enabled = false
    running = false
end

-- Wait that bails out if the run has been cancelled. Returns true if still
-- alive, false if cancelled.
local function aliveWait(token, seconds)
    local elapsed = 0
    while elapsed < seconds do
        local dt = task.wait()
        if token ~= cancelToken then
            return false
        end
        elapsed += dt
    end
    return token == cancelToken
end

-- Timeline (per spec, locked to a 1-second cadence):
--   T+0     "3"  pops in (1.5 -> 1.0, 200ms Back/Out), soft pop sound
--   T+1000  "2"  same scale-in (the prior digit is replaced as the new one pops)
--   T+2000  "1"  same
--   T+3000  "GO!" pops in (1.8 -> 1.0, 350ms Back/Out), louder pop sound, gradient
--   T+3500  "GO!" fades out over 500ms
--   T+4000  overlay hides
local function runSequence()
    local token = cancelToken
    screenGui.Enabled = true

    -- T+0: "3"
    configureSmall("3")
    playPop(1.0)
    popIn(1.5, SMALL_DUR)
    if not aliveWait(token, 1.0) then return end

    -- T+1000: "2"
    configureSmall("2")
    playPop(1.0)
    popIn(1.5, SMALL_DUR)
    if not aliveWait(token, 1.0) then return end

    -- T+2000: "1"
    configureSmall("1")
    playPop(1.0)
    popIn(1.5, SMALL_DUR)
    if not aliveWait(token, 1.0) then return end

    -- T+3000: "GO!"
    configureGo()
    playPop(0.85)
    popIn(1.8, GO_DUR)
    if not aliveWait(token, 0.5) then return end

    -- T+3500: fade out GO! over 500ms
    fadeOut(GO_FADE_DUR)
    if not aliveWait(token, GO_FADE_DUR) then return end

    if token == cancelToken then
        hide()
    end
end

--------------------------------------------------------------------------------
-- Attribute listener: only fire on transition INTO in_match
--------------------------------------------------------------------------------

local lastState = player:GetAttribute("GameState")

player:GetAttributeChangedSignal("GameState"):Connect(function()
    local newState = player:GetAttribute("GameState")
    local wasInMatch = (lastState == "in_match")
    lastState = newState

    if newState == "in_match" and not wasInMatch then
        if running then return end  -- guard: don't double-fire
        running = true
        cancelToken += 1
        task.spawn(runSequence)
    elseif newState ~= "in_match" and running then
        -- Interrupt: cancel any in-flight tweens / waits, hide overlay.
        cancelToken += 1
        hide()
    end
end)
