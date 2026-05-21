-- AmbientLoop: cozy lo-fi background music playlist. Cycles sequentially
-- through the AMBIENT_PLAYLIST asset ids, wrapping back to the first when
-- the last finishes. Parented to SoundService (canonical home for global
-- audio in Roblox, survives respawn, matches existing convention).
--
-- Volume defaults to 0.15 (sits under SFX) and is tunable at runtime via
-- the BobaDropMusicVolume attribute. Music can be toggled off via
-- BobaDropMusicEnabled. The Settings panel writes both.

local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer

-- TODO Sarah: paste your uploaded audio asset ids here. Format:
-- "rbxassetid://<numeric_id>", one entry per track, comma-separated.
-- The script cycles in order, wraps to the first after the last ends.
-- A single entry behaves identically to single-track looping.
--
-- Where to find the ids: in Roblox Studio, View tab → Asset Manager →
-- Audio. Click your uploaded clip, the id appears in the Properties
-- panel or at the URL.
local AMBIENT_PLAYLIST = {
    -- "rbxassetid://<first_id>",
    -- "rbxassetid://<second_id>",
}

local DEFAULT_VOLUME = 0.15
local VOLUME_ATTRIBUTE = "BobaDropMusicVolume"
local ENABLED_ATTRIBUTE = "BobaDropMusicEnabled"

local function clampVolume(v)
    if typeof(v) ~= "number" then return DEFAULT_VOLUME end
    if v < 0 then return 0 end
    if v > 1 then return 1 end
    return v
end

local function resolveVolume()
    local attr = player:GetAttribute(VOLUME_ATTRIBUTE)
    if attr == nil then
        return DEFAULT_VOLUME
    end
    return clampVolume(attr)
end

local function resolveEnabled()
    local attr = player:GetAttribute(ENABLED_ATTRIBUTE)
    if typeof(attr) ~= "boolean" then return true end
    return attr
end

local sound = Instance.new("Sound")
sound.Name = "BobaDropAmbientLoop"
-- Looped is intentionally false: we want .Ended to fire after each track
-- so the playlist can advance. Single-track playlists still loop because
-- the advance handler wraps index 1 to index 1.
sound.Looped = false
sound.Volume = resolveVolume()
sound.Parent = SoundService

local currentIndex = 1

local function playCurrent()
    if #AMBIENT_PLAYLIST == 0 then return end
    sound.SoundId = AMBIENT_PLAYLIST[currentIndex]
    if resolveEnabled() then
        sound:Play()
    end
end

local function advanceAndPlay()
    if #AMBIENT_PLAYLIST == 0 then return end
    currentIndex = (currentIndex % #AMBIENT_PLAYLIST) + 1
    playCurrent()
end

if #AMBIENT_PLAYLIST > 0 then
    playCurrent()
else
    warn("[AmbientLoop] AMBIENT_PLAYLIST is empty. Add asset ids in src/StarterGui/Audio/AmbientLoop.client.lua")
end

-- Runtime volume control.
player:GetAttributeChangedSignal(VOLUME_ATTRIBUTE):Connect(function()
    sound.Volume = resolveVolume()
end)

-- Runtime enable / disable. On re-enable, resume the current track if it
-- was mid-play; otherwise start (or re-start) the current index from the
-- top. On disable, pause where it is.
player:GetAttributeChangedSignal(ENABLED_ATTRIBUTE):Connect(function()
    if resolveEnabled() then
        if sound.IsPlaying then return end
        if sound.TimePosition > 0 and sound.TimePosition < sound.TimeLength then
            sound:Resume()
        else
            playCurrent()
        end
    else
        sound:Pause()
    end
end)

-- Playlist advance: when a track ends, move to the next index and play.
sound.Ended:Connect(function()
    if resolveEnabled() then
        advanceAndPlay()
    end
end)
