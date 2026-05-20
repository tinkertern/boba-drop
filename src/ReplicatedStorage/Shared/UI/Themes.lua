-- Cosmetic theme palettes for Premium Themes Pack.
-- Each theme overrides the four pearl colors, the cup background tint,
-- and the chain-counter gradient endpoints. Themes.byKey(key) returns
-- a table the renderer can apply; falls back to Default for unknown keys.

local Themes = {}

Themes.Default = {
    name = "Default",
    locked = false,
    PearlBrown = Color3.fromRGB(160, 110, 80),
    PearlPink = Color3.fromRGB(255, 175, 195),
    PearlGreen = Color3.fromRGB(165, 215, 145),
    PearlWhite = Color3.fromRGB(250, 245, 235),
    CupTint = Color3.fromRGB(255, 246, 232),
    ChainGradientStart = Color3.fromRGB(255, 200, 150),
    ChainGradientEnd = Color3.fromRGB(255, 138, 124),
}

Themes.BrownSugarBoba = {
    name = "Brown Sugar Boba",
    locked = true,
    PearlBrown = Color3.fromRGB(184, 121, 74),   -- warm caramel
    PearlPink = Color3.fromRGB(245, 232, 208),   -- cream
    PearlGreen = Color3.fromRGB(92, 59, 31),     -- dark brown
    PearlWhite = Color3.fromRGB(217, 168, 95),   -- amber
    CupTint = Color3.fromRGB(255, 232, 200),
    ChainGradientStart = Color3.fromRGB(217, 168, 95),
    ChainGradientEnd = Color3.fromRGB(184, 121, 74),
}

Themes.StrawberryMilk = {
    name = "Strawberry Milk",
    locked = true,
    PearlBrown = Color3.fromRGB(255, 156, 181),  -- strawberry pink
    PearlPink = Color3.fromRGB(255, 240, 240),   -- cream
    PearlGreen = Color3.fromRGB(197, 111, 136),  -- berry
    PearlWhite = Color3.fromRGB(255, 212, 221),  -- blush
    CupTint = Color3.fromRGB(255, 230, 235),
    ChainGradientStart = Color3.fromRGB(255, 212, 221),
    ChainGradientEnd = Color3.fromRGB(255, 156, 181),
}

Themes.Matcha = {
    name = "Matcha",
    locked = true,
    PearlBrown = Color3.fromRGB(135, 169, 107),  -- matcha green
    PearlPink = Color3.fromRGB(240, 232, 200),   -- cream
    PearlGreen = Color3.fromRGB(74, 103, 65),    -- forest
    PearlWhite = Color3.fromRGB(192, 207, 168),  -- sage
    CupTint = Color3.fromRGB(220, 235, 215),
    ChainGradientStart = Color3.fromRGB(192, 207, 168),
    ChainGradientEnd = Color3.fromRGB(135, 169, 107),
}

Themes.ORDER = {
    "Default",
    "BrownSugarBoba",
    "StrawberryMilk",
    "Matcha",
}

function Themes.byKey(key)
    return Themes[key] or Themes.Default
end

return Themes
