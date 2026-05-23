-- Server-side persistence for client-driven audio settings.
-- Settings.client.lua writes BobaDropMusicVolume / BobaDropSoundFxVolume /
-- BobaDropMusicEnabled attributes on the LocalPlayer when the user adjusts
-- a slider or flips the music toggle. This script saves those values to
-- DataStore (debounced) and restores them on rejoin, so a player who turns
-- off music doesn't have to do it every session.
--
-- Mirrors the TutorialState.server.lua pattern: server owns the DataStore
-- side, client owns the UI side, attributes are the wire.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")

local store = DataStoreService:GetDataStore("BobaDrop_Settings_v1")
local SAVE_DEBOUNCE = 2.5  -- coalesce rapid slider drags into one write

local ATTR_MUSIC_VOL = "BobaDropMusicVolume"
local ATTR_SFX_VOL = "BobaDropSoundFxVolume"
local ATTR_MUSIC_ENABLED = "BobaDropMusicEnabled"

local function keyFor(player)
    return "u" .. tostring(player.UserId)
end

-- Per-player pending-save task. A rapid-fire slider drag fires hundreds of
-- attribute changes per second; coalescing into one DataStore write avoids
-- hitting Roblox's per-key rate limit.
local pending = {}

local function flushSave(player)
    if not player or not player.Parent then return end
    local data = {
        musicVolume = tonumber(player:GetAttribute(ATTR_MUSIC_VOL)),
        sfxVolume = tonumber(player:GetAttribute(ATTR_SFX_VOL)),
        musicEnabled = (player:GetAttribute(ATTR_MUSIC_ENABLED) == true),
    }
    pcall(function()
        store:SetAsync(keyFor(player), data)
    end)
end

local function scheduleSave(player)
    if pending[player.UserId] then
        task.cancel(pending[player.UserId])
    end
    pending[player.UserId] = task.delay(SAVE_DEBOUNCE, function()
        pending[player.UserId] = nil
        flushSave(player)
    end)
end

local function loadState(player)
    task.spawn(function()
        local ok, stored = pcall(function()
            return store:GetAsync(keyFor(player))
        end)
        if not ok or not player.Parent then return end
        if type(stored) == "table" then
            if type(stored.musicVolume) == "number" then
                player:SetAttribute(ATTR_MUSIC_VOL, stored.musicVolume)
            end
            if type(stored.sfxVolume) == "number" then
                player:SetAttribute(ATTR_SFX_VOL, stored.sfxVolume)
            end
            if type(stored.musicEnabled) == "boolean" then
                player:SetAttribute(ATTR_MUSIC_ENABLED, stored.musicEnabled)
            end
        end
        -- Hook save-on-change AFTER load completes so our own SetAttribute
        -- calls above don't recursively schedule a save of values we just
        -- loaded.
        player:GetAttributeChangedSignal(ATTR_MUSIC_VOL):Connect(function()
            scheduleSave(player)
        end)
        player:GetAttributeChangedSignal(ATTR_SFX_VOL):Connect(function()
            scheduleSave(player)
        end)
        player:GetAttributeChangedSignal(ATTR_MUSIC_ENABLED):Connect(function()
            scheduleSave(player)
        end)
    end)
end

Players.PlayerAdded:Connect(loadState)
for _, p in Players:GetPlayers() do
    loadState(p)
end

Players.PlayerRemoving:Connect(function(player)
    if pending[player.UserId] then
        task.cancel(pending[player.UserId])
        pending[player.UserId] = nil
    end
    -- One final flush so changes in the last SAVE_DEBOUNCE seconds before
    -- leaving aren't lost. Synchronous pcall is fine here; Roblox waits a
    -- few seconds on PlayerRemoving for handlers to finish.
    flushSave(player)
end)

print("[SettingsState] ready")
