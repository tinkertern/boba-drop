-- tests/ChainResolver.spec.luau
local t = require("./_test_helpers")
local Board = require("../src/ReplicatedStorage/Shared/Logic/Board")
local ChainResolver = require("../src/ReplicatedStorage/Shared/Logic/ChainResolver")

local function newBoard() return Board.new({ seed = 1 }) end

t.describe("ChainResolver", function()
    t.it("returns zero on an empty board", function()
        local b = newBoard()
        local result = ChainResolver.resolve(b)
        t.assertEq(result.chainLength, 0)
        t.assertEq(result.totalPopped, 0)
        t.assertEq(#result.steps, 0)
    end)

    t.it("returns zero when no 4-group exists", function()
        local b = newBoard()
        for r = 1, 3 do b:placeAt(r, 1, "Brown") end -- only 3 in column
        local result = ChainResolver.resolve(b)
        t.assertEq(result.chainLength, 0)
    end)

    t.it("pops a single 4-group and returns chainLength 1", function()
        local b = newBoard()
        for r = 1, 4 do b:placeAt(r, 1, "Pink") end
        local result = ChainResolver.resolve(b)
        t.assertEq(result.chainLength, 1)
        t.assertEq(result.totalPopped, 4)
        for r = 1, 4 do t.assertEq(b:cellAt(r, 1), nil) end
    end)

    t.it("triggers a 2-chain when gravity drops into a new match", function()
        local b = newBoard()
        -- Setup:
        --   row 4: . . . . . .
        --   row 3: Pink at col 1 (will fall)
        --   row 2: Brown Brown Brown Brown _ _    (will pop)
        --   row 1: Pink Pink Pink _ _ _
        for c = 1, 4 do b:placeAt(2, c, "Brown") end
        for c = 1, 3 do b:placeAt(1, c, "Pink") end
        b:placeAt(3, 1, "Pink") -- floating pink atop col 1
        local result = ChainResolver.resolve(b)
        t.assertEq(result.chainLength, 2, "should be a 2-chain")
        -- After: Pink popped from rows 1+3 (now 4 in a column after gravity); Brown popped first
        t.assertEq(result.totalPopped, 8) -- 4 Brown + 4 Pink
    end)

    t.it("counts distinct colors in a single chain step", function()
        local b = newBoard()
        -- Two 4-groups of different colors pop in the same step
        for c = 1, 4 do b:placeAt(1, c, "Pink") end
        for c = 1, 4 do b:placeAt(3, c, "Green") end -- floating row 3
        local result = ChainResolver.resolve(b)
        t.assertEq(result.chainLength, 1, "single simultaneous step")
        t.assertEq(result.steps[1].colors, 2, "two distinct colors in step 1")
    end)

    t.it("resolves a 3-chain (cascade through 3 levels)", function()
        local b = newBoard()
        -- Cascade design: only Brown is a valid 4-group at start. Pink + Green become
        -- 4-groups only after gravity drops the floaters in col 2 down into place.
        --
        -- Initial layout (col 1 stacked, col 2 has a floater per color):
        --   col 1: B B B P P P G G G   (rows 1-9, top is row 9)
        --   col 2: B P G               (rows 1-3, top is row 3)
        --
        -- Step 1: (1,1)(2,1)(3,1)(1,2) Browns form an L-shaped 4-group → pop.
        -- Gravity: col 1 collapses Pinks to rows 1-3, Greens to rows 4-6; col 2
        -- Pink falls to row 1, Green to row 2.
        -- Step 2: Pinks at (1,1)(2,1)(3,1)(1,2) form a new 4-group → pop.
        -- Gravity: col 1 Greens collapse to rows 1-3; col 2 Green falls to row 1.
        -- Step 3: Greens at (1,1)(2,1)(3,1)(1,2) form a new 4-group → pop.
        for r = 1, 3 do b:placeAt(r, 1, "Brown") end
        for r = 4, 6 do b:placeAt(r, 1, "Pink") end
        for r = 7, 9 do b:placeAt(r, 1, "Green") end
        b:placeAt(1, 2, "Brown")
        b:placeAt(2, 2, "Pink")
        b:placeAt(3, 2, "Green")
        local result = ChainResolver.resolve(b)
        t.assertEq(result.chainLength, 3)
        t.assertEq(result.totalPopped, 12)
    end)

    t.it("garbage adjacent to a popped group is cleared (neighbour-clear rule)", function()
        local b = newBoard()
        for c = 1, 4 do b:placeAt(1, c, "Pink") end
        b:placeAt(2, 1, "Garbage") -- directly above a popped Pink
        b:placeAt(2, 2, "Garbage") -- directly above a popped Pink
        b:placeAt(1, 5, "Garbage") -- directly right of the rightmost popped Pink
        local result = ChainResolver.resolve(b)
        t.assertEq(result.chainLength, 1)
        t.assertEq(result.totalPopped, 4, "popped counts colors only, not garbage")
        t.assertEq(#result.steps[1].garbageCleared, 3, "all three orthogonally-adjacent garbage cleared")
        t.assertEq(b:cellAt(1, 1), nil, "garbage at (2,1) cleared then would fall; board now empty there")
    end)

    t.it("garbage that is only diagonally adjacent to a popped group is NOT cleared", function()
        local b = newBoard()
        for c = 1, 4 do b:placeAt(1, c, "Pink") end
        -- Garbage at (2, 5) is diagonal to the popped Pink at (1, 4). Orthogonal only.
        b:placeAt(2, 5, "Garbage")
        local result = ChainResolver.resolve(b)
        t.assertEq(result.chainLength, 1)
        t.assertEq(#result.steps[1].garbageCleared, 0, "diagonal adjacency does not count")
        t.assertEq(b:cellAt(1, 5), "Garbage", "the lone garbage falls to row 1 col 5 and survives")
    end)
end)

t.summary()
