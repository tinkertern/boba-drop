-- src/ReplicatedStorage/Shared/Logic/Scoring.lua
local Constants = require("../Logic/Constants")

local Scoring = {}

local function chainMultiplier(step)
    local table = Constants.CHAIN_MULTIPLIER
    if step <= #table then return table[step] end
    -- beyond the table: doubling rule
    local last = table[#table]
    return last * (2 ^ (step - #table))
end

local function colorBonus(distinctColors)
    local table = Constants.COLOR_BONUS
    if distinctColors <= #table then return table[distinctColors] end
    return table[#table]
end

function Scoring.compute(event)
    -- event: { popped = int, chainStep = int >=1, colors = int >=1 }
    assert(event.popped and event.chainStep and event.colors, "Scoring.compute: invalid event")
    return event.popped * chainMultiplier(event.chainStep) * colorBonus(event.colors)
end

return Scoring
