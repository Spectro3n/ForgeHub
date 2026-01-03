-- ============================================================================
-- FORGEHUB - AIMBOT SETTINGS v4.6
-- Atualizado com TP Bullet e configurações modulares
-- ============================================================================

local Settings = {}

-- ============================================================================
-- MODOS DE RAGE
-- ============================================================================
Settings.RageMode = false
Settings.UltraRageMode = false
Settings.GodRageMode = false
Settings.RageHeadOnly = true             -- Rage sempre mira na cabeça

-- ============================================================================
-- TARGET MODE
-- ============================================================================
Settings.TargetMode = "FOV"              -- "FOV" ou "Closest"
Settings.AimOutsideFOV = false           -- Permite mirar fora do FOV
Settings.AutoResetOnKill = true          -- Reset automático após kill
Settings.MinAimHeightBelowCamera = 50    -- Altura mínima abaixo da câmera

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
Settings.IgnoreTeam = true               -- Alias
Settings.VisibleCheck = true
Settings.MaxLockTime = 1.5
Settings.UpdateRate = 0
Settings.ThreadedAim = true
Settings.RestoreCameraOnStop = false

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
Settings.SwitchDelay = 0.1
Settings.InstantKill = false

-- ============================================================================
-- LOCK
-- ============================================================================
Settings.LockImprovementThreshold = 0.8
Settings.ShowTargetIndicator = true

-- ============================================================================
-- TP BULLET (NOVO)
-- ============================================================================
Settings.TPBullet = false
Settings.TPBulletPosition = "Behind"     -- "Behind", "Above", "Side", "Front", "Custom"
Settings.TPBulletDistance = 5
Settings.TPBulletHeight = 0
Settings.TPBulletReturn = true           -- Retornar após tiro
Settings.TPBulletReturnDelay = 0.1
Settings.TPBulletCooldown = 0.15
Settings.TPBulletMaxDistance = 500
Settings.TPBulletSafety = true           -- Verificação de segurança
Settings.TPBulletCustomOffset = Vector3.new(0, 0, -5)

-- ============================================================================
-- ALIASES (Compatibilidade)
-- ============================================================================
Settings.EnhancedMode = false            -- Alias para RageMode
Settings.UltraMode = false               -- Alias para UltraRageMode
Settings.MaxMode = false                 -- Alias para GodRageMode
Settings.HeadOnly = false                -- Alias para RageHeadOnly

-- ============================================================================
-- FUNÇÕES DE SYNC
-- ============================================================================
function Settings:SyncAliases()
    -- Sincroniza aliases bidirecionalmente
    self.EnhancedMode = self.RageMode
    self.UltraMode = self.UltraRageMode
    self.MaxMode = self.GodRageMode
    self.HeadOnly = self.RageHeadOnly
    self.IgnoreTeam = self.IgnoreTeamAimbot
end

function Settings:MergeWith(globalSettings)
    if not globalSettings then return end
    
    for key, value in pairs(self) do
        if type(value) ~= "function" then
            if globalSettings[key] == nil then
                globalSettings[key] = value
            end
        end
    end
    
    self:SyncAliases()
    return globalSettings
end

function Settings:SyncFrom(globalSettings)
    if not globalSettings then return end
    
    for key, value in pairs(globalSettings) do
        if self[key] ~= nil and type(self[key]) ~= "function" then
            self[key] = value
        end
    end
    
    self:SyncAliases()
end

-- ============================================================================
-- API DE CONFIGURAÇÃO
-- ============================================================================
local API = {}

function API:SetRageMode(enabled)
    Settings.RageMode = enabled
    Settings.EnhancedMode = enabled
    if not enabled then
        Settings.UltraRageMode = false
        Settings.GodRageMode = false
        Settings.UltraMode = false
        Settings.MaxMode = false
    end
end

function API:SetUltraRageMode(enabled)
    Settings.UltraRageMode = enabled
    Settings.UltraMode = enabled
    if enabled then
        Settings.RageMode = true
        Settings.EnhancedMode = true
    end
    if not enabled then
        Settings.GodRageMode = false
        Settings.MaxMode = false
    end
end

function API:SetGodRageMode(enabled)
    Settings.GodRageMode = enabled
    Settings.MaxMode = enabled
    if enabled then
        Settings.RageMode = true
        Settings.UltraRageMode = true
        Settings.EnhancedMode = true
        Settings.UltraMode = true
    end
end

function API:SetTPBullet(enabled)
    Settings.TPBullet = enabled
end

function API:SetTPBulletPosition(position)
    local valid = {"Behind", "Above", "Side", "Front", "Custom"}
    for _, v in ipairs(valid) do
        if v == position then
            Settings.TPBulletPosition = position
            return true
        end
    end
    return false
end

function API:GetRageLevel()
    if Settings.GodRageMode then return 3 end
    if Settings.UltraRageMode then return 2 end
    if Settings.RageMode then return 1 end
    return 0
end

function API:IsRageActive()
    return Settings.RageMode or Settings.UltraRageMode or Settings.GodRageMode
end

-- ============================================================================
-- EXPORT
-- ============================================================================
return {
    Settings = Settings,
    API = API,
}