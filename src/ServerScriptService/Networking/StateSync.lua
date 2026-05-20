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
    self._activePieceRemote = getRemote(Events.Names.ActivePieceUpdate)
    -- Synchronous wiring: RoomManager fires onRoomReady AFTER GameState exists
    -- but BEFORE startRound, so the first onPieceSpawned dispatch has subscribers.
    roomManager:onRoomReady(function(room) self:wireRoom(room) end)
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
                cells = event.cells,
                isLocal = (tostring(p.UserId) == event.playerId),
            })
        end
    end)
    gs:subscribe("onPieceLocked", function(event)
        if not self._pieceLockedRemote then return end
        for _, p in room.players do
            self._pieceLockedRemote:FireClient(p, {
                playerId = event.playerId,
                a = event.a, b = event.b,
                aRow = event.aRow, aCol = event.aCol,
                bRow = event.bRow, bCol = event.bCol,
                cells = event.cells,
                isLocal = (tostring(p.UserId) == event.playerId),
            })
        end
    end)
    -- ActivePieceUpdate: forward both the initial spawn and every successful
    -- move/rotate/softDrop/tick so the client renderer can paint the falling pair.
    -- GameState's two source events have slightly different shapes (onPieceSpawned
    -- flattens, onPieceMoved nests under `piece`); normalize here.
    local function fireActivePiece(event)
        if not self._activePieceRemote then return end
        local piece = event.piece
        local a = piece and piece.a or event.a
        local b = piece and piece.b or event.b
        local pivotRow = piece and piece.pivotRow or event.pivotRow
        local pivotCol = piece and piece.pivotCol or event.pivotCol
        local orientation = piece and piece.orientation or event.orientation
        for _, p in room.players do
            self._activePieceRemote:FireClient(p, {
                playerId = event.playerId,
                isLocal = (tostring(p.UserId) == event.playerId),
                colors = { a = a, b = b },
                pivotRow = pivotRow,
                pivotCol = pivotCol,
                orientation = orientation,
            })
        end
    end
    gs:subscribe("onPieceSpawned", fireActivePiece)
    gs:subscribe("onPieceMoved", fireActivePiece)
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

return StateSync
