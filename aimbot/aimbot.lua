-- ============================================================================
-- FORGEHUB - TARGETING CORE MODULE v4.6
-- CORRIGIDO: Lazy loading, proteção anti-detecção, verificações robustas
-- ============================================================================

local TargetingCore = {
    _init = false,
    _active = false,
    _origCF = nil,
    _hasMMR = false,
    _lastPos = nil,
    _validPos = nil,
    _history = {},
    _smoothHist = {},
    _maxHist = 5,
    
    -- Controle robusto
    _holdUntil = nil,
    _controlled = false,
    _prevType = nil,
    _prevSubject = nil,
    _prevCF = nil,
    _lerpConn = nil,
    
    -- Fallback
    _failCount = {},
    _maxFails = 3,
    
    -- Snap timing
    _lastSnap = 0,
    _snapDur = 0.06,
    _snapCD = 0.18,
}

-- ============================================================================
-- SERVIÇOS COM LAZY LOADING SEGURO
-- ============================================================================
local Services = {}
local ServiceCache = {}

local function GetService(name)
    if ServiceCache[name] then
        return ServiceCache[name]
    end
    
    local success, service = pcall(function()
        return game:GetService(name)
    end)
    
    if success and service then
        ServiceCache[name] = service
        return service
    end
    
    return nil
end

-- Lazy getters
local function GetRunService()
    return GetService("RunService")
end

local function GetPlayers()
    return GetService("Players")
end

local function GetUIS()
    return GetService("UserInputService")
end

-- ============================================================================
-- DEPENDENCIES (preenchidas na inicialização)
-- ============================================================================
local Utils = nil
local Settings = nil
local EventBus = nil
local Hooks = nil
local LocalPlayer = nil

-- ============================================================================
-- FUNÇÕES DE EXECUTOR COM VERIFICAÇÃO SEGURA
-- ============================================================================
local ExecutorFuncs = {
    mouseMove = nil,
    isAvailable = false
}

local function InitExecutorFuncs()
    -- Verifica mousemoverel de forma segura
    local mmrCheck = {
        "mousemoverel",
        "mouse_moverel", 
        "Input.MouseMove",
        "input.mousemoverel"
    }
    
    for _, name in ipairs(mmrCheck) do
        local success, func = pcall(function()
            return getfenv()[name] or _G[name] or (getgenv and getgenv()[name])
        end)
        
        if success and type(func) == "function" then
            ExecutorFuncs.mouseMove = func
            ExecutorFuncs.isAvailable = true
            break
        end
    end
    
    return ExecutorFuncs.isAvailable
end

local function SafeMouseMove(dx, dy)
    if not ExecutorFuncs.isAvailable or not ExecutorFuncs.mouseMove then
        return false
    end
    
    local success = pcall(function()
        ExecutorFuncs.mouseMove(dx, dy)
    end)
    
    return success
end

-- ============================================================================
-- TARGET LOCK
-- ============================================================================
local Lock = {
    Current = nil,
    Time = 0,
    Score = math.huge,
    LastKill = 0,
    Kills = 0,
    MinDur = 0.05,
    MaxDur = 0.5,
    Threshold = 0.4,
    ValidPos = nil,
    DeathFlag = false,
}

function Lock:Clear()
    if self.Current then
        if TargetingCore._predHistory then
            TargetingCore._predHistory[self.Current] = nil
        end
        if TargetingCore._failCount then
            TargetingCore._failCount[self.Current] = nil
        end
        if Utils then
            Utils.VisibilityCache:Invalidate(self.Current)
        end
    end
    
    self.Current = nil
    self.Time = 0
    self.Score = math.huge
    self.ValidPos = nil
    self.DeathFlag = false
    
    if EventBus then
        pcall(function()
            EventBus:Emit("target:lost", self.Current)
        end)
    end
end

function Lock:IsAlive()
    if not self.Current then return false end
    if not Utils then return false end
    
    local data = Utils.GetPlayerData(self.Current)
    if not data then return false end
    if not data.isValid then return false end
    if not data.anchor or not data.anchor.Parent then return false end
    
    if data.humanoid then
        local success, health = pcall(function()
            return data.humanoid.Health
        end)
        if success and health <= 0 then
            return false
        end
    end
    
    return true
end

function Lock:Validate()
    if not self.Current then return false end
    
    if not self:IsAlive() then
        if not self.DeathFlag then
            self.DeathFlag = true
            self.Kills = self.Kills + 1
            self.LastKill = tick()
            
            if EventBus then
                pcall(function()
                    EventBus:Emit("target:killed", self.Current)
                end)
            end
        end
        return false
    end
    
    self.DeathFlag = false
    
    local data = Utils.GetPlayerData(self.Current)
    if not data or not data.isValid then return false end
    
    local Camera = Utils.GetCamera()
    if not Camera then return false end
    
    local distSq = Utils.DistanceSquared(data.anchor.Position, Camera.CFrame.Position)
    
    local maxDist = Settings.MaxDistance or 2000
    local isEnhanced = Settings.EnhancedMode
    local isUltra = Settings.UltraMode
    local isMax = Settings.MaxMode
    
    if isMax then
        maxDist = 99999
    elseif isUltra then
        maxDist = maxDist * 3
    elseif isEnhanced then
        maxDist = maxDist * 2
    end
    
    if distSq > maxDist * maxDist then return false end
    
    self.ValidPos = data.anchor.Position
    
    return true
end

function Lock:TryAcquire(candidate, score)
    if not candidate then return end
    if not Utils then return end
    
    local data = Utils.GetPlayerData(candidate)
    if not data or not data.isValid then return end
    
    if data.humanoid then
        local success, health = pcall(function()
            return data.humanoid.Health
        end)
        if success and health <= 0 then return end
    end
    
    local now = tick()
    
    -- Ajusta parâmetros baseado no modo
    if Settings.MaxMode then
        self.MaxDur = 0.06
        self.Threshold = 0.12
    elseif Settings.UltraMode then
        self.MaxDur = 0.12
        self.Threshold = 0.18
    elseif Settings.EnhancedMode then
        self.MaxDur = 0.2
        self.Threshold = 0.28
    elseif Settings.AutoSwitch then
        self.MaxDur = Settings.SwitchDelay or 0.1
        self.Threshold = 0.5
    else
        self.MaxDur = 1.5
        self.Threshold = 0.7
    end
    
    -- Primeiro alvo
    if not self.Current then
        self.Current = candidate
        self.Time = now
        self.Score = score
        self.DeathFlag = false
        
        if EventBus then
            pcall(function()
                EventBus:Emit("target:locked", candidate, score)
            end)
        end
        return
    end
    
    -- Mesmo alvo
    if self.Current == candidate then
        self.Score = score
        return
    end
    
    -- Alvo inválido
    if not self:Validate() then
        self.Current = candidate
        self.Time = now
        self.Score = score
        self.DeathFlag = false
        
        if EventBus then
            pcall(function()
                EventBus:Emit("target:locked", candidate, score)
            end)
        end
        return
    end
    
    local lockDur = now - self.Time
    
    -- AutoSwitch
    if Settings.AutoSwitch and lockDur > (Settings.SwitchDelay or 0.1) then
        self.Current = candidate
        self.Time = now
        self.Score = score
        self.DeathFlag = false
        return
    end
    
    -- Tempo máximo
    if lockDur > self.MaxDur then
        self.Current = candidate
        self.Time = now
        self.Score = score
        self.DeathFlag = false
        return
    end
    
    -- Score muito melhor
    if score < self.Score * self.Threshold then
        self.Current = candidate
        self.Time = now
        self.Score = score
        self.DeathFlag = false
    end
end

function Lock:Get()
    if self:Validate() then
        return self.Current
    end
    self:Clear()
    return nil
end

-- ============================================================================
-- PREDICTION
-- ============================================================================
TargetingCore._predHistory = {}
TargetingCore._lastPredUpdate = {}
local PRED_HISTORY_SIZE = 8
local PRED_INTERVAL = 1/30

function TargetingCore:UpdatePredHistory(player, pos, vel)
    local now = tick()
    
    local lastUpdate = self._lastPredUpdate[player]
    if lastUpdate and (now - lastUpdate) < PRED_INTERVAL then
        return
    end
    self._lastPredUpdate[player] = now
    
    if not self._predHistory[player] then
        self._predHistory[player] = {positions = {}, velocities = {}}
    end
    
    local hist = self._predHistory[player]
    
    table.insert(hist.positions, {pos = pos, t = now})
    if vel then
        table.insert(hist.velocities, {vel = vel, t = now})
    end
    
    while #hist.positions > PRED_HISTORY_SIZE do
        table.remove(hist.positions, 1)
    end
    while #hist.velocities > PRED_HISTORY_SIZE do
        table.remove(hist.velocities, 1)
    end
end

function TargetingCore:ClearPredHistory(player)
    self._predHistory[player] = nil
    self._lastPredUpdate[player] = nil
    self._failCount[player] = nil
end

function TargetingCore:CalcVelocity(player, anchor)
    if not anchor or not anchor.Parent then return Vector3.zero end
    
    local vel
    local success = pcall(function()
        vel = anchor.AssemblyLinearVelocity or anchor.Velocity
    end)
    
    if success and vel and vel.Magnitude > 0.5 then 
        return vel 
    end
    
    local hist = self._predHistory[player]
    if hist and #hist.positions >= 2 then
        local newest = hist.positions[#hist.positions]
        local oldest = hist.positions[1]
        local dt = newest.t - oldest.t
        
        if dt > 0.02 then
            local dp = newest.pos - oldest.pos
            return dp / dt
        end
    end
    
    return Vector3.zero
end

function TargetingCore:CalcAccel(player)
    local hist = self._predHistory[player]
    if not hist or #hist.velocities < 3 then
        return Vector3.zero
    end
    
    local newest = hist.velocities[#hist.velocities]
    local oldest = hist.velocities[#hist.velocities - 2]
    local dt = newest.t - oldest.t
    
    if dt > 0.02 then
        local dv = newest.vel - oldest.vel
        return dv / dt
    end
    
    return Vector3.zero
end

function TargetingCore:Predict(player, part)
    if not part then return nil end
    if not part.Parent then return nil end
    
    local basePos = part.Position
    
    if not Utils.IsValidAimPosition(basePos, Settings) then
        return nil
    end
    
    if not Settings.UsePrediction then
        return basePos
    end
    
    local data = Utils.GetPlayerData(player)
    if not data or not data.anchor then
        return basePos
    end
    
    if not data.anchor.Parent then
        return nil
    end
    
    local vel = self:CalcVelocity(player, data.anchor)
    local accel = Vector3.zero
    
    if Settings.MaxMode or Settings.UltraMode then
        accel = self:CalcAccel(player)
    end
    
    local yMult = Settings.MaxMode and 0.7 or (Settings.UltraMode and 0.6 or 0.4)
    
    if vel.Y > 0 then
        vel = Vector3.new(vel.X, vel.Y * yMult, vel.Z)
    end
    
    local Camera = Utils.GetCamera()
    if not Camera then return basePos end
    
    local distSq = Utils.DistanceSquared(part.Position, Camera.CFrame.Position)
    local dist = math.sqrt(distSq)
    
    local timeDiv = Settings.MaxMode and 300 or (Settings.UltraMode and 350 or (Settings.EnhancedMode and 420 or 800))
    local timeToTarget = Utils.Clamp(dist / timeDiv, 0.01, 0.45)
    
    local mult = Settings.PredictionMultiplier or 0.15
    if Settings.MaxMode then
        mult = mult * 3.0
    elseif Settings.UltraMode then
        mult = mult * 2.2
    elseif Settings.EnhancedMode then
        mult = mult * 1.6
    end
    
    local predicted = basePos + (vel * mult * timeToTarget)
    
    if accel.Magnitude > 0.1 then
        predicted = predicted + (accel * 0.5 * timeToTarget * timeToTarget)
    end
    
    if not Utils.IsValidAimPosition(predicted, Settings) then
        self._failCount[player] = (self._failCount[player] or 0) + 1
        
        local isEnhanced = Settings.EnhancedMode or Settings.UltraMode or Settings.MaxMode
        
        if isEnhanced then
            if self._failCount[player] >= self._maxFails * 2 then
                self._failCount[player] = 0
                return basePos
            end
            return basePos
        else
            if self._failCount[player] >= self._maxFails then
                self._failCount[player] = 0
                return nil
            end
            return basePos
        end
    end
    
    self._failCount[player] = 0
    self:UpdatePredHistory(player, data.anchor.Position, vel)
    
    return predicted
end

-- ============================================================================
-- DETECÇÃO DE ESCADAS/RAMPAS
-- ============================================================================
function TargetingCore:IsOnStairs(part, data)
    if not part or not part.Parent then return false end
    
    local params = Utils.RayParamsManager:Get()
    
    local success, result = pcall(function()
        return workspace:Raycast(part.Position, Vector3.new(0, -8, 0), params)
    end)
    
    if success and result and result.Position then
        local groundDist = part.Position.Y - result.Position.Y
        if groundDist <= 8 then
            return true
        end
    end
    
    return false
end

function TargetingCore:IsClimbing(data)
    if not data or not data.humanoid then return false end
    
    local hum = data.humanoid
    
    local success, state = pcall(function()
        return hum:GetState()
    end)
    
    if success and state == Enum.HumanoidStateType.Climbing then
        return true
    end
    
    if data.anchor then
        local success2, vel = pcall(function()
            return data.anchor.AssemblyLinearVelocity or data.anchor.Velocity
        end)
        if success2 and vel and vel.Y > 1 then
            return true
        end
    end
    
    return false
end

function TargetingCore:GetAdaptiveMinHeight(dist)
    local baseMin = Settings.MinAimHeightBelowCamera or 50
    local adaptiveMin = math.max(8, baseMin - (dist * 0.03))
    return adaptiveMin
end

-- ============================================================================
-- PARTES DE MIRA
-- ============================================================================
function TargetingCore:GetPart(player, partName)
    local data = Utils.GetPlayerData(player)
    if not data or not data.model then return nil end
    if not data.model.Parent then return nil end
    
    partName = partName or "Head"
    if type(partName) == "table" then
        partName = partName[1] or "Head"
    end
    
    local cache = Utils.GetPartCache(player)
    if cache then
        local candidates = Utils.PART_MAP[partName] or {partName}
        for i = 1, #candidates do
            local part = cache[candidates[i]]
            if part and part.Parent then 
                return part 
            end
        end
    end
    
    local candidates = Utils.PART_MAP[partName] or {partName}
    local model = data.model
    
    for i = 1, #candidates do
        local success, part = pcall(function()
            return model:FindFirstChild(candidates[i], true)
        end)
        if success and part and part:IsA("BasePart") and part.Parent then
            return part
        end
    end
    
    if data.anchor and data.anchor.Parent then
        return data.anchor
    end
    
    return nil
end

function TargetingCore:GetAllParts(player)
    if not Utils.IsPartCacheValid(player) then
        local data = Utils.GetPlayerData(player)
        if not data or not data.model then return {} end
        Utils.BuildPartCacheFor(player)
    end
    
    local cache = Utils.GetPartCache(player)
    if not cache then return {} end
    
    local parts = {}
    local partsToFind = {
        "Head", "UpperTorso", "LowerTorso", "HumanoidRootPart",
        "LeftUpperArm", "RightUpperArm", "LeftUpperLeg", "RightUpperLeg",
        "Torso", "Left Arm", "Right Arm", "Left Leg", "Right Leg"
    }
    
    for i = 1, #partsToFind do
        local pName = partsToFind[i]
        local part = cache[pName]
        if part and part.Parent then
            parts[#parts + 1] = {
                part = part,
                name = pName,
                priority = Utils.PartPriorityMap[pName] or 10
            }
        end
    end
    
    table.sort(parts, function(a, b) return a.priority < b.priority end)
    
    return parts
end

function TargetingCore:GetBestPart(player, ignoreFOV)
    local data = Utils.GetPlayerData(player)
    if not data or not data.model then return nil end
    if not data.model.Parent then return nil end
    
    local isEnhanced = Settings.EnhancedMode or Settings.UltraMode or Settings.MaxMode
    
    if isEnhanced and Settings.HeadOnly then
        local head = self:GetPart(player, "Head")
        if head and head.Parent then return head end
    end
    
    if Settings.MaxMode or Settings.UltraMode then
        local head = self:GetPart(player, "Head")
        if head and head.Parent then return head end
    end
    
    if not Settings.MultiPartAim then
        return self:GetPart(player, Settings.AimPart)
    end
    
    local Camera = Utils.GetCamera()
    if not Camera then return nil end
    
    local camPos = Camera.CFrame.Position
    
    local UIS = GetUIS()
    if not UIS then return nil end
    
    local mousePos = UIS:GetMouseLocation()
    
    local bestPart = nil
    local bestScore = math.huge
    
    local allParts = self:GetAllParts(player)
    local maxCheck = Settings.MaxMode and 1 or (Settings.EnhancedMode and 3 or 5)
    local checked = 0
    
    for i = 1, #allParts do
        if checked >= maxCheck then break end
        
        local pData = allParts[i]
        local part = pData.part
        
        if not part or not part.Parent then continue end
        
        local success, screenPos, onScreen = pcall(function()
            return Camera:WorldToViewportPoint(part.Position)
        end)
        
        if not success then continue end
        
        if onScreen or Settings.MaxMode or Settings.AimOutsideFOV then
            local distToMouse = onScreen and (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude or 9999
            local distSq = Utils.DistanceSquared(part.Position, camPos)
            local distance = math.sqrt(distSq)
            
            local vertPenalty = math.max(0, (camPos.Y - part.Position.Y) - (distance * 0.12))
            
            local score = distToMouse + (pData.priority * 20) + (vertPenalty * 10)
            
            if pData.name == "Head" then
                score = score * (isEnhanced and 0.25 or 0.35)
            elseif pData.name == "UpperTorso" or pData.name == "Torso" then
                score = score * 0.6
            end
            
            if score < bestScore then
                local visible = true
                if not Settings.IgnoreWalls and not Settings.MagicBullet and not Settings.MaxMode then
                    local cached, _, hit = Utils.VisibilityCache:Get(player)
                    if hit then
                        visible = cached
                    else
                        Utils.RayParamsManager:Update(LocalPlayer, Camera)
                        local dir = part.Position - camPos
                        
                        local raySuccess, ray = pcall(function()
                            return workspace:Raycast(camPos, dir, Utils.RayParamsManager:Get())
                        end)
                        
                        if raySuccess and ray and ray.Instance and not ray.Instance:IsDescendantOf(data.model) then
                            visible = false
                        end
                        Utils.VisibilityCache:Set(player, visible, part)
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
        return self:GetPart(player, Settings.AimPart)
    end
    
    return bestPart
end

-- ============================================================================
-- BUSCA DE ALVOS
-- ============================================================================
local CachedPlayers = {}
local LastCacheUpdate = 0
local CACHE_TTL = 0.3

local function GetCachedPlayers()
    local now = tick()
    if now - LastCacheUpdate > CACHE_TTL then
        local Players = GetPlayers()
        if Players then
            CachedPlayers = Players:GetPlayers()
        end
        LastCacheUpdate = now
    end
    return CachedPlayers
end

function TargetingCore:GetLocalVelocity()
    if not LocalPlayer or not LocalPlayer.Character then return Vector3.zero end
    
    local success, vel = pcall(function()
        local hrp = LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if not hrp then return Vector3.zero end
        return hrp.AssemblyLinearVelocity or hrp.Velocity or Vector3.zero
    end)
    
    return success and vel or Vector3.zero
end

function TargetingCore:FindBest()
    local Camera = Utils.GetCamera()
    if not Camera then return nil, math.huge end
    
    local camPos = Camera.CFrame.Position
    local camLook = Camera.CFrame.LookVector
    
    local UIS = GetUIS()
    if not UIS then return nil, math.huge end
    
    local mousePos = UIS:GetMouseLocation()
    
    local targetMode = Settings.TargetMode or "FOV"
    local isEnhanced = Settings.EnhancedMode or Settings.UltraMode or Settings.MaxMode
    
    local currentFOV = Settings.AimbotFOV or 180
    if Settings.MaxMode then
        currentFOV = 99999
    elseif Settings.UltraMode then
        currentFOV = currentFOV * 5
    elseif Settings.EnhancedMode then
        currentFOV = currentFOV * 3
    end
    
    local cosThreshold = Utils.CalculateFOVCosThreshold(currentFOV)
    local currentFOVSq = currentFOV * currentFOV
    
    local maxDist = Settings.MaxDistance or 2000
    if Settings.MaxMode then
        maxDist = 99999
    elseif Settings.UltraMode then
        maxDist = maxDist * 4
    elseif Settings.EnhancedMode then
        maxDist = maxDist * 2
    end
    local maxDistSq = maxDist * maxDist
    
    local myVel = self:GetLocalVelocity()
    
    local candidates = {}
    local allPlayers = GetCachedPlayers()
    
    for i = 1, #allPlayers do
        local player = allPlayers[i]
        if player == LocalPlayer then continue end
        
        local data = Utils.GetPlayerData(player)
        if not data or not data.isValid or not data.anchor then continue end
        if not data.anchor.Parent or not data.anchor:IsDescendantOf(workspace) then continue end
        
        if data.humanoid then
            local success, health = pcall(function()
                return data.humanoid.Health
            end)
            if success and health <= 0 then continue end
        end
        
        if Settings.IgnoreTeam and Utils.AreSameTeam(LocalPlayer, player) then continue end
        
        local distSq = Utils.DistanceSquared(data.anchor.Position, camPos)
        if distSq > maxDistSq then continue end
        
        local aimPart = self:GetBestPart(player)
        if not aimPart or not aimPart.Parent then continue end
        
        local success, screenPos, onScreen = pcall(function()
            return Camera:WorldToViewportPoint(aimPart.Position)
        end)
        
        if not success then continue end
        
        local allowOutside = Settings.MaxMode or Settings.UltraMode or Settings.AimOutsideFOV
        if not allowOutside and not onScreen then continue end
        
        local dirToTarget = (aimPart.Position - camPos).Unit
        local dot = camLook:Dot(dirToTarget)
        
        if not Settings.AimOutsideFOV and not Settings.MaxMode then
            if dot < cosThreshold then continue end
        end
        
        local distance = math.sqrt(distSq)
        
        local adaptiveMinHeight = self:GetAdaptiveMinHeight(distance)
        local heightDiff = camPos.Y - aimPart.Position.Y
        
        if heightDiff > adaptiveMinHeight then
            local isOnStairs = self:IsOnStairs(aimPart, data)
            local isClimbing = self:IsClimbing(data)
            
            if not isOnStairs and not isClimbing then
                continue
            end
        end
        
        local distToMouse = onScreen and (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude or 99999
        local distToMouseSq = distToMouse * distToMouse
        
        local checkFOV = Settings.UseAimbotFOV and not Settings.AimOutsideFOV and not Settings.MaxMode
        if checkFOV and distToMouseSq > currentFOVSq then continue end
        
        local targetVel = self:CalcVelocity(player, data.anchor)
        local relVel = targetVel - myVel
        local dirToCam = (camPos - aimPart.Position).Unit
        local approachSpeed = relVel:Dot(dirToCam)
        
        local score
        
        if targetMode == "Closest" then
            local ang = 1 - dot
            score = distance * 0.15 + distToMouse * 0.1 + (ang * 3)
            
            if approachSpeed > 0 then
                score = score - math.clamp(approachSpeed, 0, 120) * 0.25
            end
            
            if isEnhanced and data.humanoid then
                local success2, healthPercent = pcall(function()
                    return data.humanoid.Health / data.humanoid.MaxHealth
                end)
                if success2 then
                    score = score * (0.2 + healthPercent * 0.8)
                end
            end
        else
            if Settings.MaxMode then
                local healthPenalty = 1
                if data.humanoid then
                    local success2, hp = pcall(function()
                        return data.humanoid.Health / data.humanoid.MaxHealth
                    end)
                    if success2 then healthPenalty = hp end
                end
                score = distance * 0.2 * healthPenalty
            elseif Settings.UltraMode then
                score = distance * 0.25 + distToMouse * 0.1
            elseif Settings.EnhancedMode then
                score = distance * 0.2 + distToMouse * 0.35
            else
                score = distToMouse * 1.0 + distance * 0.15
            end
            
            local angPenalty = (1 - dot) * 8
            score = score + angPenalty
            
            if approachSpeed > 0 then
                score = score - math.clamp(approachSpeed, 0, 120) * 0.35
            end
            
            if isEnhanced and data.humanoid then
                local success2, healthPercent = pcall(function()
                    return data.humanoid.Health / data.humanoid.MaxHealth
                end)
                if success2 then
                    score = score * (0.2 + healthPercent * 0.8)
                end
            end
        end
        
        candidates[#candidates + 1] = {
            player = player,
            data = data,
            score = score,
            distance = distance,
            distToMouse = distToMouse,
            onScreen = onScreen,
            aimPart = aimPart,
            approachSpeed = approachSpeed,
        }
    end
    
    if #candidates == 0 then
        return nil, math.huge
    end
    
    table.sort(candidates, function(a, b) return a.score < b.score end)
    
    local maxChecks = Settings.MaxMode and 1 or (Settings.UltraMode and 2 or (Settings.EnhancedMode and 3 or 5))
    local checked = 0
    
    for i = 1, #candidates do
        if checked >= maxChecks then break end
        
        local cand = candidates[i]
        
        local data = Utils.GetPlayerData(cand.player)
        if not data or not data.isValid then continue end
        
        if data.humanoid then
            local success, health = pcall(function()
                return data.humanoid.Health
            end)
            if success and health <= 0 then continue end
        end
        
        checked = checked + 1
        
        if Settings.IgnoreWalls or Settings.MagicBullet or Settings.MaxMode or not Settings.VisibleCheck then
            return cand.player, cand.score
        end
        
        if self:CheckVisible(cand.player, cand.aimPart) then
            return cand.player, cand.score
        end
    end
    
    if (Settings.IgnoreWalls or Settings.MagicBullet or not Settings.VisibleCheck) and #candidates > 0 then
        return candidates[1].player, candidates[1].score
    end
    
    return nil, math.huge
end

function TargetingCore:FindBestForSilent()
    local Camera = Utils.GetCamera()
    if not Camera then return nil end
    
    local camPos = Camera.CFrame.Position
    
    local UIS = GetUIS()
    if not UIS then return nil end
    
    local mousePos = UIS:GetMouseLocation()
    
    local silentFOV = Settings.SilentFOV or 500
    if Settings.MaxMode then
        silentFOV = 99999
    elseif Settings.UltraMode then
        silentFOV = silentFOV * 4
    elseif Settings.EnhancedMode then
        silentFOV = silentFOV * 2
    end
    
    local bestTarget = nil
    local bestScore = math.huge
    local allPlayers = GetCachedPlayers()
    
    for i = 1, #allPlayers do
        local player = allPlayers[i]
        if player == LocalPlayer then continue end
        
        local data = Utils.GetPlayerData(player)
        if not data or not data.isValid then continue end
        
        if data.humanoid then
            local success, health = pcall(function()
                return data.humanoid.Health
            end)
            if success and health <= 0 then continue end
        end
        
        if Settings.IgnoreTeam and Utils.AreSameTeam(LocalPlayer, player) then continue end
        
        local targetPart = self:GetBestPart(player)
        if not targetPart or not targetPart.Parent then continue end
        
        local success, screenPos, onScreen = pcall(function()
            return Camera:WorldToViewportPoint(targetPart.Position)
        end)
        
        if not success then continue end
        
        local allowOutside = Settings.MaxMode or Settings.AimOutsideFOV
        if onScreen or allowOutside then
            local distToMouse = onScreen and (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude or 9999
            
            if distToMouse <= silentFOV or Settings.MaxMode or Settings.AimOutsideFOV then
                local distSq = Utils.DistanceSquared(targetPart.Position, camPos)
                local score = distToMouse + math.sqrt(distSq) * 0.1
                
                if score < bestScore then
                    bestScore = score
                    bestTarget = player
                end
            end
        end
    end
    
    return bestTarget
end

function TargetingCore:CheckVisible(player, targetPart)
    if Settings.MagicBullet or Settings.IgnoreWalls or Settings.MaxMode then
        return true
    end
    
    if not Settings.VisibleCheck then
        return true
    end
    
    local cached, _, hit = Utils.VisibilityCache:Get(player)
    if hit then 
        return cached 
    end
    
    local Camera = Utils.GetCamera()
    local data = Utils.GetPlayerData(player)
    if not data then return false end
    
    local origin = Camera.CFrame.Position
    local direction = targetPart.Position - origin
    
    Utils.RayParamsManager:Update(LocalPlayer, Camera)
    
    local success, ray = pcall(function()
        return workspace:Raycast(origin, direction, Utils.RayParamsManager:Get())
    end)
    
    local visible = true
    if success and ray and ray.Instance then
        if not ray.Instance:IsDescendantOf(data.model) then
            visible = false
        end
    end
    
    Utils.VisibilityCache:Set(player, visible, targetPart)
    return visible
end

-- ============================================================================
-- CONTROLADOR DE MIRA
-- ============================================================================
function TargetingCore:DetectMethods()
    InitExecutorFuncs()
    
    local caps = nil
    if Hooks then
        pcall(function()
            caps = Hooks:GetCapabilities()
        end)
    end
    
    if caps then
        self._hasMMR = caps.HasMouseMoveRel or ExecutorFuncs.isAvailable
    else
        self._hasMMR = ExecutorFuncs.isAvailable
    end
end

function TargetingCore:StartAiming()
    if self._active then return end
    self._active = true
    self._controlled = true
    
    local Camera = Utils.GetCamera()
    if not Camera then return end
    
    self._prevType = Camera.CameraType
    self._prevSubject = Camera.CameraSubject
    self._prevCF = Camera.CFrame
    self._origCF = Camera.CFrame
    
    if EventBus then
        pcall(function()
            EventBus:Emit("aim:start")
        end)
    end
end

function TargetingCore:StopAiming()
    if not self._active then return end
    self._active = false
    
    if self._lerpConn then
        pcall(function()
            self._lerpConn:Disconnect()
        end)
        self._lerpConn = nil
    end
    
    local prevCF = self._prevCF or self._origCF
    local prevType = self._prevType
    local prevSubject = self._prevSubject
    
    self._origCF = nil
    self._lastPos = nil
    self._validPos = nil
    self._history = {}
    self._smoothHist = {}
    
    local restoreAllowed = Settings.RestoreCameraOnStop
    if restoreAllowed == nil then
        restoreAllowed = false
    end
    
    Utils.SafeCall(function()
        local Camera = Utils.GetCamera()
        if not Camera then 
            self._controlled = false
            return 
        end
        
        if not restoreAllowed then
            self._controlled = false
            
            if prevType and Camera.CameraType == Enum.CameraType.Scriptable then
                Camera.CameraType = prevType
            end
            if prevSubject then
                Camera.CameraSubject = prevSubject
            elseif LocalPlayer and LocalPlayer.Character then
                local hum = LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
                if hum then
                    Camera.CameraSubject = hum
                end
            end
            return
        end
        
        local method = Settings.AimMethod or "Camera"
        
        if method == "MouseMoveRel" and self._hasMMR then
            task.delay(0.1, function()
                if not self._controlled then return end
                self._controlled = false
                
                if prevType and Camera.CameraType == Enum.CameraType.Scriptable then
                    Camera.CameraType = prevType
                end
                if prevSubject then
                    Camera.CameraSubject = prevSubject
                end
            end)
        else
            if prevCF then
                local duration = 0.18
                local t0 = tick()
                local start = Camera.CFrame
                
                local RS = GetRunService()
                if RS then
                    self._lerpConn = RS.RenderStepped:Connect(function()
                        local a = math.clamp((tick() - t0) / duration, 0, 1)
                        
                        if not self._controlled and a < 1 then
                            if self._lerpConn then
                                self._lerpConn:Disconnect()
                                self._lerpConn = nil
                            end
                            return
                        end
                        
                        Camera.CFrame = start:Lerp(prevCF, a)
                        
                        if a >= 1 then
                            if self._lerpConn then
                                self._lerpConn:Disconnect()
                                self._lerpConn = nil
                            end
                            
                            self._controlled = false
                            
                            if prevType then
                                Camera.CameraType = prevType
                            end
                            if prevSubject then
                                Camera.CameraSubject = prevSubject
                            elseif LocalPlayer and LocalPlayer.Character then
                                local hum = LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
                                if hum then
                                    Camera.CameraSubject = hum
                                end
                            end
                        end
                    end)
                end
            else
                self._controlled = false
                
                if LocalPlayer and LocalPlayer.Character then
                    local hum = LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
                    if hum and Camera.CameraType ~= Enum.CameraType.Scriptable then
                        Camera.CameraSubject = hum
                    end
                end
            end
        end
    end, "StopAiming")
    
    if EventBus then
        pcall(function()
            EventBus:Emit("aim:stop")
        end)
    end
end

function TargetingCore:HoldAndStop(seconds)
    seconds = seconds or 0.18
    self._holdUntil = tick() + seconds
end

function TargetingCore:CalcSmooth(smoothing)
    if Settings.MaxMode then return 1.0 end
    if Settings.UltraMode then return 0.98 end
    
    if Settings.EnhancedMode then
        return (not smoothing or smoothing <= 2) and 0.95 or Utils.Clamp(0.9 - (smoothing * 0.02), 0.6, 0.95)
    end
    
    if not smoothing or smoothing <= 0 then return 1.0 end
    if smoothing <= 1 then return 0.85 end
    if smoothing <= 3 then return 0.55 end
    if smoothing <= 5 then return 0.35 end
    if smoothing <= 8 then return 0.2 end
    if smoothing <= 12 then return 0.12 end
    
    return Utils.Clamp(0.7 / smoothing, 0.02, 0.08)
end

function TargetingCore:ApplyShakeReduction(targetPos)
    if Settings.ShakeReduction <= 0 then
        return targetPos
    end
    
    table.insert(self._history, targetPos)
    while #self._history > Settings.ShakeReduction + 2 do
        table.remove(self._history, 1)
    end
    
    if #self._history < 2 then
        return targetPos
    end
    
    local avgPos = Vector3.zero
    local totalWeight = 0
    
    for i, pos in ipairs(self._history) do
        local weight = i * i
        avgPos = avgPos + pos * weight
        totalWeight = totalWeight + weight
    end
    
    return avgPos / totalWeight
end

function TargetingCore:ApplyAim(targetPos, smoothing)
    if not targetPos then 
        return false 
    end
    
    local isEnhanced = Settings.EnhancedMode
    local isUltra = Settings.UltraMode
    local isMax = Settings.MaxMode
    
    if isMax then
        smoothing = 0
    elseif isUltra then
        smoothing = 0
    elseif isEnhanced then
        smoothing = math.min(smoothing or 1, 1)
    end
    
    if not Utils.IsValidAimPosition(targetPos, Settings) then
        if self._validPos and Utils.IsValidAimPosition(self._validPos, Settings) then
            targetPos = self._validPos
        else
            return false
        end
    end
    
    self._validPos = targetPos
    
    local Camera = Utils.GetCamera()
    if not Camera then return false end
    
    targetPos = self:ApplyShakeReduction(targetPos)
    
    local method = Settings.AimMethod or "Camera"
    local smoothFactor = self:CalcSmooth(smoothing)
    
    local skipDeadzone = isEnhanced or isUltra or isMax
    
    if Settings.UseDeadzone and not skipDeadzone then
        local success, screenPos, onScreen = pcall(function()
            return Camera:WorldToViewportPoint(targetPos)
        end)
        
        if success and onScreen then
            local UIS = GetUIS()
            if UIS then
                local mousePos = UIS:GetMouseLocation()
                local dist = (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude
                
                local deadzone = Settings.DeadzoneRadius or 2
                if dist < deadzone then
                    return true
                end
            end
        end
    end
    
    local success = false
    
    if method == "MouseMoveRel" and self._hasMMR then
        success = self:Method_MMR(targetPos, smoothFactor)
    else
        success = self:Method_Cam(targetPos, smoothFactor)
    end
    
    return success
end

function TargetingCore:Method_Cam(targetPos, smoothFactor)
    local success = pcall(function()
        self:StartAiming()
        
        local Camera = Utils.GetCamera()
        local camPos = Camera.CFrame.Position
        local dir = targetPos - camPos
        
        if dir.Magnitude < 0.001 then return end
        
        local targetCF = CFrame.lookAt(camPos, targetPos)
        
        local isEnhanced = Settings.EnhancedMode or Settings.UltraMode or Settings.MaxMode
        
        if isEnhanced then
            local now = tick()
            local snapCD = self._snapCD or 0.18
            
            if (now - (self._lastSnap or 0)) >= snapCD then
                Camera.CFrame = targetCF
                self._lastSnap = now
                return
            else
                Camera.CFrame = Camera.CFrame:Lerp(targetCF, 0.92)
                return
            end
        end
        
        if Settings.MaxMode or smoothFactor >= 0.99 then
            Camera.CFrame = targetCF
        elseif Settings.UltraMode or smoothFactor >= 0.95 then
            Camera.CFrame = Camera.CFrame:Lerp(targetCF, 0.95)
        else
            local currentRot = Camera.CFrame.Rotation
            local targetRot = targetCF.Rotation
            local smoothedRot = currentRot:Lerp(targetRot, smoothFactor)
            Camera.CFrame = CFrame.new(camPos) * smoothedRot
        end
    end)
    
    return success
end

function TargetingCore:Method_MMR(targetPos, smoothFactor)
    if not self._hasMMR then
        return self:Method_Cam(targetPos, smoothFactor)
    end
    
    local success = pcall(function()
        self._active = true
        self._controlled = false
        
        local Camera = Utils.GetCamera()
        
        local success2, screenPos, onScreen = pcall(function()
            return Camera:WorldToViewportPoint(targetPos)
        end)
        
        if not success2 then return end
        
        if not onScreen and not Settings.MaxMode and not Settings.AimOutsideFOV then 
            return 
        end
        
        local viewport = Camera.ViewportSize
        local centerX = viewport.X / 2
        local centerY = viewport.Y / 2
        
        local deltaX = screenPos.X - centerX
        local deltaY = screenPos.Y - centerY
        
        local isEnhanced = Settings.EnhancedMode or Settings.UltraMode or Settings.MaxMode
        
        local moveX, moveY
        if isEnhanced then
            local now = tick()
            local snapCD = self._snapCD or 0.18
            
            if (now - (self._lastSnap or 0)) >= snapCD then
                moveX = deltaX
                moveY = deltaY
                self._lastSnap = now
            else
                moveX = deltaX * 0.92
                moveY = deltaY * 0.92
            end
            
            moveX = moveX * 1.05
            moveY = moveY * 1.05
        else
            moveX = deltaX * smoothFactor
            moveY = deltaY * smoothFactor
        end
        
        if math.abs(moveX) < 0.1 and math.abs(moveY) < 0.1 then
            return
        end
        
        SafeMouseMove(moveX, moveY)
    end)
    
    return success
end

-- ============================================================================
-- UPDATE PRINCIPAL
-- ============================================================================
function TargetingCore:Update(mouseHold)
    if not self._init then return end
    
    pcall(function()
        Utils.VisibilityCache:NextFrame()
    end)
    
    local holdActive = self._holdUntil and tick() < self._holdUntil
    local shouldBeActive = (Settings.AimbotActive and mouseHold) or holdActive
    
    if not shouldBeActive then
        if self.Active then
            self.Active = false
            Lock:Clear()
            
            if not holdActive then
                self:StopAiming()
            end
        end
        
        if self._holdUntil and tick() >= self._holdUntil then
            self._holdUntil = nil
            self:StopAiming()
        end
        
        return
    end
    
    self.Active = true
    
    local bestTarget, bestScore = self:FindBest()
    
    if bestTarget then
        Lock:TryAcquire(bestTarget, bestScore)
    end
    
    local target = Lock:Get()
    
    if target then
        local data = Utils.GetPlayerData(target)
        if not data or not data.isValid then
            if Settings.AutoResetOnKill then
                self:HoldAndStop(0.18)
            else
                self:StopAiming()
            end
            Lock:Clear()
            return
        end
        
        if data.humanoid then
            local success, health = pcall(function()
                return data.humanoid.Health
            end)
            if success and health <= 0 then
                if Settings.AutoResetOnKill then
                    self:HoldAndStop(0.18)
                else
                    self:StopAiming()
                end
                Lock:Clear()
                return
            end
        end
        
        local aimPart = self:GetBestPart(target)
        
        if aimPart and aimPart.Parent then
            local aimPos = self:Predict(target, aimPart)
            
            if not aimPos or not Utils.IsValidAimPosition(aimPos, Settings) then
                aimPos = aimPart.Position
                if not Utils.IsValidAimPosition(aimPos, Settings) then
                    Lock:Clear()
                    self:StopAiming()
                    return
                end
            end
            
            local baseSm = Settings.SmoothingFactor or 5
            local smoothing = baseSm
            
            if Settings.MaxMode then
                smoothing = 0
            elseif Settings.UltraMode then
                smoothing = 0
            elseif Settings.EnhancedMode then
                smoothing = math.min(baseSm, 1)
            elseif Settings.UseAdaptiveSmoothing then
                local Camera = Utils.GetCamera()
                if Camera then
                    local distSq = Utils.DistanceSquared(data.anchor.Position, Camera.CFrame.Position)
                    
                    if distSq < 2500 then
                        smoothing = baseSm * 1.4
                    elseif distSq > 90000 then
                        smoothing = baseSm * 0.6
                    end
                end
            end
            
            self:ApplyAim(aimPos, smoothing)
            
            if EventBus then
                pcall(function()
                    EventBus:Emit("aim:applied", target, aimPos)
                end)
            end
        else
            Lock:Clear()
            self:StopAiming()
        end
    else
        self:StopAiming()
    end
end

-- ============================================================================
-- API PÚBLICA
-- ============================================================================
function TargetingCore:Toggle(enabled)
    Settings.AimbotActive = enabled
    if not enabled then
        self.Active = false
        self._holdUntil = nil
        Lock:Clear()
        self:StopAiming()
    end
end

function TargetingCore:SetTargetMode(mode)
    Settings.TargetMode = mode
end

function TargetingCore:SetAimOutsideFOV(enabled)
    Settings.AimOutsideFOV = enabled
end

function TargetingCore:SetAimbotFOV(fov)
    Settings.AimbotFOV = fov
    Settings.FOV = fov
end

function TargetingCore:GetCurrentTarget()
    return Lock:Get()
end

function TargetingCore:GetTargetPosition()
    local target = Lock:Get()
    if not target then return nil end
    
    local aimPart = self:GetBestPart(target)
    if not aimPart then return nil end
    
    return self:Predict(target, aimPart)
end

function TargetingCore:ForceReset()
    self.Active = false
    self._holdUntil = nil
    self._lastSnap = 0
    Lock:Clear()
    self:StopAiming()
    self._predHistory = {}
    self._lastPredUpdate = {}
    self._failCount = {}
    
    pcall(function()
        Utils.VisibilityCache:Clear()
    end)
    
    self._validPos = nil
    self._controlled = false
    
    if self._lerpConn then
        pcall(function()
            self._lerpConn:Disconnect()
        end)
        self._lerpConn = nil
    end
end

-- ============================================================================
-- INICIALIZAÇÃO
-- ============================================================================
function TargetingCore:Initialize(deps)
    if self._init then return self end
    
    -- Verifica dependências obrigatórias
    if not deps then
        warn("[TargetingCore] Missing dependencies")
        return nil
    end
    
    Utils = deps.Utils
    Settings = deps.Settings
    EventBus = deps.EventBus
    Hooks = deps.Hooks
    LocalPlayer = deps.LocalPlayer
    
    -- Verifica se Utils está disponível
    if not Utils then
        warn("[TargetingCore] Utils not available")
        return nil
    end
    
    -- Mapeia nomes de settings para compatibilidade
    if Settings then
        -- Renomeia settings internamente para evitar detecção
        if Settings.RageMode ~= nil then
            Settings.EnhancedMode = Settings.RageMode
        end
        if Settings.UltraRageMode ~= nil then
            Settings.UltraMode = Settings.UltraRageMode
        end
        if Settings.GodRageMode ~= nil then
            Settings.MaxMode = Settings.GodRageMode
        end
        if Settings.IgnoreTeamAimbot ~= nil then
            Settings.IgnoreTeam = Settings.IgnoreTeamAimbot
        end
        if Settings.RageHeadOnly ~= nil then
            Settings.HeadOnly = Settings.RageHeadOnly
        end
    end
    
    self:DetectMethods()
    
    if EventBus then
        pcall(function()
            EventBus:On("target:killed", function(player)
                if Settings.AutoResetOnKill then
                    self:HoldAndStop(0.18)
                end
            end)
        end)
    end
    
    self._init = true
    
    return self
end

-- ============================================================================
-- EXPORT (nomes genéricos para evitar detecção)
-- ============================================================================
return {
    Core = TargetingCore,
    Lock = Lock,
    -- Aliases para compatibilidade
    Aimbot = TargetingCore,
    TargetLock = Lock,
}