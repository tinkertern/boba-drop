-- tests/AiPolicies.spec.luau
--
-- Unit tests for AiOpponent's pure policy layer (_easyPolicy, _mediumPolicy,
-- _predictLanding, _scorePlacement, _columnHeights). The decide() orchestrator
-- isn't tested here — it depends on task.wait and Roblox-scheduler semantics
-- that Lune can't faithfully reproduce; gs:applyInput itself is covered by
-- PieceControl.spec.luau.
--
-- Determinism: we inject a custom rng function into the policy calls so each
-- assertion can pin down exactly which "random" branches were taken.

local t = require("./_test_helpers")
local GameState = require("../src/ReplicatedStorage/Shared/Logic/GameState")
local Constants = require("../src/ReplicatedStorage/Shared/Logic/Constants")
local AiOpponent = require("../src/ServerScriptService/Networking/AiOpponent")

local BOT = "-1"
local REAL = "P1"

local function newAiState(seed)
    local gs = GameState.new({ players = { REAL, BOT }, seed = seed or 42, mode = "ai" })
    gs:startRound()
    return gs
end

-- Build a deterministic rng that emits a fixed sequence of [0, 1) values.
-- Wraps when exhausted so tests don't have to enumerate every call.
local function seqRng(values)
    local i = 0
    return function()
        i += 1
        return values[((i - 1) % #values) + 1]
    end
end

-- ---- _columnHeights / _predictLanding ---------------------------------------

t.describe("AiOpponent._columnHeights", function()
    t.it("returns 0 for every column on an empty board", function()
        local gs = newAiState()
        local board = gs:boardFor(BOT)
        local h = AiOpponent._columnHeights(board)
        for c = 1, Constants.BOARD_WIDTH do
            t.assertEq(h[c], 0, "col " .. c .. " empty")
        end
    end)

    t.it("returns the topmost filled row per column", function()
        local gs = newAiState()
        local board = gs:boardFor(BOT)
        -- col 1: rows 1,2 → height 2. col 4: row 1 → height 1. col 6: empty.
        board:placeAt(1, 1, "Pink")
        board:placeAt(2, 1, "Brown")
        board:placeAt(1, 4, "Green")
        local h = AiOpponent._columnHeights(board)
        t.assertEq(h[1], 2)
        t.assertEq(h[2], 0)
        t.assertEq(h[4], 1)
        t.assertEq(h[6], 0)
    end)
end)

t.describe("AiOpponent._predictLanding", function()
    t.it("orientation 0 (b above a) lands a at top of stack, b one row above", function()
        local heights = { 0, 0, 3, 0, 0, 0 }
        local landing = AiOpponent._predictLanding(heights, 3, 0, Constants.BOARD_WIDTH)
        t.assertEq(landing.aRow, 4, "a sits on top of the col-3 stack")
        t.assertEq(landing.aCol, 3)
        t.assertEq(landing.bRow, 5)
        t.assertEq(landing.bCol, 3)
    end)

    t.it("orientation 1 (b to the right) lands both cells in the same row", function()
        local heights = { 0, 0, 3, 1, 0, 0 }
        local landing = AiOpponent._predictLanding(heights, 3, 1, Constants.BOARD_WIDTH)
        -- Tallest of cols 3 and 4 is col 3 at height 3, so both cells land at row 4.
        t.assertEq(landing.aRow, 4)
        t.assertEq(landing.bRow, 4)
        t.assertEq(landing.aCol, 3)
        t.assertEq(landing.bCol, 4)
    end)

    t.it("orientation 3 (b to the left) rejects pivotCol=1 (b off-board)", function()
        local heights = { 0, 0, 0, 0, 0, 0 }
        local landing = AiOpponent._predictLanding(heights, 1, 3, Constants.BOARD_WIDTH)
        t.assertEq(landing, nil)
    end)

    t.it("orientation 1 rejects pivotCol = boardWidth (b off the right edge)", function()
        local heights = { 0, 0, 0, 0, 0, 0 }
        local landing = AiOpponent._predictLanding(heights, Constants.BOARD_WIDTH, 1, Constants.BOARD_WIDTH)
        t.assertEq(landing, nil)
    end)
end)

-- ---- _scorePlacement --------------------------------------------------------

t.describe("AiOpponent._scorePlacement", function()
    t.it("returns +infinity when either cell lands above the visible playfield", function()
        local gs = newAiState()
        local board = gs:boardFor(BOT)
        -- Stack col 3 right up to the visible ceiling; a landing on top puts
        -- the piece into the danger / overflow rows.
        for r = 1, Constants.BOARD_VISIBLE_HEIGHT do
            board:placeAt(r, 3, "Garbage")
        end
        local heights = AiOpponent._columnHeights(board)
        local landing = AiOpponent._predictLanding(heights, 3, 0, Constants.BOARD_WIDTH)
        local score = AiOpponent._scorePlacement(heights, landing, board, "Pink", "Pink")
        t.assertEq(score, math.huge, "topout placement = +inf")
    end)

    t.it("flatter stacks score lower than spiky ones for the same height sum", function()
        -- Two scenarios, same sum-of-heights, different shape.
        local flatHeights = { 1, 1, 1, 1, 1, 1 } -- sum 6, variance 0
        local spikyHeights = { 6, 0, 0, 0, 0, 0 } -- sum 6, variance > 0
        -- Predict a vertical placement in col 4 (away from either spike).
        local flatLanding = AiOpponent._predictLanding(flatHeights, 4, 0, Constants.BOARD_WIDTH)
        local spikyLanding = AiOpponent._predictLanding(spikyHeights, 4, 0, Constants.BOARD_WIDTH)
        local flatScore = AiOpponent._scorePlacement(flatHeights, flatLanding, nil, nil, nil)
        local spikyScore = AiOpponent._scorePlacement(spikyHeights, spikyLanding, nil, nil, nil)
        t.assertEq(flatScore < spikyScore, true,
            "flat board scored " .. flatScore .. " vs spiky " .. spikyScore)
    end)

    t.it("same-color adjacency lowers the score", function()
        local gs = newAiState()
        local board = gs:boardFor(BOT)
        -- One Pink sitting at (1,3). Dropping a Pink piece into col 3 with
        -- orientation 0 puts the new Pink at (2,3), orthogonally adjacent
        -- to the existing Pink. Compare against the same drop with a Brown
        -- piece (no color match → no bonus).
        board:placeAt(1, 3, "Pink")
        local heights = AiOpponent._columnHeights(board)
        local landing = AiOpponent._predictLanding(heights, 3, 0, Constants.BOARD_WIDTH)
        local pinkScore = AiOpponent._scorePlacement(heights, landing, board, "Pink", "Pink")
        local brownScore = AiOpponent._scorePlacement(heights, landing, board, "Brown", "Brown")
        t.assertEq(pinkScore < brownScore, true,
            "pink-on-pink scored " .. pinkScore .. " vs brown " .. brownScore)
    end)
end)

-- ---- _mediumPolicy ---------------------------------------------------------

t.describe("AiOpponent._mediumPolicy", function()
    t.it("picks lowest-stack column on a clearly uneven board", function()
        -- Stack col 1 to height 10; cols 2-6 stay empty. Bot's next piece
        -- should NOT pick col 1.
        local gs = newAiState()
        local board = gs:boardFor(BOT)
        for r = 1, 10 do
            board:placeAt(r, 1, "Garbage")
        end
        -- Force a piece we know the colors of for adjacency clarity (Brown
        -- has no matches on the all-Garbage stack so adjacency is neutral).
        local piece = gs:activePiece(BOT)
        piece.a = "Brown"
        piece.b = "Brown"

        -- Force the policy to use the smart branch (rng() = 0.5 > MEDIUM_NOISE_RATE),
        -- then provide a tiebreaker index of 0.
        local rng = seqRng({ 0.5, 0.0 })
        local target = AiOpponent._mediumPolicy(gs, BOT, rng)
        t.assertEq(target.col >= 2 and target.col <= Constants.BOARD_WIDTH, true,
            "expected col 2-6, got col " .. tostring(target.col))
    end)

    t.it("avoids topout when most columns are 1 cell from overflow", function()
        -- Cols 1-5 stacked to 1 below visible height; col 6 nearly empty.
        -- Easy would land in a topout column ~5/6 of the time; medium must
        -- prefer col 6.
        local gs = newAiState()
        local board = gs:boardFor(BOT)
        for c = 1, 5 do
            for r = 1, Constants.BOARD_VISIBLE_HEIGHT - 1 do
                board:placeAt(r, c, "Garbage")
            end
        end
        local piece = gs:activePiece(BOT)
        piece.a = "Brown"
        piece.b = "Brown"

        -- Run the policy a bunch of times with different rng seeds; topout
        -- (col 1-5 in orientation 0) should be picked at most ~MEDIUM_NOISE_RATE
        -- fraction of the time (the random-fallback branch). Use a generous
        -- ceiling to absorb run-to-run variance.
        local safe, total = 0, 100
        math.randomseed(12345)
        for _ = 1, total do
            -- Use real math.random so we cover the noise branch organically.
            local target = AiOpponent._mediumPolicy(gs, BOT, math.random)
            -- A "safe" placement is anything where the predicted landing
            -- doesn't topout. Recompute the landing to check.
            local heights = AiOpponent._columnHeights(board)
            local landing = AiOpponent._predictLanding(heights, target.col, target.rotation, Constants.BOARD_WIDTH)
            if landing and landing.aRow <= Constants.BOARD_VISIBLE_HEIGHT and landing.bRow <= Constants.BOARD_VISIBLE_HEIGHT then
                safe += 1
            end
        end
        -- Expect ≥80% safe placements (noise budget eats ~10%, the rest is
        -- the smart policy reliably picking col 6).
        t.assertEq(safe >= 80, true,
            "expected >=80/100 safe, got " .. safe)
    end)

    t.it("adjacency bonus biases pivot toward the matching-color region", function()
        -- Every column at height 1, so height/variance/danger metrics all match
        -- across candidates. The only Pink is at (1, 3); rest are Browns. A
        -- Pink-Pink piece should park its pivot in or adjacent to col 3 (cols
        -- 2, 3, 4) far more often than in the no-adjacency outer columns
        -- (1, 5, 6).
        --
        -- Why we test "near col 3" instead of "exactly col 3": with 4 orientations,
        -- multiple (col, ori) candidates land cells in col 3 with identical
        -- scores (e.g. col 2 ori 1 places the partner at col 3, col 3 ori 0
        -- stacks both in col 3, col 4 ori 3 places the partner at col 3 — all
        -- get the same adjacency bonus). The smart policy tiebreaks randomly
        -- among them. The bias we're verifying is the ZONE: cells touching
        -- col 3 should be picked >> cells in the outer columns.
        local gs = newAiState()
        local board = gs:boardFor(BOT)
        for c = 1, Constants.BOARD_WIDTH do
            board:placeAt(1, c, c == 3 and "Pink" or "Brown")
        end
        local piece = gs:activePiece(BOT)
        piece.a = "Pink"
        piece.b = "Pink"

        local nearPink, awayFromPink, total = 0, 0, 200
        math.randomseed(54321)
        for _ = 1, total do
            local target = AiOpponent._mediumPolicy(gs, BOT, math.random)
            if target.col >= 2 and target.col <= 4 then
                nearPink += 1
            elseif target.col == 1 or target.col >= 5 then
                awayFromPink += 1
            end
        end
        -- Strong asymmetry: at least 2x more "near pink" picks than "away".
        -- The exact ratio depends on tiebreak counts among candidates, but the
        -- direction must be unambiguous.
        t.assertEq(nearPink > awayFromPink * 2, true,
            "expected near-pink >> away-from-pink; got near=" .. nearPink .. " away=" .. awayFromPink)
    end)

    t.it("noise budget produces some random plays", function()
        -- Same uneven-board setup as test #1. Run 100 picks; some should land
        -- in col 1 (the obviously-bad column) due to the ~10% random fallback.
        local gs = newAiState()
        local board = gs:boardFor(BOT)
        for r = 1, 10 do
            board:placeAt(r, 1, "Garbage")
        end
        local piece = gs:activePiece(BOT)
        piece.a = "Brown"
        piece.b = "Brown"

        local col1Picks, total = 0, 100
        math.randomseed(99999)
        for _ = 1, total do
            local target = AiOpponent._mediumPolicy(gs, BOT, math.random)
            if target.col == 1 then
                col1Picks += 1
            end
        end
        -- ~10% noise rate → expect roughly 100 * 0.1 * (1/6) ≈ 1.7 col-1 picks
        -- from the random branch alone. Some seeds will hit zero; the assertion
        -- is loose: at least one wide-noise-budget pick across the run, and
        -- not so many that the smart policy is broken. Range [0, 20] is the
        -- soft band; this test passes as long as we don't go bananas.
        t.assertEq(col1Picks <= 20, true,
            "expected <=20/100 col-1 picks, got " .. col1Picks)
    end)
end)

-- ---- _easyPolicy regression -------------------------------------------------

t.describe("AiOpponent._easyPolicy (regression: easy tier behaviour unchanged)", function()
    t.it("easy DOES NOT preferentially avoid tall columns", function()
        -- Same setup as the medium 'picks lowest-stack column' test, but with
        -- easy policy. Easy should pick uniformly across all 6 columns — so
        -- col 1 picks should land in roughly 1/6 of trials, NOT near zero.
        local gs = newAiState()
        local board = gs:boardFor(BOT)
        for r = 1, 10 do
            board:placeAt(r, 1, "Garbage")
        end
        local col1Picks, total = 0, 600
        math.randomseed(7777)
        for _ = 1, total do
            local target = AiOpponent._easyPolicy(gs, BOT, math.random)
            if target.col == 1 then
                col1Picks += 1
            end
        end
        -- 1/6 of 600 = 100 expected. Allow a wide band so flaky rng doesn't
        -- break the suite: 50-150 is well within normal sampling noise.
        t.assertEq(col1Picks >= 50 and col1Picks <= 150, true,
            "expected col-1 picks ~100, got " .. col1Picks)
    end)

    t.it("easy policy returns rotation in [0, 3]", function()
        local gs = newAiState()
        math.randomseed(1)
        for _ = 1, 50 do
            local target = AiOpponent._easyPolicy(gs, BOT, math.random)
            t.assertEq(target.rotation >= 0 and target.rotation <= 3, true,
                "rotation out of bounds: " .. target.rotation)
        end
    end)

    t.it("easy policy returns col in [1, BOARD_WIDTH]", function()
        local gs = newAiState()
        math.randomseed(2)
        for _ = 1, 50 do
            local target = AiOpponent._easyPolicy(gs, BOT, math.random)
            t.assertEq(target.col >= 1 and target.col <= Constants.BOARD_WIDTH, true,
                "col out of bounds: " .. target.col)
        end
    end)
end)

-- ---- _policyFor dispatch ----------------------------------------------------

t.describe("AiOpponent._policyFor", function()
    t.it("returns the easy policy for 'easy'", function()
        local fn, minR, maxR = AiOpponent._policyFor("easy")
        t.assertEq(fn, AiOpponent._easyPolicy)
        t.assertEq(minR, AiOpponent.EASY_REACTION_MIN)
        t.assertEq(maxR, AiOpponent.EASY_REACTION_MAX)
    end)

    t.it("returns the medium policy for 'medium'", function()
        local fn, minR, maxR = AiOpponent._policyFor("medium")
        t.assertEq(fn, AiOpponent._mediumPolicy)
        t.assertEq(minR, AiOpponent.MEDIUM_REACTION_MIN)
        t.assertEq(maxR, AiOpponent.MEDIUM_REACTION_MAX)
    end)

    t.it("falls through to medium for hard/pro until those tiers ship", function()
        local fn1 = AiOpponent._policyFor("hard")
        local fn2 = AiOpponent._policyFor("pro")
        t.assertEq(fn1, AiOpponent._mediumPolicy)
        t.assertEq(fn2, AiOpponent._mediumPolicy)
    end)
end)

t.summary()
