-- tests/GameState.spec.luau
local t = require("./_test_helpers")
local GameState = require("../src/ReplicatedStorage/Shared/Logic/GameState")

local function newState()
    return GameState.new({
        players = { "P1", "P2" },
        seed = 42,
    })
end

t.describe("GameState", function()
    t.it("starts in 'waiting' phase", function()
        local gs = newState()
        t.assertEq(gs:phase(), "waiting")
    end)

    t.it("startRound transitions to 'playing' and assigns boards", function()
        local gs = newState()
        gs:startRound()
        t.assertEq(gs:phase(), "playing")
        t.assertEq(gs:boardFor("P1") ~= nil, true)
        t.assertEq(gs:boardFor("P2") ~= nil, true)
    end)

    t.it("both players' boards use the same seed each round", function()
        local gs = newState()
        gs:startRound()
        local p1Pieces = gs:boardFor("P1"):peek(5)
        local p2Pieces = gs:boardFor("P2"):peek(5)
        for i = 1, 5 do
            t.assertEq(p1Pieces[i].a, p2Pieces[i].a)
            t.assertEq(p1Pieces[i].b, p2Pieces[i].b)
        end
    end)

    t.it("emits 'onChainResolved' to subscribers", function()
        local gs = newState()
        gs:startRound()
        local received = nil
        gs:subscribe("onChainResolved", function(event) received = event end)
        gs:_dispatch("onChainResolved", { playerId = "P1", chainLength = 3 })
        t.assertEq(received.playerId, "P1")
        t.assertEq(received.chainLength, 3)
    end)

    t.it("forfeitRound advances the opponent's round score", function()
        local gs = newState()
        gs:startRound()
        gs:forfeitRound("P1", "disconnect")
        t.assertEq(gs:roundsWon("P2"), 1)
        t.assertEq(gs:roundsWon("P1"), 0)
    end)

    t.it("forfeitRound fires onRoundEnd", function()
        local gs = newState()
        gs:startRound()
        local fired = nil
        gs:subscribe("onRoundEnd", function(e) fired = e end)
        gs:forfeitRound("P1", "afk")
        t.assertEq(fired.loser, "P1")
        t.assertEq(fired.winner, "P2")
        t.assertEq(fired.reason, "afk")
    end)

    t.it("match ends when a player reaches 2 round wins", function()
        local gs = newState()
        gs:startRound(); gs:forfeitRound("P1", "test")
        gs:startRound(); gs:forfeitRound("P1", "test")
        t.assertEq(gs:phase(), "matchOver")
        t.assertEq(gs:matchWinner(), "P2")
    end)

    t.it("draw round does not increment either score and is not counted", function()
        local gs = newState()
        gs:startRound()
        gs:declareDraw()
        t.assertEq(gs:roundsWon("P1"), 0)
        t.assertEq(gs:roundsWon("P2"), 0)
        t.assertEq(gs:phase(), "playing", "draw doesn't advance match")
    end)
end)

t.describe("GameState garbage", function()
    t.it("queues incoming garbage with a 2-placement delay", function()
        local gs = newState()
        gs:startRound()
        gs:queueGarbage("P2", 6) -- P1 sent a 4-chain → P2 gets 6 cubes
        t.assertEq(gs:pendingGarbage("P2"), 6)
        t.assertEq(gs:placementsUntilGarbage("P2"), 2)
    end)

    t.it("counter cancellation subtracts outgoing from incoming", function()
        local gs = newState()
        gs:startRound()
        gs:queueGarbage("P2", 6) -- P2 has 6 incoming
        gs:applyOutgoingChain("P2", 3) -- P2 then 2-chains, sends 1 cube
        t.assertEq(gs:pendingGarbage("P2"), 3) -- 6 - 3 = 3 remaining
    end)

    t.it("counter that exceeds incoming sends remainder to opponent", function()
        local gs = newState()
        gs:startRound()
        gs:queueGarbage("P2", 3) -- P2 has 3 incoming
        gs:applyOutgoingChain("P2", 12) -- P2's 5-chain sends 12 cubes
        t.assertEq(gs:pendingGarbage("P2"), 0) -- all canceled
        t.assertEq(gs:pendingGarbage("P1"), 9) -- 12 - 3 = 9 to opponent
    end)

    t.it("drawn round clears queued garbage on both sides", function()
        local gs = newState()
        gs:startRound()
        gs:queueGarbage("P1", 5)
        gs:queueGarbage("P2", 3)
        gs:declareDraw()
        t.assertEq(gs:pendingGarbage("P1"), 0)
        t.assertEq(gs:pendingGarbage("P2"), 0)
    end)
end)

t.summary()
