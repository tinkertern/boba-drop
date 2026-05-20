-- tests/Scoring.spec.luau
local t = require("./_test_helpers")
local Scoring = require("../src/ReplicatedStorage/Shared/Logic/Scoring")

t.describe("Scoring", function()
    t.it("4 popped, 1-chain, 1-color = 4 × 1 × 1 = 4", function()
        t.assertEq(Scoring.compute({ popped = 4, chainStep = 1, colors = 1 }), 4)
    end)

    t.it("4 popped, 2-chain, 1-color = 4 × 3 × 1 = 12", function()
        t.assertEq(Scoring.compute({ popped = 4, chainStep = 2, colors = 1 }), 12)
    end)

    t.it("8 popped, 3-chain, 2-colors = 8 × 6 × 2 = 96", function()
        t.assertEq(Scoring.compute({ popped = 8, chainStep = 3, colors = 2 }), 96)
    end)

    t.it("12 popped, 5-chain, 4-colors = 12 × 24 × 8 = 2304", function()
        t.assertEq(Scoring.compute({ popped = 12, chainStep = 5, colors = 4 }), 2304)
    end)

    t.it("chain step beyond table caps multiplier at doubled last entry", function()
        -- 8-chain → 96 × 2 × 2 = 384 (doubling rule)
        local step = 8
        local expectedMult = 96 * (2 ^ (step - 7)) -- 96 = chain 7
        t.assertEq(Scoring.compute({ popped = 1, chainStep = step, colors = 1 }), expectedMult)
    end)
end)

t.summary()
