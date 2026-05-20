-- src/ReplicatedStorage/Shared/Logic/MatchDetector.lua
local Constants = require("../Logic/Constants")
local PieceTypes = require("../PieceTypes")

local MatchDetector = {}

-- Returns a list of groups, each { color = string, cells = { {row, col}, ... } }
-- A group is connected via orthogonal adjacency of the same color, size >= MIN_MATCH_SIZE.
-- Garbage cubes never form groups.
function MatchDetector.findGroups(board)
    local visited = {}
    for r = 1, board.height do visited[r] = {} end

    local results = {}

    local function key(r, c) return r * 100 + c end

    for startRow = 1, board.height do
        for startCol = 1, board.width do
            local color = board:cellAt(startRow, startCol)
            if color and not PieceTypes.isGarbage(color) and not visited[startRow][startCol] then
                -- BFS
                local queue = { { startRow, startCol } }
                local cells = {}
                visited[startRow][startCol] = true
                while #queue > 0 do
                    local cur = table.remove(queue, 1)
                    table.insert(cells, cur)
                    local r, c = cur[1], cur[2]
                    local neighbors = { { r + 1, c }, { r - 1, c }, { r, c + 1 }, { r, c - 1 } }
                    for _, n in neighbors do
                        local nr, nc = n[1], n[2]
                        if nr >= 1 and nr <= board.height and nc >= 1 and nc <= board.width then
                            if not visited[nr][nc] and board:cellAt(nr, nc) == color then
                                visited[nr][nc] = true
                                table.insert(queue, { nr, nc })
                            end
                        end
                    end
                end
                if #cells >= Constants.MIN_MATCH_SIZE then
                    table.insert(results, { color = color, cells = cells })
                end
            end
        end
    end

    return results
end

return MatchDetector
