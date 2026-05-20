-- tests/PieceControl.spec.luau
-- Tests for active-piece spawn / move / rotate / lock flow inside GameState.
local t = require("./_test_helpers")
local GameState = require("../src/ReplicatedStorage/Shared/Logic/GameState")
local Constants = require("../src/ReplicatedStorage/Shared/Logic/Constants")

local function newRound()
    local gs = GameState.new({ players = { "P1", "P2" }, seed = 42 })
    gs:startRound()
    return gs
end

t.describe("Active piece spawn", function()
    t.it("startRound spawns an active piece for both players", function()
        local gs = newRound()
        local p1 = gs:activePiece("P1")
        local p2 = gs:activePiece("P2")
        t.assertEq(p1 ~= nil, true, "P1 piece spawned")
        t.assertEq(p2 ~= nil, true, "P2 piece spawned")
        t.assertEq(type(p1.a), "string")
        t.assertEq(type(p1.b), "string")
        t.assertEq(p1.orientation, 0, "default orientation = b above a")
    end)

    t.it("spawn position is inside the board column range", function()
        local gs = newRound()
        local p = gs:activePiece("P1")
        t.assertEq(p.pivotCol >= 1 and p.pivotCol <= Constants.BOARD_WIDTH, true)
    end)
end)

t.describe("applyInput: move", function()
    t.it("moves left when there's room", function()
        local gs = newRound()
        local startCol = gs:activePiece("P1").pivotCol
        gs:applyInput("P1", { type = "move", direction = "left" })
        t.assertEq(gs:activePiece("P1").pivotCol, startCol - 1)
    end)

    t.it("does not move past the left wall", function()
        local gs = newRound()
        for _ = 1, 10 do
            gs:applyInput("P1", { type = "move", direction = "left" })
        end
        t.assertEq(gs:activePiece("P1").pivotCol >= 1, true)
    end)

    t.it("does not move past the right wall (accounting for orientation)", function()
        local gs = newRound()
        for _ = 1, 10 do
            gs:applyInput("P1", { type = "move", direction = "right" })
        end
        local p = gs:activePiece("P1")
        -- b is above a in orientation 0, so right wall = board width
        t.assertEq(p.pivotCol <= Constants.BOARD_WIDTH, true)
    end)
end)

t.describe("applyInput: rotate", function()
    t.it("rotates cw cycles orientation 0->1->2->3->0", function()
        local gs = newRound()
        t.assertEq(gs:activePiece("P1").orientation, 0)
        gs:applyInput("P1", { type = "rotate", direction = "cw" })
        t.assertEq(gs:activePiece("P1").orientation, 1)
        gs:applyInput("P1", { type = "rotate", direction = "cw" })
        t.assertEq(gs:activePiece("P1").orientation, 2)
        gs:applyInput("P1", { type = "rotate", direction = "cw" })
        t.assertEq(gs:activePiece("P1").orientation, 3)
        gs:applyInput("P1", { type = "rotate", direction = "cw" })
        t.assertEq(gs:activePiece("P1").orientation, 0)
    end)

    t.it("ccw is the inverse of cw", function()
        local gs = newRound()
        gs:applyInput("P1", { type = "rotate", direction = "ccw" })
        t.assertEq(gs:activePiece("P1").orientation, 3)
    end)
end)

t.describe("applyInput: hardDrop locks the piece and spawns next", function()
    t.it("hardDrop lands the piece on the floor and a new piece appears", function()
        local gs = newRound()
        local before = gs:activePiece("P1")
        local beforeA = before.a
        local beforeB = before.b
        gs:applyInput("P1", { type = "hardDrop" })
        local board = gs:boardFor("P1")
        -- Cell at row 1, current pivotCol should now hold the a-color
        local col = before.pivotCol
        t.assertEq(board:cellAt(1, col), beforeA, "a-piece on the floor")
        t.assertEq(board:cellAt(2, col), beforeB, "b-piece on top")
        local after = gs:activePiece("P1")
        t.assertEq(after ~= nil, true, "next piece spawned")
        -- Different bag entry (or same colors but new identity)
        t.assertEq(gs:phase(), "playing")
    end)
end)

t.describe("Lock → ChainResolver integration", function()
    t.it("locking a piece that completes a 4-group dispatches onChainResolved", function()
        local gs = newRound()
        -- Pre-seed board with 3 Pinks in column 3 rows 1-3 so a Pink-Pink piece dropped there pops
        local board = gs:boardFor("P1")
        for r = 1, 3 do board:placeAt(r, 3, "Pink") end
        -- Force the active piece to be Pink-Pink at col 3
        local p = gs:activePiece("P1")
        p.a = "Pink"; p.b = "Pink"; p.pivotCol = 3; p.orientation = 0
        local got = nil
        gs:subscribe("onChainResolved", function(e) got = e end)
        gs:applyInput("P1", { type = "hardDrop" })
        t.assertEq(got ~= nil, true, "chain event fired")
        t.assertEq(got.playerId, "P1")
        t.assertEq(got.chainLength >= 1, true)
        t.assertEq(got.scoreAdded > 0, true, "server-computed scoreAdded present")
    end)

    t.it("scoreAdded is added to the player's round score", function()
        local gs = newRound()
        local board = gs:boardFor("P1")
        for r = 1, 3 do board:placeAt(r, 3, "Pink") end
        local p = gs:activePiece("P1")
        p.a = "Pink"; p.b = "Pink"; p.pivotCol = 3; p.orientation = 0
        local before = gs:scoreOf("P1")
        gs:applyInput("P1", { type = "hardDrop" })
        t.assertEq(gs:scoreOf("P1") > before, true)
    end)
end)

t.describe("Garbage drop application", function()
    t.it("drops queued garbage after the configured placement delay", function()
        local gs = newRound()
        -- Queue 3 garbage on P1
        gs:queueGarbage("P1", 3)
        t.assertEq(gs:pendingGarbage("P1"), 3)
        t.assertEq(gs:placementsUntilGarbage("P1"), 2)
        -- Place piece 1: decrements but doesn't drop
        gs:applyInput("P1", { type = "hardDrop" })
        t.assertEq(gs:pendingGarbage("P1"), 3)
        t.assertEq(gs:placementsUntilGarbage("P1"), 1)
        -- Place piece 2: drops garbage onto board
        gs:applyInput("P1", { type = "hardDrop" })
        t.assertEq(gs:pendingGarbage("P1"), 0)
        -- 3 garbage cubes should now exist on the board somewhere
        local board = gs:boardFor("P1")
        local count = 0
        for r = 1, board.height do
            for c = 1, board.width do
                if board:cellAt(r, c) == "Garbage" then count += 1 end
            end
        end
        t.assertEq(count, 3, "3 garbage cubes dropped")
    end)
end)

t.describe("Overflow round end", function()
    t.it("stacking into the overflow row ends the round with the stacker as loser", function()
        local gs = newRound()
        local board = gs:boardFor("P1")
        -- Fill column 3 with garbage (non-matching) up to row 13. Garbage never
        -- forms groups so the chain resolver won't clear it.
        for r = 1, Constants.BOARD_TOTAL_HEIGHT - 1 do board:placeAt(r, 3, "Garbage") end
        local p = gs:activePiece("P1")
        p.a = "Pink"; p.b = "Green"; p.pivotCol = 3; p.orientation = 0
        local roundEndFired = nil
        gs:subscribe("onRoundEnd", function(e) roundEndFired = e end)
        gs:applyInput("P1", { type = "hardDrop" })
        t.assertEq(roundEndFired ~= nil, true, "round ended")
        t.assertEq(roundEndFired.loser, "P1")
        t.assertEq(roundEndFired.winner, "P2")
        t.assertEq(roundEndFired.reason, "overflow")
    end)
end)

t.summary()
