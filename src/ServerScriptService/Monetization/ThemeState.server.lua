-- Server-side persistence for the player's equipped theme selection.
-- ThemesInventory.client.lua writes the BobaDropActiveTheme attribute on
-- equip; this script saves it to DataStore on change and restores it on
-- rejoin so a player who bought + equipped Galaxy doesn't snap back to
-- Default the next time they join.
--
-- GamePasses.lua seeds BobaDropActiveTheme = "Default" synchronously on
-- PlayerAdded if the attribute is nil. Our async DataStore load runs after
-- that seed and overrides with the stored value if any exists. Race-free
-- because GamePasses always sets a value first, so the inventory client
-- never sees a nil attribute, and our load only ever upgrades it to a
-- previously-equipped theme.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")

local store = DataStoreService:GetDataStore("BobaDrop_Themes_v1")
local SAVE_DEBOUNCE = 1.5
local ATTR_ACTIVE_THEME = "BobaDropActiveTheme"

local function keyFor(player)
    return "u" .. tostring(player.UserId)
end

local pending = {}

local function flushSave(player)
    if not player or not player.Parent then return end
    local theme = player:GetAttribute(ATTR_ACTIVE_THEME)
    if type(theme) ~= "string" then return end
    pcall(function()
        store:SetAsync(keyFor(player), theme)
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
        if type(stored) == "string" then
            player:SetAttribute(ATTR_ACTIVE_THEME, stored)
        end
        player:GetAttributeChangedSignal(ATTR_ACTIVE_THEME):Connect(function()
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
    flushSave(player)
end)

print("[ThemeState] ready")
