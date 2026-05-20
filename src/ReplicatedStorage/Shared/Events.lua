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
    PieceLocked = "PieceLocked",   -- payload: { playerId, position = {row, col}, color = string }
    ChainCompleted = "ChainCompleted", -- payload: { playerId, chainLength, totalPopped, isLocal }
    GarbageIncoming = "GarbageIncoming", -- payload: { playerId, cubes = number, dropsInPlacements = number }
    GarbageApplied = "GarbageApplied", -- payload: { playerId, cubes = number, canceledByCounter = number }
    RoundEnd = "RoundEnd",         -- payload: { winner, loser, reason, round, p1Score, p2Score }
    MatchEnd = "MatchEnd",         -- payload: { winner, finalScores = { [pid] = number }, bestChain = { [pid] = number } }
}

return Events
