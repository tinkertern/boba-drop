-- src/ReplicatedStorage/Shared/Logic/Board.lua
local Constants = require("../Logic/Constants")
local PieceTypes = require("../PieceTypes")

local Board = {}
Board.__index = Board

-- Pure pseudo-RNG: linear congruential generator so we control seeding precisely
-- and Lune tests reproduce deterministically.
local function makeRng(seed)
    local state = seed % 2147483647
    if state <= 0 then state += 2147483646 end
    return function()
        state = (state * 16807) % 2147483647
        return state
    end
end

local function shuffledBag(rng)
    local bag = {}
    for _, a in Constants.COLORS do
        for _, b in Constants.COLORS do
            table.insert(bag, { a = a, b = b })
        end
    end
    -- Fisher-Yates
    for i = #bag, 2, -1 do
        local j = (rng() % i) + 1
        bag[i], bag[j] = bag[j], bag[i]
    end
    return bag
end

function Board.new(ctx)
    assert(ctx and ctx.seed, "Board.new requires ctx.seed (injected RNG seed)")
    local self = setmetatable({}, Board)
    self.width = Constants.BOARD_WIDTH
    self.height = Constants.BOARD_TOTAL_HEIGHT
    self.cells = {} -- cells[row][col] = colorName or nil
    for r = 1, self.height do
        self.cells[r] = {}
    end
    self._rng = makeRng(ctx.seed)
    self._bag = shuffledBag(self._rng)
    self._bagIndex = 1
    return self
end

function Board:_drawOne()
    if self._bagIndex > #self._bag then
        self._bag = shuffledBag(self._rng)
        self._bagIndex = 1
    end
    local piece = self._bag[self._bagIndex]
    self._bagIndex += 1
    return piece
end

function Board:peek(n)
    -- Non-destructive: return the next n pieces without consuming them.
    -- Snapshot index + bag state so we can restore.
    local result = {}
    local savedIndex = self._bagIndex
    local savedBag = table.clone(self._bag)
    for _ = 1, n do
        table.insert(result, self:_drawOne())
    end
    self._bagIndex = savedIndex
    self._bag = savedBag
    return result
end

function Board:advance(n)
    -- Destructive: consume n pieces from the bag.
    local result = {}
    for _ = 1, n do
        table.insert(result, self:_drawOne())
    end
    return result
end

function Board:cellAt(row, col)
    if row < 1 or row > self.height or col < 1 or col > self.width then return nil end
    return self.cells[row][col]
end

function Board:placeAt(row, col, color)
    assert(PieceTypes.isValid(color), "invalid color: " .. tostring(color))
    self.cells[row][col] = color
end

function Board:clearAt(row, col)
    self.cells[row][col] = nil
end

function Board:gravitySettle()
    for col = 1, self.width do
        local writeRow = 1
        for row = 1, self.height do
            local c = self.cells[row][col]
            if c ~= nil then
                if row ~= writeRow then
                    self.cells[writeRow][col] = c
                    self.cells[row][col] = nil
                end
                writeRow += 1
            end
        end
    end
end

return Board
