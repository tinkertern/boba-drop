-- tests/Board.spec.luau
local t = require("./_test_helpers")
local Board = require("../src/ReplicatedStorage/Shared/Logic/Board")
local Constants = require("../src/ReplicatedStorage/Shared/Logic/Constants")

local function newBoardWithSeed(seed)
    -- Board.new takes a context object; pass an injected RNG seed.
    return Board.new({ seed = seed })
end

t.describe("Board", function()
    t.it("starts empty", function()
        local b = newBoardWithSeed(1)
        for r = 1, Constants.BOARD_TOTAL_HEIGHT do
            for c = 1, Constants.BOARD_WIDTH do
                t.assertEq(b:cellAt(r, c), nil)
            end
        end
    end)

    t.it("dimensions are 6 wide × 14 tall (12 visible + 2 danger)", function()
        local b = newBoardWithSeed(1)
        t.assertEq(b.width, 6)
        t.assertEq(b.height, 14)
    end)

    t.it("peek(2) returns the next 2 pieces", function()
        local b = newBoardWithSeed(42)
        local upcoming = b:peek(2)
        t.assertEq(#upcoming, 2)
        for _, piece in upcoming do
            assert(piece.a and piece.b, "piece must have top (a) and bottom (b) colors")
        end
    end)

    t.it("same seed produces same piece sequence (determinism)", function()
        local b1, b2 = newBoardWithSeed(42), newBoardWithSeed(42)
        local p1, p2 = b1:peek(5), b2:peek(5)
        for i = 1, 5 do
            t.assertEq(p1[i].a, p2[i].a)
            t.assertEq(p1[i].b, p2[i].b)
        end
    end)

    t.it("different seeds produce different sequences", function()
        local b1, b2 = newBoardWithSeed(1), newBoardWithSeed(2)
        local p1, p2 = b1:peek(10), b2:peek(10)
        local anyDiff = false
        for i = 1, 10 do
            if p1[i].a ~= p2[i].a or p1[i].b ~= p2[i].b then
                anyDiff = true
                break
            end
        end
        assert(anyDiff, "10 piece prefixes should not be identical across seeds")
    end)

    t.it("bag refills after 16 pairs (all combos drawn)", function()
        local b = newBoardWithSeed(7)
        local first = b:peek(16)
        b:advance(16) -- consume 16 pairs
        local second = b:peek(16) -- next 16 from new bag
        -- Both bags contain the same 16 combinations (possibly different order)
        local function bagSet(pairs)
            local s = {}
            for _, p in pairs do s[p.a .. "/" .. p.b] = true end
            return s
        end
        local set1 = bagSet(first)
        local set2 = bagSet(second)
        for k in set1 do t.assertEq(set2[k], true, "missing pair " .. k .. " in refill") end
        for k in set2 do t.assertEq(set1[k], true, "missing pair " .. k .. " in original") end
    end)

    t.it("placeAt sets a cell", function()
        local b = newBoardWithSeed(1)
        b:placeAt(1, 1, "Brown")
        t.assertEq(b:cellAt(1, 1), "Brown")
    end)

    t.it("gravitySettle drops a floating cell to the floor", function()
        local b = newBoardWithSeed(1)
        b:placeAt(5, 3, "Pink") -- floating at row 5, col 3
        b:gravitySettle()
        t.assertEq(b:cellAt(5, 3), nil, "old position should be empty")
        t.assertEq(b:cellAt(1, 3), "Pink", "should be at row 1 (bottom)")
    end)

    t.it("gravitySettle preserves stacking order in a column", function()
        local b = newBoardWithSeed(1)
        b:placeAt(8, 2, "Brown")
        b:placeAt(5, 2, "Pink")
        b:placeAt(3, 2, "Green")
        b:gravitySettle()
        t.assertEq(b:cellAt(1, 2), "Green") -- lowest of the three placed → bottom
        t.assertEq(b:cellAt(2, 2), "Pink")
        t.assertEq(b:cellAt(3, 2), "Brown")
    end)
end)

t.summary()
