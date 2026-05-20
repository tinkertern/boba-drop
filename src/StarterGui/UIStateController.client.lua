-- UIStateController: single source of truth for which ScreenGuis are
-- visible based on the player's GameState attribute.
--
-- Read player:GetAttribute("GameState") which is one of:
--   "lobby"     — pre-queue lobby. Tutorial + Themes + (nothing else).
--   "matching"  — queue pill is up but no match yet. Same screens as lobby.
--   "in_match"  — gameplay is live. Board + HUD pieces visible, lobby hidden.
--   "match_end" — results panel on top of (still-visible) board. Lobby hidden.
--
-- The server (RoomManager → StateSync) is the writer for this attribute.
-- Client default until the server writes is "lobby" so first frame after spawn
-- shows the lobby UI, not a blank screen.
--
-- This controller only toggles ScreenGui.Enabled. It does not create, destroy,
-- or rearrange any GUI. Each existing client script is still responsible for
-- building its own ScreenGui and its internal visibility (e.g. Shop's modal
-- frame is hidden inside the always-Enabled Shop ScreenGui).

local Players = game:GetService("Players")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local STATES = {
    Lobby = "lobby",
    Matching = "matching",
    InMatch = "in_match",
    MatchEnd = "match_end",
}

-- Visibility map. true = ScreenGui.Enabled, false = disabled.
-- Backdrop + Shop are intentionally absent; they are always enabled and manage
-- their own internal visibility, so the controller leaves them alone.
local VISIBILITY = {
    [STATES.Lobby] = {
        Lobby = true,
        BoardPlaceholder = false,
        ScoreDisplay = false,
        ChainCounter = false,
        GarbagePreview = false,
        CounterCancel = false,
        MatchEnd = false,
    },
    [STATES.Matching] = {
        Lobby = true,
        BoardPlaceholder = false,
        ScoreDisplay = false,
        ChainCounter = false,
        GarbagePreview = false,
        CounterCancel = false,
        MatchEnd = false,
    },
    [STATES.InMatch] = {
        Lobby = false,
        BoardPlaceholder = true,
        ScoreDisplay = true,
        ChainCounter = true,
        GarbagePreview = true,
        CounterCancel = true,
        MatchEnd = false,
    },
    [STATES.MatchEnd] = {
        Lobby = false,
        BoardPlaceholder = true, -- board stays visible as backdrop to results
        ScoreDisplay = true,
        ChainCounter = false,
        GarbagePreview = false,
        CounterCancel = false,
        MatchEnd = true,
    },
}

local currentState = player:GetAttribute("GameState") or STATES.Lobby
if not VISIBILITY[currentState] then
    currentState = STATES.Lobby
end

local function applyVisibility()
    local map = VISIBILITY[currentState]
    if not map then return end
    for name, enabled in pairs(map) do
        local gui = playerGui:FindFirstChild(name)
        if gui and gui:IsA("ScreenGui") then
            gui.Enabled = enabled
        end
    end
end

-- Apply once on load (some ScreenGuis may already exist, some may arrive later).
applyVisibility()

-- Catch ScreenGuis that get created after this script runs. Most client scripts
-- in /StarterGui/ create their ScreenGui on first frame, but order isn't
-- guaranteed, so this is the safety net.
playerGui.ChildAdded:Connect(function(child)
    if not child:IsA("ScreenGui") then return end
    local map = VISIBILITY[currentState]
    if not map then return end
    if map[child.Name] ~= nil then
        child.Enabled = map[child.Name]
    end
end)

-- React to server-driven state changes.
player:GetAttributeChangedSignal("GameState"):Connect(function()
    local newState = player:GetAttribute("GameState")
    if not newState or not VISIBILITY[newState] then return end
    if newState == currentState then return end
    currentState = newState
    applyVisibility()
end)

-- Lightweight global for debug/manual driving from the command bar in Studio.
-- Set _G.BobaDropUIState.set("in_match") to test transitions before the server
-- wires GameState attribute writes. Safe to delete once that's live.
_G.BobaDropUIState = {
    get = function() return currentState end,
    set = function(newState)
        if not VISIBILITY[newState] then
            warn("[UIStateController] unknown state: " .. tostring(newState))
            return
        end
        currentState = newState
        applyVisibility()
    end,
    STATES = STATES,
}
