-- Boba Drop visual language: warm, bubbly, cozy. Soft pastels, rounded
-- corners, gentle motion. All UI files read from this module — never
-- hardcode colors / fonts / corner radii / easing / durations elsewhere.

local UIConstants = {}

--------------------------------------------------------------------------------
-- Colors
--------------------------------------------------------------------------------

UIConstants.Colors = {
    -- Pastel base palette
    Cream = Color3.fromRGB(255, 246, 232),       -- #FFF6E8 — card / panel / button surface
    Backdrop = Color3.fromRGB(250, 226, 192),    -- #FAE2C0 — full-screen behind everything; warmer than Cream so cream surfaces read as elevated
    Peach = Color3.fromRGB(255, 214, 165),       -- #FFD6A5
    Mint = Color3.fromRGB(199, 229, 192),        -- #C7E5C0
    Coral = Color3.fromRGB(255, 138, 124),       -- chain-gradient end + danger accent
    WarmCancel = Color3.fromRGB(232, 146, 114),  -- #E89272 burnt-tan; cancel/dismiss buttons that must not read as "go" (mint)
    Warning = Color3.fromRGB(194, 92, 63),       -- #C25C3F deep burnt coral; lose-state words ("overflow") so they read as worse than Coral

    -- Text — never pure black
    TextDark = Color3.fromRGB(61, 40, 23),       -- #3D2817
    TextSoft = Color3.fromRGB(120, 90, 70),      -- secondary labels
    TextOnWarm = Color3.fromRGB(255, 250, 240),  -- light text on coral/peach buttons

    -- Warm dark wash. Same hex as TextDark but named for its non-text use
    -- (modal scrims, shadow tints). Keeps semantics tidy at call sites.
    WarmDark = Color3.fromRGB(61, 40, 23),       -- #3D2817

    -- Pearls (desaturated but vibrant, never neon)
    PearlBrown = Color3.fromRGB(160, 110, 80),
    PearlPink = Color3.fromRGB(255, 175, 195),
    PearlGreen = Color3.fromRGB(165, 215, 145),
    PearlWhite = Color3.fromRGB(250, 245, 235),
    PearlHighlight = Color3.fromRGB(255, 255, 255),

    -- Garbage (cute, not threatening — pastel blue ice)
    IceBase = Color3.fromRGB(180, 215, 235),
    IceFrost = Color3.fromRGB(225, 240, 250),
    GarbageBlock = Color3.fromRGB(180, 215, 235),  -- same as IceBase, used for in-cup garbage pearls
    GarbageWarning = Color3.fromRGB(255, 168, 168),  -- soft worry-pink, not panic-red

    -- Chain counter gradient (peach → coral, celebratory)
    ChainGradientStart = Color3.fromRGB(255, 200, 150),
    ChainGradientEnd = Color3.fromRGB(255, 138, 124),

    -- Strokes / dividers
    StrokeSoft = Color3.fromRGB(220, 200, 180),
    StrokeWarm = Color3.fromRGB(180, 140, 100),

    -- Counter-cancel feedback
    Blocked = Color3.fromRGB(120, 200, 255),
}

--------------------------------------------------------------------------------
-- Typography
--------------------------------------------------------------------------------

-- Fonts use the new FontFace API (Font.new). Consumers set
-- TextLabel.FontFace, not the legacy TextLabel.Font enum.
-- FredokaOne = chunky friendly display font. Gotham = neutral HUD/body.
UIConstants.Fonts = {
    Display = Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Regular, Enum.FontStyle.Normal),
    HUD = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold, Enum.FontStyle.Normal),
    Tutorial = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Regular, Enum.FontStyle.Normal),
}

UIConstants.TextSizes = {
    Display = 48,
    DisplayLarge = 64,
    Score = 32,
    HUDLabel = 14,
    Body = 16,
    SmallButton = 14,
}

--------------------------------------------------------------------------------
-- Shape — UICorner radii
--------------------------------------------------------------------------------

UIConstants.Corners = {
    Pearl = UDim.new(0.5, 0),       -- circle
    Cell = UDim.new(0, 4),          -- subtle softness on grid cells
    Card = UDim.new(0, 16),         -- tutorial card, score pill
    Panel = UDim.new(0, 20),        -- match-end panel, shop modal
    Button = UDim.new(0, 12),       -- buttons, close icons
    Pill = UDim.new(1, 0),          -- fully-rounded pill (for counters)
}

--------------------------------------------------------------------------------
-- Motion
--------------------------------------------------------------------------------

UIConstants.Easing = {
    UI = { Style = Enum.EasingStyle.Back, Direction = Enum.EasingDirection.Out },
    UIIn = { Style = Enum.EasingStyle.Back, Direction = Enum.EasingDirection.In },
    Sine = { Style = Enum.EasingStyle.Sine, Direction = Enum.EasingDirection.InOut },
    Linear = { Style = Enum.EasingStyle.Linear, Direction = Enum.EasingDirection.Out },
}

UIConstants.Durations = {
    -- Gameplay-pacing values
    PopTell = 0.25,
    GravitySettle = 0.30,
    ChainCounterPersist = 1.0,
    GarbageWarningLead = 0.5,
    BlockedFlash = 0.4,

    -- Motion grammar
    ButtonPress = 0.12,         -- squish on press
    BounceIn = 0.35,            -- chain counter / score appear
    PopScale = 0.30,            -- pearl pop scale-up
    SparkleFade = 0.6,          -- particle fade-out
    IdleFloatPeriod = 2.0,      -- bob cycle for idle elements
    GradientShimmerPeriod = 3.0,
}

UIConstants.Motion = {
    PopScalePeak = 1.3,
    ButtonPressScale = 0.92,
    FloatBobPx = 3,             -- 2-4px range
}

function UIConstants.tween(duration, easingName)
    local e = UIConstants.Easing[easingName or "UI"]
    return TweenInfo.new(duration, e.Style, e.Direction)
end

--------------------------------------------------------------------------------
-- Glossy pearl spec
--------------------------------------------------------------------------------

UIConstants.Pearl = {
    HighlightSize = UDim2.fromScale(0.32, 0.26),
    HighlightAnchor = Vector2.new(0.5, 0.5),
    HighlightPosition = UDim2.fromScale(0.32, 0.28),
    HighlightTransparency = 0.6,
}

--------------------------------------------------------------------------------
-- HUD z-order
--------------------------------------------------------------------------------

UIConstants.ZOrder = {
    Background = 0,
    Board = 10,
    GarbageWarning = 50,
    ChainCounter = 60,
    MainMenu = 75,           -- player-facing landing screen, above HUD but below Tutorial / RoundBanner
    RoundBanner = 80,
    Tutorial = 90,
    ShopOverlay = 100,
    BlockedFlash = 110,
}

--------------------------------------------------------------------------------
-- Sizes / breakpoints
--------------------------------------------------------------------------------

UIConstants.Sizes = {
    MobileOpponentCupScale = 0.30,
    MinTouchTarget = 44,
    MinGarbageWarningRow = 24,
    MinSmallPearlPx = 20,
}

--------------------------------------------------------------------------------
-- Sparkle / particle spec (Day 3+ when pops actually fire)
--------------------------------------------------------------------------------

UIConstants.Sparkles = {
    CountMin = 3,
    CountMax = 5,
    RisePx = 24,
    Size = UDim2.fromOffset(8, 8),
    Colors = { Color3.fromRGB(255, 230, 180), Color3.fromRGB(255, 200, 220), Color3.fromRGB(255, 255, 255) },
}

return UIConstants
