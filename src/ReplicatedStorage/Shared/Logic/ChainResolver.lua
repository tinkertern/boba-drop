-- src/ReplicatedStorage/Shared/Logic/ChainResolver.lua
local MatchDetector = require("../Logic/MatchDetector")

local ChainResolver = {}

-- Synchronously resolves all chain reactions on a board.
-- Returns: {
--   chainLength = number,
--   totalPopped = number,
--   steps = {
--     {
--       popped = number,                          -- cell count this step
--       colors = number,                          -- distinct color cardinality
--       cellsPopped = { { row, col, color }, ... } -- per-cell list for renderer targeting
--     }, ...
--   }
-- }
function ChainResolver.resolve(board)
    local steps = {}
    local totalPopped = 0

    while true do
        local groups = MatchDetector.findGroups(board)
        if #groups == 0 then break end

        local stepPopped = 0
        local seenColors = {}
        local cellsPopped = {}
        for _, group in groups do
            for _, cell in group.cells do
                table.insert(cellsPopped, { row = cell[1], col = cell[2], color = group.color })
                board:clearAt(cell[1], cell[2])
                stepPopped += 1
            end
            seenColors[group.color] = true
        end

        local colorCount = 0
        for _ in seenColors do colorCount += 1 end

        table.insert(steps, { popped = stepPopped, colors = colorCount, cellsPopped = cellsPopped })
        totalPopped += stepPopped

        board:gravitySettle()
    end

    return {
        chainLength = #steps,
        totalPopped = totalPopped,
        steps = steps,
    }
end

return ChainResolver
