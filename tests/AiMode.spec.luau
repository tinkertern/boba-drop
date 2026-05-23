-- tests/AiMode.spec.luau
-- Tests the GameState half of single-player vs AI: a 2-player state where one
-- of the player ids is the BOT sentinel ("-1"). Confirms the bot is just
-- another player from GameState's perspective — spawns dispatch with its id,
-- its chains route garbage to the real opponent, topouts on either side
-- declare the other the winner, and onMatchEnd carries mode = "ai".
--
-- This file does NOT exercise RoomManager / Main.server / StateSync directly
-- (those need the Roblox Player Instance, which we don't have in Lune). The
-- AI decision loop is also out of scope here — it's a thin orchestration over
-- gs:applyInput which is already covered by PieceControl.spec.luau. What we
-- DO need to lock in is that GameState's existing versus pipeline doesn't
-- crash or misroute when one of the player ids is "-1".
local t = require("./_test_helpers")
local GameState = require("../src/ReplicatedStorage/Shared/Logic/GameState")
local Constants = require("../src/ReplicatedStorage/Shared/Logic/Constants")

local BOT = "-1"
local REAL = "P1"

local function newAiState()
    return GameState.new({ players = { REAL, BOT }, seed = 42, mode = "ai" })
end

t.describe("GameState AI mode construction", function()
    t.it("accepts { realUserId, '-1', mode = 'ai' } without erroring", function()
        local gs = newAiState()
        t.assertEq(gs:phase(), "waiting")
        t.assertEq(gs:isSolo(), false, "2-player state is not solo")
        t.assertEq(gs:mode(), "ai", "ctx.mode override is honored — MatchEnd payload carries 'ai' to the client")
    end)

    t.it("startRound spawns a board + active piece for both real and bot", function()
        local gs = newAiState()
        gs:startRound()
        t.assertEq(gs:phase(), "playing")
        t.assertEq(gs:boardFor(REAL) ~= nil, true, "real player board")
        t.assertEq(gs:boardFor(BOT) ~= nil, true, "bot board exists too")
        t.assertEq(gs:activePiece(REAL) ~= nil, true, "real piece spawned")
        t.assertEq(gs:activePiece(BOT) ~= nil, true, "bot piece spawned")
    end)
end)

t.describe("GameState AI mode piece spawn dispatch", function()
    t.it("startRound dispatches onPieceSpawned with playerId = '-1' for the bot", function()
        local gs = newAiState()
        local spawns = {}
        gs:subscribe("onPieceSpawned", function(e) table.insert(spawns, e.playerId) end)
        gs:startRound()
        -- Both spawns should fire — order is not contractual but both ids
        -- must appear exactly once.
        local seenReal, seenBot = false, false
        for _, pid in spawns do
            if pid == REAL then seenReal = true end
            if pid == BOT then seenBot = true end
        end
        t.assertEq(seenReal, true, "real-player spawn dispatched")
        t.assertEq(seenBot, true, "bot spawn dispatched with playerId = '-1'")
    end)

    t.it("bot hardDrop dispatches onPieceLocked with playerId = '-1'", function()
        local gs = newAiState()
        gs:startRound()
        local lockedFor = nil
        gs:subscribe("onPieceLocked", function(e) lockedFor = e.playerId end)
        gs:applyInput(BOT, { type = "hardDrop" })
        t.assertEq(lockedFor, BOT, "lock event carried bot id")
    end)
end)

t.describe("GameState AI mode chain → garbage routing", function()
    t.it("bot chain pop routes garbage to the real player (versus pipeline)", function()
        local gs = newAiState()
        gs:startRound()
        -- Pre-seed the bot's board so its next piece pops a 4-group of Pinks.
        local botBoard = gs:boardFor(BOT)
        for r = 1, 3 do botBoard:placeAt(r, 3, "Pink") end
        local p = gs:activePiece(BOT)
        p.a = "Pink"; p.b = "Pink"; p.pivotCol = 3; p.orientation = 0

        local chainEvent = nil
        local garbageIncoming = nil
        gs:subscribe("onChainResolved", function(e) chainEvent = e end)
        gs:subscribe("onGarbageIncoming", function(e) garbageIncoming = e end)
        gs:applyInput(BOT, { type = "hardDrop" })

        t.assertEq(chainEvent ~= nil, true, "bot's chain fired")
        t.assertEq(chainEvent.playerId, BOT, "chain attributed to bot")
        t.assertEq(chainEvent.garbageOut > 0, true, "chain produces garbage")
        t.assertEq(garbageIncoming ~= nil, true, "garbage routed somewhere")
        t.assertEq(garbageIncoming.playerId, REAL, "garbage targeted the real player")
        t.assertEq(gs:pendingGarbage(REAL) > 0, true, "real player has pending garbage")
        t.assertEq(gs:pendingGarbage(BOT), 0, "bot has no self-garbage")
    end)
end)

t.describe("GameState AI mode match-end routing", function()
    t.it("real-player topout fires onMatchEnd with winner = '-1', loser = real, mode = 'versus'", function()
        local gs = newAiState()
        gs:startRound()
        -- Fill column 3 on the real player's board so the next hardDrop overflows.
        local board = gs:boardFor(REAL)
        for r = 1, Constants.BOARD_TOTAL_HEIGHT - 1 do board:placeAt(r, 3, "Garbage") end
        local p = gs:activePiece(REAL)
        p.a = "Pink"; p.b = "Green"; p.pivotCol = 3; p.orientation = 0

        local matchEnd = nil
        gs:subscribe("onMatchEnd", function(e) matchEnd = e end)
        gs:applyInput(REAL, { type = "hardDrop" })

        t.assertEq(matchEnd ~= nil, true, "match end fired")
        t.assertEq(matchEnd.winner, BOT, "bot is the winner")
        -- onMatchEnd payload from _endRound carries only winner, but onRoundEnd
        -- carries loser — verify via finalScores key presence as a side-channel.
        t.assertEq(matchEnd.finalScores[REAL] ~= nil, true, "real player in finalScores")
        t.assertEq(matchEnd.finalScores[BOT] ~= nil, true, "bot in finalScores")
        -- mode = "ai" is the ctx.mode override threaded through GameState into
        -- the MatchEnd payload — Producer's MatchEnd.client.lua reads this to
        -- pick the "you vs bot" header variant.
        t.assertEq(matchEnd.mode, "ai")
    end)

    t.it("bot topout fires onMatchEnd with winner = real, loser = '-1'", function()
        local gs = newAiState()
        gs:startRound()
        local board = gs:boardFor(BOT)
        for r = 1, Constants.BOARD_TOTAL_HEIGHT - 1 do board:placeAt(r, 3, "Garbage") end
        local p = gs:activePiece(BOT)
        p.a = "Pink"; p.b = "Green"; p.pivotCol = 3; p.orientation = 0

        local matchEnd = nil
        local roundEnd = nil
        gs:subscribe("onMatchEnd", function(e) matchEnd = e end)
        gs:subscribe("onRoundEnd", function(e) roundEnd = e end)
        gs:applyInput(BOT, { type = "hardDrop" })

        t.assertEq(matchEnd ~= nil, true, "match end fired")
        t.assertEq(matchEnd.winner, REAL, "real player wins")
        t.assertEq(matchEnd.mode, "ai", "MatchEnd carries mode = 'ai'")
        t.assertEq(roundEnd ~= nil, true, "round end also fired")
        t.assertEq(roundEnd.loser, BOT, "bot is the loser of the round")
        t.assertEq(roundEnd.winner, REAL)
    end)

    t.it("real player forfeit (leave during AI mode) routes round to bot", function()
        -- Mirrors RoomManager:requestLeave's forfeitRound call for an AI room.
        -- The downstream GameState must not crash on the bot having no Player.
        local gs = newAiState()
        gs:startRound()
        local matchEnd = nil
        gs:subscribe("onMatchEnd", function(e) matchEnd = e end)
        gs:forfeitRound(REAL, "leave")
        t.assertEq(matchEnd ~= nil, true, "match-end fired on forfeit")
        t.assertEq(matchEnd.winner, BOT, "bot wins the forfeit")
    end)
end)

t.summary()
