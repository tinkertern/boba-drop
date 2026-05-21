-- AmbientLoop: cozy lo-fi background ambience that plays continuously while
-- the player is in the experience. Parented to SoundService (not a ScreenGui)
-- because SoundService is the canonical home for ambient/global audio in
-- Roblox: it survives respawns automatically, is not affected by camera or
-- character lifecycle, and matches the existing convention used by
-- CountdownOverlay and the pearl pop sounds in this project.
--
-- Volume is intentionally low (0.15) so it sits under SFX. A future Settings
-- panel will let the player tune it via the BobaDropMusicVolume attribute
-- on the LocalPlayer; this script already listens for that attribute so the
-- wiring is in place even though no UI exposes it yet.

local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer

-- Asset choice: rbxassetid://9046862282 is a known lo-fi loop on the Roblox
-- audio library. It's a safe, free, evergreen pick. Sarah can swap this for
-- a curated cozy/cafe ambience later by changing AMBIENT_ASSET_ID. Possible
-- swap candidates noted in the scope doc: rbxassetid://1840684528 (cafe).
local AMBIENT_ASSET_ID = "rbxassetid://9046862282"

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

-- BobaDropMusicEnabled defaults to true. The Settings panel writes this
-- attribute when the player flips the "PLAY MUSIC" toggle, and we
-- pause/resume playback here so the change is immediate.
local function resolveEnabled()
    local attr = player:GetAttribute(ENABLED_ATTRIBUTE)
    if typeof(attr) ~= "boolean" then return true end
    return attr
end

local sound = Instance.new("Sound")
sound.Name = "BobaDropAmbientLoop"
sound.SoundId = AMBIENT_ASSET_ID
sound.Looped = true
sound.Volume = resolveVolume()
sound.Parent = SoundService

if resolveEnabled() then
    sound:Play()
end

-- Runtime volume control. The Settings panel sets this attribute on the
-- LocalPlayer; we listen here so changes take effect immediately without
-- needing to restart playback.
player:GetAttributeChangedSignal(VOLUME_ATTRIBUTE):Connect(function()
    sound.Volume = resolveVolume()
end)

-- Runtime enable / disable. Pause keeps the playback position so when the
-- player flips music back on, the loop resumes where it left off rather
-- than re-streaming from the start.
player:GetAttributeChangedSignal(ENABLED_ATTRIBUTE):Connect(function()
    if resolveEnabled() then
        sound:Resume()
    else
        sound:Pause()
    end
end)

-- Safety net: if the asset fails to stream in or stops for any reason, kick
-- it back on, but only if music is currently enabled. Looped = true normally
-- handles this; Roblox occasionally pauses sounds on focus loss or network
-- hiccups.
sound.Ended:Connect(function()
    if resolveEnabled() then
        sound:Play()
    end
end)
