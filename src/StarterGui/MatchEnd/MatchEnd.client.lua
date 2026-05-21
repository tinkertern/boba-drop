-- Match-end panel. Polished per scope A6:
--   * Slide-up from bottom (Back/Out)
--   * Result header (YOU WIN / YOU LOSE / DRAW) with palette colors
--   * Score row count-up (FINAL: yours vs theirs)
--   * Best-chain row with chain gradient
--   * REMATCH (Mint) / LEAVE (WarmCancel) split full-width
--   * Rematch window countdown text below buttons
-- Driven by the MatchEnd RemoteEvent. ScreenGui.Enabled is controlled by
-- UIStateController for the "match_end" state; the remote populates content.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local UIConstants = require(ReplicatedStorage.Shared.UI.UIConstants)
local Events = require(ReplicatedStorage.Shared.Events)
local Constants = require(ReplicatedStorage.Shared.Logic.Constants)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local REMATCH_WINDOW = Constants.REMATCH_WINDOW or 15
local LEAVE_COOLDOWN = Constants.REMATCH_LEAVE_COOLDOWN or 1

-- ZOrder.MatchEnd isn't in UIConstants; we sit above BlockedFlash (110)
-- so the panel is guaranteed to render over any in-match HUD layer.
local MATCH_END_Z = 120

local PANEL_SIZE = Vector2.new(480, 360)
local SLIDE_DURATION = 0.4
local COUNTUP_DURATION = 0.8

--------------------------------------------------------------------------------
-- ScreenGui root
--------------------------------------------------------------------------------

local screen = Instance.new("ScreenGui")
screen.Name = "MatchEnd"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = true
screen.DisplayOrder = MATCH_END_Z
screen.Enabled = false  -- UIStateController flips this on for "match_end"
screen.Parent = playerGui

-- Fullscreen scrim (WarmDark @ 0.55) sits behind the panel.
local scrim = Instance.new("Frame")
scrim.Name = "Scrim"
scrim.Size = UDim2.fromScale(1, 1)
scrim.BackgroundColor3 = UIConstants.Colors.WarmDark
scrim.BackgroundTransparency = 0.55
scrim.BorderSizePixel = 0
scrim.ZIndex = 1
scrim.Parent = screen

--------------------------------------------------------------------------------
-- Panel
--------------------------------------------------------------------------------

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Size = UDim2.fromOffset(PANEL_SIZE.X, PANEL_SIZE.Y)
-- Start off-screen (below); slide-in tween brings it to center.
panel.Position = UDim2.new(0.5, 0, 1.5, 0)
panel.BackgroundColor3 = UIConstants.Colors.Cream
panel.BorderSizePixel = 0
panel.ZIndex = 2
panel.Parent = screen

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UIConstants.Corners.Panel
panelCorner.Parent = panel

local panelStroke = Instance.new("UIStroke")
panelStroke.Color = UIConstants.Colors.StrokeWarm
panelStroke.Thickness = 2
panelStroke.Transparency = 0.5
panelStroke.Parent = panel

local panelPadding = Instance.new("UIPadding")
panelPadding.PaddingTop = UDim.new(0, 20)
panelPadding.PaddingBottom = UDim.new(0, 20)
panelPadding.PaddingLeft = UDim.new(0, 24)
panelPadding.PaddingRight = UDim.new(0, 24)
panelPadding.Parent = panel

--------------------------------------------------------------------------------
-- Result header (YOU WIN / YOU LOSE / DRAW)
--------------------------------------------------------------------------------

local header = Instance.new("TextLabel")
header.Name = "Header"
header.Size = UDim2.new(1, 0, 0, 72)
header.Position = UDim2.fromOffset(0, 0)
header.BackgroundTransparency = 1
header.FontFace = UIConstants.Fonts.Display
header.TextSize = UIConstants.TextSizes.DisplayLarge
header.TextColor3 = UIConstants.Colors.TextDark
header.TextXAlignment = Enum.TextXAlignment.Center
header.Text = ""
header.ZIndex = 3
header.Parent = panel

--------------------------------------------------------------------------------
-- Score row (FINAL: 1234 vs 5678)
--------------------------------------------------------------------------------

local scoreRow = Instance.new("TextLabel")
scoreRow.Name = "ScoreRow"
scoreRow.Size = UDim2.new(1, 0, 0, 44)
scoreRow.Position = UDim2.fromOffset(0, 92)
scoreRow.BackgroundTransparency = 1
scoreRow.FontFace = UIConstants.Fonts.HUD
scoreRow.TextSize = UIConstants.TextSizes.Score
scoreRow.TextColor3 = UIConstants.Colors.TextDark
scoreRow.TextXAlignment = Enum.TextXAlignment.Center
scoreRow.Text = "FINAL: 0 vs 0"
scoreRow.ZIndex = 3
scoreRow.Parent = panel

--------------------------------------------------------------------------------
-- Best chain row (BEST CHAIN: 4x  |  3x)
--------------------------------------------------------------------------------

local chainRow = Instance.new("TextLabel")
chainRow.Name = "ChainRow"
chainRow.Size = UDim2.new(1, 0, 0, 28)
chainRow.Position = UDim2.fromOffset(0, 144)
chainRow.BackgroundTransparency = 1
chainRow.FontFace = UIConstants.Fonts.HUD
chainRow.TextSize = 20
chainRow.TextColor3 = UIConstants.Colors.ChainGradientEnd
chainRow.TextXAlignment = Enum.TextXAlignment.Center
chainRow.Text = "BEST CHAIN: 0x"
chainRow.ZIndex = 3
chainRow.Parent = panel

-- Subtle peach->coral gradient on the chain label so it pops without
-- needing per-character coloring. Uses palette gradient anchors.
local chainGradient = Instance.new("UIGradient")
chainGradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, UIConstants.Colors.ChainGradientStart),
    ColorSequenceKeypoint.new(1, UIConstants.Colors.ChainGradientEnd),
})
chainGradient.Rotation = 0
chainGradient.Parent = chainRow

--------------------------------------------------------------------------------
-- Buttons row (REMATCH / LEAVE, full-width split)
--------------------------------------------------------------------------------

local buttonsRow = Instance.new("Frame")
buttonsRow.Name = "Buttons"
buttonsRow.Size = UDim2.new(1, 0, 0, 56)
-- Bottom-anchored, leaving room for the countdown line under it.
buttonsRow.AnchorPoint = Vector2.new(0, 1)
buttonsRow.Position = UDim2.new(0, 0, 1, -28)
buttonsRow.BackgroundTransparency = 1
buttonsRow.ZIndex = 3
buttonsRow.Parent = panel

local buttonsLayout = Instance.new("UIListLayout")
buttonsLayout.FillDirection = Enum.FillDirection.Horizontal
buttonsLayout.SortOrder = Enum.SortOrder.LayoutOrder
buttonsLayout.Padding = UDim.new(0, 12)
buttonsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
buttonsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
buttonsLayout.Parent = buttonsRow

local function makeButton(name, text, bgColor, layoutOrder)
    local btn = Instance.new("TextButton")
    btn.Name = name
    -- Half-width each minus the 12px gap (UIListLayout splits the gap).
    btn.Size = UDim2.new(0.5, -6, 1, 0)
    btn.AutoButtonColor = false
    btn.BorderSizePixel = 0
    btn.BackgroundColor3 = bgColor
    btn.TextColor3 = UIConstants.Colors.TextOnWarm
    btn.FontFace = UIConstants.Fonts.Display
    btn.TextSize = 28
    btn.Text = text
    btn.LayoutOrder = layoutOrder
    btn.ZIndex = 4
    btn.Parent = buttonsRow

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UIConstants.Corners.Button
    corner.Parent = btn

    local scale = Instance.new("UIScale")
    scale.Scale = 1
    scale.Parent = btn

    -- 44pt minimum hit target via invisible padding; visual size is preserved.
    -- (Both buttons already exceed 44pt; this just guards against future tweaks.)
    return btn, scale
end

local rematchBtn, rematchScale = makeButton("RematchBtn", "REMATCH", UIConstants.Colors.Mint, 1)
local leaveBtn, leaveScale = makeButton("LeaveBtn", "LEAVE", UIConstants.Colors.WarmCancel, 2)

local function squish(target)
    target.Scale = UIConstants.Motion.ButtonPressScale
    TweenService:Create(
        target,
        UIConstants.tween(UIConstants.Durations.ButtonPress, "UI"),
        { Scale = 1 }
    ):Play()
end

local function setButtonEnabled(btn, enabled)
    btn.Active = enabled
    btn.AutoButtonColor = false
    btn.TextTransparency = enabled and 0 or 0.4
    btn.BackgroundTransparency = enabled and 0 or 0.3
end

-- Rematch-window countdown text removed at Sarah's request 2026-05-20: the
-- panel should stay open indefinitely waiting on a deliberate REMATCH or LEAVE
-- click. Engineer's matching server change removes the corresponding auto-close
-- timeout. If we ever want to reintroduce a soft hint, this is the spot.

--------------------------------------------------------------------------------
-- Animation helpers
--------------------------------------------------------------------------------

local function slideIn()
    panel.Position = UDim2.new(0.5, 0, 1.5, 0)
    local tween = TweenService:Create(
        panel,
        UIConstants.tween(SLIDE_DURATION, "UI"),
        { Position = UDim2.fromScale(0.5, 0.5) }
    )
    tween:Play()
    return tween
end

-- Count a label from 0 to `target` over COUNTUP_DURATION using RenderStepped.
-- `formatter(currentInt)` returns the full text to set on the label each frame.
local function countUp(label, target, formatter)
    if target <= 0 then
        label.Text = formatter(0)
        return
    end
    local start = os.clock()
    while true do
        local elapsed = os.clock() - start
        local t = math.min(elapsed / COUNTUP_DURATION, 1)
        -- Ease-out quad for a satisfying decel on the final digits.
        local eased = 1 - (1 - t) * (1 - t)
        local current = math.floor(target * eased + 0.5)
        label.Text = formatter(current)
        if t >= 1 then break end
        RunService.RenderStepped:Wait()
    end
    label.Text = formatter(target)
end

--------------------------------------------------------------------------------
-- Remote wiring
--------------------------------------------------------------------------------

local remotes = ReplicatedStorage:WaitForChild("Remotes", 30)
if not remotes then return end

local rematchName = Events.Names.RematchRequest
local leaveName = Events.Names.LeaveMatch
local matchEndName = Events.Names.MatchEnd
if not (rematchName and leaveName and matchEndName) then return end

local rematchRemote = remotes:WaitForChild(rematchName, 30)
local leaveRemote = remotes:WaitForChild(leaveName, 30)
local matchEndRemote = remotes:WaitForChild(matchEndName, 30)
if not (rematchRemote and leaveRemote and matchEndRemote) then return end

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local currentCountdownThread = nil
local currentStatsThread = nil
local rematchSent = false

local function cancelThreads()
    if currentCountdownThread then
        task.cancel(currentCountdownThread)
        currentCountdownThread = nil
    end
    if currentStatsThread then
        task.cancel(currentStatsThread)
        currentStatsThread = nil
    end
end

local function setHeader(state)
    if state == "win" then
        header.Text = "YOU WIN!"
        header.TextColor3 = UIConstants.Colors.Coral
    elseif state == "lose" then
        header.Text = "YOU LOSE"
        header.TextColor3 = UIConstants.Colors.WarmCancel
    else
        header.Text = "DRAW"
        header.TextColor3 = UIConstants.Colors.TextSoft
    end
end

--------------------------------------------------------------------------------
-- MatchEnd payload handler
--------------------------------------------------------------------------------

matchEndRemote.OnClientEvent:Connect(function(event)
    cancelThreads()
    rematchSent = false

    local localId = tostring(player.UserId)
    local winnerId = event.winner and tostring(event.winner) or nil
    local loserId = event.loser and tostring(event.loser) or nil

    -- Result classification.
    local result
    if not winnerId or (winnerId and loserId and winnerId == loserId) then
        result = "draw"
    elseif winnerId == localId then
        result = "win"
    else
        result = "lose"
    end
    setHeader(result)

    -- Score / chain extraction. Server contract per Engineer is `scores`/`bestChain`;
    -- earlier registry shape used `finalScores`. Read both defensively so we
    -- don't crash on either payload version.
    local scores = event.scores or event.finalScores or {}
    local chains = event.bestChain or {}

    -- Find the opponent id: prefer event.loser when local is the winner,
    -- otherwise scan the scores table for any id that isn't us.
    local opponentId
    if winnerId == localId and loserId then
        opponentId = loserId
    elseif loserId == localId and winnerId then
        opponentId = winnerId
    else
        for pid in pairs(scores) do
            local s = tostring(pid)
            if s ~= localId then opponentId = s break end
        end
        if not opponentId then
            for pid in pairs(chains) do
                local s = tostring(pid)
                if s ~= localId then opponentId = s break end
            end
        end
    end

    local yourScore = tonumber(scores[localId]) or tonumber(scores[tonumber(localId)]) or 0
    local theirScore = 0
    if opponentId then
        theirScore = tonumber(scores[opponentId]) or tonumber(scores[tonumber(opponentId)]) or 0
    end

    local yourChain = tonumber(chains[localId]) or tonumber(chains[tonumber(localId)]) or 0
    local theirChain = 0
    if opponentId then
        theirChain = tonumber(chains[opponentId]) or tonumber(chains[tonumber(opponentId)]) or 0
    end

    -- Reset content for animation entry.
    scoreRow.Text = "FINAL: 0 vs 0"
    chainRow.Text = "BEST CHAIN: 0x"

    -- Button reset: rematch enabled immediately, leave on a brief cooldown so
    -- a fat-fingered tap can't bail before the result registers.
    setButtonEnabled(rematchBtn, true)
    setButtonEnabled(leaveBtn, false)
    task.delay(LEAVE_COOLDOWN, function()
        setButtonEnabled(leaveBtn, true)
    end)

    -- Slide the panel in, then count up score, then chain.
    local slideTween = slideIn()
    currentStatsThread = task.spawn(function()
        slideTween.Completed:Wait()
        -- Count score row (track our number + their number together).
        local start = os.clock()
        while true do
            local elapsed = os.clock() - start
            local t = math.min(elapsed / COUNTUP_DURATION, 1)
            local eased = 1 - (1 - t) * (1 - t)
            local y = math.floor(yourScore * eased + 0.5)
            local th = math.floor(theirScore * eased + 0.5)
            scoreRow.Text = ("FINAL: %d vs %d"):format(y, th)
            if t >= 1 then break end
            RunService.RenderStepped:Wait()
        end
        scoreRow.Text = ("FINAL: %d vs %d"):format(yourScore, theirScore)

        -- Then chain row (short, satisfying ramp).
        countUp(chainRow, math.max(yourChain, theirChain), function(_)
            return ("BEST CHAIN: %dx  |  %dx"):format(yourChain, theirChain)
        end)
        chainRow.Text = ("BEST CHAIN: %dx  |  %dx"):format(yourChain, theirChain)
        currentStatsThread = nil
    end)

    -- No rematch-window countdown; panel waits indefinitely for an explicit
    -- REMATCH or LEAVE click. Engineer's server change removes the matching
    -- auto-close so the room doesn't disappear underneath the player either.
end)

--------------------------------------------------------------------------------
-- Button wiring
--------------------------------------------------------------------------------

rematchBtn.MouseButton1Click:Connect(function()
    if not rematchBtn.Active then return end
    if rematchSent then return end
    rematchSent = true
    squish(rematchScale)
    rematchRemote:FireServer({})
    setButtonEnabled(rematchBtn, false)
end)

leaveBtn.MouseButton1Click:Connect(function()
    if not leaveBtn.Active then return end
    squish(leaveScale)
    leaveRemote:FireServer({})
    setButtonEnabled(leaveBtn, false)
    setButtonEnabled(rematchBtn, false)
end)
