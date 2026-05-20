-- Server-owned dismiss-state for the lobby tutorial card.
-- DataStoreService is server-only; client reads via Player attribute,
-- writes via the DismissTutorial RemoteEvent.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")

local ATTRIBUTE = "TutorialDismissed"
local store = DataStoreService:GetDataStore("BobaDrop_TutorialDismissed")

local function keyFor(player)
    return "u" .. tostring(player.UserId)
end

local remote = Instance.new("RemoteEvent")
remote.Name = "DismissTutorial"
remote.Parent = ReplicatedStorage

local function loadState(player)
    player:SetAttribute(ATTRIBUTE, false)
    task.spawn(function()
        local ok, value = pcall(function()
            return store:GetAsync(keyFor(player))
        end)
        if ok and value == true and player.Parent then
            player:SetAttribute(ATTRIBUTE, true)
        end
    end)
end

Players.PlayerAdded:Connect(loadState)
for _, p in Players:GetPlayers() do
    loadState(p)
end

remote.OnServerEvent:Connect(function(player)
    if player:GetAttribute(ATTRIBUTE) then return end
    player:SetAttribute(ATTRIBUTE, true)
    task.spawn(function()
        pcall(function()
            store:SetAsync(keyFor(player), true)
        end)
    end)
end)
