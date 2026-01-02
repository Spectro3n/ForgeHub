-- ============================================================================
-- FORGEHUB - AIMBOT MODULE v4.2 (FIXED + TARGET MODES)
-- ============================================================================

local Core = _G.ForgeHubCore
if not Core then
    error("ForgeHubCore não encontrado! Carregue main.lua primeiro.")
end

-- ============================================================================
-- IMPORTS (PRELOCALIZADOS PARA PERFORMANCE)
-- ============================================================================
local Players = Core.Players
local RunService = Core.RunService
local UserInputService = Core.UserInputService
local Workspace = Core.Workspace
local LocalPlayer = Core.LocalPlayer
local Settings = Core.Settings
local State = Core.State
local Notify = Core.Notify

local mathMax = math.max
local mathMin = math.min
local mathAbs = math.abs
local mathSin = math.sin
local mathRandom = math.random
local mathClamp = math.clamp
local mathSqrt = math.sqrt
local mathHuge = math.huge

local tick = tick
local pairs = pairs
local ipairs = ipairs
local type = type
local typeof = typeof
local pcall = pcall
local unpack = unpack
local tableInsert = table.insert
local tableRemove = table.remove
local tableSort = table.sort

-- ============================================================================
-- SETTINGS (COM NOVAS OPÇÕES)
-- ============================================================================
-- Modos de Rage
Settings.RageMode = Settings.RageMode or false
Settings.UltraRageMode = Settings.UltraRageMode or false
Settings.GodRageMode = Settings.GodRageMode or false

-- ★ NOVAS OPÇÕES DE TARGET ★
Settings.TargetMode = Settings.TargetMode or "FOV" -- "FOV" ou "Closest"
Settings.AimOutsideFOV = Settings.AimOutsideFOV or false -- Mira fora do FOV também
Settings.AutoResetOnKill = Settings.AutoResetOnKill or true -- Reset automático após kill

-- Silent Aim Settings
Settings.SilentAim = Settings.SilentAim or false
Settings.SilentFOV = Settings.SilentFOV or 500
Settings.SilentHitChance = Settings.SilentHitChance or 100
Settings.SilentHeadshotChance = Settings.SilentHeadshotChance or 100
Settings.SilentPrediction = Settings.SilentPrediction or true

-- Magic Bullet Settings
Settings.MagicBullet = Settings.MagicBullet or false
Settings.MagicBulletMethod = Settings.MagicBulletMethod or "Teleport"
Settings.MagicBulletSpeed = Settings.MagicBulletSpeed or 9999
Settings.MagicBulletIgnoreWalls = Settings.MagicBulletIgnoreWalls or true
Settings.MagicBulletAutoHit = Settings.MagicBulletAutoHit or true

-- Trigger Bot Settings
Settings.TriggerBot = Settings.TriggerBot or false
Settings.TriggerFOV = Settings.TriggerFOV or 50
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
Settings.UpdateRate = Settings.UpdateRate or 0
Settings.ThreadedAim = Settings.ThreadedAim or true

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================
local CameraCache = {ref = nil, lastUpdate = 0}

local function GetCamera()
    local now = tick()
    if now - CameraCache.lastUpdate > 0.05 or not CameraCache.ref then
        CameraCache.ref = workspace.CurrentCamera
        CameraCache.lastUpdate = now
    end
    return CameraCache.ref
end

local function SafeCall(func, name)
    local success, err = pcall(func)
    if not success then
        warn("[Aimbot] Erro em " .. (name or "unknown") .. ": " .. tostring(err))
    end
    return success, err
end

local function Clamp(value, min, max)
    return mathMax(min, mathMin(max, value))
end

local function RandomChance(percent)
    return mathRandom(1, 100) <= percent
end

local function DistanceSquared(pos1, pos2)
    local delta = pos1 - pos2
    return delta.X * delta.X + delta.Y * delta.Y + delta.Z * delta.Z
end

-- ★ NOVO: Validação de posição (evita mirar no chão)
local function IsValidAimPosition(position)
    if not position then return false end
    if typeof(position) ~= "Vector3" then return false end
    
    -- Verifica se a posição é muito baixa (provavelmente chão)
    local Camera = GetCamera()
    if Camera then
        local camY = Camera.CFrame.Position.Y
        -- Se a posição está mais de 50 studs abaixo da câmera, provavelmente é inválida
        if position.Y < camY - 50 then
            return false
        end
    end
    
    -- Verifica valores NaN ou infinitos
    if position.X ~= position.X or position.Y ~= position.Y or position.Z ~= position.Z then
        return false
    end
    
    return true
end

-- ============================================================================
-- RAYCAST PARAMS
-- ============================================================================
local RayParams = RaycastParams.new()
RayParams.FilterType = Enum.RaycastFilterType.Exclude
RayParams.FilterDescendantsInstances = {}
local RayParamsLastUpdate = 0

local function UpdateRayParams()
    local now = tick()
    if now - RayParamsLastUpdate < 0.5 then return end
    RayParamsLastUpdate = now
    
    local filter = {GetCamera()}
    if LocalPlayer.Character then
        tableInsert(filter, LocalPlayer.Character)
    end
    RayParams.FilterDescendantsInstances = filter
end

LocalPlayer.CharacterAdded:Connect(function()
    task.wait(0.1)
    RayParamsLastUpdate = 0
    UpdateRayParams()
end)
UpdateRayParams()

-- ============================================================================
-- VISIBILITY CACHE
-- ============================================================================
local VisibilityCache = {
    Data = {},
    Frame = 0,
    MaxAge = 4,
    CleanupInterval = 5,
}

function VisibilityCache:NextFrame()
    self.Frame = self.Frame + 1
    
    if self.Frame % self.CleanupInterval == 0 then
        local toRemove = {}
        local maxAge = self.MaxAge
        local currentFrame = self.Frame
        
        for key, data in pairs(self.Data) do
            if currentFrame - data.frame > maxAge then
                toRemove[#toRemove + 1] = key
            end
        end
        
        for i = 1, #toRemove do
            self.Data[toRemove[i]] = nil
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

function VisibilityCache:Invalidate(player)
    self.Data[player] = nil
end

-- ============================================================================
-- PART CACHE
-- ============================================================================
local PartCache = {}
local PartCacheTime = {}

local PART_NAMES = {
    "Head", "UpperTorso", "Torso", "HumanoidRootPart", "LowerTorso",
    "LeftUpperArm", "RightUpperArm", "LeftUpperLeg", "RightUpperLeg",
    "Left Arm", "Right Arm", "Left Leg", "Right Leg", "Neck"
}

local function BuildPartCacheFor(player)
    local char = player.Character
    if not char then 
        PartCache[player] = nil
        return 
    end
    
    local map = {}
    for i = 1, #PART_NAMES do
        local name = PART_NAMES[i]
        local p = char:FindFirstChild(name, true)
        if p and p:IsA("BasePart") then 
            map[name] = p 
        end
    end
    
    map._humanoid = char:FindFirstChildOfClass("Humanoid")
    map._anchor = map.HumanoidRootPart or map.Torso or map.Head
    map._model = char
    
    PartCache[player] = map
    PartCacheTime[player] = tick()
end

local function GetCachedPart(player, partName)
    local cache = PartCache[player]
    if cache then
        return cache[partName]
    end
    return nil
end

local function InvalidatePartCache(player)
    PartCache[player] = nil
    PartCacheTime[player] = nil
end

-- ★ NOVO: Verifica se o cache ainda é válido
local function IsPartCacheValid(player)
    local cache = PartCache[player]
    if not cache then return false end
    
    local anchor = cache._anchor
    if not anchor then return false end
    if not anchor.Parent then return false end
    if not anchor:IsDescendantOf(workspace) then return false end
    
    local humanoid = cache._humanoid
    if humanoid and humanoid.Health <= 0 then return false end
    
    return true
end

-- Setup part cache listeners
Players.PlayerAdded:Connect(function(player)
    player.CharacterAdded:Connect(function()
        task.wait(0.1)
        BuildPartCacheFor(player)
    end)
    player.CharacterRemoving:Connect(function()
        InvalidatePartCache(player)
        VisibilityCache:Invalidate(player)
    end)
    
    if player.Character then
        BuildPartCacheFor(player)
    end
end)

Players.PlayerRemoving:Connect(function(player)
    InvalidatePartCache(player)
    VisibilityCache:Invalidate(player)
end)

for _, player in ipairs(Players:GetPlayers()) do
    if player ~= LocalPlayer and player.Character then
        BuildPartCacheFor(player)
    end
    
    player.CharacterAdded:Connect(function()
        task.wait(0.1)
        BuildPartCacheFor(player)
    end)
    player.CharacterRemoving:Connect(function()
        InvalidatePartCache(player)
        VisibilityCache:Invalidate(player)
    end)
end

-- ============================================================================
-- PLAYER DATA HELPER
-- ============================================================================
local PlayerDataCache = {}
local PLAYER_DATA_CACHE_TTL = 0.1

local function GetPlayerData(player)
    if not player then return nil end
    
    local now = tick()
    local cached = PlayerDataCache[player]
    
    if cached and (now - cached.time) < PLAYER_DATA_CACHE_TTL then
        -- ★ FIX: Revalida se ainda é válido
        if cached.data and cached.data.isValid then
            local anchor = cached.data.anchor
            if anchor and anchor.Parent and anchor:IsDescendantOf(workspace) then
                local hum = cached.data.humanoid
                if not hum or hum.Health > 0 then
                    return cached.data
                end
            end
        end
        -- Cache inválido, limpa
        PlayerDataCache[player] = nil
    end
    
    -- Usa PartCache primeiro
    if IsPartCacheValid(player) then
        local partCache = PartCache[player]
        local anchor = partCache._anchor
        local humanoid = partCache._humanoid
        
        local data = {
            isValid = true,
            model = partCache._model,
            anchor = anchor,
            humanoid = humanoid,
            health = humanoid and humanoid.Health or 100,
            maxHealth = humanoid and humanoid.MaxHealth or 100,
        }
        PlayerDataCache[player] = {data = data, time = now}
        return data
    end
    
    -- Fallback para SemanticEngine
    local SemanticEngine = Core.SemanticEngine
    if SemanticEngine and SemanticEngine.GetCachedPlayerData then
        local data = SemanticEngine:GetCachedPlayerData(player)
        if data and data.isValid then 
            -- ★ FIX: Valida antes de cachear
            if data.anchor and data.anchor.Parent and data.anchor:IsDescendantOf(workspace) then
                if not data.humanoid or data.humanoid.Health > 0 then
                    PlayerDataCache[player] = {data = data, time = now}
                    return data
                end
            end
        end
    end
    
    -- Fallback manual
    local character = player.Character
    if not character then return nil end
    
    local anchor = character:FindFirstChild("HumanoidRootPart")
                or character:FindFirstChild("Torso")
                or character:FindFirstChild("Head")
    
    if not anchor or not anchor.Parent or not anchor:IsDescendantOf(workspace) then 
        return nil 
    end
    
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    
    -- ★ FIX: Não retorna dados de jogadores mortos
    if humanoid and humanoid.Health <= 0 then
        return nil
    end
    
    local data = {
        isValid = true,
        model = character,
        anchor = anchor,
        humanoid = humanoid,
        health = humanoid and humanoid.Health or 100,
        maxHealth = humanoid and humanoid.MaxHealth or 100,
    }
    
    PlayerDataCache[player] = {data = data, time = now}
    BuildPartCacheFor(player)
    
    return data
end

-- ★ NOVO: Invalida cache de player
local function InvalidatePlayerData(player)
    PlayerDataCache[player] = nil
    InvalidatePartCache(player)
    VisibilityCache:Invalidate(player)
end

Players.PlayerRemoving:Connect(function(player)
    InvalidatePlayerData(player)
end)

-- ============================================================================
-- TEAM CHECK
-- ============================================================================
local TeamCache = {}
local TEAM_CACHE_TTL = 1

local function AreSameTeam(player1, player2)
    if not player1 or not player2 then return false end
    
    local cacheKey = tostring(player1.UserId) .. "_" .. tostring(player2.UserId)
    local now = tick()
    local cached = TeamCache[cacheKey]
    
    if cached and (now - cached.time) < TEAM_CACHE_TTL then
        return cached.result
    end
    
    local result = false
    
    local SemanticEngine = Core.SemanticEngine
    if SemanticEngine and SemanticEngine.AreSameTeam then
        local success, res = pcall(function()
            return SemanticEngine:AreSameTeam(player1, player2)
        end)
        if success then 
            result = res 
        end
    else
        if player1.Team and player2.Team then
            result = player1.Team == player2.Team
        end
    end
    
    TeamCache[cacheKey] = {result = result, time = now}
    return result
end

-- ============================================================================
-- GET AIM PART
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

local PART_MAP = {
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

local function GetAimPart(player, partName)
    local data = GetPlayerData(player)
    if not data or not data.model then return nil end
    
    -- ★ FIX: Valida que o model ainda existe
    if not data.model.Parent then return nil end
    
    partName = partName or "Head"
    if type(partName) == "table" then
        partName = partName[1] or "Head"
    end
    
    local partCache = PartCache[player]
    if partCache then
        local candidates = PART_MAP[partName] or {partName}
        for i = 1, #candidates do
            local part = partCache[candidates[i]]
            if part and part.Parent then 
                return part 
            end
        end
    end
    
    local candidates = PART_MAP[partName] or {partName}
    local model = data.model
    
    for i = 1, #candidates do
        local part = model:FindFirstChild(candidates[i], true)
        if part and part:IsA("BasePart") and part.Parent then
            return part
        end
    end
    
    -- ★ FIX: Valida anchor antes de retornar
    if data.anchor and data.anchor.Parent then
        return data.anchor
    end
    
    return nil
end

-- ============================================================================
-- MULTI-PART AIM SYSTEM
-- ============================================================================
local function GetAllAimParts(player)
    if not IsPartCacheValid(player) then
        local data = GetPlayerData(player)
        if not data or not data.model then return {} end
        BuildPartCacheFor(player)
    end
    
    local partCache = PartCache[player]
    if not partCache then return {} end
    
    local parts = {}
    local partsToFind = {
        "Head", "UpperTorso", "LowerTorso", "HumanoidRootPart",
        "LeftUpperArm", "RightUpperArm", "LeftUpperLeg", "RightUpperLeg",
        "Torso", "Left Arm", "Right Arm", "Left Leg", "Right Leg"
    }
    
    for i = 1, #partsToFind do
        local partName = partsToFind[i]
        local part = partCache[partName]
        if part and part.Parent then
            parts[#parts + 1] = {
                part = part,
                name = partName,
                priority = PartPriorityMap[partName] or 10
            }
        end
    end
    
    tableSort(parts, function(a, b) return a.priority < b.priority end)
    
    return parts
end

local function GetBestAimPart(player, ignoreFOV)
    local data = GetPlayerData(player)
    if not data or not data.model then return nil end
    if not data.model.Parent then return nil end
    
    if Settings.GodRageMode or Settings.UltraRageMode then
        local head = GetAimPart(player, "Head")
        if head and head.Parent then return head end
    end
    
    if not Settings.MultiPartAim then
        return GetAimPart(player, Settings.AimPart)
    end
    
    local Camera = GetCamera()
    local camPos = Camera.CFrame.Position
    local mousePos = UserInputService:GetMouseLocation()
    
    local bestPart = nil
    local bestScore = mathHuge
    
    local allParts = GetAllAimParts(player)
    local maxPartsToCheck = Settings.GodRageMode and 1 or (Settings.RageMode and 3 or 5)
    local checked = 0
    
    local WorldToViewportPoint = Camera.WorldToViewportPoint
    
    for i = 1, #allParts do
        if checked >= maxPartsToCheck then break end
        
        local partData = allParts[i]
        local part = partData.part
        
        if not part or not part.Parent then continue end
        
        local screenPos, onScreen = WorldToViewportPoint(Camera, part.Position)
        
        if onScreen or Settings.GodRageMode or Settings.AimOutsideFOV then
            local distToMouse = onScreen and (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude or 9999
            local score = distToMouse + (partData.priority * 20)
            
            if partData.name == "Head" then
                score = score * 0.3
            end
            
            if score < bestScore then
                local visible = true
                if not Settings.IgnoreWalls and not Settings.MagicBullet and not Settings.GodRageMode then
                    local cachedVis, _, hit = VisibilityCache:Get(player)
                    if hit then
                        visible = cachedVis
                    else
                        UpdateRayParams()
                        local direction = part.Position - camPos
                        local ray = Workspace:Raycast(camPos, direction, RayParams)
                        if ray and ray.Instance and not ray.Instance:IsDescendantOf(data.model) then
                            visible = false
                        end
                        VisibilityCache:Set(player, visible, part)
                    end
                    checked = checked + 1
                end
                
                if visible then
                    bestScore = score
                    bestPart = part
                end
            end
        end
    end
    
    if not bestPart or not bestPart.Parent then
        return GetAimPart(player, Settings.AimPart)
    end
    
    return bestPart
end

-- ============================================================================
-- PREDICTION SYSTEM
-- ============================================================================
local PredictionHistory = {}
local LastPredUpdate = {}
local MAX_HISTORY = 8
local PRED_UPDATE_INTERVAL = 1/30

local function UpdatePredictionHistory(player, position, velocity)
    local now = tick()
    
    if LastPredUpdate[player] and (now - LastPredUpdate[player]) < PRED_UPDATE_INTERVAL then
        return
    end
    LastPredUpdate[player] = now
    
    if not PredictionHistory[player] then
        PredictionHistory[player] = {positions = {}, velocities = {}}
    end
    
    local history = PredictionHistory[player]
    
    tableInsert(history.positions, {position = position, time = now})
    if velocity then
        tableInsert(history.velocities, {velocity = velocity, time = now})
    end
    
    while #history.positions > MAX_HISTORY do
        tableRemove(history.positions, 1)
    end
    while #history.velocities > MAX_HISTORY do
        tableRemove(history.velocities, 1)
    end
end

local function ClearPredictionHistory(player)
    PredictionHistory[player] = nil
    LastPredUpdate[player] = nil
end

local function CalculateVelocity(player, anchor)
    if not anchor or not anchor.Parent then return Vector3.zero end
    
    local vel = anchor.AssemblyLinearVelocity or anchor.Velocity
    if vel and vel.Magnitude > 0.5 then 
        return vel 
    end
    
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
    if not targetPart.Parent then return nil end
    
    local basePos = targetPart.Position
    
    -- ★ FIX: Valida posição base
    if not IsValidAimPosition(basePos) then
        return nil
    end
    
    if not Settings.UsePrediction then
        return basePos
    end
    
    local data = GetPlayerData(player)
    if not data or not data.anchor then
        return basePos
    end
    
    if not data.anchor.Parent then
        return nil
    end
    
    local velocity = CalculateVelocity(player, data.anchor)
    local acceleration = Vector3.zero
    
    if Settings.GodRageMode then
        acceleration = CalculateAcceleration(player)
    end
    
    local yMultiplier = Settings.GodRageMode and 0.6 or (Settings.UltraRageMode and 0.5 or 0.4)
    
    if velocity.Y > 0 then
        velocity = Vector3.new(velocity.X, velocity.Y * yMultiplier, velocity.Z)
    end
    
    local Camera = GetCamera()
    local distSq = DistanceSquared(targetPart.Position, Camera.CFrame.Position)
    local distance = mathSqrt(distSq)
    
    local timeDiv = Settings.GodRageMode and 400 or (Settings.UltraRageMode and 500 or (Settings.RageMode and 600 or 800))
    local timeToTarget = Clamp(distance / timeDiv, 0.01, 0.35)
    
    local multiplier = Settings.PredictionMultiplier or 0.15
    if Settings.GodRageMode then
        multiplier = multiplier * 2.0
    elseif Settings.UltraRageMode then
        multiplier = multiplier * 1.6
    elseif Settings.RageMode then
        multiplier = multiplier * 1.3
    end
    
    local predictedPos = basePos + (velocity * multiplier * timeToTarget)
    
    if acceleration.Magnitude > 0.1 then
        predictedPos = predictedPos + (acceleration * 0.5 * timeToTarget * timeToTarget)
    end
    
    -- ★ FIX: Valida posição predita
    if not IsValidAimPosition(predictedPos) then
        return basePos
    end
    
    UpdatePredictionHistory(player, data.anchor.Position, velocity)
    
    return predictedPos
end

-- ============================================================================
-- VISIBILITY CHECK
-- ============================================================================
local function IsVisible(player, targetPart)
    if Settings.MagicBullet or Settings.IgnoreWalls or Settings.GodRageMode then
        return true
    end
    
    if not Settings.VisibleCheck then
        return true
    end
    
    local cached, cachedPart, hit = VisibilityCache:Get(player)
    if hit then 
        return cached 
    end
    
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
-- TARGET LOCK SYSTEM (MELHORADO)
-- ============================================================================
local TargetLock = {
    CurrentTarget = nil,
    LockTime = 0,
    LastScore = mathHuge,
    LastKill = 0,
    KillCount = 0,
    MinLockDuration = 0.05,
    MaxLockDuration = 0.5,
    ImprovementThreshold = 0.4,
    LastValidPosition = nil, -- ★ NOVO: Última posição válida
    DeathDetected = false, -- ★ NOVO: Flag de morte detectada
}

function TargetLock:Reset()
    -- ★ FIX: Limpa tudo ao resetar
    if self.CurrentTarget then
        ClearPredictionHistory(self.CurrentTarget)
        VisibilityCache:Invalidate(self.CurrentTarget)
    end
    
    self.CurrentTarget = nil
    self.LockTime = 0
    self.LastScore = mathHuge
    self.LastValidPosition = nil
    self.DeathDetected = false
end

-- ★ NOVO: Verifica se alvo está vivo
function TargetLock:IsTargetAlive()
    if not self.CurrentTarget then return false end
    
    local data = GetPlayerData(self.CurrentTarget)
    if not data then return false end
    if not data.isValid then return false end
    if not data.anchor or not data.anchor.Parent then return false end
    
    if data.humanoid then
        if data.humanoid.Health <= 0 then
            return false
        end
    end
    
    return true
end

function TargetLock:IsValid()
    if not self.CurrentTarget then return false end
    
    -- ★ FIX: Verifica se está vivo primeiro
    if not self:IsTargetAlive() then
        if not self.DeathDetected then
            self.DeathDetected = true
            self.KillCount = self.KillCount + 1
            self.LastKill = tick()
            
            if Notify and Settings.AutoResetOnKill then
                -- Notifica kill
            end
        end
        return false
    end
    
    self.DeathDetected = false
    
    local data = GetPlayerData(self.CurrentTarget)
    if not data or not data.isValid then return false end
    
    local Camera = GetCamera()
    local distSq = DistanceSquared(data.anchor.Position, Camera.CFrame.Position)
    
    local maxDist = Settings.MaxDistance or 2000
    if Settings.GodRageMode then
        maxDist = 99999
    elseif Settings.UltraRageMode then
        maxDist = maxDist * 3
    elseif Settings.RageMode then
        maxDist = maxDist * 2
    end
    
    if distSq > maxDist * maxDist then return false end
    
    -- ★ NOVO: Atualiza última posição válida
    self.LastValidPosition = data.anchor.Position
    
    return true
end

function TargetLock:TryLock(candidate, score)
    if not candidate then return end
    
    -- ★ FIX: Verifica se o candidato está vivo
    local data = GetPlayerData(candidate)
    if not data or not data.isValid then return end
    if data.humanoid and data.humanoid.Health <= 0 then return end
    
    local now = tick()
    
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
        self.DeathDetected = false
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
        self.DeathDetected = false
        return
    end
    
    local lockDuration = now - self.LockTime
    
    if Settings.AutoSwitch and lockDuration > (Settings.TargetSwitchDelay or 0.1) then
        self.CurrentTarget = candidate
        self.LockTime = now
        self.LastScore = score
        self.DeathDetected = false
        return
    end
    
    if lockDuration > self.MaxLockDuration then
        self.CurrentTarget = candidate
        self.LockTime = now
        self.LastScore = score
        self.DeathDetected = false
        return
    end
    
    if score < self.LastScore * self.ImprovementThreshold then
        self.CurrentTarget = candidate
        self.LockTime = now
        self.LastScore = score
        self.DeathDetected = false
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
-- AIM CONTROLLER
-- ============================================================================
local AimController = {
    IsAiming = false,
    OriginalCFrame = nil,
    HasMouseMoveRel = false,
    LastAimPos = nil,
    AimHistory = {},
    MaxHistory = 5,
    SmoothHistory = {},
    LastValidAimPos = nil, -- ★ NOVO
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
    self.LastValidAimPos = nil
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
    if Settings.GodRageMode then return 1.0 end
    if Settings.UltraRageMode then return 0.98 end
    
    if Settings.RageMode then
        return (not smoothing or smoothing <= 2) and 0.95 or Clamp(0.9 - (smoothing * 0.02), 0.6, 0.95)
    end
    
    if not smoothing or smoothing <= 0 then return 1.0 end
    if smoothing <= 1 then return 0.85 end
    if smoothing <= 3 then return 0.55 end
    if smoothing <= 5 then return 0.35 end
    if smoothing <= 8 then return 0.2 end
    if smoothing <= 12 then return 0.12 end
    
    return Clamp(0.7 / smoothing, 0.02, 0.08)
end

function AimController:ApplyShakeReduction(targetPos)
    if Settings.ShakeReduction <= 0 then
        return targetPos
    end
    
    tableInsert(self.AimHistory, targetPos)
    while #self.AimHistory > Settings.ShakeReduction + 2 do
        tableRemove(self.AimHistory, 1)
    end
    
    if #self.AimHistory < 2 then
        return targetPos
    end
    
    local avgPos = Vector3.zero
    local totalWeight = 0
    
    for i, pos in ipairs(self.AimHistory) do
        local weight = i * i
        avgPos = avgPos + pos * weight
        totalWeight = totalWeight + weight
    end
    
    return avgPos / totalWeight
end

function AimController:ApplyAim(targetPosition, smoothing)
    -- ★ FIX: Validação rigorosa da posição
    if not targetPosition then 
        return false 
    end
    
    if not IsValidAimPosition(targetPosition) then
        -- Tenta usar última posição válida
        if self.LastValidAimPos and IsValidAimPosition(self.LastValidAimPos) then
            targetPosition = self.LastValidAimPos
        else
            return false
        end
    end
    
    -- ★ NOVO: Salva última posição válida
    self.LastValidAimPos = targetPosition
    
    local Camera = GetCamera()
    if not Camera then return false end
    
    targetPosition = self:ApplyShakeReduction(targetPosition)
    
    local method = Settings.AimMethod or "Camera"
    local smoothFactor = self:CalculateSmoothFactor(smoothing)
    
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
        
        if not onScreen and not Settings.GodRageMode and not Settings.AimOutsideFOV then 
            return 
        end
        
        local viewport = Camera.ViewportSize
        local centerX = viewport.X / 2
        local centerY = viewport.Y / 2
        
        local deltaX = screenPos.X - centerX
        local deltaY = screenPos.Y - centerY
        
        local moveX, moveY
        if Settings.GodRageMode or Settings.UltraRageMode then
            moveX = deltaX
            moveY = deltaY
        else
            moveX = deltaX * smoothFactor
            moveY = deltaY * smoothFactor
        end
        
        if mathAbs(moveX) < 0.1 and mathAbs(moveY) < 0.1 then
            return
        end
        
        mousemoverel(moveX, moveY)
    end)
    
    return success
end

-- ============================================================================
-- SILENT AIM SYSTEM
-- ============================================================================
local SilentAim = {
    Enabled = false,
    HookedNamecall = false,
    Hooks = {},
    LastTarget = nil,
    LastAimPos = nil,
    Initialized = false,
}

local WEAPON_KEYWORDS_SET = {
    shoot = true, fire = true, bullet = true, gun = true, 
    weapon = true, damage = true, hit = true, attack = true
}

local function IsWeaponRemote(name)
    local lowerName = name:lower()
    for keyword in pairs(WEAPON_KEYWORDS_SET) do
        if lowerName:find(keyword) then
            return true
        end
    end
    return false
end

function SilentAim:GetTargetPosition()
    local target = TargetLock:GetTarget()
    if not target then
        target = FindBestTargetForSilent()
    end
    
    if not target then return nil end
    
    -- ★ FIX: Verifica se alvo está vivo
    local data = GetPlayerData(target)
    if not data or not data.isValid then return nil end
    if data.humanoid and data.humanoid.Health <= 0 then return nil end
    
    self.LastTarget = target
    
    local aimPart = GetBestAimPart(target, true)
    if not aimPart or not aimPart.Parent then return nil end
    
    if Settings.SilentHeadshotChance < 100 then
        if not RandomChance(Settings.SilentHeadshotChance) then
            local torso = GetAimPart(target, "UpperTorso")
            if torso and torso.Parent then aimPart = torso end
        end
    end
    
    local pos = PredictPosition(target, aimPart)
    
    -- ★ FIX: Valida posição
    if not pos or not IsValidAimPosition(pos) then
        return nil
    end
    
    self.LastAimPos = pos
    return pos
end

function SilentAim:IsInFOV(position)
    if Settings.GodRageMode then return true end
    
    local Camera = GetCamera()
    local screenPos, onScreen = Camera:WorldToViewportPoint(position)
    
    if not onScreen then return Settings.UltraRageMode or Settings.AimOutsideFOV end
    
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
    if Settings.SilentHitChance < 100 then
        return RandomChance(Settings.SilentHitChance)
    end
    return true
end

function SilentAim:Initialize()
    if self.Initialized then return end
    self.Initialized = true
    
    SafeCall(function()
        if type(getrawmetatable) ~= "function" then return end
        
        local mt = getrawmetatable(game)
        if not mt then return end
        
        local oldNamecall = mt.__namecall
        
        if type(hookmetamethod) == "function" then
            local newNamecall = function(self, ...)
                if not SilentAim.Enabled or not Settings.SilentAim then
                    return oldNamecall(self, ...)
                end
                
                local method = getnamecallmethod()
                
                if method == "Raycast" or method == "FindPartOnRay" or 
                   method == "FindPartOnRayWithIgnoreList" or method == "FindPartOnRayWithWhitelist" then
                    
                    if SilentAim:ShouldHit() then
                        local targetPos = SilentAim:GetTargetPosition()
                        if targetPos and SilentAim:IsInFOV(targetPos) then
                            local args = {...}
                            
                            if method == "Raycast" then
                                local origin = args[1]
                                if origin then
                                    args[2] = (targetPos - origin).Unit * 5000
                                    return oldNamecall(self, unpack(args))
                                end
                            else
                                local ray = args[1]
                                if typeof(ray) == "Ray" then
                                    args[1] = Ray.new(ray.Origin, (targetPos - ray.Origin).Unit * 5000)
                                    return oldNamecall(self, unpack(args))
                                end
                            end
                        end
                    end
                end
                
                return oldNamecall(self, ...)
            end
            
            pcall(function()
                hookmetamethod(game, "__namecall", newNamecall)
                SilentAim.HookedNamecall = true
            end)
        end
    end, "SilentAim:InitializeNamecall")
    
    SafeCall(function()
        if type(hookfunction) ~= "function" then return end
        
        local function HookRemote(remote)
            if SilentAim.Hooks[remote] then return end
            if not remote:IsA("RemoteEvent") and not remote:IsA("RemoteFunction") then return end
            if not IsWeaponRemote(remote.Name) then return end
            
            if remote:IsA("RemoteEvent") then
                local oldFireServer = remote.FireServer
                SilentAim.Hooks[remote] = oldFireServer
                
                remote.FireServer = function(self, ...)
                    if SilentAim.Enabled and Settings.SilentAim then
                        local targetPos = SilentAim:GetTargetPosition()
                        if targetPos and SilentAim:ShouldHit() then
                            local args = {...}
                            for i, arg in ipairs(args) do
                                if typeof(arg) == "Vector3" then
                                    args[i] = targetPos
                                elseif typeof(arg) == "CFrame" then
                                    args[i] = CFrame.new(targetPos)
                                elseif type(arg) == "table" then
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
        
        local containers = {workspace, game:GetService("ReplicatedStorage")}
        for _, container in ipairs(containers) do
            pcall(function()
                for _, remote in ipairs(container:GetDescendants()) do
                    pcall(function() HookRemote(remote) end)
                end
            end)
        end
        
        game.DescendantAdded:Connect(function(desc)
            if not (desc:IsA("RemoteEvent") or desc:IsA("RemoteFunction")) then return end
            if not IsWeaponRemote(desc.Name) then return end
            
            task.defer(function()
                pcall(function() HookRemote(desc) end)
            end)
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
-- MAGIC BULLET SYSTEM
-- ============================================================================
local MagicBullet = {
    Enabled = false,
    BulletHooks = {},
    LastFire = 0,
    Initialized = false,
}

local TrackedProjectiles = setmetatable({}, {__mode = "k"})
local ProjectileHeartbeatConnection = nil

local BULLET_KEYWORDS_SET = {
    bullet = true, projectile = true, shot = true, missile = true, arrow = true
}

local function IsBullet(name)
    local lowerName = name:lower()
    for keyword in pairs(BULLET_KEYWORDS_SET) do
        if lowerName:find(keyword) then
            return true
        end
    end
    return false
end

local function TrackProjectile(proj)
    TrackedProjectiles[proj] = tick()
end

local function ProcessProjectiles()
    if not MagicBullet.Enabled or not Settings.MagicBullet then return end
    
    local target = TargetLock:GetTarget()
    if not target then return end
    
    -- ★ FIX: Verifica se alvo está vivo
    local data = GetPlayerData(target)
    if not data or not data.isValid then return end
    if data.humanoid and data.humanoid.Health <= 0 then return end
    
    local aimPart = GetBestAimPart(target)
    if not aimPart or not aimPart.Parent then return end
    
    local targetPos = PredictPosition(target, aimPart)
    if not targetPos or not IsValidAimPosition(targetPos) then return end
    
    for proj, _ in pairs(TrackedProjectiles) do
        if not proj or not proj.Parent then
            TrackedProjectiles[proj] = nil
        else
            local direction = (targetPos - proj.Position).Unit
            
            if Settings.MagicBulletMethod == "Teleport" then
                proj.CFrame = CFrame.new(targetPos)
            elseif Settings.MagicBulletMethod == "Curve" then
                proj.AssemblyLinearVelocity = direction * Settings.MagicBulletSpeed
            elseif Settings.MagicBulletMethod == "Phase" then
                proj.CanCollide = false
                proj.AssemblyLinearVelocity = direction * Settings.MagicBulletSpeed
            end
        end
    end
end

function MagicBullet:Initialize()
    if self.Initialized then return end
    self.Initialized = true
    
    if not ProjectileHeartbeatConnection then
        ProjectileHeartbeatConnection = RunService.Heartbeat:Connect(ProcessProjectiles)
    end
    
    workspace.DescendantAdded:Connect(function(desc)
        if not desc:IsA("BasePart") then return end
        if not IsBullet(desc.Name) then return end
        
        TrackProjectile(desc)
    end)
    
    SafeCall(function()
        if type(hookfunction) ~= "function" then return end
        
        local function HookWeaponRemote(remote)
            if not remote:IsA("RemoteEvent") then return end
            if SilentAim.Hooks[remote] then return end
            if MagicBullet.BulletHooks[remote] then return end
            if not IsWeaponRemote(remote.Name) then return end
            
            local oldFire = remote.FireServer
            MagicBullet.BulletHooks[remote] = oldFire
            
            remote.FireServer = function(self, ...)
                if MagicBullet.Enabled and Settings.MagicBullet then
                    local target = TargetLock:GetTarget()
                    if target then
                        local aimPart = GetBestAimPart(target)
                        if aimPart and aimPart.Parent then
                            local targetPos = PredictPosition(target, aimPart)
                            if targetPos and IsValidAimPosition(targetPos) then
                                local args = {...}
                                
                                for i, arg in ipairs(args) do
                                    if typeof(arg) == "Vector3" then
                                        args[i] = targetPos
                                    elseif typeof(arg) == "CFrame" then
                                        args[i] = CFrame.lookAt(arg.Position, targetPos)
                                    elseif typeof(arg) == "Ray" then
                                        args[i] = Ray.new(arg.Origin, (targetPos - arg.Origin).Unit * 5000)
                                    elseif type(arg) == "table" then
                                        if arg.Position then arg.Position = targetPos end
                                        if arg.EndPos then arg.EndPos = targetPos end
                                        if arg.HitPos then arg.HitPos = targetPos end
                                        if arg.Origin and arg.Direction then
                                            arg.Direction = (targetPos - arg.Origin).Unit * 5000
                                        end
                                    end
                                end
                                
                                return oldFire(self, unpack(args))
                            end
                        end
                    end
                end
                return oldFire(self, ...)
            end
        end
        
        local containers = {workspace, game:GetService("ReplicatedStorage")}
        for _, container in ipairs(containers) do
            pcall(function()
                for _, remote in ipairs(container:GetDescendants()) do
                    pcall(function() HookWeaponRemote(remote) end)
                end
            end)
        end
        
        game.DescendantAdded:Connect(function(desc)
            if not desc:IsA("RemoteEvent") then return end
            if not IsWeaponRemote(desc.Name) then return end
            
            task.defer(function()
                pcall(function() HookWeaponRemote(desc) end)
            end)
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
    
    if Settings.GodRageMode then
        triggerFOV = triggerFOV * 5
    elseif Settings.UltraRageMode then
        triggerFOV = triggerFOV * 3
    elseif Settings.RageMode then
        triggerFOV = triggerFOV * 2
    end
    
    local triggerFOVSq = triggerFOV * triggerFOV
    local camPos = Camera.CFrame.Position
    local WorldToViewportPoint = Camera.WorldToViewportPoint
    
    for _, player in ipairs(Players:GetPlayers()) do
        if player == LocalPlayer then continue end
        
        local data = GetPlayerData(player)
        if not data or not data.isValid then continue end
        if data.humanoid and data.humanoid.Health <= 0 then continue end
        
        if Settings.IgnoreTeamAimbot and AreSameTeam(LocalPlayer, player) then continue end
        
        local targetPart = Settings.TriggerHeadOnly and GetAimPart(player, "Head") or GetBestAimPart(player)
        if not targetPart or not targetPart.Parent then continue end
        
        local screenPos, onScreen = WorldToViewportPoint(Camera, targetPart.Position)
        if not onScreen then continue end
        
        local dx = screenPos.X - mousePos.X
        local dy = screenPos.Y - mousePos.Y
        local distSq = dx * dx + dy * dy
        
        if distSq <= triggerFOVSq then
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
    local rate = Settings.GodRageMode and 0.01 or (Settings.UltraRageMode and 0.02 or (Settings.RageMode and 0.03 or self.FireRate))
    
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
-- TARGET FINDER (COM TARGET MODE)
-- ============================================================================
local CachedPlayers = {}
local LastPlayerCacheUpdate = 0
local PLAYER_CACHE_TTL = 0.3

local function GetCachedPlayers()
    local now = tick()
    if now - LastPlayerCacheUpdate > PLAYER_CACHE_TTL then
        CachedPlayers = Players:GetPlayers()
        LastPlayerCacheUpdate = now
    end
    return CachedPlayers
end

-- ★ NOVA FUNÇÃO: FindBestTarget com Target Mode
local function FindBestTarget()
    local Camera = GetCamera()
    if not Camera then return nil, mathHuge end
    
    local camPos = Camera.CFrame.Position
    local camLook = Camera.CFrame.LookVector
    local mousePos = UserInputService:GetMouseLocation()
    local WorldToViewportPoint = Camera.WorldToViewportPoint
    
    -- ★ NOVO: Pega o modo de target
    local targetMode = Settings.TargetMode or "FOV" -- "FOV" ou "Closest"
    
    local currentFOV = Settings.AimbotFOV or 180
    if Settings.GodRageMode then
        currentFOV = 99999
    elseif Settings.UltraRageMode then
        currentFOV = currentFOV * 5
    elseif Settings.RageMode then
        currentFOV = currentFOV * 3
    end
    local currentFOVSq = currentFOV * currentFOV
    
    local maxDist = Settings.MaxDistance or 2000
    if Settings.GodRageMode then
        maxDist = 99999
    elseif Settings.UltraRageMode then
        maxDist = maxDist * 4
    elseif Settings.RageMode then
        maxDist = maxDist * 2
    end
    local maxDistSq = maxDist * maxDist
    
    local candidates = {}
    local allPlayers = GetCachedPlayers()
    
    for i = 1, #allPlayers do
        local player = allPlayers[i]
        if player == LocalPlayer then continue end
        
        local data = GetPlayerData(player)
        if not data or not data.isValid or not data.anchor then continue end
        if not data.anchor.Parent or not data.anchor:IsDescendantOf(workspace) then continue end
        
        -- ★ FIX: Verifica se está vivo
        if data.humanoid and data.humanoid.Health <= 0 then continue end
        
        if Settings.IgnoreTeamAimbot and AreSameTeam(LocalPlayer, player) then continue end
        
        local distSq = DistanceSquared(data.anchor.Position, camPos)
        if distSq > maxDistSq then continue end
        
        local screenPos, onScreen = WorldToViewportPoint(Camera, data.anchor.Position)
        
        -- ★ NOVO: AimOutsideFOV permite mirar em alvos fora da tela
        local allowOutside = Settings.GodRageMode or Settings.UltraRageMode or Settings.AimOutsideFOV
        if not allowOutside and not onScreen then continue end
        
        local distToMouse = onScreen and (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude or 99999
        local distToMouseSq = distToMouse * distToMouse
        
        -- ★ NOVO: Se AimOutsideFOV está ativo, não checa FOV
        local checkFOV = Settings.UseAimbotFOV and not Settings.AimOutsideFOV and not Settings.GodRageMode
        if checkFOV and distToMouseSq > currentFOVSq then continue end
        
        local dirToTarget = (data.anchor.Position - camPos).Unit
        local dot = camLook:Dot(dirToTarget)
        
        local minDot = Settings.GodRageMode and -1 or (Settings.UltraRageMode and -0.5 or (Settings.RageMode and -0.2 or 0.1))
        -- ★ NOVO: AimOutsideFOV permite mirar em qualquer direção
        if Settings.AimOutsideFOV then
            minDot = -1
        end
        if dot < minDot then continue end
        
        local distance = mathSqrt(distSq)
        local score
        
        -- ★ NOVO: Calcula score baseado no TargetMode
        if targetMode == "Closest" then
            -- Modo Closest: prioriza distância
            score = distance
            
            -- Ainda considera saúde em rage modes
            if (Settings.RageMode or Settings.UltraRageMode or Settings.GodRageMode) and data.humanoid then
                local healthPercent = data.humanoid.Health / data.humanoid.MaxHealth
                score = score * (0.3 + healthPercent * 0.7)
            end
        else
            -- Modo FOV: prioriza proximidade ao mouse
            if Settings.GodRageMode then
                local healthPenalty = data.humanoid and (data.humanoid.Health / data.humanoid.MaxHealth) or 1
                score = distance * 0.3 * healthPenalty
            elseif Settings.UltraRageMode then
                score = distance * 0.4 + distToMouse * 0.1
            elseif Settings.RageMode then
                score = distance * 0.3 + distToMouse * 0.4
            else
                score = distToMouse * 1.0 + distance * 0.15
            end
            
            if (Settings.RageMode or Settings.UltraRageMode or Settings.GodRageMode) and data.humanoid then
                local healthPercent = data.humanoid.Health / data.humanoid.MaxHealth
                score = score * (0.3 + healthPercent * 0.7)
            end
        end
        
        candidates[#candidates + 1] = {
            player = player,
            data = data,
            score = score,
            distance = distance,
            distToMouse = distToMouse,
            onScreen = onScreen,
        }
    end
    
    -- Se não encontrou candidatos e AimOutsideFOV está ativo, não retorna nil ainda
    if #candidates == 0 then
        return nil, mathHuge
    end
    
    tableSort(candidates, function(a, b) return a.score < b.score end)
    
    local maxChecks = Settings.GodRageMode and 1 or (Settings.UltraRageMode and 2 or (Settings.RageMode and 3 or 5))
    local checked = 0
    
    for i = 1, #candidates do
        if checked >= maxChecks then break end
        
        local candidate = candidates[i]
        
        -- ★ FIX: Revalida que ainda está vivo
        local data = GetPlayerData(candidate.player)
        if not data or not data.isValid then continue end
        if data.humanoid and data.humanoid.Health <= 0 then continue end
        
        local aimPart = GetBestAimPart(candidate.player)
        if not aimPart or not aimPart.Parent then continue end
        
        checked = checked + 1
        
        if Settings.IgnoreWalls or Settings.MagicBullet or Settings.GodRageMode or not Settings.VisibleCheck then
            return candidate.player, candidate.score
        end
        
        if IsVisible(candidate.player, aimPart) then
            return candidate.player, candidate.score
        end
    end
    
    if (Settings.IgnoreWalls or Settings.MagicBullet or not Settings.VisibleCheck) and #candidates > 0 then
        return candidates[1].player, candidates[1].score
    end
    
    return nil, mathHuge
end

local function FindBestTargetForSilent()
    local Camera = GetCamera()
    if not Camera then return nil end
    
    local camPos = Camera.CFrame.Position
    local mousePos = UserInputService:GetMouseLocation()
    local WorldToViewportPoint = Camera.WorldToViewportPoint
    
    local silentFOV = Settings.SilentFOV or 500
    if Settings.GodRageMode then
        silentFOV = 99999
    elseif Settings.UltraRageMode then
        silentFOV = silentFOV * 4
    elseif Settings.RageMode then
        silentFOV = silentFOV * 2
    end
    
    local bestTarget = nil
    local bestScore = mathHuge
    local allPlayers = GetCachedPlayers()
    
    for i = 1, #allPlayers do
        local player = allPlayers[i]
        if player == LocalPlayer then continue end
        
        local data = GetPlayerData(player)
        if not data or not data.isValid then continue end
        if data.humanoid and data.humanoid.Health <= 0 then continue end
        
        if Settings.IgnoreTeamAimbot and AreSameTeam(LocalPlayer, player) then continue end
        
        local targetPart = GetBestAimPart(player)
        if not targetPart or not targetPart.Parent then continue end
        
        local screenPos, onScreen = WorldToViewportPoint(Camera, targetPart.Position)
        
        local allowOutside = Settings.GodRageMode or Settings.AimOutsideFOV
        if onScreen or allowOutside then
            local distToMouse = onScreen and (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude or 9999
            
            if distToMouse <= silentFOV or Settings.GodRageMode or Settings.AimOutsideFOV then
                local distSq = DistanceSquared(targetPart.Position, camPos)
                local score = distToMouse + mathSqrt(distSq) * 0.1
                
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
    LastPredUpdate = {}
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
    _lastUpdateTick = 0,
}

function Aimbot:Update()
    local now = tick()
    local updateRate = Settings.UpdateRate or 0
    if updateRate > 0 then
        if now - self._lastUpdateTick < (1 / updateRate) then
            return
        end
        self._lastUpdateTick = now
    end
    
    VisibilityCache:NextFrame()
    AimbotState.FrameCount = AimbotState.FrameCount + 1
    
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
    
    if Settings.SilentAim then
        SilentAim:Enable()
    end
    
    if Settings.MagicBullet then
        MagicBullet:Enable()
    end
    
    local bestTarget, bestScore = FindBestTarget()
    
    if bestTarget then
        TargetLock:TryLock(bestTarget, bestScore)
    end
    
    local target = TargetLock:GetTarget()
    
    if target then
        -- ★ FIX: Verifica se alvo ainda é válido
        local data = GetPlayerData(target)
        if not data or not data.isValid then
            TargetLock:Reset()
            AimController:StopAiming()
            return
        end
        
        if data.humanoid and data.humanoid.Health <= 0 then
            TargetLock:Reset()
            AimController:StopAiming()
            return
        end
        
        local aimPart = GetBestAimPart(target)
        
        if aimPart and aimPart.Parent then
            local aimPos = PredictPosition(target, aimPart)
            
            -- ★ FIX: Valida posição antes de aplicar
            if not aimPos or not IsValidAimPosition(aimPos) then
                -- Tenta usar posição direta da parte
                aimPos = aimPart.Position
                if not IsValidAimPosition(aimPos) then
                    TargetLock:Reset()
                    AimController:StopAiming()
                    return
                end
            end
            
            local baseSm = Settings.SmoothingFactor or 5
            local smoothing = baseSm
            
            if Settings.GodRageMode then
                smoothing = 0
            elseif Settings.UltraRageMode then
                smoothing = 0
            elseif Settings.RageMode then
                smoothing = mathMin(baseSm, 1)
            elseif Settings.UseAdaptiveSmoothing then
                local distSq = DistanceSquared(data.anchor.Position, GetCamera().CFrame.Position)
                
                if distSq < 2500 then
                    smoothing = baseSm * 1.4
                elseif distSq > 90000 then
                    smoothing = baseSm * 0.6
                end
            end
            
            AimController:ApplyAim(aimPos, smoothing)
            
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

function Aimbot:SetTargetMode(mode)
    Settings.TargetMode = mode
    if Notify then
        Notify("Target Mode", mode == "Closest" and "📏 MAIS PRÓXIMO" or "🎯 FOV")
    end
end

function Aimbot:SetAimOutsideFOV(enabled)
    Settings.AimOutsideFOV = enabled
    if Notify then
        Notify("Aim Outside FOV", enabled and "ATIVADO ✅" or "DESATIVADO")
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
    print("  AIMBOT v4.2 - TARGET MODES + FIX")
    print("═══════════════════════════════════════════")
    print("[✓] Target Mode: " .. (Settings.TargetMode or "FOV"))
    print("[✓] Aim Outside FOV: " .. tostring(Settings.AimOutsideFOV))
    print("[✓] Auto Reset on Kill: " .. tostring(Settings.AutoResetOnKill))
    print("[✓] MouseMoveRel: " .. (AimController.HasMouseMoveRel and "OK" or "N/A"))
    print("[✓] SilentAim Hooks: " .. (SilentAim.HookedNamecall and "OK" or "N/A"))
    print("═══════════════════════════════════════════")
end

function Aimbot:Debug()
    print("\n═══════════════ AIMBOT DEBUG v4.2 ═══════════════")
    print("Initialized: " .. tostring(self.Initialized))
    print("Connection Active: " .. tostring(self.Connection ~= nil))
    
    print("\n─── TARGET SETTINGS ───")
    print("  TargetMode: " .. (Settings.TargetMode or "FOV"))
    print("  AimOutsideFOV: " .. tostring(Settings.AimOutsideFOV))
    print("  AutoResetOnKill: " .. tostring(Settings.AutoResetOnKill))
    
    print("\n─── RAGE STATUS ───")
    print("  RageMode: " .. tostring(Settings.RageMode))
    print("  UltraRageMode: " .. tostring(Settings.UltraRageMode))
    print("  GodRageMode: " .. tostring(Settings.GodRageMode))
    
    print("\n─── FEATURES ───")
    print("  SilentAim: " .. tostring(Settings.SilentAim))
    print("  MagicBullet: " .. tostring(Settings.MagicBullet))
    print("  TriggerBot: " .. tostring(Settings.TriggerBot))
    
    print("\n─── Target ───")
    local target = TargetLock:GetTarget()
    print("  Current: " .. (target and target.Name or "None"))
    print("  Is Alive: " .. tostring(target and TargetLock:IsTargetAlive() or false))
    print("  Kills: " .. TargetLock.KillCount)
    print("  Last Valid Pos: " .. tostring(TargetLock.LastValidPosition))
    
    print("\n─── Test ───")
    local t, s = FindBestTarget()
    print("  Best: " .. (t and (t.Name .. " score:" .. string.format("%.1f", s)) or "None"))
    
    print("═══════════════════════════════════════════\n")
end

function Aimbot:ForceReset()
    print("[Aimbot] Force reset")
    AimbotState:Reset()
    PartCache = {}
    PartCacheTime = {}
    TeamCache = {}
    PlayerDataCache = {}
    PredictionHistory = {}
    LastPredUpdate = {}
    VisibilityCache:Clear()
    AimController.LastValidAimPos = nil
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
    
    Update = function() Aimbot:Update() end,
    Initialize = function() Aimbot:Initialize() end,
    Toggle = function(enabled) Aimbot:Toggle(enabled) end,
    
    SetRageMode = function(enabled) Aimbot:SetRageMode(enabled) end,
    SetUltraRageMode = function(enabled) Aimbot:SetUltraRageMode(enabled) end,
    SetGodRageMode = function(enabled) Aimbot:SetGodRageMode(enabled) end,
    
    SetSilentAim = function(enabled) Aimbot:SetSilentAim(enabled) end,
    SetMagicBullet = function(enabled) Aimbot:SetMagicBullet(enabled) end,
    SetTriggerBot = function(enabled) Aimbot:SetTriggerBot(enabled) end,
    
    -- ★ NOVAS FUNÇÕES
    SetTargetMode = function(mode) Aimbot:SetTargetMode(mode) end,
    SetAimOutsideFOV = function(enabled) Aimbot:SetAimOutsideFOV(enabled) end,
    
    SetSilentFOV = function(fov) Aimbot:SetSilentFOV(fov) end,
    SetTriggerFOV = function(fov) Aimbot:SetTriggerFOV(fov) end,
    SetAimbotFOV = function(fov) Aimbot:SetAimbotFOV(fov) end,
    
    Debug = function() Aimbot:Debug() end,
    ForceReset = function() Aimbot:ForceReset() end,
    
    CameraBypass = {
        GetLockedTarget = function() return TargetLock:GetTarget() end,
        ClearLock = function() TargetLock:Reset() end,
    },
    
    GetClosestPlayer = FindBestTarget,
    AimMethods = AimController,
}

return Aimbot