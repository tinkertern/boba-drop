-- tests/MatchDetector.spec.luau
local t = require("./_test_helpers")
local Board = require("../src/ReplicatedStorage/Shared/Logic/Board")
local MatchDetector = require("../src/ReplicatedStorage/Shared/Logic/MatchDetector")

local function emptyBoard()
    return Board.new({ seed = 1 })
end

t.describe("MatchDetector", function()
    t.it("finds no matches on an empty board", function()
        local b = emptyBoard()
        local groups = MatchDetector.findGroups(b)
        t.assertEq(#groups, 0)
    end)

    t.it("finds no matches for a 3-blob cluster (below threshold)", function()
        local b = emptyBoard()
        b:placeAt(1, 1, "Brown")
        b:placeAt(2, 1, "Brown")
        b:placeAt(1, 2, "Brown")
        local groups = MatchDetector.findGroups(b)
        t.assertEq(#groups, 0)
    end)

    t.it("finds a single 4-blob group in an L shape", function()
        local b = emptyBoard()
        b:placeAt(1, 1, "Pink")
        b:placeAt(2, 1, "Pink")
        b:placeAt(3, 1, "Pink")
        b:placeAt(1, 2, "Pink")
        local groups = MatchDetector.findGroups(b)
        t.assertEq(#groups, 1)
        t.assertEq(#groups[1].cells, 4)
        t.assertEq(groups[1].color, "Pink")
    end)

    t.it("finds two separate groups of the same color", function()
        local b = emptyBoard()
        -- Group 1: 4 Green in column 1
        for r = 1, 4 do b:placeAt(r, 1, "Green") end
        -- Group 2: 4 Green in column 6 (not adjacent to column 1)
        for r = 1, 4 do b:placeAt(r, 6, "Green") end
        local groups = MatchDetector.findGroups(b)
        t.assertEq(#groups, 2)
        for _, g in groups do t.assertEq(g.color, "Green") end
    end)

    t.it("does not connect diagonally", function()
        local b = emptyBoard()
        -- 4 Brown in a diagonal: (1,1), (2,2), (3,3), (4,4) — should NOT match
        b:placeAt(1, 1, "Brown")
        b:placeAt(2, 2, "Brown")
        b:placeAt(3, 3, "Brown")
        b:placeAt(4, 4, "Brown")
        local groups = MatchDetector.findGroups(b)
        t.assertEq(#groups, 0)
    end)

    t.it("ignores garbage cubes (they never form groups)", function()
        local b = emptyBoard()
        for r = 1, 5 do b:placeAt(r, 1, "Garbage") end
        local groups = MatchDetector.findGroups(b)
        t.assertEq(#groups, 0)
    end)

    t.it("returns multiple groups of different colors in one scan", function()
        local b = emptyBoard()
        for r = 1, 4 do b:placeAt(r, 1, "White") end
        for c = 1, 4 do b:placeAt(8, c, "Pink") end
        local groups = MatchDetector.findGroups(b)
        t.assertEq(#groups, 2)
        local colors = { groups[1].color, groups[2].color }
        table.sort(colors)
        t.assertEq(colors[1], "Pink")
        t.assertEq(colors[2], "White")
    end)

    t.it("finds a 5-blob group across a row-and-column corner", function()
        local b = emptyBoard()
        -- T shape: 4 across row 3, plus one above
        b:placeAt(3, 2, "Brown")
        b:placeAt(3, 3, "Brown")
        b:placeAt(3, 4, "Brown")
        b:placeAt(3, 5, "Brown")
        b:placeAt(4, 3, "Brown")
        local groups = MatchDetector.findGroups(b)
        t.assertEq(#groups, 1)
        t.assertEq(#groups[1].cells, 5)
    end)
end)

t.summary()
