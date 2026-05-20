-- src/ReplicatedStorage/Shared/Logic/GameState.lua
local Constants = require("../Logic/Constants")
local Board = require("../Logic/Board")
local ChainResolver = require("../Logic/ChainResolver")
local Scoring = require("../Logic/Scoring")

local GameState = {}
GameState.__index = GameState

-- Spawn coordinates: just above the visible playfield, in the danger rows.
-- Pivot (a) sits at row 13, partner (b) starts above at row 14 (orientation 0).
local SPAWN_ROW = Constants.BOARD_VISIBLE_HEIGHT + 1
local SPAWN_COL = math.floor(Constants.BOARD_WIDTH / 2)

local function partnerOffset(orientation)
    -- 0: b above a, 1: b right, 2: b below, 3: b left
    if orientation == 0 then return 1, 0
    elseif orientation == 1 then return 0, 1
    elseif orientation == 2 then return -1, 0
    else return 0, -1
    end
end

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
    self._activePieces = {}
    self._bestChain = { [ctx.players[1]] = 0, [ctx.players[2]] = 0 }
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
function GameState:activePiece(playerId) return self._activePieces[playerId] end
function GameState:bestChain(playerId) return self._bestChain[playerId] end

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
    self._activePieces = {}
    for _, p in self._players do
        self._boards[p] = Board.new({ seed = roundSeed })
        self._scores[p] = 0
        self._pendingGarbage[p] = 0
        self._placementsUntilGarbage[p] = 0
        self._bestChain[p] = 0
    end
    self:_dispatch("onRoundStart", { round = self._roundNumber })
    -- Spawn the first active piece for each player
    for _, p in self._players do
        self:_spawnPiece(p)
    end
end

function GameState:_otherPlayer(playerId)
    for _, p in self._players do
        if p ~= playerId then return p end
    end
    error("unknown player " .. tostring(playerId))
end

function GameState:_endRound(winner, loser, reason)
    self._roundsWon[winner] += 1
    self:_dispatch("onRoundEnd", {
        winner = winner,
        loser = loser,
        reason = reason,
        round = self._roundNumber,
        scores = { [self._players[1]] = self._scores[self._players[1]], [self._players[2]] = self._scores[self._players[2]] },
    })
    if self._roundsWon[winner] >= Constants.ROUNDS_TO_WIN then
        self._phase = "matchOver"
        self._matchWinner = winner
        self:_dispatch("onMatchEnd", {
            winner = winner,
            finalScores = { [self._players[1]] = self._scores[self._players[1]], [self._players[2]] = self._scores[self._players[2]] },
            bestChain = { [self._players[1]] = self._bestChain[self._players[1]], [self._players[2]] = self._bestChain[self._players[2]] },
        })
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

-- ----- Active piece lifecycle -----

function GameState:_spawnPiece(playerId)
    local board = self._boards[playerId]
    if not board then return end
    local nextPiece = board:advance(1)[1]
    self._activePieces[playerId] = {
        a = nextPiece.a,
        b = nextPiece.b,
        pivotRow = SPAWN_ROW,
        pivotCol = SPAWN_COL,
        orientation = 0,
    }
    self:_dispatch("onPieceSpawned", {
        playerId = playerId,
        a = nextPiece.a,
        b = nextPiece.b,
        pivotRow = SPAWN_ROW,
        pivotCol = SPAWN_COL,
        orientation = 0,
    })
end

local function cellsOf(piece)
    local dr, dc = partnerOffset(piece.orientation)
    return { piece.pivotRow, piece.pivotCol }, { piece.pivotRow + dr, piece.pivotCol + dc }
end

local function withinBoard(board, row, col)
    return row >= 1 and col >= 1 and col <= board.width and row <= board.height
end

function GameState:_pieceFits(playerId, piece)
    local board = self._boards[playerId]
    local aPos, bPos = cellsOf(piece)
    for _, pos in { aPos, bPos } do
        if pos[2] < 1 or pos[2] > board.width then return false end
        if pos[1] < 1 then return false end
        -- Allow rows above the board's top (piece can rotate with b above ceiling
        -- while spawning); blocking happens during lock based on filled cells.
        if pos[1] <= board.height and board:cellAt(pos[1], pos[2]) ~= nil then return false end
    end
    return true
end

function GameState:_dropDistance(playerId, piece)
    -- How many rows the piece can fall before colliding.
    local board = self._boards[playerId]
    local dist = 0
    while true do
        local test = {
            a = piece.a, b = piece.b,
            pivotRow = piece.pivotRow - (dist + 1),
            pivotCol = piece.pivotCol,
            orientation = piece.orientation,
        }
        if not self:_pieceFits(playerId, test) then break end
        dist += 1
    end
    return dist
end

function GameState:applyInput(playerId, input)
    if self._phase ~= "playing" then return end
    local piece = self._activePieces[playerId]
    if not piece then return end

    if input.type == "move" then
        local delta = input.direction == "left" and -1 or 1
        local candidate = {
            a = piece.a, b = piece.b,
            pivotRow = piece.pivotRow,
            pivotCol = piece.pivotCol + delta,
            orientation = piece.orientation,
        }
        if self:_pieceFits(playerId, candidate) then
            piece.pivotCol = candidate.pivotCol
            self:_dispatch("onPieceMoved", { playerId = playerId, piece = piece })
        end
    elseif input.type == "rotate" then
        local newOri = (input.direction == "cw") and ((piece.orientation + 1) % 4) or ((piece.orientation + 3) % 4)
        local candidate = {
            a = piece.a, b = piece.b,
            pivotRow = piece.pivotRow,
            pivotCol = piece.pivotCol,
            orientation = newOri,
        }
        if self:_pieceFits(playerId, candidate) then
            piece.orientation = newOri
            self:_dispatch("onPieceMoved", { playerId = playerId, piece = piece })
        end
        -- No wallkick per design.md known limitations.
    elseif input.type == "softDrop" then
        if input.held then
            local candidate = {
                a = piece.a, b = piece.b,
                pivotRow = piece.pivotRow - 1,
                pivotCol = piece.pivotCol,
                orientation = piece.orientation,
            }
            if self:_pieceFits(playerId, candidate) then
                piece.pivotRow = candidate.pivotRow
                self:_dispatch("onPieceMoved", { playerId = playerId, piece = piece })
            else
                self:_lockPiece(playerId)
            end
        end
    elseif input.type == "hardDrop" then
        local dist = self:_dropDistance(playerId, piece)
        piece.pivotRow -= dist
        self:_lockPiece(playerId)
    elseif input.type == "tick" then
        -- Gravity step (server-driven). Same effect as a single soft-drop step.
        local candidate = {
            a = piece.a, b = piece.b,
            pivotRow = piece.pivotRow - 1,
            pivotCol = piece.pivotCol,
            orientation = piece.orientation,
        }
        if self:_pieceFits(playerId, candidate) then
            piece.pivotRow = candidate.pivotRow
            self:_dispatch("onPieceMoved", { playerId = playerId, piece = piece })
        else
            self:_lockPiece(playerId)
        end
    end
end

function GameState:_lockPiece(playerId)
    local piece = self._activePieces[playerId]
    if not piece then return end
    local board = self._boards[playerId]

    local aPos, bPos = cellsOf(piece)
    -- Place cells that land inside the board grid. If a cell is above the
    -- board (off-grid above), it's discarded (effectively a partial lock).
    if withinBoard(board, aPos[1], aPos[2]) then
        board:placeAt(aPos[1], aPos[2], piece.a)
    end
    if withinBoard(board, bPos[1], bPos[2]) then
        board:placeAt(bPos[1], bPos[2], piece.b)
    end

    self:_dispatch("onPieceLocked", {
        playerId = playerId,
        a = piece.a, b = piece.b,
        aRow = aPos[1], aCol = aPos[2],
        bRow = bPos[1], bCol = bPos[2],
    })

    self._activePieces[playerId] = nil

    -- Settle in case of partial overhangs (b above ceiling, a inside).
    board:gravitySettle()

    -- Run chain
    local result = ChainResolver.resolve(board)
    if result.chainLength > 0 then
        local scoreAdded = 0
        for idx, step in result.steps do
            scoreAdded += Scoring.compute({
                popped = step.popped,
                chainStep = idx,
                colors = step.colors,
            })
        end
        self._scores[playerId] += scoreAdded
        if result.chainLength > self._bestChain[playerId] then
            self._bestChain[playerId] = result.chainLength
        end

        self:_dispatch("onChainResolved", {
            playerId = playerId,
            chainLength = result.chainLength,
            totalPopped = result.totalPopped,
            scoreAdded = scoreAdded,
            steps = result.steps,
        })

        -- Convert chain length to outgoing garbage and route through counter logic
        local outgoing = Constants.GARBAGE_TABLE[result.chainLength] or Constants.GARBAGE_CAP
        if result.chainLength >= 6 then outgoing = Constants.GARBAGE_CAP end
        if outgoing > 0 then
            self:applyOutgoingChain(playerId, outgoing)
        end
    end

    -- Garbage placement countdown: decrement after each placement.
    -- Drops happen when the counter hits zero AND there's pending garbage.
    if self._pendingGarbage[playerId] > 0 then
        self._placementsUntilGarbage[playerId] -= 1
        if self._placementsUntilGarbage[playerId] <= 0 then
            self:_dropGarbage(playerId)
        end
    end

    -- Overflow check: any cell occupied in the danger rows (above visible) ends the round
    if self:_isOverflowed(playerId) then
        local winner = self:_otherPlayer(playerId)
        self:_endRound(winner, playerId, "overflow")
        return
    end

    -- If the round just ended for any other reason, stop
    if self._phase ~= "playing" then return end

    -- Spawn the next piece
    self:_spawnPiece(playerId)

    -- If the freshly-spawned piece overlaps existing cells, that's also overflow
    local fresh = self._activePieces[playerId]
    if fresh and not self:_pieceFits(playerId, fresh) then
        local winner = self:_otherPlayer(playerId)
        self:_endRound(winner, playerId, "overflow")
    end
end

function GameState:_isOverflowed(playerId)
    local board = self._boards[playerId]
    for r = Constants.BOARD_VISIBLE_HEIGHT + 1, board.height do
        for c = 1, board.width do
            if board:cellAt(r, c) ~= nil then return true end
        end
    end
    return false
end

function GameState:_dropGarbage(playerId)
    local board = self._boards[playerId]
    local cubes = self._pendingGarbage[playerId]
    if cubes <= 0 then return end

    -- Distribute cubes across columns roughly evenly. Drop into the lowest
    -- empty cell of each column. Excess cubes go column-by-column in order.
    local perCol = math.floor(cubes / board.width)
    local extra = cubes % board.width

    local placed = 0
    for col = 1, board.width do
        local target = perCol + (col <= extra and 1 or 0)
        for _ = 1, target do
            -- find lowest empty cell in column
            local r = 1
            while r <= board.height and board:cellAt(r, col) ~= nil do
                r += 1
            end
            if r <= board.height then
                board:placeAt(r, col, "Garbage")
                placed += 1
            end
        end
    end

    self._pendingGarbage[playerId] = 0
    self._placementsUntilGarbage[playerId] = 0
    self:_dispatch("onGarbageApplied", {
        playerId = playerId,
        cubes = placed,
        canceledByCounter = 0,
    })
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
