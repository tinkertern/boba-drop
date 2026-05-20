-- src/ReplicatedStorage/Shared/PieceTypes.lua
local PieceTypes = {}

PieceTypes.COLORS = { "Brown", "Pink", "Green", "White" }

local DOT_COUNTS = { Brown = 1, Pink = 2, Green = 3, White = 4 }
local SHAPES = { Brown = "square", Pink = "triangle", Green = "circle", White = "star" }

function PieceTypes.dotCount(color)
    return DOT_COUNTS[color]
end

function PieceTypes.shape(color)
    return SHAPES[color]
end

function PieceTypes.isGarbage(color)
    return color == "Garbage"
end

function PieceTypes.isValid(color)
    return DOT_COUNTS[color] ~= nil or color == "Garbage"
end

return PieceTypes
