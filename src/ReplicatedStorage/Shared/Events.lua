-- src/ReplicatedStorage/Shared/Events.lua
-- Event name + payload-shape registry. Single source of truth.
local Events = {}

Events.Names = {
    -- Client → Server
    InputMove = "InputMove",       -- payload: { direction = "left" | "right" }
    InputRotate = "InputRotate",   -- payload: { direction = "cw" | "ccw" }
    InputSoftDrop = "InputSoftDrop", -- payload: { held = boolean }
    InputHardDrop = "InputHardDrop", -- payload: {}
    RematchRequest = "RematchRequest", -- payload: {} — in practice mode, a single fire restarts the solo room (no second-vote wait)
    LeaveMatch = "LeaveMatch",     -- payload: {}
    EnterQueue = "EnterQueue",     -- payload: { mode = "versus" | "practice" | "ai", difficulty? = "easy" | "normal" | "hard" | "pro" } — versus enters matchmaking, practice skips queue and starts a solo room immediately, ai spins up a 2-player room (real + bot, userId = "-1"). Difficulty defaults to "easy"; unknown values fall back to easy.
    LeaveQueue = "LeaveQueue",     -- payload: {}
    PauseRequest = "PauseRequest", -- payload: { paused = boolean } — practice-mode only; halts gravity tick + soft drop + AFK timer for the requesting player. Silently ignored in versus.

    -- Server → Client
    ActivePieceUpdate = "ActivePieceUpdate", -- payload: { playerId, isLocal, colors = { a, b }, pivotRow, pivotCol, orientation }
    NextPieceQueueUpdate = "NextPieceQueueUpdate", -- payload: { playerId, isLocal, queue = [{ a, b }, { a, b }] } — next 2 pairs from the player's bag, non-destructive peek
    PieceLocked = "PieceLocked",   -- payload: { playerId, a, b, aRow, aCol, bRow, bCol, cells = post-gravity board snapshot }
    ChainCompleted = "ChainCompleted", -- payload: { playerId, chainLength, totalPopped, scoreAdded, garbageOut, isLocal, cells = post-chain snapshot, steps = [{ popped, colors, cellsPopped = [{row, col, color}, ...], garbageCleared = [{row, col}, ...] }, ...] }
    RoundStartCountdown = "RoundStartCountdown", -- payload: { startsAt = workspace:GetServerTimeNow() + ROUND_START_COUNTDOWN } — clients sync the 3-2-1-GO overlay to this end timestamp
    GarbageIncoming = "GarbageIncoming", -- payload: { playerId, cubes = number, dropsInPlacements = number }
    GarbageApplied = "GarbageApplied", -- payload: { playerId, cubes = number, canceledByCounter = number, cellsDropped = [{ row, col }, ...] }
    RoundEnd = "RoundEnd",         -- payload: { winner, loser, reason, round, p1Score, p2Score }
    MatchEnd = "MatchEnd",         -- payload: { winner, loser?, result = "win" | "practice_ended", mode = "versus" | "practice" | "ai", difficulty? = "easy" | "medium" | "hard" | "pro", finalScores = { [pid] = number }, bestChain = { [pid] = number } } — in "ai" mode, winner / loser may be the bot userId "-1"; difficulty present only when mode == "ai"
}

return Events
