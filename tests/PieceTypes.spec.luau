-- tests/PieceTypes.spec.luau
local t = require("./_test_helpers")
local PieceTypes = require("../src/ReplicatedStorage/Shared/PieceTypes")

t.describe("PieceTypes", function()
    t.it("exposes 4 colors in canonical order", function()
        t.assertEq(#PieceTypes.COLORS, 4)
        t.assertEq(PieceTypes.COLORS[1], "Brown")
        t.assertEq(PieceTypes.COLORS[2], "Pink")
        t.assertEq(PieceTypes.COLORS[3], "Green")
        t.assertEq(PieceTypes.COLORS[4], "White")
    end)

    t.it("assigns dot counts 1..4 to colors", function()
        t.assertEq(PieceTypes.dotCount("Brown"), 1)
        t.assertEq(PieceTypes.dotCount("Pink"), 2)
        t.assertEq(PieceTypes.dotCount("Green"), 3)
        t.assertEq(PieceTypes.dotCount("White"), 4)
    end)

    t.it("assigns distinct shape fallbacks per color", function()
        local shapes = {}
        for _, color in PieceTypes.COLORS do
            local s = PieceTypes.shape(color)
            assert(s, "shape missing for " .. color)
            assert(not shapes[s], "duplicate shape " .. s)
            shapes[s] = true
        end
    end)

    t.it("recognizes garbage as a special non-color", function()
        t.assertEq(PieceTypes.isGarbage("Garbage"), true)
        t.assertEq(PieceTypes.isGarbage("Brown"), false)
    end)
end)

t.summary()
