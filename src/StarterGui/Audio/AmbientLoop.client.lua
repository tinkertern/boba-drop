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

local sound = Instance.new("Sound")
sound.Name = "BobaDropAmbientLoop"
sound.SoundId = AMBIENT_ASSET_ID
sound.Looped = true
sound.Volume = resolveVolume()
sound.Parent = SoundService

sound:Play()

-- Runtime volume control. The future Settings panel will set this attribute
-- on the LocalPlayer; we listen here so changes take effect immediately
-- without needing to restart playback.
player:GetAttributeChangedSignal(VOLUME_ATTRIBUTE):Connect(function()
    sound.Volume = resolveVolume()
end)

-- Safety net: if the asset fails to stream in or stops for any reason, kick
-- it back on. Looped = true normally handles this, but Roblox occasionally
-- pauses sounds on focus loss or network hiccups.
sound.Ended:Connect(function()
    sound:Play()
end)
