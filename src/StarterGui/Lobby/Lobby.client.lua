-- Lobby UI: tutorial card + matchmaking queue panel + themes button.
-- Tutorial dismiss state lives on the server (DataStore); client reads
-- via player:GetAttribute("TutorialDismissed") and fires DismissTutorial
-- RemoteEvent to request the write. Queue UI is client-side elapsed
-- timer; the server-side RoomManager actually matches players. Themes
-- button opens the Shop modal via _G.BobaDropShop.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local UIConstants = require(ReplicatedStorage.Shared.UI.UIConstants)
local Constants = require(ReplicatedStorage.Shared.Logic.Constants)

local ATTRIBUTE = "TutorialDismissed"

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local dismissRemote = ReplicatedStorage:WaitForChild("DismissTutorial")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "Lobby"
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = UIConstants.ZOrder.Tutorial
screenGui.Parent = playerGui

local card = Instance.new("Frame")
card.Name = "Tutorial"
card.Size = UDim2.fromOffset(340, 130)
card.Position = UDim2.fromScale(0.5, 0.22)
card.AnchorPoint = Vector2.new(0.5, 0.5)
card.BackgroundColor3 = UIConstants.Colors.Cream
card.BackgroundTransparency = 0
card.BorderSizePixel = 0
card.Parent = screenGui

local cardCorner = Instance.new("UICorner")
cardCorner.CornerRadius = UIConstants.Corners.Card
cardCorner.Parent = card

local cardStroke = Instance.new("UIStroke")
cardStroke.Color = UIConstants.Colors.StrokeWarm
cardStroke.Thickness = 2
cardStroke.Transparency = 0.4
cardStroke.Parent = card

-- Text lives in a wrapper so its UIPadding does not also shift the close
-- button — the X stays anchored to the card's actual top-right corner.
local textWrapper = Instance.new("Frame")
textWrapper.Name = "TextWrapper"
textWrapper.Size = UDim2.fromScale(1, 1)
textWrapper.BackgroundTransparency = 1
textWrapper.Parent = card

local textPadding = Instance.new("UIPadding")
textPadding.PaddingTop = UDim.new(0, 14)
textPadding.PaddingBottom = UDim.new(0, 14)
textPadding.PaddingLeft = UDim.new(0, 18)
textPadding.PaddingRight = UDim.new(0, 44) -- reserve space for close button
textPadding.Parent = textWrapper

-- Small color dots above the body text — telegraphs what pearls look
-- like before the player ever sees the board.
local dotRow = Instance.new("Frame")
dotRow.Name = "DotRow"
dotRow.Size = UDim2.fromOffset(78, 14)
dotRow.Position = UDim2.fromOffset(0, 0)
dotRow.BackgroundTransparency = 1
dotRow.Parent = textWrapper

local dotLayout = Instance.new("UIListLayout")
dotLayout.FillDirection = Enum.FillDirection.Horizontal
dotLayout.Padding = UDim.new(0, 6)
dotLayout.VerticalAlignment = Enum.VerticalAlignment.Center
dotLayout.Parent = dotRow

local function makeDot(color)
    local dot = Instance.new("Frame")
    dot.Size = UDim2.fromOffset(14, 14)
    dot.BackgroundColor3 = color
    dot.BorderSizePixel = 0
    dot.Parent = dotRow

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(1, 0)
    corner.Parent = dot

    local stroke = Instance.new("UIStroke")
    stroke.Color = UIConstants.Colors.StrokeWarm
    stroke.Thickness = 0.5
    stroke.Transparency = 0.4
    stroke.Parent = dot
end

makeDot(UIConstants.Colors.PearlBrown)
makeDot(UIConstants.Colors.PearlPink)
makeDot(UIConstants.Colors.PearlGreen)
makeDot(UIConstants.Colors.PearlWhite)

-- RichText body: key verbs are colored + bolded so the rules read with
-- some rhythm instead of as a wall of dark-brown text. "pop" / "Chain" /
-- "ice cubes" / "overflow" each take an accent color drawn from the
-- palette they actually represent in-game.
local label = Instance.new("TextLabel")
label.Size = UDim2.new(1, 0, 1, -20)
label.Position = UDim2.fromOffset(0, 20)
label.BackgroundTransparency = 1
label.TextColor3 = UIConstants.Colors.TextDark
label.TextWrapped = true
label.RichText = true
label.TextXAlignment = Enum.TextXAlignment.Left
label.TextYAlignment = Enum.TextYAlignment.Top
label.FontFace = UIConstants.Fonts.Tutorial
label.TextSize = UIConstants.TextSizes.Body
label.Text = table.concat({
    "Match <b>4+</b> same-color pearls to <b><font color=\"rgb(255,138,124)\">pop</font></b>.",
    "<b><font color=\"rgb(255,175,195)\">Chain</font></b> pops send <b><font color=\"rgb(120,180,220)\">ice cubes</font></b> to your opponent.",
    "Don't <b><font color=\"rgb(255,138,124)\">overflow</font></b> your cup.",
}, "\n")
label.Parent = textWrapper

-- Direct child of card (not textWrapper) so the text-padding does not push
-- this off into the middle. Anchored to the card's actual top-right corner.
local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.fromOffset(28, 28)
closeBtn.Position = UDim2.new(1, -10, 0, 10)
closeBtn.AnchorPoint = Vector2.new(1, 0)
closeBtn.Text = "×"
closeBtn.FontFace = UIConstants.Fonts.Display
closeBtn.TextSize = 22
closeBtn.TextColor3 = UIConstants.Colors.TextOnWarm
closeBtn.BackgroundColor3 = UIConstants.Colors.Peach
closeBtn.BorderSizePixel = 0
closeBtn.AutoButtonColor = false
closeBtn.Parent = card

local closeCorner = Instance.new("UICorner")
closeCorner.CornerRadius = UIConstants.Corners.Button
closeCorner.Parent = closeBtn

local closeScale = Instance.new("UIScale")
closeScale.Scale = 1
closeScale.Parent = closeBtn

local function squish(target)
    target.Scale = UIConstants.Motion.ButtonPressScale
    TweenService:Create(
        target,
        UIConstants.tween(UIConstants.Durations.ButtonPress, "UI"),
        { Scale = 1 }
    ):Play()
end

-- Idle bob so the card feels alive (2-4px float bob, period IdleFloatPeriod).
local basePosY = card.Position.Y.Scale
local baseOffsetY = card.Position.Y.Offset
local bobAmp = UIConstants.Motion.FloatBobPx
local startTime = os.clock()
local bobConn = RunService.RenderStepped:Connect(function()
    if not card.Visible then return end
    local t = (os.clock() - startTime) / UIConstants.Durations.IdleFloatPeriod
    local offset = math.sin(t * math.pi * 2) * bobAmp
    card.Position = UDim2.new(card.Position.X.Scale, card.Position.X.Offset, basePosY, baseOffsetY + offset)
end)

-- Queue state (declared early so applyVisibility can see it).
local queueStarted = tick()
local queueActive = true

-- Debug override: when true, force the card visible regardless of the
-- DataStore-persisted dismiss attribute. Toggled by the corner "?" button
-- below. Remove the whole `Debug toggle` block (and the forceShow read in
-- applyVisibility) to retire this once we don't need it.
local forceShow = false

local function applyVisibility()
    -- Tutorial card auto-hides while the matchmaking queue is active so
    -- the two centered cards never overlap. Player either reads the rules
    -- or watches the queue, not both at once.
    if queueActive then
        card.Visible = false
        return
    end
    if forceShow then
        card.Visible = true
        return
    end
    card.Visible = not player:GetAttribute(ATTRIBUTE)
end

local function requestDismiss()
    squish(closeScale)
    forceShow = false
    card.Visible = false
    dismissRemote:FireServer()
end

applyVisibility()
player:GetAttributeChangedSignal(ATTRIBUTE):Connect(applyVisibility)

closeBtn.MouseButton1Click:Connect(requestDismiss)
card.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        requestDismiss()
    end
end)

-- Queue panel: cream pill below the tutorial card showing the elapsed
-- search time and a Cancel button. Counts up client-side; the server
-- RoomManager actually drives the match-found transition.
local queuePanel = Instance.new("Frame")
queuePanel.Name = "Queue"
queuePanel.Size = UDim2.fromOffset(340, 116)
queuePanel.Position = UDim2.fromScale(0.5, 0.45)
queuePanel.AnchorPoint = Vector2.new(0.5, 0.5)
queuePanel.BackgroundColor3 = UIConstants.Colors.Cream
queuePanel.BackgroundTransparency = 0
queuePanel.BorderSizePixel = 0
queuePanel.Parent = screenGui

local queueCorner = Instance.new("UICorner")
queueCorner.CornerRadius = UIConstants.Corners.Card
queueCorner.Parent = queuePanel

local queueStroke = Instance.new("UIStroke")
queueStroke.Color = UIConstants.Colors.StrokeWarm
queueStroke.Thickness = 2
queueStroke.Transparency = 0.4
queueStroke.Parent = queuePanel

local queueLabel = Instance.new("TextLabel")
queueLabel.Name = "Status"
queueLabel.Size = UDim2.new(1, -24, 0, 52) -- tall enough for the 2-line timeout message
queueLabel.Position = UDim2.fromOffset(12, 10)
queueLabel.BackgroundTransparency = 1
queueLabel.FontFace = UIConstants.Fonts.HUD
queueLabel.TextSize = UIConstants.TextSizes.Body
queueLabel.TextColor3 = UIConstants.Colors.TextDark
queueLabel.TextXAlignment = Enum.TextXAlignment.Left
queueLabel.TextYAlignment = Enum.TextYAlignment.Top
queueLabel.TextWrapped = true
queueLabel.Text = "Searching for opponent...  0s"
queueLabel.Parent = queuePanel

local cancelBtn = Instance.new("TextButton")
cancelBtn.Name = "CancelBtn"
cancelBtn.Size = UDim2.fromOffset(144, 36) -- wide enough for "Search again"
cancelBtn.Position = UDim2.new(0, 12, 1, -46)
cancelBtn.AnchorPoint = Vector2.new(0, 0)
cancelBtn.AutoButtonColor = false
cancelBtn.BorderSizePixel = 0
cancelBtn.BackgroundColor3 = UIConstants.Colors.Mint
cancelBtn.TextColor3 = UIConstants.Colors.TextDark
cancelBtn.FontFace = UIConstants.Fonts.Display
cancelBtn.TextSize = UIConstants.TextSizes.HUDLabel
cancelBtn.Text = "Cancel"
cancelBtn.Parent = queuePanel

local cancelCorner = Instance.new("UICorner")
cancelCorner.CornerRadius = UIConstants.Corners.Button
cancelCorner.Parent = cancelBtn

local cancelScale = Instance.new("UIScale")
cancelScale.Scale = 1
cancelScale.Parent = cancelBtn

-- Queue lifecycle: startQueue() drives the elapsed timer and flips
-- the cancel button into a Cancel / Search-again toggle, so the panel
-- always has an actionable button instead of an inert post-state.
local function setSearchAgainMode(message)
    queueActive = false
    queueLabel.Text = message
    cancelBtn.Text = "Search again"
    cancelBtn.BackgroundColor3 = UIConstants.Colors.Peach
    applyVisibility()
end

local function startQueue()
    queueStarted = tick()
    queueActive = true
    queueLabel.Text = "Searching for opponent...  0s"
    cancelBtn.Text = "Cancel"
    cancelBtn.BackgroundColor3 = UIConstants.Colors.Mint
    applyVisibility()
    task.spawn(function()
        while queueActive and queuePanel.Parent do
            local elapsed = math.floor(tick() - queueStarted)
            queueLabel.Text = ("Searching for opponent...  %ds"):format(elapsed)
            if elapsed >= Constants.QUEUE_TIMEOUT then
                setSearchAgainMode("No opponent yet. Play vs CPU or invite a friend.")
                break
            end
            task.wait(1)
        end
    end)
end

startQueue()

cancelBtn.MouseButton1Click:Connect(function()
    squish(cancelScale)
    if queueActive then
        setSearchAgainMode("Queue canceled")
    else
        startQueue()
        -- TODO Day 4: fire a real RequeueRequest RemoteEvent if/when the server adds one.
    end
end)

-- Themes button: opens the Shop modal. Disabled (greyed) while the queue
-- is active so players can't accidentally buy mid-matchmaking.
local themesBtn = Instance.new("TextButton")
themesBtn.Name = "ThemesBtn"
themesBtn.Size = UDim2.fromOffset(132, 36)
themesBtn.Position = UDim2.new(1, -56, 0, 16)
themesBtn.AnchorPoint = Vector2.new(1, 0)
themesBtn.AutoButtonColor = false
themesBtn.BorderSizePixel = 0
themesBtn.BackgroundColor3 = UIConstants.Colors.Peach
themesBtn.TextColor3 = UIConstants.Colors.TextDark
themesBtn.FontFace = UIConstants.Fonts.Display
themesBtn.TextSize = UIConstants.TextSizes.HUDLabel
themesBtn.Text = "Themes"
themesBtn.Parent = screenGui

local themesCorner = Instance.new("UICorner")
themesCorner.CornerRadius = UIConstants.Corners.Button
themesCorner.Parent = themesBtn

local themesStroke = Instance.new("UIStroke")
themesStroke.Color = UIConstants.Colors.StrokeWarm
themesStroke.Thickness = 1.5
themesStroke.Transparency = 0.4
themesStroke.Parent = themesBtn

local themesScale = Instance.new("UIScale")
themesScale.Scale = 1
themesScale.Parent = themesBtn

-- Full color-swap between enabled (vibrant peach) and disabled (muted
-- cream) so the affordance is unambiguous, not just a transparency dim.
local function applyThemesEnabled()
    local enabled = not queueActive
    themesBtn.AutoButtonColor = enabled
    if enabled then
        themesBtn.BackgroundColor3 = UIConstants.Colors.Peach
        themesBtn.TextColor3 = UIConstants.Colors.TextDark
        themesBtn.BackgroundTransparency = 0
        themesBtn.TextTransparency = 0
        themesStroke.Color = UIConstants.Colors.StrokeWarm
        themesStroke.Transparency = 0.3
    else
        themesBtn.BackgroundColor3 = UIConstants.Colors.Cream
        themesBtn.TextColor3 = UIConstants.Colors.TextSoft
        themesBtn.BackgroundTransparency = 0.15
        themesBtn.TextTransparency = 0.2
        themesStroke.Color = UIConstants.Colors.StrokeSoft
        themesStroke.Transparency = 0.55
    end
end
applyThemesEnabled()

-- Poll queueActive once per second so the themes button updates after the
-- 60s timeout flips queueActive to false.
task.spawn(function()
    while themesBtn.Parent do
        applyThemesEnabled()
        task.wait(0.5)
    end
end)

themesBtn.MouseButton1Click:Connect(function()
    if queueActive then return end
    squish(themesScale)
    if _G.BobaDropShop then
        _G.BobaDropShop.open()
    end
end)

-- ── Debug toggle ────────────────────────────────────────────────────────
-- Tiny corner button to force-show the tutorial card during testing.
-- Safe to delete this whole block once the tutorial visuals are settled.
local debugBtn = Instance.new("TextButton")
debugBtn.Name = "TutorialDebugToggle"
debugBtn.Size = UDim2.fromOffset(32, 32)
debugBtn.Position = UDim2.new(1, -16, 0, 16)
debugBtn.AnchorPoint = Vector2.new(1, 0)
debugBtn.AutoButtonColor = false
debugBtn.BorderSizePixel = 0
debugBtn.BackgroundColor3 = UIConstants.Colors.Cream
debugBtn.TextColor3 = UIConstants.Colors.TextDark
debugBtn.FontFace = UIConstants.Fonts.Display
debugBtn.TextSize = 18
debugBtn.Text = "?"
debugBtn.Parent = screenGui

local debugCorner = Instance.new("UICorner")
debugCorner.CornerRadius = UIConstants.Corners.Button
debugCorner.Parent = debugBtn

local debugStroke = Instance.new("UIStroke")
debugStroke.Color = UIConstants.Colors.StrokeWarm
debugStroke.Thickness = 1.5
debugStroke.Transparency = 0.4
debugStroke.Parent = debugBtn

local debugScale = Instance.new("UIScale")
debugScale.Scale = 1
debugScale.Parent = debugBtn

debugBtn.MouseButton1Click:Connect(function()
    squish(debugScale)
    forceShow = not forceShow
    applyVisibility()
end)
-- ─────────────────────────────────────────────────────────────────────────

screenGui.AncestryChanged:Connect(function(_, parent)
    if not parent then bobConn:Disconnect() end
end)
