-- GarbageSendFx: attacker-side floating "→ N ICE!" text when the local
-- player's chain sends garbage to the opponent. Driven by ChainCompleted's
-- garbageOut field (shipped server-side at a6c4fc0).
--
-- Without this, attackers had no visual confirmation that their chain
-- actually sent ice cubes; only the opponent's GarbagePreview pulsed, and
-- only the opponent saw that. This puts a cheap, readable signal on the
-- attacker's screen, anchored at the right edge of their board and sliding
-- toward where the opponent mini-view sits.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local UIConstants = require(ReplicatedStorage.Shared.UI.UIConstants)
local Events = require(ReplicatedStorage.Shared.Events)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ScreenGui acts as a container only; each chain spawns its own TextLabel
-- that self-destructs at the end of its animation, so concurrent sends
-- (rapid back-to-back chains) stack visually instead of clobbering one
-- another.
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "GarbageSendFx"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
-- ChainCounter is 60. Sits above HUD, below match-end panel.
screenGui.DisplayOrder = UIConstants.ZOrder.ChainCounter + 5
screenGui.Enabled = true
screenGui.Parent = playerGui

-- Local board is anchored at (0.5, 0.5) scale, size (0.45, 0.85) scale.
-- Right edge sits at scale-x 0.5 + 0.45/2 = 0.725.
local START_POSITION = UDim2.new(0.725, 0, 0.4, 0)
-- Slides rightward toward the opponent mini-view (which lives around
-- scale-x 0.78). Stop short of it so the message reads as "headed there".
local END_POSITION = UDim2.new(0.85, 0, 0.4, 0)

-- TweenInfo presets for each phase.
local TWEEN_APPEAR = TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local TWEEN_SETTLE = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TWEEN_DRIFT = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function spawnFloater(cubes)
	local label = Instance.new("TextLabel")
	label.Name = "GarbageSendFloater"
	label.AnchorPoint = Vector2.new(0, 0.5)
	label.Position = START_POSITION
	label.Size = UDim2.fromOffset(160, 40)
	label.BackgroundTransparency = 1
	label.FontFace = UIConstants.Fonts.Display
	label.TextSize = 32
	label.TextColor3 = UIConstants.Colors.IceBase
	label.TextStrokeColor3 = UIConstants.Colors.TextDark
	label.TextStrokeTransparency = 0.4
	label.TextTransparency = 1
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = "\u{2192} " .. cubes .. " ICE!"
	label.Parent = screenGui

	local scale = Instance.new("UIScale")
	scale.Scale = 0.6
	scale.Parent = label

	-- Phase 1 (T+0, 200ms): pop in. Scale 0.6 → 1.1 + text fade in.
	local appearScale = TweenService:Create(scale, TWEEN_APPEAR, { Scale = 1.1 })
	local appearText = TweenService:Create(label, TWEEN_APPEAR, {
		TextTransparency = 0,
	})
	appearScale:Play()
	appearText:Play()

	-- Phase 2 (T+200ms, 100ms): scale settle 1.1 → 1.0.
	task.delay(0.2, function()
		if not label.Parent then
			return
		end
		local settle = TweenService:Create(scale, TWEEN_SETTLE, { Scale = 1.0 })
		settle:Play()
	end)

	-- Phase 3 (T+700ms, 500ms): slide right + fade out (text + stroke).
	task.delay(0.7, function()
		if not label.Parent then
			return
		end
		local drift = TweenService:Create(label, TWEEN_DRIFT, {
			Position = END_POSITION,
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		})
		drift:Play()
	end)

	-- Phase 4 (T+1200ms): destroy.
	task.delay(1.2, function()
		if label.Parent then
			label:Destroy()
		end
	end)
end

local remotes = ReplicatedStorage:WaitForChild("Remotes", 30)
if not remotes then
	return
end
local chainRemote = remotes:WaitForChild(Events.Names.ChainCompleted, 30)
if not chainRemote then
	return
end

chainRemote.OnClientEvent:Connect(function(event)
	if not event or not event.isLocal then
		return
	end
	local out = event.garbageOut or 0
	if out > 0 then
		spawnFloater(out)
	end
end)
