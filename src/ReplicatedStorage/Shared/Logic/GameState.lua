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
    -- 1 player = practice mode (solo, no opponent). 2 players = versus.
    -- All routing that previously assumed exactly-2 is now guarded on _isSolo.
    assert(ctx.players and (#ctx.players == 1 or #ctx.players == 2), "GameState requires 1 or 2 players")
    assert(ctx.seed, "GameState requires seed")
    local self = setmetatable({}, GameState)
    self._players = ctx.players
    self._isSolo = (#ctx.players == 1)
    self._mode = self._isSolo and "practice" or "versus"
    self._baseSeed = ctx.seed
    self._phase = "waiting"
    self._roundNumber = 0
    self._roundsWon = {}
    self._scores = {} -- per-round
    self._pendingGarbage = {}
    self._placementsUntilGarbage = {}
    self._bestChain = {}
    for _, p in ctx.players do
        self._roundsWon[p] = 0
        self._scores[p] = 0
        self._pendingGarbage[p] = 0
        self._placementsUntilGarbage[p] = 0
        self._bestChain[p] = 0
    end
    self._boards = {}
    self._activePieces = {}
    self._subscribers = {}
    self._matchWinner = nil
    return self
end

function GameState:isSolo() return self._isSolo end
function GameState:mode() return self._mode end

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

function GameState:announceRoundStartCountdown(startsAt)
    -- Fired by RoomManager just before the ROUND_START_COUNTDOWN wait so the
    -- StateSync subscriber can FireClient the 3-2-1-GO overlay end timestamp
    -- to both players. Kept here (not in RoomManager) so all renderer-facing
    -- events flow through the GameState pub/sub like every other event.
    self:_dispatch("onRoundStartCountdown", { startsAt = startsAt })
end

function GameState:_otherPlayer(playerId)
    -- Solo states have no opponent; callers must guard with _isSolo before
    -- invoking this. Kept as a hard error so a missed guard surfaces loudly
    -- in tests rather than silently corrupting downstream payloads.
    for _, p in self._players do
        if p ~= playerId then return p end
    end
    error("unknown player " .. tostring(playerId))
end

function GameState:_playerKeyedTable(source)
    -- Build a player-keyed map from a source table. Versus payloads always
    -- carry both players' keys; solo payloads carry just the one.
    local out = {}
    for _, p in self._players do
        out[p] = source[p]
    end
    return out
end

function GameState:_endRound(winner, loser, reason)
    self._roundsWon[winner] += 1
    self:_dispatch("onRoundEnd", {
        winner = winner,
        loser = loser,
        reason = reason,
        round = self._roundNumber,
        scores = self:_playerKeyedTable(self._scores),
    })
    if self._roundsWon[winner] >= Constants.ROUNDS_TO_WIN then
        self._phase = "matchOver"
        self._matchWinner = winner
        self:_dispatch("onMatchEnd", {
            winner = winner,
            result = "win",
            mode = self._mode,
            finalScores = self:_playerKeyedTable(self._scores),
            bestChain = self:_playerKeyedTable(self._bestChain),
        })
    else
        self._phase = "betweenRounds"
    end
end

function GameState:_endPracticeOnTopout(playerId)
    -- Solo topout: no opponent to declare as winner, so we skip _endRound
    -- entirely (no onRoundEnd → MatchEnd client's reason subtitle stays
    -- empty, which matches the practice-mode UI variant). Fire onMatchEnd
    -- directly with result = "practice_ended".
    self._phase = "matchOver"
    self._matchWinner = nil
    self:_dispatch("onMatchEnd", {
        winner = nil,
        loser = playerId,
        result = "practice_ended",
        mode = self._mode,
        finalScores = self:_playerKeyedTable(self._scores),
        bestChain = self:_playerKeyedTable(self._bestChain),
    })
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
            cellsDropped = {},
        })
    end
    if outgoingCubes > 0 and not self._isSolo then
        local opponent = self:_otherPlayer(senderPlayerId)
        self:queueGarbage(opponent, outgoingCubes)
    end
    -- Solo: remainder is dropped on the floor. ChainResolved already carries
    -- garbageOut so the client can still show "→ N ICE" floating text.
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
    -- Surface the next-piece preview after every spawn (the bag just advanced).
    -- Producer's renderer binds this to the next-piece HUD; peek is non-destructive.
    self:_dispatch("onNextPieceQueue", {
        playerId = playerId,
        queue = board:peek(2),
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
    elseif input.type == "hardDrop" then
        local dist = self:_dropDistance(playerId, piece)
        piece.pivotRow -= dist
        -- Surface the slammed-down position so the renderer can paint the
        -- piece at its final cell before the lock event replaces it with cells.
        self:_dispatch("onPieceMoved", { playerId = playerId, piece = piece })
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

function GameState:_boardSnapshot(playerId)
    -- Deep copy of cells[row][col] = colorName | false. Producer's renderer
    -- consumes this on PieceLocked and ChainCompleted to paint declaratively.
    --
    -- Empty cells are serialized as `false` (not `nil`) so each row is a
    -- DENSE array with sequential integer keys. This sidesteps Roblox's
    -- RemoteEvent serializer which uses `#row` (stops at first nil) to
    -- decide "array vs dict" — a sparse row like {[1]="Brown", [3]="Pink"}
    -- gets truncated to ["Brown"] over the wire, silently dropping [3].
    -- Client treats `false` as "empty" (same as nil).
    local board = self._boards[playerId]
    if not board then return nil end
    local snap = {}
    for r = 1, board.height do
        snap[r] = {}
        for c = 1, board.width do
            snap[r][c] = board.cells[r][c] or false
        end
    end
    return snap
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

    self._activePieces[playerId] = nil

    -- Settle in case of partial overhangs (b above ceiling, a inside).
    -- Dispatch AFTER settle so renderer's snapshot reflects final cell positions.
    board:gravitySettle()

    self:_dispatch("onPieceLocked", {
        playerId = playerId,
        a = piece.a, b = piece.b,
        aRow = aPos[1], aCol = aPos[2],
        bRow = bPos[1], bCol = bPos[2],
        cells = self:_boardSnapshot(playerId),
    })

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

        -- Convert chain length to outgoing garbage. Compute BEFORE dispatch so
        -- the renderer's "→ N ICE!" floating text can read it off ChainCompleted
        -- directly instead of duplicating the table lookup.
        local outgoing = Constants.GARBAGE_TABLE[result.chainLength] or Constants.GARBAGE_CAP
        if result.chainLength >= 6 then outgoing = Constants.GARBAGE_CAP end

        self:_dispatch("onChainResolved", {
            playerId = playerId,
            chainLength = result.chainLength,
            totalPopped = result.totalPopped,
            scoreAdded = scoreAdded,
            garbageOut = outgoing,
            steps = result.steps,
            cells = self:_boardSnapshot(playerId),
        })

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
        if self._isSolo then
            self:_endPracticeOnTopout(playerId)
        else
            local winner = self:_otherPlayer(playerId)
            self:_endRound(winner, playerId, "overflow")
        end
        return
    end

    -- If the round just ended for any other reason, stop
    if self._phase ~= "playing" then return end

    -- Spawn the next piece
    self:_spawnPiece(playerId)

    -- If the freshly-spawned piece overlaps existing cells, that's also overflow
    local fresh = self._activePieces[playerId]
    if fresh and not self:_pieceFits(playerId, fresh) then
        if self._isSolo then
            self:_endPracticeOnTopout(playerId)
        else
            local winner = self:_otherPlayer(playerId)
            self:_endRound(winner, playerId, "overflow")
        end
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
    local cellsDropped = {}
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
                table.insert(cellsDropped, { row = r, col = col })
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
        cellsDropped = cellsDropped,
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
