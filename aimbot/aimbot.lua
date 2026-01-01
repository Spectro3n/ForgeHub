-- ============================================================================
-- FORGEHUB - AIMBOT MODULE v4.0 (ULTRA RAGE MAXIMUM POWER EDITION)
-- ============================================================================

local Core = _G.ForgeHubCore
if not Core then
    error("ForgeHubCore não encontrado! Carregue main.lua primeiro.")
end

-- ============================================================================
-- IMPORTS
-- ============================================================================
local Players = Core.Players
local RunService = Core.RunService
local UserInputService = Core.UserInputService
local Workspace = Core.Workspace
local LocalPlayer = Core.LocalPlayer
local Settings = Core.Settings
local State = Core.State
local Notify = Core.Notify

-- ============================================================================
-- ULTRA RAGE SETTINGS (Configurações Extremas)
-- ============================================================================
-- Modos de Rage
Settings.RageMode = Settings.RageMode or false
Settings.UltraRageMode = Settings.UltraRageMode or false
Settings.GodRageMode = Settings.GodRageMode or false -- NOVO: Modo Deus

-- Silent Aim Settings
Settings.SilentAim = Settings.SilentAim or false
Settings.SilentFOV = Settings.SilentFOV or 500 -- FOV do Silent
Settings.SilentHitChance = Settings.SilentHitChance or 100 -- % de chance de acerto
Settings.SilentHeadshotChance = Settings.SilentHeadshotChance or 100 -- % headshot
Settings.SilentPrediction = Settings.SilentPrediction or true

-- Magic Bullet Settings
Settings.MagicBullet = Settings.MagicBullet or false
Settings.MagicBulletMethod = Settings.MagicBulletMethod or "Teleport" -- Teleport, Curve, Phase
Settings.MagicBulletSpeed = Settings.MagicBulletSpeed or 9999
Settings.MagicBulletIgnoreWalls = Settings.MagicBulletIgnoreWalls or true
Settings.MagicBulletAutoHit = Settings.MagicBulletAutoHit or true

-- Trigger Bot Settings
Settings.TriggerBot = Settings.TriggerBot or false
Settings.TriggerFOV = Settings.TriggerFOV or 50 -- FOV do Trigger
Settings.TriggerDelay = Settings.TriggerDelay or 0.05
Settings.TriggerBurst = Settings.TriggerBurst or false
Settings.TriggerBurstCount = Settings.TriggerBurstCount or 3
Settings.TriggerHeadOnly = Settings.TriggerHeadOnly or false

-- Auto Fire/Switch
Settings.AutoFire = Settings.AutoFire or false
Settings.AutoSwitch = Settings.AutoSwitch or false
Settings.TargetSwitchDelay = Settings.TargetSwitchDelay or 0.05
Settings.InstantKill = Settings.InstantKill or false

-- Aim Settings
Settings.MultiPartAim = Settings.MultiPartAim or false
Settings.AimParts = Settings.AimParts or {"Head", "UpperTorso", "HumanoidRootPart"}
Settings.IgnoreWalls = Settings.IgnoreWalls or false
Settings.AntiAimDetection = Settings.AntiAimDetection or false
Settings.ShakeReduction = Settings.ShakeReduction or 0
Settings.AimbotFOV = Settings.AimbotFOV or 180
Settings.MaxDistance = Settings.MaxDistance or 2000

-- Performance
Settings.UpdateRate = Settings.UpdateRate or 0 -- 0 = máximo
Settings.ThreadedAim = Settings.ThreadedAim or true

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================
local function GetCamera()
    return workspace.CurrentCamera
end

local function SafeCall(func, name)
    local success, err = pcall(func)
    if not success then
        warn("[Aimbot] Erro em " .. (name or "unknown") .. ": " .. tostring(err))
    end
    return success, err
end

local function Clamp(value, min, max)
    return math.max(min, math.min(max, value))
end

local function RandomChance(percent)
    return math.random(1, 100) <= percent
end

-- ============================================================================
-- RAYCAST PARAMS
-- ============================================================================
local RayParams = RaycastParams.new()
RayParams.FilterType = Enum.RaycastFilterType.Exclude
RayParams.FilterDescendantsInstances = {}

local function UpdateRayParams()
    local filter = {GetCamera()}
    if LocalPlayer.Character then
        table.insert(filter, LocalPlayer.Character)
    end
    RayParams.FilterDescendantsInstances = filter
end

LocalPlayer.CharacterAdded:Connect(function()
    task.wait(0.1)
    UpdateRayParams()
end)
UpdateRayParams()

-- ============================================================================
-- VISIBILITY CACHE (Otimizado)
-- ============================================================================
local VisibilityCache = {
    Data = {},
    Frame = 0,
    MaxAge = 1,
}

function VisibilityCache:NextFrame()
    self.Frame = self.Frame + 1
    if self.Frame % 3 == 0 then
        local toRemove = {}
        for key, data in pairs(self.Data) do
            if self.Frame - data.frame > self.MaxAge then
                table.insert(toRemove, key)
            end
        end
        for _, key in ipairs(toRemove) do
            self.Data[key] = nil
        end
    end
end

function VisibilityCache:Get(player)
    local data = self.Data[player]
    if data and (self.Frame - data.frame) <= self.MaxAge then
        return data.visible, data.part, true
    end
    return nil, nil, false
end

function VisibilityCache:Set(player, visible, part)
    self.Data[player] = {visible = visible, part = part, frame = self.Frame}
end

function VisibilityCache:Clear()
    self.Data = {}
    self.Frame = 0
end

-- ============================================================================
-- PLAYER DATA HELPER (Otimizado)
-- ============================================================================
local PlayerDataCache = {}
local LastCacheUpdate = 0

local function GetPlayerData(player)
    if not player then return nil end
    
    local now = tick()
    local cached = PlayerDataCache[player]
    if cached and (now - cached.time) < 0.1 then
        return cached.data
    end
    
    local SemanticEngine = Core.SemanticEngine
    if SemanticEngine and SemanticEngine.GetCachedPlayerData then
        local data = SemanticEngine:GetCachedPlayerData(player)
        if data and data.isValid then 
            PlayerDataCache[player] = {data = data, time = now}
            return data 
        end
    end
    
    local character = player.Character
    if not character then return nil end
    
    local anchor = character:FindFirstChild("HumanoidRootPart")
                or character:FindFirstChild("Torso")
                or character:FindFirstChild("Head")
    
    if not anchor or not anchor:IsDescendantOf(workspace) then return nil end
    
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local data = {
        isValid = true,
        model = character,
        anchor = anchor,
        humanoid = humanoid,
        health = humanoid and humanoid.Health or 100,
        maxHealth = humanoid and humanoid.MaxHealth or 100,
    }
    
    PlayerDataCache[player] = {data = data, time = now}
    return data
end

-- Limpa cache de players que saíram
Players.PlayerRemoving:Connect(function(player)
    PlayerDataCache[player] = nil
end)

-- ============================================================================
-- TEAM CHECK
-- ============================================================================
local function AreSameTeam(player1, player2)
    if not player1 or not player2 then return false end
    
    local SemanticEngine = Core.SemanticEngine
    if SemanticEngine and SemanticEngine.AreSameTeam then
        local success, result = pcall(function()
            return SemanticEngine:AreSameTeam(player1, player2)
        end)
        if success then return result end
    end
    
    if player1.Team and player2.Team then
        return player1.Team == player2.Team
    end
    
    return false
end

-- ============================================================================
-- GET AIM PART (ULTRA VERSION)
-- ============================================================================
local PartPriorityMap = {
    Head = 1,
    UpperTorso = 2,
    Torso = 2,
    HumanoidRootPart = 3,
    LowerTorso = 4,
    LeftUpperArm = 5,
    RightUpperArm = 5,
    LeftUpperLeg = 6,
    RightUpperLeg = 6,
}

local function GetAimPart(player, partName)
    local data = GetPlayerData(player)
    if not data or not data.model then return nil end
    
    local model = data.model
    partName = partName or "Head"
    
    if type(partName) == "table" then
        partName = partName[1] or "Head"
    end
    
    local partMap = {
        Head = {"Head"},
        Torso = {"UpperTorso", "Torso"},
        Root = {"HumanoidRootPart"},
        HumanoidRootPart = {"HumanoidRootPart"},
        UpperTorso = {"UpperTorso", "Torso"},
        LowerTorso = {"LowerTorso", "Torso"},
        LeftArm = {"LeftUpperArm", "Left Arm"},
        RightArm = {"RightUpperArm", "Right Arm"},
        LeftLeg = {"LeftUpperLeg", "Left Leg"},
        RightLeg = {"RightUpperLeg", "Right Leg"},
        Neck = {"Neck", "Head"},
        Chest = {"UpperTorso", "Torso"},
    }
    
    local candidates = partMap[partName] or {partName}
    
    for _, name in ipairs(candidates) do
        local part = model:FindFirstChild(name, true)
        if part and part:IsA("BasePart") then
            return part
        end
    end
    
    return data.anchor
end

-- ============================================================================
-- MULTI-PART AIM SYSTEM (RAGE)
-- ============================================================================
local function GetAllAimParts(player)
    local data = GetPlayerData(player)
    if not data or not data.model then return {} end
    
    local parts = {}
    local model = data.model
    
    local partsToFind = {
        "Head", "UpperTorso", "LowerTorso", "HumanoidRootPart",
        "LeftUpperArm", "RightUpperArm", "LeftUpperLeg", "RightUpperLeg",
        "Torso", "Left Arm", "Right Arm", "Left Leg", "Right Leg"
    }
    
    for _, partName in ipairs(partsToFind) do
        local part = model:FindFirstChild(partName, true)
        if part and part:IsA("BasePart") then
            table.insert(parts, {
                part = part,
                name = partName,
                priority = PartPriorityMap[partName] or 10
            })
        end
    end
    
    -- Ordena por prioridade
    table.sort(parts, function(a, b) return a.priority < b.priority end)
    
    return parts
end

-- Encontra a melhor parte visível
local function GetBestAimPart(player, ignoreFOV)
    local data = GetPlayerData(player)
    if not data or not data.model then return nil end
    
    -- Em Ultra/God Rage, sempre retorna a cabeça primeiro
    if Settings.GodRageMode or Settings.UltraRageMode then
        local head = GetAimPart(player, "Head")
        if head then return head end
    end
    
    if not Settings.MultiPartAim then
        return GetAimPart(player, Settings.AimPart)
    end
    
    local Camera = GetCamera()
    local camPos = Camera.CFrame.Position
    local mousePos = UserInputService:GetMouseLocation()
    
    local bestPart = nil
    local bestScore = math.huge
    
    local allParts = GetAllAimParts(player)
    
    for _, partData in ipairs(allParts) do
        local part = partData.part
        local screenPos, onScreen = Camera:WorldToViewportPoint(part.Position)
        
        if onScreen or Settings.GodRageMode then
            local distToMouse = onScreen and (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude or 9999
            
            -- Score baseado em prioridade e distância
            local score = distToMouse + (partData.priority * 20)
            
            -- Prioriza cabeça fortemente
            if partData.name == "Head" then
                score = score * 0.3
            end
            
            if score < bestScore then
                -- Verifica visibilidade se necessário
                local visible = true
                if not Settings.IgnoreWalls and not Settings.MagicBullet then
                    UpdateRayParams()
                    local direction = part.Position - camPos
                    local ray = Workspace:Raycast(camPos, direction, RayParams)
                    if ray and ray.Instance and not ray.Instance:IsDescendantOf(data.model) then
                        visible = false
                    end
                end
                
                if visible or Settings.GodRageMode then
                    bestScore = score
                    bestPart = part
                end
            end
        end
    end
    
    return bestPart or GetAimPart(player, Settings.AimPart)
end

-- ============================================================================
-- ULTRA PREDICTION SYSTEM
-- ============================================================================
local PredictionHistory = {}
local MAX_HISTORY = 12

local function UpdatePredictionHistory(player, position, velocity)
    if not PredictionHistory[player] then
        PredictionHistory[player] = {positions = {}, velocities = {}}
    end
    
    local history = PredictionHistory[player]
    local now = tick()
    
    table.insert(history.positions, {position = position, time = now})
    if velocity then
        table.insert(history.velocities, {velocity = velocity, time = now})
    end
    
    while #history.positions > MAX_HISTORY do
        table.remove(history.positions, 1)
    end
    while #history.velocities > MAX_HISTORY do
        table.remove(history.velocities, 1)
    end
end

local function CalculateVelocity(player, anchor)
    -- Método 1: Propriedade direta
    if anchor.AssemblyLinearVelocity then
        local vel = anchor.AssemblyLinearVelocity
        if vel.Magnitude > 0.5 then return vel end
    end
    
    if anchor.Velocity then
        local vel = anchor.Velocity
        if vel.Magnitude > 0.5 then return vel end
    end
    
    -- Método 2: Cálculo por histórico
    local history = PredictionHistory[player]
    if history and #history.positions >= 2 then
        local newest = history.positions[#history.positions]
        local oldest = history.positions[1]
        local deltaTime = newest.time - oldest.time
        
        if deltaTime > 0.02 then
            local deltaPos = newest.position - oldest.position
            return deltaPos / deltaTime
        end
    end
    
    return Vector3.zero
end

local function CalculateAcceleration(player)
    local history = PredictionHistory[player]
    if not history or #history.velocities < 3 then
        return Vector3.zero
    end
    
    local newest = history.velocities[#history.velocities]
    local oldest = history.velocities[#history.velocities - 2]
    local deltaTime = newest.time - oldest.time
    
    if deltaTime > 0.02 then
        local deltaVel = newest.velocity - oldest.velocity
        return deltaVel / deltaTime
    end
    
    return Vector3.zero
end

local function PredictPosition(player, targetPart)
    if not targetPart then return nil end
    
    local basePos = targetPart.Position
    
    if not Settings.UsePrediction then
        return basePos
    end
    
    local data = GetPlayerData(player)
    if not data or not data.anchor then
        return basePos
    end
    
    local velocity = CalculateVelocity(player, data.anchor)
    local acceleration = Vector3.zero
    
    -- Em God Rage, usa predição com aceleração
    if Settings.GodRageMode then
        acceleration = CalculateAcceleration(player)
    end
    
    -- Reduz velocidade vertical para evitar over-prediction
    local yMultiplier = 0.4
    if Settings.GodRageMode then
        yMultiplier = 0.6
    elseif Settings.UltraRageMode then
        yMultiplier = 0.5
    end
    
    if velocity.Y > 0 then
        velocity = Vector3.new(velocity.X, velocity.Y * yMultiplier, velocity.Z)
    end
    
    local Camera = GetCamera()
    local distance = (targetPart.Position - Camera.CFrame.Position).Magnitude
    
    -- Tempo de resposta baseado no modo
    local timeDiv = 800
    if Settings.GodRageMode then
        timeDiv = 400
    elseif Settings.UltraRageMode then
        timeDiv = 500
    elseif Settings.RageMode then
        timeDiv = 600
    end
    
    local timeToTarget = Clamp(distance / timeDiv, 0.01, 0.35)
    
    -- Multiplicador de predição
    local multiplier = Settings.PredictionMultiplier or 0.15
    if Settings.GodRageMode then
        multiplier = multiplier * 2.0
    elseif Settings.UltraRageMode then
        multiplier = multiplier * 1.6
    elseif Settings.RageMode then
        multiplier = multiplier * 1.3
    end
    
    -- Fórmula de predição com aceleração
    local predictedPos = basePos + (velocity * multiplier * timeToTarget)
    
    if acceleration.Magnitude > 0.1 then
        predictedPos = predictedPos + (acceleration * 0.5 * timeToTarget * timeToTarget)
    end
    
    UpdatePredictionHistory(player, data.anchor.Position, velocity)
    
    return predictedPos
end

-- ============================================================================
-- VISIBILITY CHECK (RAGE CAN IGNORE)
-- ============================================================================
local function IsVisible(player, targetPart)
    -- Magic Bullet e Rage modes ignoram paredes
    if Settings.MagicBullet or Settings.IgnoreWalls or Settings.GodRageMode then
        return true
    end
    
    if not Settings.VisibleCheck then
        return true
    end
    
    local cached, cachedPart, hit = VisibilityCache:Get(player)
    if hit then return cached end
    
    local Camera = GetCamera()
    local data = GetPlayerData(player)
    if not data then return false end
    
    local origin = Camera.CFrame.Position
    local direction = targetPart.Position - origin
    
    UpdateRayParams()
    
    local ray = Workspace:Raycast(origin, direction, RayParams)
    
    local visible = true
    if ray and ray.Instance then
        if not ray.Instance:IsDescendantOf(data.model) then
            visible = false
        end
    end
    
    VisibilityCache:Set(player, visible, targetPart)
    return visible
end

-- ============================================================================
-- TARGET LOCK SYSTEM (ULTRA RAGE)
-- ============================================================================
local TargetLock = {
    CurrentTarget = nil,
    LockTime = 0,
    LastScore = math.huge,
    LastKill = 0,
    KillCount = 0,
    
    -- Configurações dinâmicas
    MinLockDuration = 0.05,
    MaxLockDuration = 0.5,
    ImprovementThreshold = 0.4,
}

function TargetLock:Reset()
    self.CurrentTarget = nil
    self.LockTime = 0
    self.LastScore = math.huge
end

function TargetLock:IsValid()
    if not self.CurrentTarget then return false end
    
    local data = GetPlayerData(self.CurrentTarget)
    if not data or not data.isValid then return false end
    
    if data.humanoid and data.humanoid.Health <= 0 then
        self.KillCount = self.KillCount + 1
        self.LastKill = tick()
        return false
    end
    
    local Camera = GetCamera()
    local distance = (data.anchor.Position - Camera.CFrame.Position).Magnitude
    
    -- Distância máxima baseada no modo
    local maxDist = Settings.MaxDistance or 2000
    if Settings.GodRageMode then
        maxDist = 99999
    elseif Settings.UltraRageMode then
        maxDist = maxDist * 3
    elseif Settings.RageMode then
        maxDist = maxDist * 2
    end
    
    if distance > maxDist then return false end
    
    return true
end

function TargetLock:TryLock(candidate, score)
    if not candidate then return end
    
    local now = tick()
    
    -- Configurações baseadas no modo
    if Settings.GodRageMode then
        self.MaxLockDuration = 0.1
        self.ImprovementThreshold = 0.2
    elseif Settings.UltraRageMode then
        self.MaxLockDuration = 0.3
        self.ImprovementThreshold = 0.3
    elseif Settings.RageMode then
        self.MaxLockDuration = 0.5
        self.ImprovementThreshold = 0.4
    elseif Settings.AutoSwitch then
        self.MaxLockDuration = Settings.TargetSwitchDelay or 0.1
        self.ImprovementThreshold = 0.5
    else
        self.MaxLockDuration = 1.5
        self.ImprovementThreshold = 0.7
    end
    
    if not self.CurrentTarget then
        self.CurrentTarget = candidate
        self.LockTime = now
        self.LastScore = score
        return
    end
    
    if self.CurrentTarget == candidate then
        self.LastScore = score
        return
    end
    
    if not self:IsValid() then
        self.CurrentTarget = candidate
        self.LockTime = now
        self.LastScore = score
        return
    end
    
    local lockDuration = now - self.LockTime
    
    -- Auto Switch imediato
    if Settings.AutoSwitch and lockDuration > (Settings.TargetSwitchDelay or 0.1) then
        self.CurrentTarget = candidate
        self.LockTime = now
        self.LastScore = score
        return
    end
    
    if lockDuration > self.MaxLockDuration then
        self.CurrentTarget = candidate
        self.LockTime = now
        self.LastScore = score
        return
    end
    
    if score < self.LastScore * self.ImprovementThreshold then
        self.CurrentTarget = candidate
        self.LockTime = now
        self.LastScore = score
    end
end

function TargetLock:GetTarget()
    if self:IsValid() then
        return self.CurrentTarget
    end
    self:Reset()
    return nil
end

-- ============================================================================
-- AIM CONTROLLER (ULTRA VERSION)
-- ============================================================================
local AimController = {
    IsAiming = false,
    OriginalCFrame = nil,
    HasMouseMoveRel = false,
    
    -- Shake reduction
    LastAimPos = nil,
    AimHistory = {},
    MaxHistory = 5,
    
    -- Smoothing curves
    SmoothHistory = {},
}

function AimController:DetectMethods()
    self.HasMouseMoveRel = type(mousemoverel) == "function"
end

function AimController:StartAiming()
    if self.IsAiming then return end
    self.IsAiming = true
    self.OriginalCFrame = GetCamera().CFrame
end

function AimController:StopAiming()
    if not self.IsAiming then return end
    self.IsAiming = false
    self.OriginalCFrame = nil
    self.LastAimPos = nil
    self.AimHistory = {}
    self.SmoothHistory = {}
    
    pcall(function()
        local Camera = GetCamera()
        if LocalPlayer.Character then
            local hum = LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
            if hum then Camera.CameraSubject = hum end
        end
    end)
end

function AimController:CalculateSmoothFactor(smoothing)
    -- GOD RAGE: Sem suavização, instantâneo
    if Settings.GodRageMode then
        return 1.0
    end
    
    -- ULTRA RAGE: Quase instantâneo
    if Settings.UltraRageMode then
        return 0.98
    end
    
    -- RAGE MODE: Mínima suavização
    if Settings.RageMode then
        if not smoothing or smoothing <= 2 then
            return 0.95
        else
            return Clamp(0.9 - (smoothing * 0.02), 0.6, 0.95)
        end
    end
    
    -- NORMAL
    if not smoothing or smoothing <= 0 then
        return 1.0
    end
    
    if smoothing <= 1 then
        return 0.85
    elseif smoothing <= 3 then
        return 0.55
    elseif smoothing <= 5 then
        return 0.35
    elseif smoothing <= 8 then
        return 0.2
    elseif smoothing <= 12 then
        return 0.12
    else
        return Clamp(0.7 / smoothing, 0.02, 0.08)
    end
end

function AimController:ApplyShakeReduction(targetPos)
    if Settings.ShakeReduction <= 0 then
        return targetPos
    end
    
    table.insert(self.AimHistory, targetPos)
    while #self.AimHistory > Settings.ShakeReduction + 2 do
        table.remove(self.AimHistory, 1)
    end
    
    if #self.AimHistory < 2 then
        return targetPos
    end
    
    -- Média ponderada (mais recentes têm mais peso)
    local avgPos = Vector3.zero
    local totalWeight = 0
    
    for i, pos in ipairs(self.AimHistory) do
        local weight = i * i -- Peso quadrático
        avgPos = avgPos + pos * weight
        totalWeight = totalWeight + weight
    end
    
    return avgPos / totalWeight
end

function AimController:ApplyAim(targetPosition, smoothing)
    if not targetPosition then return false end
    
    local Camera = GetCamera()
    if not Camera then return false end
    
    -- Aplica shake reduction
    targetPosition = self:ApplyShakeReduction(targetPosition)
    
    local method = Settings.AimMethod or "Camera"
    local smoothFactor = self:CalculateSmoothFactor(smoothing)
    
    -- Deadzone (desativado em rage modes)
    if Settings.UseDeadzone and not Settings.RageMode and not Settings.UltraRageMode and not Settings.GodRageMode then
        local screenPos, onScreen = Camera:WorldToViewportPoint(targetPosition)
        if onScreen then
            local mousePos = UserInputService:GetMouseLocation()
            local dist = (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude
            
            local deadzone = Settings.DeadzoneRadius or 2
            if dist < deadzone then
                return true
            end
        end
    end
    
    local success = false
    
    if method == "MouseMoveRel" and self.HasMouseMoveRel then
        success = self:Method_MouseMoveRel(targetPosition, smoothFactor)
    else
        success = self:Method_Camera(targetPosition, smoothFactor)
    end
    
    return success
end

function AimController:Method_Camera(targetPosition, smoothFactor)
    local success = pcall(function()
        self:StartAiming()
        
        local Camera = GetCamera()
        local camPos = Camera.CFrame.Position
        local direction = targetPosition - camPos
        
        if direction.Magnitude < 0.001 then return end
        
        local targetCFrame = CFrame.lookAt(camPos, targetPosition)
        
        -- God/Ultra Rage: Snap instantâneo
        if Settings.GodRageMode or smoothFactor >= 0.99 then
            Camera.CFrame = targetCFrame
        elseif Settings.UltraRageMode or smoothFactor >= 0.95 then
            Camera.CFrame = Camera.CFrame:Lerp(targetCFrame, 0.95)
        else
            local currentRotation = Camera.CFrame.Rotation
            local targetRotation = targetCFrame.Rotation
            local smoothedRotation = currentRotation:Lerp(targetRotation, smoothFactor)
            Camera.CFrame = CFrame.new(camPos) * smoothedRotation
        end
    end)
    
    return success
end

function AimController:Method_MouseMoveRel(targetPosition, smoothFactor)
    if not self.HasMouseMoveRel then
        return self:Method_Camera(targetPosition, smoothFactor)
    end
    
    local success = pcall(function()
        local Camera = GetCamera()
        local screenPos, onScreen = Camera:WorldToViewportPoint(targetPosition)
        
        if not onScreen and not Settings.GodRageMode then return end
        
        local viewport = Camera.ViewportSize
        local centerX = viewport.X / 2
        local centerY = viewport.Y / 2
        
        local deltaX = screenPos.X - centerX
        local deltaY = screenPos.Y - centerY
        
        -- Rage modes: movimento total
        local moveX, moveY
        if Settings.GodRageMode or Settings.UltraRageMode then
            moveX = deltaX
            moveY = deltaY
        else
            moveX = deltaX * smoothFactor
            moveY = deltaY * smoothFactor
        end
        
        -- Threshold mínimo
        if math.abs(moveX) < 0.1 and math.abs(moveY) < 0.1 then
            return
        end
        
        mousemoverel(moveX, moveY)
    end)
    
    return success
end

-- ============================================================================
-- SILENT AIM SYSTEM (ULTRA VERSION)
-- ============================================================================
local SilentAim = {
    Enabled = false,
    HookedNamecall = false,
    HookedIndex = false,
    HookedNewIndex = false,
    Hooks = {},
    LastTarget = nil,
    LastAimPos = nil,
}

function SilentAim:GetTargetPosition()
    local target = TargetLock:GetTarget()
    if not target then
        -- Busca novo alvo para silent
        target = FindBestTargetForSilent()
    end
    
    if not target then return nil end
    
    self.LastTarget = target
    
    local aimPart = GetBestAimPart(target, true)
    if not aimPart then return nil end
    
    -- Headshot chance
    if Settings.SilentHeadshotChance < 100 then
        if not RandomChance(Settings.SilentHeadshotChance) then
            -- Mira no torso em vez da cabeça
            local torso = GetAimPart(target, "UpperTorso")
            if torso then aimPart = torso end
        end
    end
    
    local pos = PredictPosition(target, aimPart)
    self.LastAimPos = pos
    return pos
end

function SilentAim:IsInFOV(position)
    if Settings.GodRageMode then return true end
    
    local Camera = GetCamera()
    local screenPos, onScreen = Camera:WorldToViewportPoint(position)
    
    if not onScreen then return Settings.UltraRageMode end
    
    local mousePos = UserInputService:GetMouseLocation()
    local dist = (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude
    
    local silentFOV = Settings.SilentFOV or 500
    if Settings.UltraRageMode then
        silentFOV = silentFOV * 3
    elseif Settings.RageMode then
        silentFOV = silentFOV * 2
    end
    
    return dist <= silentFOV
end

function SilentAim:ShouldHit()
    -- Hit chance
    if Settings.SilentHitChance < 100 then
        return RandomChance(Settings.SilentHitChance)
    end
    return true
end

function SilentAim:Initialize()
    if self.HookedNamecall then return end
    
    -- Tenta múltiplos métodos de hook
    
    -- Método 1: Hook via metatable
    SafeCall(function()
        if type(getrawmetatable) ~= "function" then return end
        
        local mt = getrawmetatable(game)
        if not mt then return end
        
        local oldNamecall = mt.__namecall
        local oldIndex = mt.__index
        
        -- Hook __namecall
        if type(hookfunction) == "function" or type(hookmetamethod) == "function" then
            local newNamecall = function(self, ...)
                if not SilentAim.Enabled or not Settings.SilentAim then
                    return oldNamecall(self, ...)
                end
                
                local method = getnamecallmethod()
                
                -- Hook Raycast methods
                if method == "Raycast" or method == "FindPartOnRay" or 
                   method == "FindPartOnRayWithIgnoreList" or method == "FindPartOnRayWithWhitelist" then
                    
                    if SilentAim:ShouldHit() then
                        local targetPos = SilentAim:GetTargetPosition()
                        if targetPos and SilentAim:IsInFOV(targetPos) then
                            local args = {...}
                            local origin
                            
                            if method == "Raycast" then
                                origin = args[1]
                                if origin then
                                    local direction = (targetPos - origin).Unit * 5000
                                    args[2] = direction
                                    return oldNamecall(self, unpack(args))
                                end
                            else
                                -- FindPartOnRay methods
                                local ray = args[1]
                                if typeof(ray) == "Ray" then
                                    origin = ray.Origin
                                    local newRay = Ray.new(origin, (targetPos - origin).Unit * 5000)
                                    args[1] = newRay
                                    return oldNamecall(self, unpack(args))
                                end
                            end
                        end
                    end
                end
                
                -- Hook Camera lookAt para bypass de anti-cheat
                if method == "GetMouseButtonDown" or method == "IsMouseButtonPressed" then
                    if Settings.AutoFire and SilentAim.LastTarget then
                        -- Pode retornar true para simular clique
                    end
                end
                
                return oldNamecall(self, ...)
            end
            
            if type(hookmetamethod) == "function" then
                local success = pcall(function()
                    hookmetamethod(game, "__namecall", newNamecall)
                end)
                if success then
                    self.HookedNamecall = true
                end
            elseif type(hookfunction) == "function" and type(setreadonly) == "function" then
                pcall(function()
                    setreadonly(mt, false)
                    hookfunction(mt.__namecall, newNamecall)
                    setreadonly(mt, true)
                    self.HookedNamecall = true
                end)
            end
        end
    end, "SilentAim:InitializeNamecall")
    
    -- Método 2: Hook via Remote Events (para jogos que usam remotes)
    SafeCall(function()
        if type(hookfunction) ~= "function" then return end
        
        -- Procura por remotes de arma/tiro
        local function HookRemote(remote)
            if not remote:IsA("RemoteEvent") and not remote:IsA("RemoteFunction") then
                return
            end
            
            local remoteName = remote.Name:lower()
            local weaponKeywords = {"shoot", "fire", "bullet", "gun", "weapon", "damage", "hit", "attack"}
            
            local isWeaponRemote = false
            for _, keyword in ipairs(weaponKeywords) do
                if remoteName:find(keyword) then
                    isWeaponRemote = true
                    break
                end
            end
            
            if not isWeaponRemote then return end
            
            -- Hook do FireServer
            if remote:IsA("RemoteEvent") then
                local oldFireServer = remote.FireServer
                self.Hooks[remote] = oldFireServer
                
                remote.FireServer = function(self, ...)
                    if SilentAim.Enabled and Settings.SilentAim then
                        local targetPos = SilentAim:GetTargetPosition()
                        if targetPos and SilentAim:ShouldHit() then
                            local args = {...}
                            -- Tenta modificar argumentos de posição
                            for i, arg in ipairs(args) do
                                if typeof(arg) == "Vector3" then
                                    args[i] = targetPos
                                elseif typeof(arg) == "CFrame" then
                                    args[i] = CFrame.new(targetPos)
                                elseif typeof(arg) == "table" then
                                    -- Tenta encontrar campos de posição
                                    if arg.Position then arg.Position = targetPos end
                                    if arg.EndPosition then arg.EndPosition = targetPos end
                                    if arg.HitPosition then arg.HitPosition = targetPos end
                                    if arg.Target then arg.Target = targetPos end
                                end
                            end
                            return oldFireServer(self, unpack(args))
                        end
                    end
                    return oldFireServer(self, ...)
                end
            end
        end
        
        -- Hook remotes existentes
        for _, remote in ipairs(game:GetDescendants()) do
            pcall(function() HookRemote(remote) end)
        end
        
        -- Hook novos remotes
        game.DescendantAdded:Connect(function(remote)
            task.wait(0.1)
            pcall(function() HookRemote(remote) end)
        end)
    end, "SilentAim:InitializeRemotes")
end

function SilentAim:Enable()
    self.Enabled = true
    self:Initialize()
end

function SilentAim:Disable()
    self.Enabled = false
end

-- ============================================================================
-- MAGIC BULLET SYSTEM (ATRAVESSA PAREDES)
-- ============================================================================
local MagicBullet = {
    Enabled = false,
    BulletHooks = {},
    LastFire = 0,
}

function MagicBullet:Initialize()
    if not Settings.MagicBullet then return end
    
    -- Método 1: Hook de projéteis
    SafeCall(function()
        local function HookProjectile(projectile)
            if not projectile:IsA("BasePart") then return end
            
            local name = projectile.Name:lower()
            local bulletKeywords = {"bullet", "projectile", "shot", "missile", "arrow"}
            
            local isBullet = false
            for _, keyword in ipairs(bulletKeywords) do
                if name:find(keyword) then
                    isBullet = true
                    break
                end
            end
            
            if not isBullet then return end
            
            -- Observa o projétil e redireciona
            local connection
            connection = RunService.Heartbeat:Connect(function()
                if not projectile or not projectile.Parent then
                    connection:Disconnect()
                    return
                end
                
                if MagicBullet.Enabled and Settings.MagicBullet then
                    local target = TargetLock:GetTarget()
                    if target then
                        local aimPart = GetBestAimPart(target)
                        if aimPart then
                            local targetPos = PredictPosition(target, aimPart)
                            local direction = (targetPos - projectile.Position).Unit
                            
                            if Settings.MagicBulletMethod == "Teleport" then
                                -- Teleporta direto para o alvo
                                projectile.CFrame = CFrame.new(targetPos)
                            elseif Settings.MagicBulletMethod == "Curve" then
                                -- Curva a bala em direção ao alvo
                                projectile.AssemblyLinearVelocity = direction * Settings.MagicBulletSpeed
                            elseif Settings.MagicBulletMethod == "Phase" then
                                -- Remove colisão e direciona
                                projectile.CanCollide = false
                                projectile.AssemblyLinearVelocity = direction * Settings.MagicBulletSpeed
                            end
                        end
                    end
                end
            end)
        end
        
        -- Monitora novos projéteis
        workspace.DescendantAdded:Connect(function(desc)
            task.spawn(function()
                pcall(function() HookProjectile(desc) end)
            end)
        end)
    end, "MagicBullet:HookProjectiles")
    
    -- Método 2: Hook de remotes de tiro
    SafeCall(function()
        if type(hookfunction) ~= "function" then return end
        
        -- Procura RemoteEvents de armas
        local function HookWeaponRemote(remote)
            if not remote:IsA("RemoteEvent") then return end
            
            local name = remote.Name:lower()
            if not (name:find("shoot") or name:find("fire") or name:find("bullet") or 
                    name:find("damage") or name:find("hit") or name:find("weapon")) then
                return
            end
            
            -- Já hookado pelo SilentAim
            if SilentAim.Hooks[remote] then return end
            
            local oldFire = remote.FireServer
            MagicBullet.BulletHooks[remote] = oldFire
            
            remote.FireServer = function(self, ...)
                if MagicBullet.Enabled and Settings.MagicBullet then
                    local target = TargetLock:GetTarget()
                    if target then
                        local aimPart = GetBestAimPart(target)
                        if aimPart then
                            local targetPos = PredictPosition(target, aimPart)
                            local args = {...}
                            
                            -- Modifica argumentos
                            for i, arg in ipairs(args) do
                                if typeof(arg) == "Vector3" then
                                    args[i] = targetPos
                                elseif typeof(arg) == "CFrame" then
                                    local origin = arg.Position
                                    args[i] = CFrame.lookAt(origin, targetPos)
                                elseif typeof(arg) == "Ray" then
                                    args[i] = Ray.new(arg.Origin, (targetPos - arg.Origin).Unit * 5000)
                                elseif type(arg) == "table" then
                                    if arg.Position then arg.Position = targetPos end
                                    if arg.EndPos then arg.EndPos = targetPos end
                                    if arg.HitPos then arg.HitPos = targetPos end
                                    if arg.Origin then
                                        local origin = arg.Origin
                                        if arg.Direction then
                                            arg.Direction = (targetPos - origin).Unit * 5000
                                        end
                                    end
                                end
                            end
                            
                            if Settings.MagicBulletAutoHit then
                                -- Força o hit
                                local data = GetPlayerData(target)
                                if data then
                                    -- Alguns jogos usam argumentos específicos
                                    for i, arg in ipairs(args) do
                                        if type(arg) == "table" then
                                            if arg.HitPart == nil and aimPart then
                                                arg.HitPart = aimPart
                                            end
                                            if arg.Target == nil then
                                                arg.Target = target
                                            end
                                            if arg.Character == nil and data.model then
                                                arg.Character = data.model
                                            end
                                        end
                                    end
                                end
                            end
                            
                            return oldFire(self, unpack(args))
                        end
                    end
                end
                return oldFire(self, ...)
            end
        end
        
        -- Hook existentes
        for _, remote in ipairs(game:GetDescendants()) do
            pcall(function() HookWeaponRemote(remote) end)
        end
        
        -- Hook novos
        game.DescendantAdded:Connect(function(desc)
            task.wait(0.1)
            pcall(function() HookWeaponRemote(desc) end)
        end)
    end, "MagicBullet:HookRemotes")
end

function MagicBullet:Enable()
    self.Enabled = true
    Settings.MagicBullet = true
    self:Initialize()
end

function MagicBullet:Disable()
    self.Enabled = false
    Settings.MagicBullet = false
end

-- ============================================================================
-- TRIGGER BOT SYSTEM
-- ============================================================================
local TriggerBot = {
    Enabled = false,
    LastTrigger = 0,
    BurstCount = 0,
    IsBursting = false,
}

function TriggerBot:GetTargetInFOV()
    local Camera = GetCamera()
    local mousePos = UserInputService:GetMouseLocation()
    local triggerFOV = Settings.TriggerFOV or 50
    
    -- Ajusta FOV baseado no modo
    if Settings.GodRageMode then
        triggerFOV = triggerFOV * 5
    elseif Settings.UltraRageMode then
        triggerFOV = triggerFOV * 3
    elseif Settings.RageMode then
        triggerFOV = triggerFOV * 2
    end
    
    for _, player in ipairs(Players:GetPlayers()) do
        if player == LocalPlayer then continue end
        
        local data = GetPlayerData(player)
        if not data or not data.isValid then continue end
        if data.humanoid and data.humanoid.Health <= 0 then continue end
        
        -- Team check
        if Settings.IgnoreTeamAimbot then
            if AreSameTeam(LocalPlayer, player) then continue end
        end
        
        local targetPart
        if Settings.TriggerHeadOnly then
            targetPart = GetAimPart(player, "Head")
        else
            targetPart = GetBestAimPart(player)
        end
        
        if not targetPart then continue end
        
        local screenPos, onScreen = Camera:WorldToViewportPoint(targetPart.Position)
        if not onScreen then continue end
        
        local dist = (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude
        
        if dist <= triggerFOV then
            -- Verifica visibilidade
            if IsVisible(player, targetPart) then
                return player, targetPart
            end
        end
    end
    
    return nil
end

function TriggerBot:Fire()
    SafeCall(function()
        if mouse1click then
            mouse1click()
        elseif type(Input) == "table" and Input.MouseButton1Click then
            Input.MouseButton1Click()
        else
            -- Fallback: simula input via Virtual Input
            local vim = game:GetService("VirtualInputManager")
            if vim then
                vim:SendMouseButtonEvent(0, 0, 0, true, game, 0)
                task.wait(0.01)
                vim:SendMouseButtonEvent(0, 0, 0, false, game, 0)
            end
        end
    end, "TriggerBot:Fire")
end

function TriggerBot:Update()
    if not self.Enabled or not Settings.TriggerBot then return end
    
    local now = tick()
    local delay = Settings.TriggerDelay or 0.05
    
    -- Ajusta delay para rage modes
    if Settings.GodRageMode then
        delay = 0.01
    elseif Settings.UltraRageMode then
        delay = 0.02
    elseif Settings.RageMode then
        delay = 0.03
    end
    
    if now - self.LastTrigger < delay then return end
    
    local target, part = self:GetTargetInFOV()
    
    if target and part then
        if Settings.TriggerBurst then
            -- Modo burst
            if not self.IsBursting then
                self.IsBursting = true
                self.BurstCount = 0
                
                task.spawn(function()
                    for i = 1, (Settings.TriggerBurstCount or 3) do
                        if not self.Enabled then break end
                        self:Fire()
                        self.BurstCount = self.BurstCount + 1
                        task.wait(0.03)
                    end
                    self.IsBursting = false
                    self.LastTrigger = tick()
                end)
            end
        else
            -- Modo normal
            self:Fire()
            self.LastTrigger = now
        end
    end
end

function TriggerBot:Enable()
    self.Enabled = true
    Settings.TriggerBot = true
end

function TriggerBot:Disable()
    self.Enabled = false
    Settings.TriggerBot = false
end

-- ============================================================================
-- AUTO FIRE SYSTEM
-- ============================================================================
local AutoFire = {
    LastFire = 0,
    FireRate = 0.05,
}

function AutoFire:TryFire()
    if not Settings.AutoFire then return end
    
    local now = tick()
    
    -- Fire rate baseado no modo
    local rate = self.FireRate
    if Settings.GodRageMode then
        rate = 0.01
    elseif Settings.UltraRageMode then
        rate = 0.02
    elseif Settings.RageMode then
        rate = 0.03
    end
    
    if now - self.LastFire < rate then return end
    
    local target = TargetLock:GetTarget()
    if not target then return end
    
    SafeCall(function()
        if mouse1click then
            mouse1click()
            self.LastFire = now
        elseif type(Input) == "table" and Input.MouseButton1Click then
            Input.MouseButton1Click()
            self.LastFire = now
        else
            local vim = game:GetService("VirtualInputManager")
            if vim then
                vim:SendMouseButtonEvent(0, 0, 0, true, game, 0)
                task.wait(0.005)
                vim:SendMouseButtonEvent(0, 0, 0, false, game, 0)
                self.LastFire = now
            end
        end
    end, "AutoFire")
end

-- ============================================================================
-- TARGET FINDER (ULTRA OPTIMIZED)
-- ============================================================================
local function FindBestTarget()
    local Camera = GetCamera()
    if not Camera then return nil, math.huge end
    
    local camPos = Camera.CFrame.Position
    local camLook = Camera.CFrame.LookVector
    local mousePos = UserInputService:GetMouseLocation()
    
    local candidates = {}
    local allPlayers = Players:GetPlayers()
    
    -- FOV ajustado para cada modo
    local currentFOV = Settings.AimbotFOV or 180
    if Settings.GodRageMode then
        currentFOV = 99999
    elseif Settings.UltraRageMode then
        currentFOV = currentFOV * 5
    elseif Settings.RageMode then
        currentFOV = currentFOV * 3
    end
    
    -- Distância máxima
    local maxDist = Settings.MaxDistance or 2000
    if Settings.GodRageMode then
        maxDist = 99999
    elseif Settings.UltraRageMode then
        maxDist = maxDist * 4
    elseif Settings.RageMode then
        maxDist = maxDist * 2
    end
    
    for _, player in ipairs(allPlayers) do
        if player == LocalPlayer then continue end
        
        local data = GetPlayerData(player)
        
        if not data or not data.isValid or not data.anchor then continue end
        if not data.anchor:IsDescendantOf(workspace) then continue end
        if data.humanoid and data.humanoid.Health <= 0 then continue end
        
        -- Team check
        if Settings.IgnoreTeamAimbot then
            if AreSameTeam(LocalPlayer, player) then continue end
        end
        
        local distance = (data.anchor.Position - camPos).Magnitude
        if distance > maxDist then continue end
        
        local screenPos, onScreen = Camera:WorldToViewportPoint(data.anchor.Position)
        
        -- Em God Rage, ignora se está na tela
        if not Settings.GodRageMode and not Settings.UltraRageMode and not onScreen then continue end
        
        local distToMouse = onScreen and (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude or 99999
        
        -- FOV check (exceto em God Rage)
        if not Settings.GodRageMode and Settings.UseAimbotFOV and distToMouse > currentFOV then continue end
        
        -- Verifica direção (menos restritivo em Rage)
        local dirToTarget = (data.anchor.Position - camPos).Unit
        local dot = camLook:Dot(dirToTarget)
        
        local minDot = 0.1
        if Settings.GodRageMode then
            minDot = -1
        elseif Settings.UltraRageMode then
            minDot = -0.5
        elseif Settings.RageMode then
            minDot = -0.2
        end
        
        if dot < minDot then continue end
        
        -- Calcula score
        local score
        if Settings.GodRageMode then
            -- Prioriza distância e saúde
            local healthPenalty = data.humanoid and (data.humanoid.Health / data.humanoid.MaxHealth) or 1
            score = distance * 0.3 * healthPenalty
        elseif Settings.UltraRageMode then
            score = distance * 0.4 + distToMouse * 0.1
        elseif Settings.RageMode then
            score = distance * 0.3 + distToMouse * 0.4
        else
            score = distToMouse * 1.0 + distance * 0.15
        end
        
        -- Prioriza alvos com menos vida
        if Settings.RageMode or Settings.UltraRageMode or Settings.GodRageMode then
            if data.humanoid then
                local healthPercent = data.humanoid.Health / data.humanoid.MaxHealth
                score = score * (0.3 + healthPercent * 0.7)
            end
        end
        
        table.insert(candidates, {
            player = player,
            data = data,
            score = score,
            distance = distance,
            distToMouse = distToMouse,
            onScreen = onScreen,
        })
    end
    
    table.sort(candidates, function(a, b) return a.score < b.score end)
    
    -- Verifica visibilidade
    local maxChecks = 1
    if Settings.GodRageMode then
        maxChecks = 1
    elseif Settings.UltraRageMode then
        maxChecks = 2
    elseif Settings.RageMode then
        maxChecks = 3
    else
        maxChecks = 5
    end
    
    local checked = 0
    
    for _, candidate in ipairs(candidates) do
        if checked >= maxChecks then break end
        
        local aimPart = GetBestAimPart(candidate.player)
        if not aimPart then continue end
        
        checked = checked + 1
        
        -- Em rage modes ou com magic bullet, ignora visibilidade
        if Settings.IgnoreWalls or Settings.MagicBullet or Settings.GodRageMode or not Settings.VisibleCheck then
            return candidate.player, candidate.score
        end
        
        if IsVisible(candidate.player, aimPart) then
            return candidate.player, candidate.score
        end
    end
    
    -- Fallback para rage modes
    if (Settings.IgnoreWalls or Settings.MagicBullet or not Settings.VisibleCheck) and #candidates > 0 then
        return candidates[1].player, candidates[1].score
    end
    
    return nil, math.huge
end

-- Target finder específico para Silent Aim
local function FindBestTargetForSilent()
    local Camera = GetCamera()
    if not Camera then return nil end
    
    local camPos = Camera.CFrame.Position
    local mousePos = UserInputService:GetMouseLocation()
    
    local silentFOV = Settings.SilentFOV or 500
    if Settings.GodRageMode then
        silentFOV = 99999
    elseif Settings.UltraRageMode then
        silentFOV = silentFOV * 4
    elseif Settings.RageMode then
        silentFOV = silentFOV * 2
    end
    
    local bestTarget = nil
    local bestScore = math.huge
    
    for _, player in ipairs(Players:GetPlayers()) do
        if player == LocalPlayer then continue end
        
        local data = GetPlayerData(player)
        if not data or not data.isValid then continue end
        if data.humanoid and data.humanoid.Health <= 0 then continue end
        
        if Settings.IgnoreTeamAimbot and AreSameTeam(LocalPlayer, player) then continue end
        
        local targetPart = GetBestAimPart(player)
        if not targetPart then continue end
        
        local screenPos, onScreen = Camera:WorldToViewportPoint(targetPart.Position)
        
        if onScreen or Settings.GodRageMode then
            local distToMouse = onScreen and (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude or 9999
            
            if distToMouse <= silentFOV or Settings.GodRageMode then
                local distance = (targetPart.Position - camPos).Magnitude
                local score = distToMouse + distance * 0.1
                
                if score < bestScore then
                    bestScore = score
                    bestTarget = player
                end
            end
        end
    end
    
    return bestTarget
end

-- ============================================================================
-- AIMBOT STATE MACHINE
-- ============================================================================
local AimbotState = {
    Active = false,
    LastUpdate = 0,
    ErrorCount = 0,
    MaxErrors = 15,
    FrameCount = 0,
}

function AimbotState:Reset()
    self.Active = false
    self.ErrorCount = 0
    self.FrameCount = 0
    TargetLock:Reset()
    AimController:StopAiming()
    VisibilityCache:Clear()
    PredictionHistory = {}
    SilentAim:Disable()
    MagicBullet:Disable()
    TriggerBot:Disable()
end

function AimbotState:OnError()
    self.ErrorCount = self.ErrorCount + 1
    if self.ErrorCount >= self.MaxErrors then
        warn("[Aimbot] Muitos erros, resetando...")
        self:Reset()
        self.ErrorCount = 0
    end
end

-- ============================================================================
-- MAIN AIMBOT MODULE
-- ============================================================================
local Aimbot = {
    Initialized = false,
    Connection = nil,
    TriggerConnection = nil,
}

function Aimbot:Update()
    VisibilityCache:NextFrame()
    AimbotState.FrameCount = AimbotState.FrameCount + 1
    
    -- Update Trigger Bot
    if Settings.TriggerBot then
        TriggerBot:Update()
    end
    
    local shouldBeActive = Settings.AimbotActive and State.MouseHold
    
    if not shouldBeActive then
        if AimbotState.Active then
            AimbotState.Active = false
            TargetLock:Reset()
            AimController:StopAiming()
        end
        return
    end
    
    AimbotState.Active = true
    
    -- Silent Aim
    if Settings.SilentAim then
        SilentAim:Enable()
    end
    
    -- Magic Bullet
    if Settings.MagicBullet then
        MagicBullet:Enable()
    end
    
    -- Busca alvo
    local bestTarget, bestScore = FindBestTarget()
    
    if bestTarget then
        TargetLock:TryLock(bestTarget, bestScore)
    end
    
    local target = TargetLock:GetTarget()
    
    if target then
        local aimPart = GetBestAimPart(target)
        
        if aimPart then
            local aimPos = PredictPosition(target, aimPart)
            
            -- Calcula smoothing
            local baseSm = Settings.SmoothingFactor or 5
            local smoothing = baseSm
            
            if Settings.GodRageMode then
                smoothing = 0
            elseif Settings.UltraRageMode then
                smoothing = 0
            elseif Settings.RageMode then
                smoothing = math.min(baseSm, 1)
            elseif Settings.UseAdaptiveSmoothing then
                local data = GetPlayerData(target)
                if data and data.anchor then
                    local Camera = GetCamera()
                    local dist = (data.anchor.Position - Camera.CFrame.Position).Magnitude
                    
                    if dist < 50 then
                        smoothing = baseSm * 1.4
                    elseif dist > 300 then
                        smoothing = baseSm * 0.6
                    end
                end
            end
            
            -- Aplica aim
            AimController:ApplyAim(aimPos, smoothing)
            
            -- Auto Fire
            if Settings.AutoFire then
                AutoFire:TryFire()
            end
        else
            TargetLock:Reset()
            AimController:StopAiming()
        end
    else
        AimController:StopAiming()
    end
end

function Aimbot:StartLoop()
    if self.Connection then
        self.Connection:Disconnect()
        self.Connection = nil
    end
    
    -- Escolhe evento baseado no modo e performance
    local event
    if Settings.GodRageMode or Settings.UltraRageMode then
        event = RunService.RenderStepped
    elseif Settings.RageMode then
        event = RunService.RenderStepped
    else
        event = RunService.Heartbeat
    end
    
    self.Connection = event:Connect(function()
        local success = SafeCall(function()
            self:Update()
        end, "AimbotUpdate")
        
        if not success then
            AimbotState:OnError()
        end
    end)
end

function Aimbot:StopLoop()
    if self.Connection then
        self.Connection:Disconnect()
        self.Connection = nil
    end
    AimbotState:Reset()
end

function Aimbot:Toggle(enabled)
    Settings.AimbotActive = enabled
    if not enabled then
        AimbotState:Reset()
    end
end

function Aimbot:SetRageMode(enabled)
    Settings.RageMode = enabled
    if enabled then
        Settings.UltraRageMode = false
        Settings.GodRageMode = false
    end
    
    if self.Initialized then
        self:StopLoop()
        self:StartLoop()
    end
    
    if Notify then
        Notify("Aimbot", "Rage Mode " .. (enabled and "ATIVADO 🔥" or "DESATIVADO"))
    end
end

function Aimbot:SetUltraRageMode(enabled)
    Settings.UltraRageMode = enabled
    if enabled then
        Settings.RageMode = true
        Settings.GodRageMode = false
    end
    
    if self.Initialized then
        self:StopLoop()
        self:StartLoop()
    end
    
    if Notify then
        Notify("Aimbot", "ULTRA RAGE " .. (enabled and "ATIVADO ⚡🔥⚡" or "DESATIVADO"))
    end
end

function Aimbot:SetGodRageMode(enabled)
    Settings.GodRageMode = enabled
    if enabled then
        Settings.RageMode = true
        Settings.UltraRageMode = true
        Settings.IgnoreWalls = true
        Settings.SilentAim = true
        Settings.MagicBullet = true
    end
    
    if self.Initialized then
        self:StopLoop()
        self:StartLoop()
    end
    
    if Notify then
        Notify("Aimbot", "👑 GOD RAGE MODE 👑 " .. (enabled and "ATIVADO" or "DESATIVADO"))
    end
end

function Aimbot:SetSilentAim(enabled)
    Settings.SilentAim = enabled
    if enabled then
        SilentAim:Enable()
    else
        SilentAim:Disable()
    end
    
    if Notify then
        Notify("Silent Aim", enabled and "ATIVADO 🎯" or "DESATIVADO")
    end
end

function Aimbot:SetMagicBullet(enabled)
    Settings.MagicBullet = enabled
    if enabled then
        MagicBullet:Enable()
    else
        MagicBullet:Disable()
    end
    
    if Notify then
        Notify("Magic Bullet", enabled and "ATIVADO ✨🔫" or "DESATIVADO")
    end
end

function Aimbot:SetTriggerBot(enabled)
    Settings.TriggerBot = enabled
    if enabled then
        TriggerBot:Enable()
    else
        TriggerBot:Disable()
    end
    
    if Notify then
        Notify("Trigger Bot", enabled and "ATIVADO ⚡" or "DESATIVADO")
    end
end

function Aimbot:SetSilentFOV(fov)
    Settings.SilentFOV = fov
end

function Aimbot:SetTriggerFOV(fov)
    Settings.TriggerFOV = fov
end

function Aimbot:SetAimbotFOV(fov)
    Settings.AimbotFOV = fov
    Settings.FOV = fov
end

function Aimbot:Initialize()
    if self.Initialized then return end
    
    AimController:DetectMethods()
    SilentAim:Initialize()
    MagicBullet:Initialize()
    
    self:StartLoop()
    
    -- Watchdog
    task.spawn(function()
        while true do
            task.wait(1.5)
            if self.Initialized and not self.Connection then
                warn("[Aimbot] Loop morreu, reiniciando...")
                self:StartLoop()
            end
        end
    end)
    
    self.Initialized = true
    
    print("═══════════════════════════════════════════")
    print("  AIMBOT v4.0 - ULTRA RAGE MAXIMUM POWER")
    print("═══════════════════════════════════════════")
    print("[✓] MouseMoveRel: " .. (AimController.HasMouseMoveRel and "OK" or "N/A"))
    print("[✓] SilentAim Hooks: " .. (SilentAim.HookedNamecall and "OK" or "N/A"))
    print("[✓] Magic Bullet: Ready")
    print("[✓] Trigger Bot: Ready")
    print("═══════════════════════════════════════════")
end

function Aimbot:Debug()
    print("\n═══════════════ AIMBOT DEBUG ═══════════════")
    print("Initialized: " .. tostring(self.Initialized))
    print("Connection Active: " .. tostring(self.Connection ~= nil))
    
    print("\n─── RAGE STATUS ───")
    print("  RageMode: " .. tostring(Settings.RageMode))
    print("  UltraRageMode: " .. tostring(Settings.UltraRageMode))
    print("  GodRageMode: " .. tostring(Settings.GodRageMode))
    
    print("\n─── FEATURES ───")
    print("  SilentAim: " .. tostring(Settings.SilentAim) .. " (FOV: " .. tostring(Settings.SilentFOV) .. ")")
    print("  MagicBullet: " .. tostring(Settings.MagicBullet))
    print("  TriggerBot: " .. tostring(Settings.TriggerBot) .. " (FOV: " .. tostring(Settings.TriggerFOV) .. ")")
    print("  AutoFire: " .. tostring(Settings.AutoFire))
    print("  AutoSwitch: " .. tostring(Settings.AutoSwitch))
    print("  IgnoreWalls: " .. tostring(Settings.IgnoreWalls))
    print("  MultiPartAim: " .. tostring(Settings.MultiPartAim))
    
    print("\n─── FOV Settings ───")
    print("  Aimbot FOV: " .. tostring(Settings.AimbotFOV))
    print("  Silent FOV: " .. tostring(Settings.SilentFOV))
    print("  Trigger FOV: " .. tostring(Settings.TriggerFOV))
    
    print("\n─── Target ───")
    local target = TargetLock:GetTarget()
    print("  Current: " .. (target and target.Name or "None"))
    print("  Kills: " .. TargetLock.KillCount)
    print("  Frames: " .. AimbotState.FrameCount)
    
    print("\n─── Test ───")
    local t, s = FindBestTarget()
    print("  Best: " .. (t and (t.Name .. " score:" .. string.format("%.1f", s)) or "None"))
    
    print("═══════════════════════════════════════════\n")
end

function Aimbot:ForceReset()
    print("[Aimbot] Force reset")
    AimbotState:Reset()
    self:StopLoop()
    task.wait(0.1)
    self:StartLoop()
end

-- ============================================================================
-- EXPORT
-- ============================================================================
Core.Aimbot = {
    Main = Aimbot,
    TargetLock = TargetLock,
    AimController = AimController,
    SilentAim = SilentAim,
    MagicBullet = MagicBullet,
    TriggerBot = TriggerBot,
    AutoFire = AutoFire,
    
    -- Funções públicas
    Update = function() Aimbot:Update() end,
    Initialize = function() Aimbot:Initialize() end,
    Toggle = function(enabled) Aimbot:Toggle(enabled) end,
    
    -- Rage Modes
    SetRageMode = function(enabled) Aimbot:SetRageMode(enabled) end,
    SetUltraRageMode = function(enabled) Aimbot:SetUltraRageMode(enabled) end,
    SetGodRageMode = function(enabled) Aimbot:SetGodRageMode(enabled) end,
    
    -- Features
    SetSilentAim = function(enabled) Aimbot:SetSilentAim(enabled) end,
    SetMagicBullet = function(enabled) Aimbot:SetMagicBullet(enabled) end,
    SetTriggerBot = function(enabled) Aimbot:SetTriggerBot(enabled) end,
    
    -- FOV
    SetSilentFOV = function(fov) Aimbot:SetSilentFOV(fov) end,
    SetTriggerFOV = function(fov) Aimbot:SetTriggerFOV(fov) end,
    SetAimbotFOV = function(fov) Aimbot:SetAimbotFOV(fov) end,
    
    -- Debug
    Debug = function() Aimbot:Debug() end,
    ForceReset = function() Aimbot:ForceReset() end,
    
    -- Compatibilidade
    CameraBypass = {
        GetLockedTarget = function() return TargetLock:GetTarget() end,
        ClearLock = function() TargetLock:Reset() end,
    },
    
    GetClosestPlayer = FindBestTarget,
    AimMethods = AimController,
}

return Aimbot