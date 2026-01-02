-- ============================================================================
-- FORGEHUB - AIMBOT SETTINGS v4.3
-- ============================================================================

local Settings = {}

-- ============================================================================
-- MODOS DE RAGE
-- ============================================================================
Settings.RageMode = false
Settings.UltraRageMode = false
Settings.GodRageMode = false

-- ============================================================================
-- TARGET MODE (NOVO)
-- ============================================================================
Settings.TargetMode = "FOV"              -- "FOV" ou "Closest"
Settings.AimOutsideFOV = false           -- Permite mirar fora do FOV
Settings.AutoResetOnKill = true          -- Reset automático após kill
Settings.MinAimHeightBelowCamera = 50    -- Altura mínima abaixo da câmera (evita chão)

-- ============================================================================
-- AIMBOT BÁSICO
-- ============================================================================
Settings.AimbotActive = false
Settings.AimbotUseKey = "MouseButton2"
Settings.AimbotToggleKey = "Q"
Settings.AimPart = "Head"
Settings.AimMethod = "Camera"            -- "Camera" ou "MouseMoveRel"
Settings.SmoothingFactor = 5
Settings.MaxDistance = 2000
Settings.IgnoreTeamAimbot = true
Settings.VisibleCheck = true
Settings.MaxLockTime = 1.5
Settings.UpdateRate = 0                  -- 0 = sem limite
Settings.ThreadedAim = true

-- ============================================================================
-- FOV
-- ============================================================================
Settings.UseAimbotFOV = true
Settings.AimbotFOV = 180
Settings.FOV = 180
Settings.ShowFOV = true
Settings.FOVColor = Color3.fromRGB(255, 255, 255)

-- ============================================================================
-- PREDICTION
-- ============================================================================
Settings.UsePrediction = true
Settings.PredictionMultiplier = 0.15

-- ============================================================================
-- SMOOTHING & DEADZONE
-- ============================================================================
Settings.UseAdaptiveSmoothing = true
Settings.UseDeadzone = true
Settings.DeadzoneRadius = 2
Settings.ShakeReduction = 0

-- ============================================================================
-- MULTI-PART AIM
-- ============================================================================
Settings.MultiPartAim = false
Settings.AimParts = {"Head", "UpperTorso", "HumanoidRootPart"}
Settings.IgnoreWalls = false
Settings.AntiAimDetection = false

-- ============================================================================
-- SILENT AIM
-- ============================================================================
Settings.SilentAim = false
Settings.SilentFOV = 500
Settings.SilentHitChance = 100
Settings.SilentHeadshotChance = 100
Settings.SilentPrediction = true

-- ============================================================================
-- MAGIC BULLET
-- ============================================================================
Settings.MagicBullet = false
Settings.MagicBulletMethod = "Teleport"  -- "Teleport", "Curve", "Phase"
Settings.MagicBulletSpeed = 9999
Settings.MagicBulletIgnoreWalls = true
Settings.MagicBulletAutoHit = true

-- ============================================================================
-- TRIGGER BOT
-- ============================================================================
Settings.TriggerBot = false
Settings.TriggerFOV = 50
Settings.TriggerDelay = 0.05
Settings.TriggerBurst = false
Settings.TriggerBurstCount = 3
Settings.TriggerHeadOnly = false
Settings.TriggerHitChance = 100

-- ============================================================================
-- AUTO FIRE / SWITCH
-- ============================================================================
Settings.AutoFire = false
Settings.AutoSwitch = false
Settings.TargetSwitchDelay = 0.05
Settings.InstantKill = false

-- ============================================================================
-- LOCK
-- ============================================================================
Settings.LockImprovementThreshold = 0.8
Settings.ShowTargetIndicator = true

-- ============================================================================
-- FUNÇÃO DE MERGE COM SETTINGS GLOBAIS
-- ============================================================================
function Settings:MergeWith(globalSettings)
    if not globalSettings then return end
    
    for key, value in pairs(self) do
        if type(value) ~= "function" then
            if globalSettings[key] == nil then
                globalSettings[key] = value
            end
        end
    end
    
    return globalSettings
end

function Settings:SyncFrom(globalSettings)
    if not globalSettings then return end
    
    for key, value in pairs(globalSettings) do
        if self[key] ~= nil and type(self[key]) ~= "function" then
            self[key] = value
        end
    end
end

return Settings