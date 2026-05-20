-- src/ReplicatedStorage/Shared/Logic/GameState.lua
local Constants = require("../Logic/Constants")
local Board = require("../Logic/Board")

local GameState = {}
GameState.__index = GameState

function GameState.new(ctx)
    assert(ctx.players and #ctx.players == 2, "GameState requires exactly 2 players")
    assert(ctx.seed, "GameState requires seed")
    local self = setmetatable({}, GameState)
    self._players = ctx.players
    self._baseSeed = ctx.seed
    self._phase = "waiting"
    self._roundNumber = 0
    self._roundsWon = { [ctx.players[1]] = 0, [ctx.players[2]] = 0 }
    self._scores = { [ctx.players[1]] = 0, [ctx.players[2]] = 0 } -- per-round
    self._pendingGarbage = { [ctx.players[1]] = 0, [ctx.players[2]] = 0 }
    self._placementsUntilGarbage = { [ctx.players[1]] = 0, [ctx.players[2]] = 0 }
    self._boards = {}
    self._subscribers = {}
    self._matchWinner = nil
    return self
end

function GameState:phase() return self._phase end
function GameState:roundsWon(playerId) return self._roundsWon[playerId] end
function GameState:scoreOf(playerId) return self._scores[playerId] end
function GameState:boardFor(playerId) return self._boards[playerId] end
function GameState:matchWinner() return self._matchWinner end
function GameState:roundNumber() return self._roundNumber end

function GameState:subscribe(eventName, fn)
    self._subscribers[eventName] = self._subscribers[eventName] or {}
    table.insert(self._subscribers[eventName], fn)
end

function GameState:_dispatch(eventName, payload)
    local list = self._subscribers[eventName]
    if not list then return end
    for _, fn in list do
        fn(payload)
    end
end

function GameState:startRound()
    self._roundNumber += 1
    self._phase = "playing"
    -- Both players use the same seed this round (versus convention)
    local roundSeed = self._baseSeed + self._roundNumber * 1009
    self._boards = {}
    for _, p in self._players do
        self._boards[p] = Board.new({ seed = roundSeed })
        self._scores[p] = 0
    end
    self:_dispatch("onRoundStart", { round = self._roundNumber })
end

function GameState:_otherPlayer(playerId)
    for _, p in self._players do
        if p ~= playerId then return p end
    end
    error("unknown player " .. tostring(playerId))
end

function GameState:_endRound(winner, loser, reason)
    self._roundsWon[winner] += 1
    self:_dispatch("onRoundEnd", { winner = winner, loser = loser, reason = reason, round = self._roundNumber })
    if self._roundsWon[winner] >= Constants.ROUNDS_TO_WIN then
        self._phase = "matchOver"
        self._matchWinner = winner
        self:_dispatch("onMatchEnd", { winner = winner })
    else
        self._phase = "betweenRounds"
    end
end

function GameState:forfeitRound(loserId, reason)
    assert(self._phase == "playing", "forfeitRound only valid during 'playing'")
    local winner = self:_otherPlayer(loserId)
    self:_endRound(winner, loserId, reason)
end

function GameState:pendingGarbage(playerId) return self._pendingGarbage[playerId] end
function GameState:placementsUntilGarbage(playerId) return self._placementsUntilGarbage[playerId] end

function GameState:queueGarbage(targetPlayerId, cubes)
    self._pendingGarbage[targetPlayerId] += cubes
    self._placementsUntilGarbage[targetPlayerId] = 2
    self:_dispatch("onGarbageIncoming", {
        playerId = targetPlayerId,
        cubes = cubes,
        dropsInPlacements = 2,
    })
end

function GameState:applyOutgoingChain(senderPlayerId, outgoingCubes)
    -- First subtract from sender's incoming queue, then any remainder goes to opponent
    local pending = self._pendingGarbage[senderPlayerId]
    if pending > 0 then
        local canceled = math.min(pending, outgoingCubes)
        self._pendingGarbage[senderPlayerId] -= canceled
        outgoingCubes -= canceled
        self:_dispatch("onGarbageApplied", {
            playerId = senderPlayerId,
            cubes = 0,
            canceledByCounter = canceled,
        })
    end
    if outgoingCubes > 0 then
        local opponent = self:_otherPlayer(senderPlayerId)
        self:queueGarbage(opponent, outgoingCubes)
    end
end

function GameState:declareDraw()
    assert(self._phase == "playing", "declareDraw only valid during 'playing'")
    -- draw does not advance match; redo the round
    -- Clear queued garbage on both sides (per spec) BEFORE dispatch+decrement
    for _, p in self._players do
        self._pendingGarbage[p] = 0
        self._placementsUntilGarbage[p] = 0
    end
    self:_dispatch("onRoundDraw", { round = self._roundNumber })
    -- decrement round number so startRound brings us back to same round number with fresh seed
    self._roundNumber -= 1
end

return GameState
