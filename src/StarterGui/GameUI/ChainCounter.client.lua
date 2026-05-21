-- Chain counter HUD. Celebratory scale-in with peach→coral gradient, then
-- floats upward and fades out so the label feels tied to the action that
-- triggered it. Listens for ChainCompleted RemoteEvent; WaitForChild with a
-- 30s timeout to avoid the infinite-yield warning pre-Day-3.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local UIConstants = require(ReplicatedStorage.Shared.UI.UIConstants)
local Events = require(ReplicatedStorage.Shared.Events)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ChainCounter"
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = UIConstants.ZOrder.ChainCounter
screenGui.Parent = playerGui

-- Holder sits at board center horizontally, roughly 35% from top.
-- Per-pop coordinates aren't yet plumbed to ChainCounter, so this is the
-- best client-side approximation of "above the action".
local BASE_POSITION = UDim2.new(0.5, 0, 0.35, 0)
local RISE_OFFSET_PX = 80
local RISE_POSITION = UDim2.new(0.5, 0, 0.35, -RISE_OFFSET_PX)

local holder = Instance.new("Frame")
holder.Name = "Holder"
holder.Size = UDim2.fromOffset(360, 100)
holder.AnchorPoint = Vector2.new(0.5, 0.5)
holder.Position = BASE_POSITION
holder.BackgroundTransparency = 1
holder.Visible = false
holder.Parent = screenGui

local label = Instance.new("TextLabel")
label.Name = "ChainLabel"
label.Size = UDim2.fromScale(1, 1)
label.AnchorPoint = Vector2.new(0.5, 0.5)
label.Position = UDim2.fromScale(0.5, 0.5)
label.BackgroundTransparency = 1
label.FontFace = UIConstants.Fonts.Display
label.TextSize = UIConstants.TextSizes.DisplayLarge
label.TextColor3 = UIConstants.Colors.TextOnWarm
label.TextStrokeColor3 = UIConstants.Colors.TextDark
label.TextStrokeTransparency = 0.6
label.TextTransparency = 1
label.Text = ""
label.Parent = holder

-- Peach → coral gradient on the text.
local gradient = Instance.new("UIGradient")
gradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, UIConstants.Colors.ChainGradientStart),
	ColorSequenceKeypoint.new(1, UIConstants.Colors.ChainGradientEnd),
})
gradient.Rotation = 90
gradient.Parent = label

local scale = Instance.new("UIScale")
scale.Scale = 0.6
scale.Parent = holder

local remotes = ReplicatedStorage:WaitForChild("Remotes", 30)
if not remotes then
	return
end
local chainRemote = remotes:WaitForChild(Events.Names.ChainCompleted, 30)
if not chainRemote then
	return
end

-- TweenInfo presets for each phase of the chain animation.
local TWEEN_APPEAR = TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local TWEEN_SETTLE = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TWEEN_RISE = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- All currently-running tweens + scheduled tasks, so a rapid repeat can
-- cancel everything cleanly before starting fresh from T+0.
local active = {
	tweens = {},
	tasks = {},
}

local function cancelActive()
	for _, t in ipairs(active.tweens) do
		t:Cancel()
	end
	active.tweens = {}
	for _, th in ipairs(active.tasks) do
		task.cancel(th)
	end
	active.tasks = {}
end

local function playChainAnimation(chainLength)
	cancelActive()

	label.Text = chainLength .. "-CHAIN!"

	-- Reset to T+0 state.
	holder.Position = BASE_POSITION
	holder.Visible = true
	scale.Scale = 0.6
	label.TextTransparency = 1
	label.TextStrokeTransparency = 1

	-- Phase 1 (T+0ms, 200ms): fade in + scale 0.6 → 1.2.
	local appearScale = TweenService:Create(scale, TWEEN_APPEAR, { Scale = 1.2 })
	local appearText = TweenService:Create(label, TWEEN_APPEAR, {
		TextTransparency = 0,
		TextStrokeTransparency = 0.6,
	})
	table.insert(active.tweens, appearScale)
	table.insert(active.tweens, appearText)
	appearScale:Play()
	appearText:Play()

	-- Phase 2 (T+200ms, 100ms): scale 1.2 → 1.0.
	local settleHandle
	settleHandle = task.delay(0.2, function()
		local settleScale = TweenService:Create(scale, TWEEN_SETTLE, { Scale = 1.0 })
		table.insert(active.tweens, settleScale)
		settleScale:Play()
	end)
	table.insert(active.tasks, settleHandle)

	-- Phase 3 (T+1000ms, 600ms): rise + fade out.
	local riseHandle
	riseHandle = task.delay(1.0, function()
		local riseMove = TweenService:Create(holder, TWEEN_RISE, { Position = RISE_POSITION })
		local riseText = TweenService:Create(label, TWEEN_RISE, {
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		})
		table.insert(active.tweens, riseMove)
		table.insert(active.tweens, riseText)
		riseMove:Play()
		riseText:Play()
	end)
	table.insert(active.tasks, riseHandle)

	-- Phase 4 (T+1600ms): hide and reset.
	local hideHandle
	hideHandle = task.delay(1.6, function()
		holder.Visible = false
		holder.Position = BASE_POSITION
		scale.Scale = 0.6
		label.TextTransparency = 1
		label.TextStrokeTransparency = 1
	end)
	table.insert(active.tasks, hideHandle)
end

chainRemote.OnClientEvent:Connect(function(payload)
	if not payload.isLocal then
		return
	end
	playChainAnimation(payload.chainLength)
end)
