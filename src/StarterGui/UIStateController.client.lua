-- UIStateController: single source of truth for which ScreenGuis are
-- visible based on the player's GameState attribute.
--
-- Read player:GetAttribute("GameState") which is one of:
--   "main_menu" — pre-queue landing screen. MainMenu is the only Enabled UI.
--   "matching"  — queue pill is up. Lobby is Enabled, MainMenu hides.
--   "in_match"  — gameplay is live. Board + HUD pieces visible, menu + lobby hidden.
--   "match_end" — results panel on top of (still-visible) board. Menu + lobby hidden.
--
-- The server (RoomManager -> StateSync) is the writer for this attribute.
-- Client default until the server writes is "main_menu" so first frame after
-- spawn shows the landing screen, not a blank screen.
--
-- This controller only toggles ScreenGui.Enabled. It does not create, destroy,
-- or rearrange any GUI. Each existing client script is still responsible for
-- building its own ScreenGui and its internal visibility (e.g. Shop's modal
-- frame is hidden inside the always-Enabled Shop ScreenGui).

local Players = game:GetService("Players")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local STATES = {
    MainMenu = "main_menu",
    Matching = "matching",
    InMatch = "in_match",
    MatchEnd = "match_end",
}

-- Visibility map. true = ScreenGui.Enabled, false = disabled.
-- Backdrop + Shop + Settings + HowToPlay are intentionally absent; they are
-- always enabled and manage their own internal visibility, so the controller
-- leaves them alone.
local VISIBILITY = {
    [STATES.MainMenu] = {
        MainMenu = true,
        Lobby = false,
        BoardPlaceholder = false,
        ScoreDisplay = false,
        ChainCounter = false,
        GarbagePreview = false,
        CounterCancel = false,
        MatchEnd = false,
    },
    [STATES.Matching] = {
        MainMenu = false,
        Lobby = true,
        BoardPlaceholder = false,
        ScoreDisplay = false,
        ChainCounter = false,
        GarbagePreview = false,
        CounterCancel = false,
        MatchEnd = false,
    },
    [STATES.InMatch] = {
        MainMenu = false,
        Lobby = false,
        BoardPlaceholder = true,
        ScoreDisplay = true,
        ChainCounter = true,
        GarbagePreview = true,
        CounterCancel = true,
        MatchEnd = false,
    },
    [STATES.MatchEnd] = {
        MainMenu = false,
        Lobby = false,
        BoardPlaceholder = true, -- board stays visible as backdrop to results
        ScoreDisplay = true,
        ChainCounter = false,
        GarbagePreview = false,
        CounterCancel = false,
        MatchEnd = true,
    },
}

local currentState = player:GetAttribute("GameState") or STATES.MainMenu
if not VISIBILITY[currentState] then
    currentState = STATES.MainMenu
end

local function applyVisibility()
    local map = VISIBILITY[currentState]
    if not map then return end
    -- Iterate by ScreenGui IsA-check, not by FindFirstChild(name): Rojo mirrors
    -- src/StarterGui/<Name>/ as a Folder in PlayerGui with the same name as the
    -- ScreenGui the inner script creates (Lobby, MatchEnd, Shop, Backdrop, MainMenu
    -- all collide). FindFirstChild returns whichever child sorts first, which is
    -- usually the Folder, so .Enabled silently no-ops and state transitions
    -- after the initial frame stop working.
    for _, gui in playerGui:GetChildren() do
        if gui:IsA("ScreenGui") and map[gui.Name] ~= nil then
            gui.Enabled = map[gui.Name]
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
