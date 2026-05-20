-- Match-end panel. Visual is final; event wiring activates Day 3 when
-- the MatchEnd / RematchRequest / LeaveMatch Remotes exist.
-- Styled per the cozy art direction: cream panel, rounded corners,
-- FredokaOne display, peach rematch button with squish-on-press.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local UIConstants = require(ReplicatedStorage.Shared.UI.UIConstants)
local Events = require(ReplicatedStorage.Shared.Events)
local Constants = require(ReplicatedStorage.Shared.Logic.Constants)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local screen = Instance.new("ScreenGui")
screen.Name = "MatchEnd"
screen.ResetOnSpawn = false
screen.DisplayOrder = UIConstants.ZOrder.RoundBanner
screen.Parent = playerGui

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.Size = UDim2.fromOffset(420, 360)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.BackgroundColor3 = UIConstants.Colors.Cream
panel.BackgroundTransparency = 0
panel.BorderSizePixel = 0
panel.Visible = false
panel.Parent = screen

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UIConstants.Corners.Panel
panelCorner.Parent = panel

local panelStroke = Instance.new("UIStroke")
panelStroke.Color = UIConstants.Colors.StrokeWarm
panelStroke.Thickness = 2
panelStroke.Transparency = 0.4
panelStroke.Parent = panel

local panelPadding = Instance.new("UIPadding")
panelPadding.PaddingTop = UDim.new(0, 24)
panelPadding.PaddingBottom = UDim.new(0, 24)
panelPadding.PaddingLeft = UDim.new(0, 24)
panelPadding.PaddingRight = UDim.new(0, 24)
panelPadding.Parent = panel

local title = Instance.new("TextLabel")
title.Name = "Title"
title.Size = UDim2.new(1, 0, 0, 56)
title.BackgroundTransparency = 1
title.FontFace = UIConstants.Fonts.Display
title.TextSize = UIConstants.TextSizes.Display
title.TextColor3 = UIConstants.Colors.TextDark
title.Text = ""
title.Parent = panel

local scoreLines = Instance.new("TextLabel")
scoreLines.Name = "ScoreLines"
scoreLines.Size = UDim2.new(1, 0, 0, 90)
scoreLines.Position = UDim2.fromOffset(0, 70)
scoreLines.BackgroundTransparency = 1
scoreLines.FontFace = UIConstants.Fonts.HUD
scoreLines.TextSize = UIConstants.TextSizes.Body
scoreLines.TextColor3 = UIConstants.Colors.TextDark
scoreLines.TextXAlignment = Enum.TextXAlignment.Left
scoreLines.TextYAlignment = Enum.TextYAlignment.Top
scoreLines.TextWrapped = true
scoreLines.Parent = panel

local countdown = Instance.new("TextLabel")
countdown.Name = "Countdown"
countdown.Size = UDim2.new(1, 0, 0, 24)
countdown.Position = UDim2.fromOffset(0, 174)
countdown.BackgroundTransparency = 1
countdown.FontFace = UIConstants.Fonts.HUD
countdown.TextSize = UIConstants.TextSizes.HUDLabel
countdown.TextColor3 = UIConstants.Colors.TextSoft
countdown.Text = ""
countdown.Parent = panel

local opponentStatus = Instance.new("TextLabel")
opponentStatus.Name = "OpponentStatus"
opponentStatus.Size = UDim2.new(1, 0, 0, 20)
opponentStatus.Position = UDim2.fromOffset(0, 202)
opponentStatus.BackgroundTransparency = 1
opponentStatus.FontFace = UIConstants.Fonts.HUD
opponentStatus.TextSize = UIConstants.TextSizes.HUDLabel
opponentStatus.TextColor3 = UIConstants.Colors.TextSoft
opponentStatus.Text = "Opponent: waiting"
opponentStatus.Parent = panel

local function makeButton(name, text, anchorX, primary)
    local btn = Instance.new("TextButton")
    btn.Name = name
    btn.Size = UDim2.fromOffset(160, 52)
    btn.Position = UDim2.new(anchorX, anchorX == 0 and 0 or -160, 1, -52)
    btn.AutoButtonColor = false
    btn.BorderSizePixel = 0
    btn.BackgroundColor3 = primary and UIConstants.Colors.Peach or UIConstants.Colors.Mint
    btn.TextColor3 = UIConstants.Colors.TextDark
    btn.FontFace = UIConstants.Fonts.Display
    btn.TextSize = UIConstants.TextSizes.Score
    btn.Text = text
    btn.Parent = panel

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UIConstants.Corners.Button
    corner.Parent = btn

    local scale = Instance.new("UIScale")
    scale.Scale = 1
    scale.Parent = btn

    return btn, scale
end

local rematchBtn, rematchScale = makeButton("RematchBtn", "Rematch", 0, true)
local leaveBtn, leaveScale = makeButton("LeaveBtn", "Leave", 1, false)

local function squish(target)
    target.Scale = UIConstants.Motion.ButtonPressScale
    TweenService:Create(
        target,
        UIConstants.tween(UIConstants.Durations.ButtonPress, "UI"),
        { Scale = 1 }
    ):Play()
end

local function setLeaveEnabled(enabled)
    leaveBtn.AutoButtonColor = enabled
    leaveBtn.Active = enabled
    leaveBtn.TextTransparency = enabled and 0 or 0.4
end
setLeaveEnabled(false)

local remotes = ReplicatedStorage:WaitForChild("Remotes", 30)
if not remotes then
    return
end

-- Day 3's Events.lua adds RematchRequest + LeaveMatch. If we're running
-- against the Day-1 subset, those names are nil; bail silently rather
-- than passing nil to WaitForChild.
local rematchName = Events.Names.RematchRequest
local leaveName = Events.Names.LeaveMatch
local matchEndName = Events.Names.MatchEnd
if not (rematchName and leaveName and matchEndName) then
    return
end

local rematchRemote = remotes:WaitForChild(rematchName, 30)
local leaveRemote = remotes:WaitForChild(leaveName, 30)
local matchEndRemote = remotes:WaitForChild(matchEndName, 30)
if not (rematchRemote and leaveRemote and matchEndRemote) then
    return
end

local currentMatchTimer = nil

matchEndRemote.OnClientEvent:Connect(function(event)
    panel.Visible = true
    local isWinner = tostring(event.winner) == tostring(player.UserId)
    title.Text = isWinner and "Match Winner!" or "Match over"

    local lines = {}
    for pid, score in event.finalScores do
        table.insert(
            lines,
            ("Player %s: %s   Best chain: %d"):format(tostring(pid), tostring(score), event.bestChain[pid] or 0)
        )
    end
    if event.closestRoundPearls then
        table.insert(lines, ("Closest round: %d pearls from overflow"):format(event.closestRoundPearls))
    end
    scoreLines.Text = table.concat(lines, "\n")

    -- 1s cooldown on the Leave button per design spec.
    setLeaveEnabled(false)
    task.delay(Constants.REMATCH_LEAVE_COOLDOWN, function()
        setLeaveEnabled(true)
    end)

    -- Rematch countdown.
    local started = tick()
    if currentMatchTimer then task.cancel(currentMatchTimer) end
    currentMatchTimer = task.spawn(function()
        while panel.Visible do
            local remaining = Constants.REMATCH_WINDOW - (tick() - started)
            if remaining <= 0 then
                panel.Visible = false
                break
            end
            countdown.Text = ("Rematch window: %.1fs"):format(remaining)
            task.wait(0.1)
        end
    end)
end)

rematchBtn.MouseButton1Click:Connect(function()
    squish(rematchScale)
    rematchRemote:FireServer({})
    rematchBtn.Active = false
    rematchBtn.AutoButtonColor = false
    opponentStatus.Text = "Opponent: waiting"
end)

leaveBtn.MouseButton1Click:Connect(function()
    if not leaveBtn.Active then return end
    squish(leaveScale)
    leaveRemote:FireServer({})
    panel.Visible = false
end)
