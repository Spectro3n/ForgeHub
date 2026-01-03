-- ============================================================================
-- FORGEHUB - AIMBOT SETTINGS v4.7 (SYNC VERSION)
-- Agora funciona como defaults + funções de sync
-- ============================================================================

local SettingsDefaults = {
    -- Modos Rage
    RageMode = false,
    UltraRageMode = false,
    GodRageMode = false,
    RageHeadOnly = true,
    
    -- Target Mode
    TargetMode = "FOV",
    AimOutsideFOV = false,
    AutoResetOnKill = true,
    MinAimHeightBelowCamera = 50,
    
    -- Aimbot Básico
    AimbotActive = false,
    AimbotUseKey = "MouseButton2",
    AimbotToggleKey = "Q",
    AimPart = "Head",
    AimMethod = "Camera",
    SmoothingFactor = 5,
    MaxDistance = 2000,
    IgnoreTeamAimbot = true,
    IgnoreTeam = true,
    VisibleCheck = true,
    MaxLockTime = 1.5,
    
    -- FOV
    UseAimbotFOV = true,
    AimbotFOV = 180,
    FOV = 180,
    ShowFOV = true,
    
    -- Prediction
    UsePrediction = true,
    PredictionMultiplier = 0.15,
    
    -- Smoothing
    UseAdaptiveSmoothing = true,
    UseDeadzone = true,
    DeadzoneRadius = 2,
    ShakeReduction = 0,
    
    -- Multi-Part
    MultiPartAim = false,
    AimParts = {"Head", "UpperTorso", "HumanoidRootPart"},
    IgnoreWalls = false,
    
    -- Trigger Bot
    TriggerBot = false,
    TriggerFOV = 50,
    TriggerDelay = 0.05,
    TriggerBurst = false,
    TriggerBurstCount = 3,
    TriggerHeadOnly = false,
    
    -- Auto Fire / Switch
    AutoFire = false,
    AutoSwitch = false,
    TargetSwitchDelay = 0.05,
    
    -- TP Bullet
    TPBullet = false,
    TPBulletPosition = "Behind",
    TPBulletDistance = 5,
    TPBulletHeight = 0,
    TPBulletReturn = true,
    TPBulletReturnDelay = 0.1,
    TPBulletMaxDistance = 500,
    TPBulletSafety = true,
}

-- ============================================================================
-- API
-- ============================================================================
local API = {}

-- Aplica defaults no Settings global
function API.ApplyDefaults(globalSettings)
    if not globalSettings then return end
    
    for key, value in pairs(SettingsDefaults) do
        if globalSettings[key] == nil then
            globalSettings[key] = value
        end
    end
    
    -- Sync aliases
    globalSettings.IgnoreTeam = globalSettings.IgnoreTeamAimbot
    globalSettings.FOV = globalSettings.AimbotFOV
end

function API.GetDefaults()
    return SettingsDefaults
end

-- ============================================================================
-- EXPORT
-- ============================================================================
return API