-- ============================================================================
-- FORGEHUB - TP BULLET MODULE v1.0
-- Teleporta o jogador para posição relativa ao alvo - Adaptado ao Settings
-- ============================================================================

local TPBullet = {
    _init = false,
    _active = false,
    _lastTP = 0,
    _originalPos = nil,
    _teleported = false,
}

-- ============================================================================
-- SERVICES
-- ============================================================================
local ServiceCache = {}

local function GetService(name)
    if ServiceCache[name] then return ServiceCache[name] end
    local success, service = pcall(function() return game:GetService(name) end)
    if success and service then ServiceCache[name] = service end
    return service
end

local function GetPlayers() return GetService("Players") end

-- ============================================================================
-- DEPENDENCIES
-- ============================================================================
local Utils = nil
local Settings = nil
local EventBus = nil
local Hooks = nil
local LocalPlayer = nil
local BaseAimbot = nil
local RageModule = nil

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================
local function GetLocalCharacter()
    if not LocalPlayer then return nil end
    return LocalPlayer.Character
end

local function GetLocalHRP()
    local char = GetLocalCharacter()
    if not char then return nil end
    return char:FindFirstChild("HumanoidRootPart")
end

local function IsPositionSafe(position)
    if not Settings.TPBulletSafety then return true end
    
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {GetLocalCharacter()}
    
    local result = workspace:Raycast(position + Vector3.new(0, 3, 0), Vector3.new(0, -10, 0), params)
    
    if not result then return false end
    
    local groundDist = (position - result.Position).Magnitude
    if groundDist > 15 then return false end
    
    return true
end

-- ============================================================================
-- POSITION CALCULATION
-- ============================================================================
function TPBullet:CalculateTPPosition(targetPart)
    if not targetPart or not targetPart.Parent then return nil end
    
    local targetPos = targetPart.Position
    local targetCFrame = targetPart.CFrame
    
    local hrp = GetLocalHRP()
    if not hrp then return nil end
    
    local myPos = hrp.Position
    
    -- Usar settings
    local position = Settings.TPBulletPosition or "Behind"
    local distance = Settings.TPBulletDistance or 5
    local height = Settings.TPBulletHeight or 0
    
    local offset = Vector3.zero
    
    if position == "Behind" then
        local targetLook = targetCFrame.LookVector
        offset = -targetLook * distance
        offset = offset + Vector3.new(0, height, 0)
        
    elseif position == "Above" then
        offset = Vector3.new(0, distance, 0)
        
    elseif position == "Side" then
        local targetRight = targetCFrame.RightVector
        offset = targetRight * distance
        offset = offset + Vector3.new(0, height, 0)
        
    elseif position == "Front" then
        local targetLook = targetCFrame.LookVector
        offset = targetLook * distance
        offset = offset + Vector3.new(0, height, 0)
        
    elseif position == "Custom" then
        offset = Settings.TPBulletCustomOffset or Vector3.new(0, 0, -5)
        
    else
        local targetLook = targetCFrame.LookVector
        offset = -targetLook * distance
    end
    
    local finalPos = targetPos + offset
    
    -- Verificar distância máxima
    local maxDist = Settings.TPBulletMaxDistance or 500
    local tpDist = (finalPos - myPos).Magnitude
    if tpDist > maxDist then
        return nil
    end
    
    -- Ajustar altura para o chão
    if position ~= "Above" then
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = {GetLocalCharacter(), targetPart.Parent}
        
        local groundRay = workspace:Raycast(finalPos + Vector3.new(0, 5, 0), Vector3.new(0, -20, 0), params)
        if groundRay then
            finalPos = groundRay.Position + Vector3.new(0, 3, 0)
        end
    end
    
    return finalPos
end

-- ============================================================================
-- TELEPORT FUNCTIONS
-- ============================================================================
function TPBullet:TeleportTo(position)
    if not position then return false end
    
    local hrp = GetLocalHRP()
    if not hrp then return false end
    
    -- Verificar cooldown
    local cooldown = Settings.TPBulletCooldown or 0.15
    local now = tick()
    if now - self._lastTP < cooldown then
        return false
    end
    
    -- Verificar segurança
    if Settings.TPBulletSafety and not IsPositionSafe(position) then
        return false
    end
    
    -- Salvar posição original
    if not self._teleported then
        self._originalPos = hrp.Position
    end
    
    -- Teleportar
    local success = pcall(function()
        hrp.CFrame = CFrame.new(position)
    end)
    
    if success then
        self._lastTP = now
        self._teleported = true
        
        if EventBus then
            pcall(function() EventBus:Emit("tpbullet:teleported", position) end)
        end
    end
    
    return success
end

function TPBullet:ReturnToOriginal()
    if not self._teleported or not self._originalPos then return false end
    
    local hrp = GetLocalHRP()
    if not hrp then return false end
    
    local success = pcall(function()
        hrp.CFrame = CFrame.new(self._originalPos)
    end)
    
    if success then
        self._teleported = false
        self._originalPos = nil
        
        if EventBus then
            pcall(function() EventBus:Emit("tpbullet:returned") end)
        end
    end
    
    return success
end

-- ============================================================================
-- TARGET ACQUISITION
-- ============================================================================
function TPBullet:GetCurrentTarget()
    -- Tentar pegar alvo do Rage primeiro
    if RageModule and RageModule:IsActive() and RageModule.GetCurrentTarget then
        local target = RageModule:GetCurrentTarget()
        if target then return target end
    end
    
    -- Fallback para aimbot legit
    if BaseAimbot and BaseAimbot.GetCurrentTarget then
        return BaseAimbot:GetCurrentTarget()
    end
    
    return nil
end

function TPBullet:GetTargetPart(target)
    if not target then return nil end
    
    local data = Utils.GetPlayerData(target)
    if not data or not data.model then return nil end
    
    local hrp = data.model:FindFirstChild("HumanoidRootPart")
    if hrp and hrp.Parent then return hrp end
    
    return data.anchor
end

-- ============================================================================
-- MAIN UPDATE
-- ============================================================================
function TPBullet:Update(mouseHold)
    if not self._init then return end
    if not Settings.TPBullet then return end
    
    -- Verificar se aimbot está ativo
    if not Settings.AimbotActive or not mouseHold then
        -- Retornar à posição original se configurado
        if self._teleported and Settings.TPBulletReturn then
            local delay = Settings.TPBulletReturnDelay or 0.1
            task.delay(delay, function()
                self:ReturnToOriginal()
            end)
        end
        self._active = false
        return
    end
    
    self._active = true
    
    -- Obter alvo atual
    local target = self:GetCurrentTarget()
    if not target then
        if self._teleported and Settings.TPBulletReturn then
            self:ReturnToOriginal()
        end
        return
    end
    
    -- Verificar se alvo está vivo
    local data = Utils.GetPlayerData(target)
    if not data or not data.isValid then
        if self._teleported and Settings.TPBulletReturn then
            self:ReturnToOriginal()
        end
        return
    end
    
    if data.humanoid then
        local s, h = pcall(function() return data.humanoid.Health end)
        if s and h <= 0 then
            if self._teleported and Settings.TPBulletReturn then
                self:ReturnToOriginal()
            end
            return
        end
    end
    
    -- Calcular posição de TP
    local targetPart = self:GetTargetPart(target)
    if not targetPart then return end
    
    local tpPos = self:CalculateTPPosition(targetPart)
    if not tpPos then return end
    
    -- Executar teleporte
    self:TeleportTo(tpPos)
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================
function TPBullet:Enable()
    Settings.TPBullet = true
    if EventBus then
        pcall(function() EventBus:Emit("tpbullet:enabled") end)
    end
end

function TPBullet:Disable()
    Settings.TPBullet = false
    if self._teleported then
        self:ReturnToOriginal()
    end
    self._active = false
    if EventBus then
        pcall(function() EventBus:Emit("tpbullet:disabled") end)
    end
end

function TPBullet:Toggle(enabled)
    if enabled then
        self:Enable()
    else
        self:Disable()
    end
end

function TPBullet:SetPosition(position)
    local valid = {"Behind", "Above", "Side", "Front", "Custom"}
    for _, v in ipairs(valid) do
        if v == position then
            Settings.TPBulletPosition = position
            return true
        end
    end
    return false
end

function TPBullet:SetDistance(dist)
    Settings.TPBulletDistance = math.clamp(dist, 1, 50)
end

function TPBullet:SetHeight(height)
    Settings.TPBulletHeight = math.clamp(height, -10, 20)
end

function TPBullet:SetCustomOffset(offset)
    if typeof(offset) == "Vector3" then
        Settings.TPBulletCustomOffset = offset
    end
end

function TPBullet:SetReturnAfterShot(enabled)
    Settings.TPBulletReturn = enabled
end

function TPBullet:SetReturnDelay(delay)
    Settings.TPBulletReturnDelay = math.clamp(delay, 0, 1)
end

function TPBullet:SetCooldown(cd)
    Settings.TPBulletCooldown = math.clamp(cd, 0.05, 1)
end

function TPBullet:SetMaxDistance(dist)
    Settings.TPBulletMaxDistance = math.clamp(dist, 50, 2000)
end

function TPBullet:SetSafetyCheck(enabled)
    Settings.TPBulletSafety = enabled
end

function TPBullet:ForceReturn()
    return self:ReturnToOriginal()
end

function TPBullet:ForceReset()
    self._active = false
    self._teleported = false
    self._originalPos = nil
    self._lastTP = 0
end

function TPBullet:IsActive()
    return self._active
end

function TPBullet:IsTeleported()
    return self._teleported
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================
function TPBullet:Initialize(deps)
    if self._init then return self end
    
    if not deps then
        warn("[TPBullet] Missing dependencies")
        return nil
    end
    
    Utils = deps.Utils
    Settings = deps.Settings
    EventBus = deps.EventBus
    Hooks = deps.Hooks
    LocalPlayer = deps.LocalPlayer
    BaseAimbot = deps.Aimbot
    RageModule = deps.Rage
    
    if not Utils then
        warn("[TPBullet] Utils not available")
        return nil
    end
    
    self._init = true
    return self
end

-- ============================================================================
-- EXPORT
-- ============================================================================
return {
    TPBullet = TPBullet,
    Type = "TPBullet",
}