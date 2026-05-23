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
--   - hard: medium scoring + 1-step chain lookahead. For each candidate
--           placement, simulate it on a cloned board, run ChainResolver, and
--           award a large bonus proportional to chainLength + totalPopped.
--           Tighter 200-300ms reaction, no noise budget. ChainResolver +
--           board-clone + placement-simulate are passed as a `deps` table
--           (dependency injection) so the policy stays pure and Lune-testable:
--           AiOpponent.lua lives in ServerScriptService and ChainResolver
--           lives in ReplicatedStorage; an earlier attempt to bridge the gap
--           with a "../../" string require was reverted as un-tested-path in
--           the Roblox runtime. `decide()` injects the real deps via Roblox
--           instance requires; tests inject Lune-friendly string-require deps.
--   - pro: hard + 2-piece lookahead + chain-setup heuristic. For each candidate
--          placement of the CURRENT piece, also peek at the next queued piece
--          and evaluate its best possible response. Score combines current
--          placement's chain bonus + next placement's chain bonus (discounted
--          by PRO_NEXT_CHAIN_DISCOUNT for uncertainty) + a setup bonus that
--          rewards leaving adjacent same-color pairs on the board (potential
--          chains 2 turns out). 150-200ms reaction, no noise budget, fully
--          deterministic tiebreaks (lowest col first, then lowest orientation)
--          so the bot feels precise and machine-like vs hard's slight variance.
--          To keep compute bounded, only the top PRO_LOOKAHEAD_TOPK current
--          placements (ranked by single-piece score) get the deep next-piece
--          lookahead. Worst-case: TOPK * 22 next-piece simulations + 22 current
--          base-score sims = ~200 chain-resolve calls per decision. decide()
--          uses a compute-then-wait pattern so the reaction window absorbs the
--          computation latency. This is "pro-flavored" — measurably tougher
--          than hard, but not research-grade tree search (deferred to v1.1).

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
AiOpponent.HARD_REACTION_MIN = 0.2
AiOpponent.HARD_REACTION_MAX = 0.3
AiOpponent.PRO_REACTION_MIN = 0.15
AiOpponent.PRO_REACTION_MAX = 0.20
AiOpponent.INPUT_WAIT_MIN = 0.08
AiOpponent.INPUT_WAIT_MAX = 0.15

-- Probability that medium ignores its policy and plays a random placement.
-- Keeps the bot from feeling robotic; gives the human room to win.
AiOpponent.MEDIUM_NOISE_RATE = 0.10
-- Hard doesn't get a noise budget — the whole point of the tier is that it
-- exploits chains reliably. Mistakes only come from short-horizon planning.
AiOpponent.HARD_NOISE_RATE = 0.0
-- Pro: zero noise, fully deterministic. Tiebreaks are positional (lowest col,
-- then lowest rotation) instead of random, which gives the bot a precise,
-- thinking-machine feel vs hard's slight human-style variance.
AiOpponent.PRO_NOISE_RATE = 0.0

-- Chain lookahead bonuses for hard tier (subtracted from score; bigger =
-- stronger preference). The per-link bonus is sized so a single chain link
-- swamps every medium-score delta on a normal board (heightSum across all
-- columns at visibleHeight=12 caps at ~72 * 0.6 = 43; 50 per link comfortably
-- dominates). The per-pop bonus is a tiebreaker among equal-chain-length
-- options so wider clears beat narrower ones.
AiOpponent.HARD_CHAIN_BONUS_PER_LINK = 50
AiOpponent.HARD_POP_BONUS_PER_CELL = 5

-- Pro lookahead bonuses (subtracted from score; bigger = stronger preference).
-- Chain bonus matches hard so chains-now still dominate. Next-piece chain bonus
-- is the same per-link rate scaled by PRO_NEXT_CHAIN_DISCOUNT (uncertainty: we
-- don't know which orientation the player would force on us in a real match).
-- Setup bonus (per adjacent same-color pair left on the board) is intentionally
-- small — it's a hint that a third matching piece *could* chain next turn, not
-- a guarantee. Should never outweigh an actual chain bonus.
AiOpponent.PRO_LOOKAHEAD_DEPTH = 1 -- pieces ahead to look (1 = current + next)
AiOpponent.PRO_LOOKAHEAD_TOPK = 8 -- only deep-search the top K current candidates
AiOpponent.PRO_CHAIN_BONUS_PER_LINK = 50
AiOpponent.PRO_POP_BONUS_PER_CELL = 5
AiOpponent.PRO_NEXT_CHAIN_DISCOUNT = 0.5 -- next-piece chain bonus weighted at half
AiOpponent.PRO_SETUP_BONUS_PER_PAIR = 8 -- per adjacent same-color pair on post-placement board

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

-- Hard: medium scoring + 1-step chain lookahead -----------------------------
--
-- Snapshot just enough of a Board to satisfy ChainResolver + MatchDetector.
-- Producers a fresh table exposing `cells`, `width`, `height`, `cellAt`,
-- `clearAt`, and `gravitySettle`. Anything else on Board (RNG state, bag,
-- placeAt) is intentionally omitted — the simulator writes cells directly
-- into the `cells` table, mirroring how _lockPiece does it on the real board.
--
-- Why not just `Board.new` with a copied cells grid? Board.new requires a
-- seed and rebuilds the bag/RNG, which is wasted work and couples the
-- simulator to Board's constructor surface. The cloned object only needs to
-- look like a Board from ChainResolver's perspective.
local function cloneBoardCells(board)
    local cloned = {
        width = board.width,
        height = board.height,
        cells = {},
    }
    for r = 1, board.height do
        cloned.cells[r] = {}
        if board.cells[r] then
            for c = 1, board.width do
                cloned.cells[r][c] = board.cells[r][c]
            end
        end
    end
    function cloned:cellAt(row, col)
        if row < 1 or row > self.height or col < 1 or col > self.width then return nil end
        return self.cells[row][col]
    end
    function cloned:clearAt(row, col)
        self.cells[row][col] = nil
    end
    function cloned:gravitySettle()
        for col = 1, self.width do
            local writeRow = 1
            for row = 1, self.height do
                local cell = self.cells[row][col]
                if cell ~= nil then
                    if row ~= writeRow then
                        self.cells[writeRow][col] = cell
                        self.cells[row][col] = nil
                    end
                    writeRow += 1
                end
            end
        end
    end
    return cloned
end
AiOpponent._cloneBoardCells = cloneBoardCells -- exposed for tests

-- Apply a piece placement to a cloned board, then settle gravity (mirrors
-- GameState:_lockPiece's lock-and-settle step). Cells that land above the
-- board's row range are silently dropped, matching GameState's `withinBoard`
-- guard. Returns the cloned board (mutated in place) for chaining.
local function simulatePlacement(clonedBoard, landing, aColor, bColor)
    if landing.aRow >= 1 and landing.aRow <= clonedBoard.height
        and landing.aCol >= 1 and landing.aCol <= clonedBoard.width then
        clonedBoard.cells[landing.aRow][landing.aCol] = aColor
    end
    if landing.bRow >= 1 and landing.bRow <= clonedBoard.height
        and landing.bCol >= 1 and landing.bCol <= clonedBoard.width then
        clonedBoard.cells[landing.bRow][landing.bCol] = bColor
    end
    clonedBoard:gravitySettle()
    return clonedBoard
end
AiOpponent._simulatePlacement = simulatePlacement -- exposed for tests

-- Count unordered pairs of orthogonally adjacent cells that share a color.
-- Each pair is counted once (we only check the up + right neighbour of every
-- cell, never down + left, so (1,1)-(1,2) and (1,2)-(1,1) don't double-count).
-- "Garbage" cells are excluded — they can't participate in matches, so a pair
-- of Garbage adjacents isn't a setup. Used by the pro tier as a heuristic for
-- "this placement leaves the board with potential 2-turns-out chains".
local function countAdjacentSameColorPairs(board)
    local pairs_count = 0
    for r = 1, board.height do
        for c = 1, board.width do
            local cell = board.cells[r] and board.cells[r][c]
            if cell ~= nil and cell ~= "Garbage" then
                -- Right neighbour
                local right = (c + 1 <= board.width) and board.cells[r][c + 1] or nil
                if right == cell then
                    pairs_count += 1
                end
                -- Up neighbour
                local up = (r + 1 <= board.height) and board.cells[r + 1] and board.cells[r + 1][c] or nil
                if up == cell then
                    pairs_count += 1
                end
            end
        end
    end
    return pairs_count
end
AiOpponent._countAdjacentSameColorPairs = countAdjacentSameColorPairs -- exposed for tests

-- Hard policy: enumerate candidates, score with medium scoring, simulate the
-- placement, and subtract a large chain bonus. Highest "goodness" wins
-- (equivalent to lowest score after the chain bonus is subtracted).
--
-- `deps` must contain { ChainResolver, cloneBoardCells, simulatePlacement }.
-- The real `decide()` injects these via Roblox instance requires; tests inject
-- via Lune string requires. The policy never touches a global ChainResolver
-- so the ServerScriptService → ReplicatedStorage boundary stays clean.
function AiOpponent._hardPolicy(gs, playerId, rng, deps)
    rng = rng or math.random
    if not deps or not deps.ChainResolver or not deps.cloneBoardCells or not deps.simulatePlacement then
        -- Defensive: if a caller forgot to wire deps (e.g. mistakenly used the
        -- hard policy without injection), fall back to medium so we don't
        -- error mid-match. decide() is the only production caller and always
        -- passes a full deps bundle.
        return AiOpponent._mediumPolicy(gs, playerId, rng)
    end

    -- Hard has no noise budget — skip the random-fallback branch medium uses.
    if AiOpponent.HARD_NOISE_RATE > 0 and rng() < AiOpponent.HARD_NOISE_RATE then
        return AiOpponent._easyPolicy(gs, playerId, rng)
    end

    local board = gs:boardFor(playerId)
    local piece = gs:activePiece(playerId)
    if not board or not piece then
        return AiOpponent._mediumPolicy(gs, playerId, rng)
    end

    local heights = columnHeights(board)
    local boardWidth = Constants.BOARD_WIDTH

    local bestScore = math.huge
    local bestCandidates = {}

    for col = 1, boardWidth do
        for rotation = 0, 3 do
            local landing = predictLanding(heights, col, rotation, boardWidth)
            if landing then
                local baseScore = scorePlacement(heights, landing, board, piece.a, piece.b, AiOpponent.MEDIUM_WEIGHTS)
                local score = baseScore
                -- Only simulate chains for non-topout placements. Topout
                -- placements stay at +inf so we never accidentally pick a
                -- "fatal but chains" suicide play.
                if score ~= math.huge then
                    local clonedBoard = deps.cloneBoardCells(board)
                    deps.simulatePlacement(clonedBoard, landing, piece.a, piece.b)
                    local result = deps.ChainResolver.resolve(clonedBoard)
                    if result.chainLength > 0 then
                        score -= AiOpponent.HARD_CHAIN_BONUS_PER_LINK * result.chainLength
                        score -= AiOpponent.HARD_POP_BONUS_PER_CELL * result.totalPopped
                    end
                end
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
        return AiOpponent._mediumPolicy(gs, playerId, rng)
    end

    -- Random tiebreak among equal-scoring candidates.
    local pickIndex = math.floor(rng() * #bestCandidates) + 1
    if pickIndex > #bestCandidates then pickIndex = #bestCandidates end
    return bestCandidates[pickIndex]
end

-- Pro: 2-piece lookahead + chain-setup heuristic ----------------------------
--
-- Algorithm:
--   Phase 1 — enumerate all (col, rotation) for the CURRENT piece. For each,
--             predict landing, score with medium scoring, and simulate the
--             placement on a cloned board. Resolve chains; record post-chain
--             board snapshot + chain bonus. Skip topout placements.
--   Phase 2 — sort phase-1 candidates by their phase-1 score (best first) and
--             keep only the top K. This is the pruning step that keeps the
--             ~22*22 = 484 worst-case simulation count bounded — only K*22 of
--             those simulations actually run.
--   Phase 3 — for each surviving current candidate, peek at the next queued
--             piece and enumerate (col, rotation) for IT on the post-chain
--             clone. Take the best (lowest score) next-piece chain bonus,
--             weighted by PRO_NEXT_CHAIN_DISCOUNT (uncertainty). Also compute
--             the setup bonus on the post-chain board (adjacent same-color
--             pair count * PRO_SETUP_BONUS_PER_PAIR).
--   Phase 4 — combined score = phase-1 score + (-) discounted-next-chain-bonus
--             + (-) setup-bonus. Pick the LOWEST score. Tiebreak is positional:
--             since we iterate col 1..6 then rotation 0..3 and use strict `<`,
--             ties resolve to lowest col first, then lowest rotation. No rng.
--
-- Perf approach: combination of pruning (top-K = 8 by phase-1 score) AND the
-- decide()-level compute-then-wait pattern (reaction window absorbs the
-- compute). Worst case is ~22 + 8*22 = ~198 chain-resolve calls per decision,
-- well within the 150-200ms reaction budget on a Roblox server.
--
-- deps: { ChainResolver, cloneBoardCells, simulatePlacement,
--         [countAdjacentSameColorPairs] }. The last is optional and falls
--         back to the module-level helper if missing (so existing callers
--         don't have to update their deps tables).
function AiOpponent._proPolicy(gs, playerId, rng, deps)
    rng = rng or math.random
    if not deps or not deps.ChainResolver or not deps.cloneBoardCells or not deps.simulatePlacement then
        -- Defensive: fall back to hard (which has its own deps guard). decide()
        -- always wires deps, so this only triggers if a caller (test or
        -- future code path) misuses the policy.
        return AiOpponent._hardPolicy(gs, playerId, rng, deps)
    end
    local countPairs = deps.countAdjacentSameColorPairs or countAdjacentSameColorPairs

    -- Pro: no noise budget. Guard kept for symmetry with hard, in case we ever
    -- want to dial it up for tuning.
    if AiOpponent.PRO_NOISE_RATE > 0 and rng() < AiOpponent.PRO_NOISE_RATE then
        return AiOpponent._easyPolicy(gs, playerId, rng)
    end

    local board = gs:boardFor(playerId)
    local piece = gs:activePiece(playerId)
    if not board or not piece then
        return AiOpponent._hardPolicy(gs, playerId, rng, deps)
    end

    local heights = columnHeights(board)
    local boardWidth = Constants.BOARD_WIDTH

    -- Phase 1: enumerate current-piece candidates, score + simulate + resolve.
    -- Stash post-chain clone alongside score so Phase 3 doesn't re-simulate.
    local phase1 = {} -- list of { col, rotation, score, postChainBoard }
    for col = 1, boardWidth do
        for rotation = 0, 3 do
            local landing = predictLanding(heights, col, rotation, boardWidth)
            if landing then
                local baseScore = scorePlacement(heights, landing, board, piece.a, piece.b, AiOpponent.MEDIUM_WEIGHTS)
                if baseScore ~= math.huge then
                    local clonedBoard = deps.cloneBoardCells(board)
                    deps.simulatePlacement(clonedBoard, landing, piece.a, piece.b)
                    local result = deps.ChainResolver.resolve(clonedBoard)
                    local score = baseScore
                    if result.chainLength > 0 then
                        score -= AiOpponent.PRO_CHAIN_BONUS_PER_LINK * result.chainLength
                        score -= AiOpponent.PRO_POP_BONUS_PER_CELL * result.totalPopped
                    end
                    -- Setup bonus: adjacent same-color pairs left on the
                    -- post-chain board. This is the "potential 2-turns-out
                    -- chain" hint. Bonus is small so it never overrides a
                    -- real chain.
                    local pairCount = countPairs(clonedBoard)
                    score -= AiOpponent.PRO_SETUP_BONUS_PER_PAIR * pairCount

                    table.insert(phase1, {
                        col = col,
                        rotation = rotation,
                        score = score,
                        postChainBoard = clonedBoard,
                    })
                end
            end
        end
    end

    if #phase1 == 0 then
        -- Every placement tops out. Fall back to hard (which itself falls
        -- back to medium) so the bot still plays the least-bad option.
        return AiOpponent._hardPolicy(gs, playerId, rng, deps)
    end

    -- Phase 2: prune to top-K by phase-1 score. Stable-sort: ties keep their
    -- original (col, rotation) order, which preserves our positional tiebreak.
    table.sort(phase1, function(a, b)
        if a.score ~= b.score then return a.score < b.score end
        if a.col ~= b.col then return a.col < b.col end
        return a.rotation < b.rotation
    end)
    local topK = AiOpponent.PRO_LOOKAHEAD_TOPK
    if #phase1 < topK then topK = #phase1 end

    -- Phase 3: peek at next piece and evaluate its best response per surviving
    -- current candidate. If no next piece is available (queue empty — shouldn't
    -- happen in normal play but defend), the discounted-next bonus is 0 and
    -- we effectively fall back to phase-1 scoring + setup bonus.
    local nextPieces = board:peek(1)
    local nextPiece = nextPieces and nextPieces[1]

    local bestCombinedScore = math.huge
    local bestPick = nil

    for i = 1, topK do
        local candidate = phase1[i]
        local nextChainBonus = 0

        if nextPiece then
            local postHeights = columnHeights(candidate.postChainBoard)
            -- Find the best (lowest) chain-only score for the next piece on
            -- the post-current board. We only care about the chain bonus
            -- delta here — base-scoring the next piece doesn't help us choose
            -- among CURRENT placements (the next piece's pile-shape concerns
            -- are 1 turn further out and dominated by our current shape).
            local bestNextChainBonus = 0
            for nc = 1, boardWidth do
                for nr = 0, 3 do
                    local nextLanding = predictLanding(postHeights, nc, nr, boardWidth)
                    if nextLanding then
                        -- Topout check on the post-chain board's geometry.
                        -- Use scorePlacement just for the topout guard; we
                        -- ignore the returned shape score.
                        local nextBase = scorePlacement(postHeights, nextLanding, candidate.postChainBoard,
                            nextPiece.a, nextPiece.b, AiOpponent.MEDIUM_WEIGHTS)
                        if nextBase ~= math.huge then
                            local nextClone = deps.cloneBoardCells(candidate.postChainBoard)
                            deps.simulatePlacement(nextClone, nextLanding, nextPiece.a, nextPiece.b)
                            local nextResult = deps.ChainResolver.resolve(nextClone)
                            if nextResult.chainLength > 0 then
                                local thisBonus =
                                    AiOpponent.PRO_CHAIN_BONUS_PER_LINK * nextResult.chainLength
                                    + AiOpponent.PRO_POP_BONUS_PER_CELL * nextResult.totalPopped
                                if thisBonus > bestNextChainBonus then
                                    bestNextChainBonus = thisBonus
                                end
                            end
                        end
                    end
                end
            end
            nextChainBonus = bestNextChainBonus * AiOpponent.PRO_NEXT_CHAIN_DISCOUNT
        end

        local combined = candidate.score - nextChainBonus
        -- Phase 4 tiebreak: strict `<` keeps the FIRST tied candidate, which
        -- (post-sort) is the lowest col then lowest rotation. Deterministic.
        if combined < bestCombinedScore then
            bestCombinedScore = combined
            bestPick = candidate
        end
    end

    if not bestPick then
        return AiOpponent._hardPolicy(gs, playerId, rng, deps)
    end
    return { col = bestPick.col, rotation = bestPick.rotation }
end

-- Resolve the policy function for a difficulty string. Unknown difficulties
-- fall through to medium (callers should already have validated, but defend).
function AiOpponent._policyFor(difficulty)
    if difficulty == "easy" then
        return AiOpponent._easyPolicy, AiOpponent.EASY_REACTION_MIN, AiOpponent.EASY_REACTION_MAX
    elseif difficulty == "hard" then
        return AiOpponent._hardPolicy, AiOpponent.HARD_REACTION_MIN, AiOpponent.HARD_REACTION_MAX
    elseif difficulty == "pro" then
        return AiOpponent._proPolicy, AiOpponent.PRO_REACTION_MIN, AiOpponent.PRO_REACTION_MAX
    else
        -- normal/medium and any unknown difficulty use medium.
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

    -- Build deps for policies that need them (hard + pro tiers). Cheap to
    -- construct; the requires are cached after the first call. Easy/medium
    -- ignore the 4th arg, so passing the deps unconditionally is safe.
    local deps = nil
    if policy == AiOpponent._hardPolicy or policy == AiOpponent._proPolicy then
        local ReplicatedStorage = game:GetService("ReplicatedStorage")
        local ChainResolver = require(ReplicatedStorage.Shared.Logic.ChainResolver)
        deps = {
            ChainResolver = ChainResolver,
            cloneBoardCells = AiOpponent._cloneBoardCells,
            simulatePlacement = AiOpponent._simulatePlacement,
            countAdjacentSameColorPairs = AiOpponent._countAdjacentSameColorPairs,
        }
    end

    -- Reaction timing strategy:
    --   - easy / medium / hard: wait first, then compute. Compute is fast
    --     (single-piece score sweep, ~22 simulations max for hard) so it
    --     doesn't blow the reaction budget.
    --   - pro: compute FIRST, then wait the remainder of the reaction window.
    --     Pro's 2-piece lookahead can take 50-200ms; running it inside the
    --     reaction window means the bot still feels like it's "thinking" for
    --     the expected 150-200ms rather than 150-200ms + compute lag. If
    --     compute exceeds the reaction max, we skip the wait entirely and
    --     warn so we can tune topK or budgets if it becomes a pattern.
    local reactionTarget = randRange(reactionMin, reactionMax)
    local target
    if policy == AiOpponent._proPolicy then
        local computeStart = os.clock()
        target = policy(capturedGs, botId, math.random, deps)
        local computeElapsed = os.clock() - computeStart
        if not alive() then return end
        local remaining = reactionTarget - computeElapsed
        if remaining > 0 then
            task.wait(remaining)
        elseif computeElapsed > AiOpponent.PRO_REACTION_MAX then
            -- Compute blew the reaction window. Not fatal — the bot just
            -- reacts faster than designed — but a signal that topK/depth
            -- needs tuning. warn() is captured by Roblox's output console.
            warn(string.format(
                "[AiOpponent] pro policy compute %.0fms exceeded reaction max %.0fms",
                computeElapsed * 1000, AiOpponent.PRO_REACTION_MAX * 1000))
        end
    else
        task.wait(reactionTarget)
        if not alive() then return end
        target = policy(capturedGs, botId, math.random, deps)
    end
    if not target then return end -- policy bailed; nothing safe to do
    if not alive() then return end

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
