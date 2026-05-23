-- tests/PracticeMode.spec.luau
-- Tests the 1-player (practice) variant of GameState: solo construction,
-- chain-pop garbage-routing guard (no opponent → don't crash, still report
-- garbageOut so the client can show "you'd send N ICE"), and the
-- practice topout dispatch (onMatchEnd with result = "practice_ended",
-- mode = "practice", no onGarbageApplied followup).
local t = require("./_test_helpers")
local GameState = require("../src/ReplicatedStorage/Shared/Logic/GameState")
local Constants = require("../src/ReplicatedStorage/Shared/Logic/Constants")

local function newSolo()
    return GameState.new({ players = { "P1" }, seed = 42 })
end

t.describe("GameState solo construction", function()
    t.it("accepts a single-player players list without erroring", function()
        local gs = newSolo()
        t.assertEq(gs:phase(), "waiting")
    end)

    t.it("startRound spawns a board + active piece for the lone player only", function()
        local gs = newSolo()
        gs:startRound()
        t.assertEq(gs:phase(), "playing")
        t.assertEq(gs:boardFor("P1") ~= nil, true)
        t.assertEq(gs:activePiece("P1") ~= nil, true)
    end)
end)

t.describe("GameState solo chain pop", function()
    t.it("dispatches onChainResolved with non-zero garbageOut on a 4-group pop", function()
        local gs = newSolo()
        gs:startRound()
        -- Seed 3 Pinks in column 3 rows 1-3 so a Pink-Pink piece pops a 4-group.
        local board = gs:boardFor("P1")
        for r = 1, 3 do board:placeAt(r, 3, "Pink") end
        local p = gs:activePiece("P1")
        p.a = "Pink"; p.b = "Pink"; p.pivotCol = 3; p.orientation = 0

        local chainEvent = nil
        gs:subscribe("onChainResolved", function(e) chainEvent = e end)
        gs:applyInput("P1", { type = "hardDrop" })

        t.assertEq(chainEvent ~= nil, true, "chain fired")
        t.assertEq(chainEvent.playerId, "P1")
        t.assertEq(chainEvent.garbageOut > 0, true, "garbageOut populated for solo feedback")
    end)

    t.it("does NOT dispatch onGarbageApplied or onGarbageIncoming on a solo chain pop", function()
        local gs = newSolo()
        gs:startRound()
        local board = gs:boardFor("P1")
        for r = 1, 3 do board:placeAt(r, 3, "Pink") end
        local p = gs:activePiece("P1")
        p.a = "Pink"; p.b = "Pink"; p.pivotCol = 3; p.orientation = 0

        local garbageAppliedFired = false
        local garbageIncomingFired = false
        gs:subscribe("onGarbageApplied", function() garbageAppliedFired = true end)
        gs:subscribe("onGarbageIncoming", function() garbageIncomingFired = true end)
        gs:applyInput("P1", { type = "hardDrop" })

        t.assertEq(garbageAppliedFired, false, "no garbage arrives (no opponent)")
        t.assertEq(garbageIncomingFired, false, "no garbage routed (no opponent)")
    end)

    t.it("applyOutgoingChain on a solo state is a no-op (does not error on missing opponent)", function()
        local gs = newSolo()
        gs:startRound()
        -- Direct call bypassing the chain pipeline: must not crash on _otherPlayer.
        gs:applyOutgoingChain("P1", 12)
        t.assertEq(gs:pendingGarbage("P1"), 0, "no self-routing")
    end)
end)

t.describe("GameState solo topout", function()
    t.it("topout fires onMatchEnd with result='practice_ended' and mode='practice'", function()
        local gs = newSolo()
        gs:startRound()
        -- Fill column 3 with Garbage up to row BOARD_TOTAL_HEIGHT - 1 so the
        -- next hardDrop lands the piece into the overflow danger row.
        local board = gs:boardFor("P1")
        for r = 1, Constants.BOARD_TOTAL_HEIGHT - 1 do board:placeAt(r, 3, "Garbage") end
        local p = gs:activePiece("P1")
        p.a = "Pink"; p.b = "Green"; p.pivotCol = 3; p.orientation = 0

        local matchEnd = nil
        local roundEndFired = false
        gs:subscribe("onMatchEnd", function(e) matchEnd = e end)
        gs:subscribe("onRoundEnd", function() roundEndFired = true end)
        gs:applyInput("P1", { type = "hardDrop" })

        t.assertEq(matchEnd ~= nil, true, "match end fired")
        t.assertEq(matchEnd.result, "practice_ended")
        t.assertEq(matchEnd.mode, "practice")
        t.assertEq(roundEndFired, false, "solo topout skips onRoundEnd (no opponent winner to declare)")
        t.assertEq(gs:phase(), "matchOver")
    end)

    t.it("versus onMatchEnd payload still carries mode='versus'", function()
        local gs = GameState.new({ players = { "P1", "P2" }, seed = 42 })
        gs:startRound()
        local matchEnd = nil
        gs:subscribe("onMatchEnd", function(e) matchEnd = e end)
        gs:forfeitRound("P1", "leave")
        t.assertEq(matchEnd ~= nil, true)
        t.assertEq(matchEnd.mode, "versus")
    end)
end)

t.summary()
