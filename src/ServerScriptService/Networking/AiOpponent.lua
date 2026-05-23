-- src/ServerScriptService/Networking/AiOpponent.lua
--
-- Server-driven AI bot input generation for single-player vs AI rooms.
--
-- Two-layer design:
--   1) PURE POLICY FUNCTIONS — given a GameState + bot id, return a target
--      (col, rotation). No yields, no globals, no Roblox API. Lune-testable.
--   2) DECIDE WRAPPER — `AiOpponent.decide(gs, room, event)` orchestrates the
--      policy: reaction wait, rotate-to-target, move-to-target, hardDrop.
--      Uses task.wait + math.random so it's not directly Lune-tested, but the
--      heuristics it relies on ARE.
--
-- Difficulty tiers:
--   - easy: random column, random orientation, sometimes skip rotate (~30%),
--           400-700ms reaction. Existing behaviour preserved 1:1 from the
--           pre-refactor inline loop in Main.server.lua.
--   - medium: scored placement search (prefer low/flat stacks, avoid topout,
--             mild same-color adjacency bonus), 300-500ms reaction, ~10% of
--             plays fall through to easy for human-feeling noise.
--
-- Hard / pro tiers are not implemented; they fall through to `_mediumPolicy`
-- so RoomManager's validDifficulties guard ({easy/normal/hard/pro = true})
-- doesn't reach a nil policy when those tiers ship in later patches.

-- Board geometry inlined here. The Logic modules use string requires for sibling
-- modules within ReplicatedStorage/Shared/Logic/, but going *across* services
-- (ServerScriptService → ReplicatedStorage) via "../../" isn't a tested path in
-- the Roblox runtime. These values are stable (no live tuning) and changing them
-- is already a multi-file effort, so the tiny duplication is the safer ship.
local Constants = {
    BOARD_WIDTH = 6,
    BOARD_VISIBLE_HEIGHT = 12,
    BOARD_TOTAL_HEIGHT = 14, -- BOARD_VISIBLE_HEIGHT + BOARD_DANGER_ROWS (2)
}

local AiOpponent = {}

-- Tunables --------------------------------------------------------------------

AiOpponent.EASY_REACTION_MIN = 0.4
AiOpponent.EASY_REACTION_MAX = 0.7
AiOpponent.MEDIUM_REACTION_MIN = 0.3
AiOpponent.MEDIUM_REACTION_MAX = 0.5
AiOpponent.INPUT_WAIT_MIN = 0.08
AiOpponent.INPUT_WAIT_MAX = 0.15

-- Probability that medium ignores its policy and plays a random placement.
-- Keeps the bot from feeling robotic; gives the human room to win.
AiOpponent.MEDIUM_NOISE_RATE = 0.10

-- Score weights for medium policy. Lower = better. Exported as a table so
-- tests can reason about / override them.
AiOpponent.MEDIUM_WEIGHTS = {
    heightSum = 0.6,
    heightMax = 1.5,
    dangerProximity = 4.0, -- per cell within 2 rows of topout
    heightVariance = 0.3,
    adjacencyBonus = 0.5, -- subtracted, so larger = stronger preference
}

-- Pure helpers ----------------------------------------------------------------

-- 0: b above a, 1: b right, 2: b below, 3: b left
-- Mirrors GameState's `partnerOffset` (kept local to avoid coupling AiOpponent
-- to GameState internals; if the convention ever changes, both will need to
-- update — same as any client renderer that reads orientation).
local function partnerOffset(orientation)
    if orientation == 0 then return 1, 0
    elseif orientation == 1 then return 0, 1
    elseif orientation == 2 then return -1, 0
    else return 0, -1
    end
end

-- Read column heights from the bot's board. Height = row number of the topmost
-- filled cell in the column (0 if empty). After gravitySettle, stacks are
-- contiguous from row 1, so this is also the count of filled cells.
local function columnHeights(board)
    local heights = {}
    for c = 1, board.width do
        local h = 0
        for r = 1, board.height do
            if board.cells[r] and board.cells[r][c] ~= nil then
                h = r
            end
        end
        heights[c] = h
    end
    return heights
end
AiOpponent._columnHeights = columnHeights -- exposed for tests

-- Predict where a piece lands given column heights + a target (col, orientation).
-- Returns { aRow, aCol, bRow, bCol } or nil if the placement is illegal (off-board
-- horizontally). Cells may land in the danger rows or above the board ceiling;
-- callers score that as topout-imminent, they don't reject outright here.
local function predictLanding(heights, pivotCol, orientation, boardWidth)
    local dr, dc = partnerOffset(orientation)
    local aCol = pivotCol
    local bCol = pivotCol + dc
    -- Horizontal legality — both cells must be on-board
    if aCol < 1 or aCol > boardWidth then return nil end
    if bCol < 1 or bCol > boardWidth then return nil end

    -- Vertical: pivotRow is constrained by the column heights of each cell's column.
    -- For each cell, the lowest row it can occupy is heights[col] + 1.
    -- The pivot row must satisfy that BOTH cells land at-or-above their column's
    -- stack top. Translate each cell's required pivotRow and take the max.
    local aMinPivot = heights[aCol] + 1 -- a is at pivotRow
    local bMinPivot = heights[bCol] + 1 - dr -- b is at pivotRow + dr; we need pivotRow + dr >= heights[bCol] + 1
    local pivotRow = math.max(aMinPivot, bMinPivot)

    return {
        aRow = pivotRow,
        aCol = aCol,
        bRow = pivotRow + dr,
        bCol = bCol,
    }
end
AiOpponent._predictLanding = predictLanding -- exposed for tests

-- Score a predicted landing. Lower is better. +inf = topout (illegal placement).
-- `aColor`/`bColor` and `board` are optional; passing them enables the same-color
-- adjacency bonus. `weights` lets tests override the tuning constants.
local function scorePlacement(heights, landing, board, aColor, bColor, weights)
    weights = weights or AiOpponent.MEDIUM_WEIGHTS
    local visibleHeight = Constants.BOARD_VISIBLE_HEIGHT
    local totalHeight = Constants.BOARD_TOTAL_HEIGHT

    -- Topout: either cell lands above the visible playfield. Rendered as a hard
    -- reject so the bot only picks danger-row placements when literally every
    -- alternative also tops out.
    if landing.aRow > visibleHeight or landing.bRow > visibleHeight then
        return math.huge
    end
    -- Off-the-top entirely: defensive — shouldn't happen given the above check,
    -- but guards against weird BOARD_TOTAL_HEIGHT configurations.
    if landing.aRow > totalHeight or landing.bRow > totalHeight then
        return math.huge
    end

    -- Build a hypothetical heights array AFTER the placement. Two cells in the
    -- same column → that column's new height = max(landing rows in that col).
    local newHeights = table.clone(heights)
    if landing.aCol == landing.bCol then
        newHeights[landing.aCol] = math.max(landing.aRow, landing.bRow)
    else
        newHeights[landing.aCol] = math.max(newHeights[landing.aCol], landing.aRow)
        newHeights[landing.bCol] = math.max(newHeights[landing.bCol], landing.bRow)
    end

    -- Aggregate metrics
    local sum = 0
    local maxH = 0
    local dangerCells = 0
    for _, h in newHeights do
        sum += h
        if h > maxH then maxH = h end
        if h >= visibleHeight - 2 then
            -- Within 2 rows of topout (rows 11+, given visibleHeight=12).
            -- Counted per column at risk, not per cell, so the penalty scales
            -- with how many lanes are danger-zone tall.
            dangerCells += 1
        end
    end
    local mean = sum / #newHeights
    local variance = 0
    for _, h in newHeights do
        variance += (h - mean) ^ 2
    end
    variance /= #newHeights

    -- Same-color adjacency bonus. Look at the 4 orthogonal neighbours of each
    -- placed cell on the CURRENT board (pre-placement). A matching neighbour
    -- means dropping here puts same-color cells next to each other, which is
    -- a tiny step toward forming a match-4 group.
    local adjacencyMatches = 0
    if board and aColor and bColor then
        local function countMatchingNeighbours(row, col, color)
            local n = 0
            local checks = { { row + 1, col }, { row - 1, col }, { row, col + 1 }, { row, col - 1 } }
            for _, rc in checks do
                local nr, nc = rc[1], rc[2]
                if nr >= 1 and nc >= 1 and nc <= board.width and nr <= board.height then
                    local existing = board.cells[nr] and board.cells[nr][nc]
                    if existing == color then n += 1 end
                end
            end
            return n
        end
        adjacencyMatches += countMatchingNeighbours(landing.aRow, landing.aCol, aColor)
        adjacencyMatches += countMatchingNeighbours(landing.bRow, landing.bCol, bColor)
        -- The two placed cells may also be adjacent to each other and the same
        -- color (e.g. AA pair landed flat). Count that too — it's a real chain
        -- ingredient.
        if aColor == bColor then
            local dr = math.abs(landing.aRow - landing.bRow)
            local dc = math.abs(landing.aCol - landing.bCol)
            if dr + dc == 1 then
                adjacencyMatches += 1
            end
        end
    end

    return weights.heightSum * sum
        + weights.heightMax * maxH
        + weights.dangerProximity * dangerCells
        + weights.heightVariance * variance
        - weights.adjacencyBonus * adjacencyMatches
end
AiOpponent._scorePlacement = scorePlacement -- exposed for tests

-- Policies --------------------------------------------------------------------

-- Easy: uniform random column + random orientation, occasionally skip rotation.
-- `rng` is optional and defaults to math.random; pass a function for determinism
-- in tests.
function AiOpponent._easyPolicy(gs, playerId, rng)
    rng = rng or math.random
    local boardWidth = Constants.BOARD_WIDTH
    local targetCol = math.floor(rng() * boardWidth) + 1
    if targetCol > boardWidth then targetCol = boardWidth end -- guard rng() == 1.0
    local targetRotation
    if rng() < 0.3 then
        targetRotation = 0
    else
        targetRotation = math.floor(rng() * 4)
        if targetRotation > 3 then targetRotation = 3 end
    end
    return { col = targetCol, rotation = targetRotation }
end

-- Medium: enumerate (col, orientation) candidates, score each predicted landing,
-- pick the lowest-scoring. ~MEDIUM_NOISE_RATE of the time, fall through to easy.
--
-- Returns { col, rotation }. Never returns nil — if every placement tops out,
-- picks the least-bad one (the bot will die, but won't crash the input loop).
function AiOpponent._mediumPolicy(gs, playerId, rng)
    rng = rng or math.random
    -- Noise budget: skip the smart policy entirely sometimes.
    if rng() < AiOpponent.MEDIUM_NOISE_RATE then
        return AiOpponent._easyPolicy(gs, playerId, rng)
    end

    local board = gs:boardFor(playerId)
    local piece = gs:activePiece(playerId)
    if not board or not piece then
        return AiOpponent._easyPolicy(gs, playerId, rng)
    end

    local heights = columnHeights(board)
    local boardWidth = Constants.BOARD_WIDTH

    local bestScore = math.huge
    local bestCandidates = {} -- list of { col, rotation } tied at bestScore

    for col = 1, boardWidth do
        for rotation = 0, 3 do
            local landing = predictLanding(heights, col, rotation, boardWidth)
            if landing then
                local score = scorePlacement(heights, landing, board, piece.a, piece.b, AiOpponent.MEDIUM_WEIGHTS)
                if score < bestScore then
                    bestScore = score
                    bestCandidates = { { col = col, rotation = rotation } }
                elseif score == bestScore then
                    table.insert(bestCandidates, { col = col, rotation = rotation })
                end
            end
        end
    end

    if #bestCandidates == 0 then
        -- Every candidate was off-board. Should be unreachable for a 6-wide
        -- board with any orientation, but fall back to easy to be safe.
        return AiOpponent._easyPolicy(gs, playerId, rng)
    end

    -- Random tiebreak among equal-scoring candidates so the bot doesn't always
    -- pick the leftmost column when the board is empty (which would feel weird).
    local pickIndex = math.floor(rng() * #bestCandidates) + 1
    if pickIndex > #bestCandidates then pickIndex = #bestCandidates end
    return bestCandidates[pickIndex]
end

-- Resolve the policy function for a difficulty string. Unknown difficulties
-- fall through to medium (callers should already have validated, but defend).
function AiOpponent._policyFor(difficulty)
    if difficulty == "easy" then
        return AiOpponent._easyPolicy, AiOpponent.EASY_REACTION_MIN, AiOpponent.EASY_REACTION_MAX
    else
        -- normal/medium/hard/pro all use medium policy for now. Hard + pro are
        -- left as TODO; promoting to medium beats falling through to easy.
        return AiOpponent._mediumPolicy, AiOpponent.MEDIUM_REACTION_MIN, AiOpponent.MEDIUM_REACTION_MAX
    end
end

-- Decide loop ----------------------------------------------------------------

local function randRange(a, b)
    return a + math.random() * (b - a)
end

-- Drive a single piece for the bot: reaction wait → policy → rotate → move →
-- hardDrop. Called from Main.server's onPieceSpawned subscriber, wrapped in a
-- task.spawn so subscribers aren't blocked by our task.wait calls.
--
-- Safety:
--   - Re-checks `alive()` before every applyInput. If the round ends mid-
--     sequence (real player tops out, leaves, the bot's piece autolocks from
--     gravity, etc.), the sequence silently exits on the next iteration.
--   - Re-reads gs:activePiece(botId) before every move — if gravity locked the
--     piece while we were waiting, the active-piece check trips and we exit.
function AiOpponent.decide(gs, room, event)
    local botId = event.playerId
    -- The room's difficulty is captured at decide-time, not loop-time, so a
    -- rematch-difficulty-change (not currently a thing, but defensive) doesn't
    -- mutate behaviour mid-sequence.
    local difficulty = (room.aiBot and room.aiBot.difficulty) or "easy"
    local policy, reactionMin, reactionMax = AiOpponent._policyFor(difficulty)

    -- Capture gs identity. If room.gameState gets reassigned mid-sequence
    -- (rematch), every `alive()` check fails and the stale sequence exits.
    local capturedGs = gs

    local function alive()
        if room.gameState ~= capturedGs then return false end
        if capturedGs:phase() ~= "playing" then return false end
        if not capturedGs:activePiece(botId) then return false end
        return true
    end

    task.wait(randRange(reactionMin, reactionMax))
    if not alive() then return end

    local target = policy(capturedGs, botId, math.random)
    if not target then return end -- policy bailed; nothing safe to do

    -- Rotate to target orientation. CW rotation N times == orientation N.
    for _ = 1, target.rotation do
        if not alive() then return end
        capturedGs:applyInput(botId, { type = "rotate", direction = "cw" })
        task.wait(randRange(AiOpponent.INPUT_WAIT_MIN, AiOpponent.INPUT_WAIT_MAX))
    end

    -- Move to target column. Read pivotCol each iteration so we react to
    -- walls (move input is a no-op when blocked, so we'd otherwise spin).
    -- Cap iterations at BOARD_WIDTH * 2 as a safety net.
    local maxIter = Constants.BOARD_WIDTH * 2
    for _ = 1, maxIter do
        if not alive() then return end
        local piece = capturedGs:activePiece(botId)
        if not piece then return end
        if piece.pivotCol == target.col then break end
        local direction = (piece.pivotCol < target.col) and "right" or "left"
        local before = piece.pivotCol
        capturedGs:applyInput(botId, { type = "move", direction = direction })
        task.wait(randRange(AiOpponent.INPUT_WAIT_MIN, AiOpponent.INPUT_WAIT_MAX))
        local after = capturedGs:activePiece(botId)
        if not after or after.pivotCol == before then break end
    end

    if not alive() then return end
    capturedGs:applyInput(botId, { type = "hardDrop" })
end

return AiOpponent
