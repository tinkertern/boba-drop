-- src/ReplicatedStorage/Shared/Events.lua
-- Event name + payload-shape registry. Single source of truth.
local Events = {}

Events.Names = {
    -- Client → Server (input)
    InputMove = "InputMove",     -- payload: { direction = "left" | "right" }
    InputRotate = "InputRotate", -- payload: { direction = "cw" | "ccw" }
    InputSoftDrop = "InputSoftDrop", -- payload: { held = boolean }
    InputHardDrop = "InputHardDrop", -- payload: {}

    -- Server → Client (state) — populated Day 3
    PieceLocked = "PieceLocked",
    ChainCompleted = "ChainCompleted",
    GarbageIncoming = "GarbageIncoming",
    GarbageApplied = "GarbageApplied",
    RoundEnd = "RoundEnd",
    MatchEnd = "MatchEnd",
}

return Events
