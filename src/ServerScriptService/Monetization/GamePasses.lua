-- Cached Game Pass ownership + filtered purchase listener.
-- Day 4 wires this into Main.server.lua. The cache survives the player's
-- session and is repopulated on PlayerAdded.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local GamePasses = {}
GamePasses.__index = GamePasses

-- Premium Themes Pack — created on create.roblox.com 2026-05-19, 99 Robux.
GamePasses.PREMIUM_THEMES_PACK_ID = 1846258540

function GamePasses.new()
    local self = setmetatable({}, GamePasses)
    self._ownership = {}  -- userId -> { [gamePassId] = boolean }
    self:_setup()
    return self
end

function GamePasses:_setup()
    Players.PlayerAdded:Connect(function(player)
        self:_cacheOwnership(player, self.PREMIUM_THEMES_PACK_ID)
    end)
    Players.PlayerRemoving:Connect(function(player)
        self._ownership[player.UserId] = nil
    end)
    for _, player in Players:GetPlayers() do
        self:_cacheOwnership(player, self.PREMIUM_THEMES_PACK_ID)
    end
    -- Filter by gamePassId so the ownership cache cannot be poisoned by
    -- finished events from other Game Passes the player has interacted with.
    MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamePassId, wasPurchased)
        if gamePassId ~= self.PREMIUM_THEMES_PACK_ID then return end
        if wasPurchased then
            self._ownership[player.UserId] = self._ownership[player.UserId] or {}
            self._ownership[player.UserId][gamePassId] = true
            print(("[GamePasses] %s purchased Premium Themes Pack"):format(player.Name))
        end
    end)
end

function GamePasses:_cacheOwnership(player, gamePassId)
    self._ownership[player.UserId] = self._ownership[player.UserId] or {}
    local ok, owned = pcall(function()
        return MarketplaceService:UserOwnsGamePassAsync(player.UserId, gamePassId)
    end)
    if ok then
        self._ownership[player.UserId][gamePassId] = owned
    else
        self._ownership[player.UserId][gamePassId] = false
        warn(("[GamePasses] UserOwnsGamePassAsync failed for %s"):format(player.Name))
    end
end

function GamePasses:owns(player, gamePassId)
    return (self._ownership[player.UserId] or {})[gamePassId] == true
end

function GamePasses:promptPurchase(player, gamePassId)
    MarketplaceService:PromptGamePassPurchase(player, gamePassId)
end

return GamePasses
