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

-- TODO Sarah: drop a real audio asset id here once you upload a cozy loop.
-- Roblox tightened audio licensing in late 2024: only audio uploaded by
-- the experience creator (or Roblox-published assets) plays in-experience.
-- The prior placeholder (rbxassetid://9046862282) was the wrong asset type
-- and Roblox rejected it at load. Until a valid id lives here, the Sound
-- object stays parented (so the volume/enabled listeners still wire up for
-- the Settings panel) but :Play() is gated so we don't spam the console.
--
-- Upload steps: creator.roblox.com → Creations → Audio → Upload, grab the
-- asset id, format as "rbxassetid://<id>".
local AMBIENT_ASSET_ID = ""

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

if AMBIENT_ASSET_ID ~= "" and resolveEnabled() then
    sound:Play()
elseif AMBIENT_ASSET_ID == "" then
    warn("[AmbientLoop] No AMBIENT_ASSET_ID set. Upload an audio asset to your Roblox account and set the id in src/StarterGui/Audio/AmbientLoop.client.lua")
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
    if AMBIENT_ASSET_ID ~= "" and resolveEnabled() then
        sound:Play()
    end
end)
