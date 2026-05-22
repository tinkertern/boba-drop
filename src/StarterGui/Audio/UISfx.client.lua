-- UISfx: 4 short UI sound effects, played from a global table so every
-- click handler in the UI tree can fire one without requiring a module.
-- Parented to SoundService (matches AmbientLoop's convention, survives
-- respawn, no GUI dependency).
--
-- Kinds + target durations:
--   click   80-150ms  light tap feedback for non-committal buttons
--                     (pills, gear, ?, toggles)
--   confirm 200-300ms positive commit feedback (PLAY, Buy, REMATCH,
--                     Search again)
--   back    100-200ms reversal / dismissal feedback (Cancel, X close,
--                     GOT IT, LEAVE)
--   error   150-250ms reserved for future invalid-action feedback
--                     (not yet wired anywhere, included so the slot
--                     exists when Sarah uploads ids)
--
-- Volume is read from the BobaDropSoundFxVolume attribute (set by the
-- Settings panel; default 0.7 matches DEFAULT_SFX there). Setting the
-- attribute to 0 silences playback without unloading. Updating the
-- attribute at runtime is reflected immediately on all 4 sounds.

local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer

-- TODO Sarah: paste your uploaded SFX asset ids below. Format:
-- "rbxassetid://<numeric_id>". An empty string disables that sound
-- silently (the wrapper checks before :Play()).
--
-- Where to find ids: Roblox Studio, View tab → Asset Manager → Audio,
-- click the uploaded clip, copy the id from the Properties panel.
local CLICK_ID   = ""
local CONFIRM_ID = ""
local BACK_ID    = ""
local ERROR_ID   = ""

local DEFAULT_SFX_VOLUME = 0.7
local SFX_VOLUME_ATTRIBUTE = "BobaDropSoundFxVolume"

local function clampVolume(v)
    if typeof(v) ~= "number" then return DEFAULT_SFX_VOLUME end
    if v < 0 then return 0 end
    if v > 1 then return 1 end
    return v
end

local function resolveVolume()
    local attr = player:GetAttribute(SFX_VOLUME_ATTRIBUTE)
    if attr == nil then
        return DEFAULT_SFX_VOLUME
    end
    return clampVolume(attr)
end

local function makeSound(name, assetId)
    local sound = Instance.new("Sound")
    sound.Name = name
    sound.Looped = false
    sound.Volume = resolveVolume()
    sound.SoundId = assetId
    sound.Parent = SoundService
    return sound
end

local clickSound   = makeSound("BobaDropSfxClick",   CLICK_ID)
local confirmSound = makeSound("BobaDropSfxConfirm", CONFIRM_ID)
local backSound    = makeSound("BobaDropSfxBack",    BACK_ID)
local errorSound   = makeSound("BobaDropSfxError",   ERROR_ID)

-- :Stop() then :Play() so a rapid double-tap gets two distinct triggers
-- rather than the second tap silently merging into the first sound's
-- mid-playback. Skips entirely when the asset id is empty (lets us ship
-- the wiring before the audio uploads land) or when SFX volume is 0.
local function playKind(sound)
    if sound.SoundId == "" then return end
    if resolveVolume() <= 0 then return end
    sound:Stop()
    sound:Play()
end

_G.BobaDropSfx = {
    click = function() playKind(clickSound) end,
    confirm = function() playKind(confirmSound) end,
    back = function() playKind(backSound) end,
    error = function() playKind(errorSound) end,
}

-- Runtime volume control. Settings slider writes the attribute; this
-- pushes the new value to all 4 sounds so the next play is at the new
-- level. Currently-playing sounds also pick up the change immediately
-- because Sound.Volume is live.
player:GetAttributeChangedSignal(SFX_VOLUME_ATTRIBUTE):Connect(function()
    local v = resolveVolume()
    clickSound.Volume = v
    confirmSound.Volume = v
    backSound.Volume = v
    errorSound.Volume = v
end)
