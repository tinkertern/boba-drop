-- tests/smoke.spec.luau
local t = require("./_test_helpers")

t.describe("smoke", function()
    t.it("the test helper works", function()
        t.assertEq(1 + 1, 2)
    end)
end)

t.summary()
