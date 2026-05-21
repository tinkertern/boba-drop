-- src/ReplicatedStorage/Shared/Events.lua
-- Event name + payload-shape registry. Single source of truth.
local Events = {}

Events.Names = {
    -- Client → Server
    InputMove = "InputMove",       -- payload: { direction = "left" | "right" }
    InputRotate = "InputRotate",   -- payload: { direction = "cw" | "ccw" }
    InputSoftDrop = "InputSoftDrop", -- payload: { held = boolean }
    InputHardDrop = "InputHardDrop", -- payload: {}
    RematchRequest = "RematchRequest", -- payload: {}
    LeaveMatch = "LeaveMatch",     -- payload: {}

    -- Server → Client
    ActivePieceUpdate = "ActivePieceUpdate", -- payload: { playerId, isLocal, colors = { a, b }, pivotRow, pivotCol, orientation }
    NextPieceQueueUpdate = "NextPieceQueueUpdate", -- payload: { playerId, isLocal, queue = [{ a, b }, { a, b }] } — next 2 pairs from the player's bag, non-destructive peek
    PieceLocked = "PieceLocked",   -- payload: { playerId, a, b, aRow, aCol, bRow, bCol, cells = post-gravity board snapshot }
    ChainCompleted = "ChainCompleted", -- payload: { playerId, chainLength, totalPopped, scoreAdded, garbageOut, isLocal, cells = post-chain snapshot, steps = [{ popped, colors, cellsPopped = [{row, col, color}, ...] }, ...] }
    RoundStartCountdown = "RoundStartCountdown", -- payload: { startsAt = workspace:GetServerTimeNow() + ROUND_START_COUNTDOWN } — clients sync the 3-2-1-GO overlay to this end timestamp
    GarbageIncoming = "GarbageIncoming", -- payload: { playerId, cubes = number, dropsInPlacements = number }
    GarbageApplied = "GarbageApplied", -- payload: { playerId, cubes = number, canceledByCounter = number }
    RoundEnd = "RoundEnd",         -- payload: { winner, loser, reason, round, p1Score, p2Score }
    MatchEnd = "MatchEnd",         -- payload: { winner, finalScores = { [pid] = number }, bestChain = { [pid] = number } }
}

return Events
