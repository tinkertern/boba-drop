-- src/ReplicatedStorage/Shared/Logic/ChainResolver.lua
local MatchDetector = require("../Logic/MatchDetector")

local ChainResolver = {}

-- Synchronously resolves all chain reactions on a board.
-- Returns: {
--   chainLength = number,
--   totalPopped = number,
--   steps = {
--     {
--       popped = number,                            -- color-cell count this step (does NOT include garbage)
--       colors = number,                            -- distinct color cardinality
--       cellsPopped = { { row, col, color }, ... }, -- per-cell list for renderer targeting
--       garbageCleared = { { row, col }, ... },     -- garbage cells cleared by orthogonal adjacency
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
        local poppedCells = {}
        for _, group in groups do
            for _, cell in group.cells do
                table.insert(cellsPopped, { row = cell[1], col = cell[2], color = group.color })
                table.insert(poppedCells, cell)
                board:clearAt(cell[1], cell[2])
                stepPopped += 1
            end
            seenColors[group.color] = true
        end

        -- Neighbour-clear: any garbage cube orthogonally adjacent to a popped
        -- cell is cleared as a side-effect (does not extend the chain length).
        local garbageCleared = {}
        local seenAdj = {}
        local function tryClearAdjGarbage(r, c)
            if r < 1 or c < 1 or r > board.height or c > board.width then return end
            local k = r * 100 + c
            if seenAdj[k] then return end
            seenAdj[k] = true
            if board:cellAt(r, c) == "Garbage" then
                board:clearAt(r, c)
                table.insert(garbageCleared, { row = r, col = c })
            end
        end
        for _, cell in poppedCells do
            tryClearAdjGarbage(cell[1] - 1, cell[2])
            tryClearAdjGarbage(cell[1] + 1, cell[2])
            tryClearAdjGarbage(cell[1], cell[2] - 1)
            tryClearAdjGarbage(cell[1], cell[2] + 1)
        end

        local colorCount = 0
        for _ in seenColors do colorCount += 1 end

        table.insert(steps, {
            popped = stepPopped,
            colors = colorCount,
            cellsPopped = cellsPopped,
            garbageCleared = garbageCleared,
        })
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
