-- ============================================================================
-- FORGEHUB - TRIGGER MODULE v4.3
-- Decide SE deve atirar (não dispara diretamente)
-- ============================================================================

local Trigger = {
    Enabled = false,
    LastCheck = 0,
    LastTarget = nil,
    BurstActive = false,
    BurstCount = 0,
    
    -- Estado de decisão
    ShouldFire = false,
    FireReason = nil,
    TargetInCrosshair = nil,
}

-- ============================================================================
-- DEPENDENCIES (serão injetadas)
-- ============================================================================
local Utils = nil
local Settings = nil
local EventBus = nil
local Hooks = nil
local Players = nil
local LocalPlayer = nil
local UserInputService = nil

-- ============================================================================
-- CORE LOGIC
-- ============================================================================
function Trigger:GetTargetInCrosshair()
    local Camera = Utils.GetCamera()
    if not Camera then return nil, nil end
    
    local mousePos = UserInputService:GetMouseLocation()
    
    local triggerFOV = Settings.TriggerFOV or 50
    if Settings.GodRageMode then
        triggerFOV = triggerFOV * 5
    elseif Settings.UltraRageMode then
        triggerFOV = triggerFOV * 3
    elseif Settings.RageMode then
        triggerFOV = triggerFOV * 2
    end
    
    local triggerFOVSq = triggerFOV * triggerFOV
    local camPos = Camera.CFrame.Position
    
    local allPlayers = Players:GetPlayers()
    
    for _, player in ipairs(allPlayers) do
        if player == LocalPlayer then continue end
        
        local data = Utils.GetPlayerData(player)
        if not data or not data.isValid then continue end
        if data.humanoid and data.humanoid.Health <= 0 then continue end
        
        if Settings.IgnoreTeamAimbot and Utils.AreSameTeam(LocalPlayer, player) then
            continue
        end
        
        -- Determina qual parte verificar
        local targetPart
        if Settings.TriggerHeadOnly then
            local partCache = Utils.GetPartCache(player)
            targetPart = partCache and partCache.Head
        else
            local partCache = Utils.GetPartCache(player)
            targetPart = partCache and (partCache.Head or partCache.UpperTorso or partCache._anchor)
        end
        
        if not targetPart or not targetPart.Parent then continue end
        
        local screenPos, onScreen = Camera:WorldToViewportPoint(targetPart.Position)
        if not onScreen then continue end
        
        local distSq = Utils.GetScreenDistanceSquared(screenPos, mousePos)
        
        if distSq <= triggerFOVSq then
            -- Verifica visibilidade se necessário
            if Settings.VisibleCheck and not Settings.IgnoreWalls then
                Utils.RayParamsManager:Update(LocalPlayer, Camera)
                local rayParams = Utils.RayParamsManager:Get()
                
                local direction = targetPart.Position - camPos
                local ray = workspace:Raycast(camPos, direction, rayParams)
                
                if ray and ray.Instance then
                    if not ray.Instance:IsDescendantOf(data.model) then
                        continue
                    end
                end
            end
            
            return player, targetPart
        end
    end
    
    return nil, nil
end

function Trigger:CheckHitChance()
    local hitChance = Settings.TriggerHitChance or 100
    if hitChance >= 100 then return true end
    return Utils.RandomChance(hitChance)
end

function Trigger:ShouldStartBurst()
    if not Settings.TriggerBurst then return false end
    if self.BurstActive then return false end
    return true
end

function Trigger:Update()
    if not self.Enabled or not Settings.TriggerBot then 
        self.ShouldFire = false
        self.TargetInCrosshair = nil
        return 
    end
    
    local now = tick()
    local delay = Settings.TriggerDelay or 0.05
    
    if Settings.GodRageMode then
        delay = 0.01
    elseif Settings.UltraRageMode then
        delay = 0.02
    elseif Settings.RageMode then
        delay = 0.03
    end
    
    if now - self.LastCheck < delay then 
        return 
    end
    
    self.LastCheck = now
    
    local target, part = self:GetTargetInCrosshair()
    self.TargetInCrosshair = target
    
    if target and part then
        if self:CheckHitChance() then
            self.ShouldFire = true
            self.FireReason = "crosshair"
            self.LastTarget = target
            
            if Settings.TriggerBurst and not self.BurstActive then
                self.BurstActive = true
                self.BurstCount = 0
                
                if EventBus then
                    EventBus:Emit("trigger:burst_start")
                end
            end
            
            if EventBus then
                EventBus:Emit("trigger:fire")
            end
        else
            self.ShouldFire = false
            self.FireReason = "hit_chance_failed"
        end
    else
        self.ShouldFire = false
        self.FireReason = nil
        
        if self.BurstActive then
            self.BurstActive = false
            if EventBus then
                EventBus:Emit("trigger:burst_end")
            end
        end
    end
end

function Trigger:IncrementBurst()
    if not self.BurstActive then return false end
    
    self.BurstCount = self.BurstCount + 1
    
    if self.BurstCount >= (Settings.TriggerBurstCount or 3) then
        self.BurstActive = false
        self.ShouldFire = false
        
        if EventBus then
            EventBus:Emit("trigger:burst_end")
        end
        
        return false
    end
    
    return true
end

function Trigger:ConsumeFire()
    local shouldFire = self.ShouldFire
    
    if Settings.TriggerBurst then
        if not self:IncrementBurst() then
            self.ShouldFire = false
        end
    else
        self.ShouldFire = false
    end
    
    return shouldFire
end

-- ============================================================================
-- ENABLE/DISABLE
-- ============================================================================
function Trigger:Enable()
    self.Enabled = true
end

function Trigger:Disable()
    self.Enabled = false
    self.ShouldFire = false
    self.BurstActive = false
    self.BurstCount = 0
    self.TargetInCrosshair = nil
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================
function Trigger:Initialize(dependencies)
    Utils = dependencies.Utils
    Settings = dependencies.Settings
    EventBus = dependencies.EventBus
    Hooks = dependencies.Hooks
    Players = dependencies.Players
    LocalPlayer = dependencies.LocalPlayer
    UserInputService = dependencies.UserInputService
    
    return true
end

-- ============================================================================
-- GETTERS
-- ============================================================================
function Trigger:GetShouldFire()
    return self.ShouldFire
end

function Trigger:GetTarget()
    return self.TargetInCrosshair
end

function Trigger:IsBurstActive()
    return self.BurstActive
end

-- ============================================================================
-- DEBUG
-- ============================================================================
function Trigger:Debug()
    print("\n═══════════ TRIGGER DEBUG ═══════════")
    print("Enabled: " .. tostring(self.Enabled))
    print("ShouldFire: " .. tostring(self.ShouldFire))
    print("FireReason: " .. tostring(self.FireReason))
    print("TargetInCrosshair: " .. (self.TargetInCrosshair and self.TargetInCrosshair.Name or "None"))
    print("BurstActive: " .. tostring(self.BurstActive))
    print("BurstCount: " .. tostring(self.BurstCount))
    print("═══════════════════════════════════════\n")
end

return Trigger