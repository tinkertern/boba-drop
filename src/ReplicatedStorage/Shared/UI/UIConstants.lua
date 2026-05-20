local UIConstants = {}

UIConstants.Colors = {
    Brown = Color3.fromRGB(120, 75, 50),
    Pink = Color3.fromRGB(255, 180, 195),
    Green = Color3.fromRGB(130, 200, 120),
    White = Color3.fromRGB(245, 240, 230),
    Garbage = Color3.fromRGB(180, 200, 220),
    Background = Color3.fromRGB(30, 30, 40),
    ChainCounterText = Color3.fromRGB(255, 230, 140),
    GarbageWarning = Color3.fromRGB(255, 90, 90),
    Blocked = Color3.fromRGB(120, 200, 255),
}

UIConstants.Fonts = {
    HUD = Enum.Font.GothamBold,
    Score = Enum.Font.GothamBlack,
    Tutorial = Enum.Font.Gotham,
}

UIConstants.Durations = {
    PopTell = 0.25,
    GravitySettle = 0.30,
    ChainCounterPersist = 1.0,
    GarbageWarningLead = 0.5,
    BlockedFlash = 0.4,
}

-- BlockedFlash is intentionally rendered in a different screen region from
-- ChainCounter so its higher z-order does not visually collide with chain text.
UIConstants.ZOrder = {
    Background = 0,
    Board = 10,
    GarbageWarning = 50,
    ChainCounter = 60,
    RoundBanner = 80,
    Tutorial = 90,
    ShopOverlay = 100,
    BlockedFlash = 110,
}

UIConstants.Sizes = {
    MobileOpponentCupScale = 0.30,
    MinTouchTarget = 44,
    MinGarbageWarningRow = 24,
    MinSmallPearlPx = 20,
}

return UIConstants
