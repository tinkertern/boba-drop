-- src/ServerScriptService/Networking/StateSync.lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Events = require(ReplicatedStorage.Shared.Events)

local StateSync = {}
StateSync.__index = StateSync

local function getRemote(name)
    return ReplicatedStorage:WaitForChild("Remotes"):WaitForChild(name)
end

function StateSync.new(roomManager)
    local self = setmetatable({}, StateSync)
    self._roomManager = roomManager
    self._chainRemote = getRemote(Events.Names.ChainCompleted)
    self._garbageInRemote = getRemote(Events.Names.GarbageIncoming)
    self._garbageAppliedRemote = getRemote(Events.Names.GarbageApplied)
    self._roundEndRemote = getRemote(Events.Names.RoundEnd)
    self._matchEndRemote = getRemote(Events.Names.MatchEnd)
    self._pieceLockedRemote = getRemote(Events.Names.PieceLocked)
    self:_attachToRooms()
    return self
end

function StateSync:_findPlayer(userIdStr)
    for _, p in Players:GetPlayers() do
        if tostring(p.UserId) == userIdStr then return p end
    end
    return nil
end

-- The RoomManager calls this when a new room starts so we wire subscriptions.
function StateSync:wireRoom(room)
    local gs = room.gameState
    gs:subscribe("onChainResolved", function(event)
        local localPlayer = self:_findPlayer(event.playerId)
        if not localPlayer then return end
        -- Fire to both players, marking isLocal appropriately
        for _, p in room.players do
            self._chainRemote:FireClient(p, {
                playerId = event.playerId,
                chainLength = event.chainLength,
                totalPopped = event.totalPopped,
                scoreAdded = event.scoreAdded,
                isLocal = (tostring(p.UserId) == event.playerId),
            })
        end
    end)
    gs:subscribe("onPieceLocked", function(event)
        if not self._pieceLockedRemote then return end
        for _, p in room.players do
            self._pieceLockedRemote:FireClient(p, event)
        end
    end)
    gs:subscribe("onGarbageIncoming", function(event)
        for _, p in room.players do
            self._garbageInRemote:FireClient(p, event)
        end
    end)
    gs:subscribe("onGarbageApplied", function(event)
        for _, p in room.players do
            self._garbageAppliedRemote:FireClient(p, event)
        end
    end)
    gs:subscribe("onRoundEnd", function(event)
        for _, p in room.players do
            self._roundEndRemote:FireClient(p, event)
        end
    end)
    gs:subscribe("onMatchEnd", function(event)
        for _, p in room.players do
            self._matchEndRemote:FireClient(p, event)
        end
        self._roomManager:onMatchEnd(room)
    end)
end

function StateSync:_attachToRooms()
    -- Poll-style: every 0.5s scan for newly-created rooms that haven't been wired
    -- (alternative: have RoomManager emit a roomCreated event; this is simpler for Day 3)
    task.spawn(function()
        local wired = {}
        while true do
            for _, room in self._roomManager._rooms do
                if not wired[room] then
                    self:wireRoom(room)
                    wired[room] = true
                end
            end
            task.wait(0.5)
        end
    end)
end

return StateSync
