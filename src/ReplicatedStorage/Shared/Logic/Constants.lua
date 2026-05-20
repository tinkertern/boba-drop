-- src/ReplicatedStorage/Shared/Logic/Constants.lua
local Constants = {}

-- Board
Constants.BOARD_WIDTH = 6
Constants.BOARD_VISIBLE_HEIGHT = 12
Constants.BOARD_DANGER_ROWS = 2 -- rows above visible; overflow at row 13+
Constants.BOARD_TOTAL_HEIGHT = Constants.BOARD_VISIBLE_HEIGHT + Constants.BOARD_DANGER_ROWS

-- Match rule
Constants.MIN_MATCH_SIZE = 4

-- Pieces
Constants.NUM_COLORS = 4
Constants.COLORS = { "Brown", "Pink", "Green", "White" }

-- Timings (seconds)
Constants.LOCK_DELAY = 0.5
Constants.GRAVITY_BASE = 0.8
Constants.GRAVITY_RAMP_PER_30S = -0.05
Constants.GRAVITY_FLOOR = 0.2
Constants.SOFT_DROP_MULT = 8
Constants.AFK_PIECE_TIMEOUT = 15
Constants.GARBAGE_QUEUE_DELAY_PLACEMENTS = 2

-- Animation pacing
Constants.POP_TELL_DURATION = 0.25
Constants.GRAVITY_SETTLE_DURATION = 0.30
Constants.CHAIN_COUNTER_PERSIST = 1.0
Constants.GARBAGE_DROP_WARNING_LEAD = 0.5

-- Garbage table (chain length → cubes sent)
Constants.GARBAGE_TABLE = {
    [1] = 0,
    [2] = 1,
    [3] = 3,
    [4] = 6,
    [5] = 12,
}
Constants.GARBAGE_CAP = 24 -- for chain length 6+

-- Scoring multipliers
Constants.CHAIN_MULTIPLIER = { 1, 3, 6, 12, 24, 48, 96 } -- doubling
Constants.COLOR_BONUS = { 1, 2, 4, 8 } -- by distinct colors in the chain step

-- Network / disconnect
Constants.DISCONNECT_GRACE = 10
Constants.REMATCH_WINDOW = 15
Constants.REMATCH_LEAVE_COOLDOWN = 1
Constants.QUEUE_TIMEOUT = 60

-- Match
Constants.ROUNDS_TO_WIN = 2 -- best of 3

return Constants
