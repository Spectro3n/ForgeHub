-- ============================================================================
-- FORGEHUB - AIMBOT CORE MODULE v4.3
-- Aimbot normal (mirar apenas)
-- ============================================================================

local Aimbot = {
    Initialized = false,
    IsAiming = false,
    OriginalCFrame = nil,
    HasMouseMoveRel = false,
    LastAimPos = nil,
    LastValidAimPos = nil,
    AimHistory = {},
    SmoothHistory = {},
    MaxHistory = 5,
}

-- ============================================================================
-- DEPENDENCIES (serão injetadas)
-- ============================================================================
local Utils = nil
local Settings = nil
local EventBus = nil
local Hooks = nil
local LocalPlayer = nil
local UserInputService = nil
local Players = nil

-- ============================================================================
-- TARGET LOCK
-- ============================================================================
local TargetLock = {
    CurrentTarget = nil,
    LockTime = 0,
    LastScore = math.huge,
    LastKill = 0,
    KillCount = 0,
    MinLockDuration = 0.05,
    MaxLockDuration = 0.5,
    ImprovementThreshold = 0.4,
    LastValidPosition = nil,
    DeathDetected = false,
}

function TargetLock:Reset()
    if self.CurrentTarget then
        -- Limpa histórico de predição
        if Aimbot.PredictionHistory then
            Aimbot.PredictionHistory[self.CurrentTarget] = nil
        end
        Utils.VisibilityCache:Invalidate(self.CurrentTarget)
    end
    
    self.CurrentTarget = nil
    self.LockTime = 0
    self.LastScore = math.huge
    self.LastValidPosition = nil
    self.DeathDetected = false
    
    if EventBus then
        EventBus:Emit("target:lost", self.CurrentTarget)
    end
end

function TargetLock:IsTargetAlive()
    if not self.CurrentTarget then return false end
    
    local data = Utils.GetPlayerData(self.CurrentTarget)
    if not data then return false end
    if not data.isValid then return false end
    if not data.anchor or not data.anchor.Parent then return false end
    
    if data.humanoid and data.humanoid.Health <= 0 then
        return false
    end
    
    return true
end

function TargetLock:IsValid()
    if not self.CurrentTarget then return false end
    
    if not self:IsTargetAlive() then
        if not self.DeathDetected then
            self.DeathDetected = true
            self.KillCount = self.KillCount + 1
            self.LastKill = tick()
            
            if EventBus then
                EventBus:Emit("target:killed", self.CurrentTarget)
            end
        end
        return false
    end
    
    self.DeathDetected = false
    
    local data = Utils.GetPlayerData(self.CurrentTarget)
    if not data or not data.isValid then return false end
    
    local Camera = Utils.GetCamera()
    local distSq = Utils.DistanceSquared(data.anchor.Position, Camera.CFrame.Position)
    
    local maxDist = Settings.MaxDistance or 2000
    if Settings.GodRageMode then
        maxDist = 99999
    elseif Settings.UltraRageMode then
        maxDist = maxDist * 3
    elseif Settings.RageMode then
        maxDist = maxDist * 2
    end
    
    if distSq > maxDist * maxDist then return false end
    
    self.LastValidPosition = data.anchor.Position
    
    return true
end

function TargetLock:TryLock(candidate, score)
    if not candidate then return end
    
    local data = Utils.GetPlayerData(candidate)
    if not data or not data.isValid then return end
    if data.humanoid and data.humanoid.Health <= 0 then return end
    
    local now = tick()
    
    -- Ajusta parâmetros baseado no modo
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
        
        if EventBus then
            EventBus:Emit("target:locked", candidate, score)
        end
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
        
        if EventBus then
            EventBus:Emit("target:locked", candidate, score)
        end
        return
    end
    
    local lockDuration = now - self.LockTime
    
    if Settings.AutoSwitch and lockDuration > (Settings.TargetSwitchDelay or 0.1) then
        self.CurrentTarget = candidate
        self.LockTime = now
        self.LastScore = score
        self.DeathDetected = false
        
        if EventBus then
            EventBus:Emit("target:locked", candidate, score)
        end
        return
    end
    
    if lockDuration > self.MaxLockDuration then
        self.CurrentTarget = candidate
        self.LockTime = now
        self.LastScore = score
        self.DeathDetected = false
        
        if EventBus then
            EventBus:Emit("target:locked", candidate, score)
        end
        return
    end
    
    if score < self.LastScore * self.ImprovementThreshold then
        self.CurrentTarget = candidate
        self.LockTime = now
        self.LastScore = score
        self.DeathDetected = false
        
        if EventBus then
            EventBus:Emit("target:locked", candidate, score)
        end
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
-- PREDICTION
-- ============================================================================
Aimbot.PredictionHistory = {}
Aimbot.LastPredUpdate = {}
local MAX_HISTORY = 8
local PRED_UPDATE_INTERVAL = 1/30

function Aimbot:UpdatePredictionHistory(player, position, velocity)
    local now = tick()
    
    if self.LastPredUpdate[player] and (now - self.LastPredUpdate[player]) < PRED_UPDATE_INTERVAL then
        return
    end
    self.LastPredUpdate[player] = now
    
    if not self.PredictionHistory[player] then
        self.PredictionHistory[player] = {positions = {}, velocities = {}}
    end
    
    local history = self.PredictionHistory[player]
    
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

function Aimbot:ClearPredictionHistory(player)
    self.PredictionHistory[player] = nil
    self.LastPredUpdate[player] = nil
end

function Aimbot:CalculateVelocity(player, anchor)
    if not anchor or not anchor.Parent then return Vector3.zero end
    
    local vel = anchor.AssemblyLinearVelocity or anchor.Velocity
    if vel and vel.Magnitude > 0.5 then 
        return vel 
    end
    
    local history = self.PredictionHistory[player]
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

function Aimbot:CalculateAcceleration(player)
    local history = self.PredictionHistory[player]
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

function Aimbot:PredictPosition(player, targetPart)
    if not targetPart then return nil end
    if not targetPart.Parent then return nil end
    
    local basePos = targetPart.Position
    
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
    
    local velocity = self:CalculateVelocity(player, data.anchor)
    local acceleration = Vector3.zero
    
    if Settings.GodRageMode then
        acceleration = self:CalculateAcceleration(player)
    end
    
    local yMultiplier = Settings.GodRageMode and 0.6 or (Settings.UltraRageMode and 0.5 or 0.4)
    
    if velocity.Y > 0 then
        velocity = Vector3.new(velocity.X, velocity.Y * yMultiplier, velocity.Z)
    end
    
    local Camera = Utils.GetCamera()
    local distSq = Utils.DistanceSquared(targetPart.Position, Camera.CFrame.Position)
    local distance = math.sqrt(distSq)
    
    local timeDiv = Settings.GodRageMode and 400 or (Settings.UltraRageMode and 500 or (Settings.RageMode and 600 or 800))
    local timeToTarget = Utils.Clamp(distance / timeDiv, 0.01, 0.35)
    
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
    
    if not Utils.IsValidAimPosition(predictedPos, Settings) then
        return basePos
    end
    
    self:UpdatePredictionHistory(player, data.anchor.Position, velocity)
    
    return predictedPos
end

-- ============================================================================
-- AIM PARTS
-- ============================================================================
function Aimbot:GetAimPart(player, partName)
    local data = Utils.GetPlayerData(player)
    if not data or not data.model then return nil end
    if not data.model.Parent then return nil end
    
    partName = partName or "Head"
    if type(partName) == "table" then
        partName = partName[1] or "Head"
    end
    
    local partCache = Utils.GetPartCache(player)
    if partCache then
        local candidates = Utils.PART_MAP[partName] or {partName}
        for i = 1, #candidates do
            local part = partCache[candidates[i]]
            if part and part.Parent then 
                return part 
            end
        end
    end
    
    local candidates = Utils.PART_MAP[partName] or {partName}
    local model = data.model
    
    for i = 1, #candidates do
        local part = model:FindFirstChild(candidates[i], true)
        if part and part:IsA("BasePart") and part.Parent then
            return part
        end
    end
    
    if data.anchor and data.anchor.Parent then
        return data.anchor
    end
    
    return nil
end

function Aimbot:GetAllAimParts(player)
    if not Utils.IsPartCacheValid(player) then
        local data = Utils.GetPlayerData(player)
        if not data or not data.model then return {} end
        Utils.BuildPartCacheFor(player)
    end
    
    local partCache = Utils.GetPartCache(player)
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
                priority = Utils.PartPriorityMap[partName] or 10
            }
        end
    end
    
    table.sort(parts, function(a, b) return a.priority < b.priority end)
    
    return parts
end

function Aimbot:GetBestAimPart(player, ignoreFOV)
    local data = Utils.GetPlayerData(player)
    if not data or not data.model then return nil end
    if not data.model.Parent then return nil end
    
    if Settings.GodRageMode or Settings.UltraRageMode then
        local head = self:GetAimPart(player, "Head")
        if head and head.Parent then return head end
    end
    
    if not Settings.MultiPartAim then
        return self:GetAimPart(player, Settings.AimPart)
    end
    
    local Camera = Utils.GetCamera()
    local camPos = Camera.CFrame.Position
    local mousePos = UserInputService:GetMouseLocation()
    
    local bestPart = nil
    local bestScore = math.huge
    
    local allParts = self:GetAllAimParts(player)
    local maxPartsToCheck = Settings.GodRageMode and 1 or (Settings.RageMode and 3 or 5)
    local checked = 0
    
    for i = 1, #allParts do
        if checked >= maxPartsToCheck then break end
        
        local partData = allParts[i]
        local part = partData.part
        
        if not part or not part.Parent then continue end
        
        local screenPos, onScreen = Camera:WorldToViewportPoint(part.Position)
        
        if onScreen or Settings.GodRageMode or Settings.AimOutsideFOV then
            local distToMouse = onScreen and (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude or 9999
            local score = distToMouse + (partData.priority * 20)
            
            if partData.name == "Head" then
                score = score * 0.3
            end
            
            if score < bestScore then
                local visible = true
                if not Settings.IgnoreWalls and not Settings.MagicBullet and not Settings.GodRageMode then
                    local cachedVis, _, hit = Utils.VisibilityCache:Get(player)
                    if hit then
                        visible = cachedVis
                    else
                        Utils.RayParamsManager:Update(LocalPlayer, Camera)
                        local direction = part.Position - camPos
                        local ray = workspace:Raycast(camPos, direction, Utils.RayParamsManager:Get())
                        if ray and ray.Instance and not ray.Instance:IsDescendantOf(data.model) then
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
        return self:GetAimPart(player, Settings.AimPart)
    end
    
    return bestPart
end

-- ============================================================================
-- TARGET FINDING (COM FOV CORRIGIDO)
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

function Aimbot:FindBestTarget()
    local Camera = Utils.GetCamera()
    if not Camera then return nil, math.huge end
    
    local camPos = Camera.CFrame.Position
    local camLook = Camera.CFrame.LookVector
    local mousePos = UserInputService:GetMouseLocation()
    
    local targetMode = Settings.TargetMode or "FOV"
    
    -- ★ CORRIGIDO: Calcula cos threshold do FOV
    local currentFOV = Settings.AimbotFOV or 180
    if Settings.GodRageMode then
        currentFOV = 99999
    elseif Settings.UltraRageMode then
        currentFOV = currentFOV * 5
    elseif Settings.RageMode then
        currentFOV = currentFOV * 3
    end
    
    local cosThreshold = Utils.CalculateFOVCosThreshold(currentFOV)
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
        
        local data = Utils.GetPlayerData(player)
        if not data or not data.isValid or not data.anchor then continue end
        if not data.anchor.Parent or not data.anchor:IsDescendantOf(workspace) then continue end
        
        if data.humanoid and data.humanoid.Health <= 0 then continue end
        
        if Settings.IgnoreTeamAimbot and Utils.AreSameTeam(LocalPlayer, player) then continue end
        
        local distSq = Utils.DistanceSquared(data.anchor.Position, camPos)
        if distSq > maxDistSq then continue end
        
        -- ★ CORRIGIDO: Usa aimPart para verificação de FOV
        local aimPart = self:GetBestAimPart(player)
        if not aimPart or not aimPart.Parent then continue end
        
        local screenPos, onScreen = Camera:WorldToViewportPoint(aimPart.Position)
        
        local allowOutside = Settings.GodRageMode or Settings.UltraRageMode or Settings.AimOutsideFOV
        if not allowOutside and not onScreen then continue end
        
        -- ★ CORRIGIDO: Usa dot product com aimPart
        local dirToTarget = (aimPart.Position - camPos).Unit
        local dot = camLook:Dot(dirToTarget)
        
        -- ★ CORRIGIDO: Verifica FOV angular
        if not Settings.AimOutsideFOV and not Settings.GodRageMode then
            if dot < cosThreshold then continue end
        end
        
        -- ★ CORRIGIDO: Verifica altura (evita chão)
        local minHeight = Settings.MinAimHeightBelowCamera or 50
        if aimPart.Position.Y < camPos.Y - minHeight then continue end
        
        local distToMouse = onScreen and (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude or 99999
        local distToMouseSq = distToMouse * distToMouse
        
        local checkFOV = Settings.UseAimbotFOV and not Settings.AimOutsideFOV and not Settings.GodRageMode
        if checkFOV and distToMouseSq > currentFOVSq then continue end
        
        local distance = math.sqrt(distSq)
        local score
        
        if targetMode == "Closest" then
            score = distance
            if (Settings.RageMode or Settings.UltraRageMode or Settings.GodRageMode) and data.humanoid then
                local healthPercent = data.humanoid.Health / data.humanoid.MaxHealth
                score = score * (0.3 + healthPercent * 0.7)
            end
        else
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
            aimPart = aimPart,
        }
    end
    
    if #candidates == 0 then
        return nil, math.huge
    end
    
    table.sort(candidates, function(a, b) return a.score < b.score end)
    
    local maxChecks = Settings.GodRageMode and 1 or (Settings.UltraRageMode and 2 or (Settings.RageMode and 3 or 5))
    local checked = 0
    
    for i = 1, #candidates do
        if checked >= maxChecks then break end
        
        local candidate = candidates[i]
        
        local data = Utils.GetPlayerData(candidate.player)
        if not data or not data.isValid then continue end
        if data.humanoid and data.humanoid.Health <= 0 then continue end
        
        checked = checked + 1
        
        if Settings.IgnoreWalls or Settings.MagicBullet or Settings.GodRageMode or not Settings.VisibleCheck then
            return candidate.player, candidate.score
        end
        
        if self:IsVisible(candidate.player, candidate.aimPart) then
            return candidate.player, candidate.score
        end
    end
    
    if (Settings.IgnoreWalls or Settings.MagicBullet or not Settings.VisibleCheck) and #candidates > 0 then
        return candidates[1].player, candidates[1].score
    end
    
    return nil, math.huge
end

function Aimbot:FindBestTargetForSilent()
    local Camera = Utils.GetCamera()
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
    local allPlayers = GetCachedPlayers()
    
    for i = 1, #allPlayers do
        local player = allPlayers[i]
        if player == LocalPlayer then continue end
        
        local data = Utils.GetPlayerData(player)
        if not data or not data.isValid then continue end
        if data.humanoid and data.humanoid.Health <= 0 then continue end
        
        if Settings.IgnoreTeamAimbot and Utils.AreSameTeam(LocalPlayer, player) then continue end
        
        local targetPart = self:GetBestAimPart(player)
        if not targetPart or not targetPart.Parent then continue end
        
        local screenPos, onScreen = Camera:WorldToViewportPoint(targetPart.Position)
        
        local allowOutside = Settings.GodRageMode or Settings.AimOutsideFOV
        if onScreen or allowOutside then
            local distToMouse = onScreen and (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude or 9999
            
            if distToMouse <= silentFOV or Settings.GodRageMode or Settings.AimOutsideFOV then
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

function Aimbot:IsVisible(player, targetPart)
    if Settings.MagicBullet or Settings.IgnoreWalls or Settings.GodRageMode then
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
    
    local ray = workspace:Raycast(origin, direction, Utils.RayParamsManager:Get())
    
    local visible = true
    if ray and ray.Instance then
        if not ray.Instance:IsDescendantOf(data.model) then
            visible = false
        end
    end
    
    Utils.VisibilityCache:Set(player, visible, targetPart)
    return visible
end

-- ============================================================================
-- AIM CONTROLLER (COM CORREÇÃO DE SNAP)
-- ============================================================================
function Aimbot:DetectMethods()
    local caps = Hooks:GetCapabilities()
    self.HasMouseMoveRel = caps.HasMouseMoveRel
end

function Aimbot:StartAiming()
    if self.IsAiming then return end
    self.IsAiming = true
    self.OriginalCFrame = Utils.GetCamera().CFrame
    
    if EventBus then
        EventBus:Emit("aim:start")
    end
end

-- ★ CORRIGIDO: StopAiming suave (evita snap)
function Aimbot:StopAiming()
    if not self.IsAiming then return end
    self.IsAiming = false
    
    local prevCFrame = self.OriginalCFrame
    self.OriginalCFrame = nil
    self.LastAimPos = nil
    self.LastValidAimPos = nil
    self.AimHistory = {}
    self.SmoothHistory = {}
    
    Utils.SafeCall(function()
        local Camera = Utils.GetCamera()
        if not Camera then return end
        
        -- ★ NOVO: Lerp suave para posição original
        if prevCFrame then
            local duration = 0.18
            local t0 = tick()
            local start = Camera.CFrame
            
            task.spawn(function()
                while tick() - t0 < duration do
                    local a = (tick() - t0) / duration
                    Camera.CFrame = start:Lerp(prevCFrame, a)
                    task.wait()
                end
                Camera.CFrame = prevCFrame
                
                -- Só restaura CameraSubject se não for Scriptable
                if LocalPlayer.Character then
                    local hum = LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
                    if hum and Camera.CameraType ~= Enum.CameraType.Scriptable then
                        Camera.CameraSubject = hum
                    end
                end
            end)
        else
            if LocalPlayer.Character then
                local hum = LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
                if hum and Camera.CameraType ~= Enum.CameraType.Scriptable then
                    Camera.CameraSubject = hum
                end
            end
        end
    end, "Aimbot:StopAiming(smooth)")
    
    if EventBus then
        EventBus:Emit("aim:stop")
    end
end

-- ★ NOVO: HoldAndStop (evita reset instantâneo após kill)
function Aimbot:HoldAndStop(seconds)
    seconds = seconds or 0.18
    if not self.IsAiming then
        self:StopAiming()
        return
    end
    
    task.spawn(function()
        task.wait(seconds)
        -- Se durante o hold o aimbot não retomou, pare suavemente
        if not self.Active then
            self:StopAiming()
        end
    end)
end

function Aimbot:CalculateSmoothFactor(smoothing)
    if Settings.GodRageMode then return 1.0 end
    if Settings.UltraRageMode then return 0.98 end
    
    if Settings.RageMode then
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

function Aimbot:ApplyShakeReduction(targetPos)
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
    
    local avgPos = Vector3.zero
    local totalWeight = 0
    
    for i, pos in ipairs(self.AimHistory) do
        local weight = i * i
        avgPos = avgPos + pos * weight
        totalWeight = totalWeight + weight
    end
    
    return avgPos / totalWeight
end

function Aimbot:ApplyAim(targetPosition, smoothing)
    if not targetPosition then 
        return false 
    end
    
    if not Utils.IsValidAimPosition(targetPosition, Settings) then
        if self.LastValidAimPos and Utils.IsValidAimPosition(self.LastValidAimPos, Settings) then
            targetPosition = self.LastValidAimPos
        else
            return false
        end
    end
    
    self.LastValidAimPos = targetPosition
    
    local Camera = Utils.GetCamera()
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

function Aimbot:Method_Camera(targetPosition, smoothFactor)
    local success = pcall(function()
        self:StartAiming()
        
        local Camera = Utils.GetCamera()
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

function Aimbot:Method_MouseMoveRel(targetPosition, smoothFactor)
    if not self.HasMouseMoveRel then
        return self:Method_Camera(targetPosition, smoothFactor)
    end
    
    local success = pcall(function()
        local Camera = Utils.GetCamera()
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
        
        if math.abs(moveX) < 0.1 and math.abs(moveY) < 0.1 then
            return
        end
        
        mousemoverel(moveX, moveY)
    end)
    
    return success
end

-- ============================================================================
-- MAIN UPDATE
-- ============================================================================
function Aimbot:Update(mouseHold)
    if not self.Initialized then return end
    
    Utils.VisibilityCache:NextFrame()
    
    local shouldBeActive = Settings.AimbotActive and mouseHold
    
    if not shouldBeActive then
        if self.Active then
            self.Active = false
            TargetLock:Reset()
            self:StopAiming()
        end
        return
    end
    
    self.Active = true
    
    local bestTarget, bestScore = self:FindBestTarget()
    
    if bestTarget then
        TargetLock:TryLock(bestTarget, bestScore)
    end
    
    local target = TargetLock:GetTarget()
    
    if target then
        local data = Utils.GetPlayerData(target)
        if not data or not data.isValid then
            -- ★ CORRIGIDO: Usa HoldAndStop para kill detection
            if Settings.AutoResetOnKill then
                self:HoldAndStop(0.18)
            else
                self:StopAiming()
            end
            TargetLock:Reset()
            return
        end
        
        if data.humanoid and data.humanoid.Health <= 0 then
            if Settings.AutoResetOnKill then
                self:HoldAndStop(0.18)
            else
                self:StopAiming()
            end
            TargetLock:Reset()
            return
        end
        
        local aimPart = self:GetBestAimPart(target)
        
        if aimPart and aimPart.Parent then
            local aimPos = self:PredictPosition(target, aimPart)
            
            if not aimPos or not Utils.IsValidAimPosition(aimPos, Settings) then
                aimPos = aimPart.Position
                if not Utils.IsValidAimPosition(aimPos, Settings) then
                    TargetLock:Reset()
                    self:StopAiming()
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
                smoothing = math.min(baseSm, 1)
            elseif Settings.UseAdaptiveSmoothing then
                local distSq = Utils.DistanceSquared(data.anchor.Position, Utils.GetCamera().CFrame.Position)
                
                if distSq < 2500 then
                    smoothing = baseSm * 1.4
                elseif distSq > 90000 then
                    smoothing = baseSm * 0.6
                end
            end
            
            self:ApplyAim(aimPos, smoothing)
            
            -- Emite evento para outros módulos (AutoFire, etc)
            if EventBus then
                EventBus:Emit("aim:applied", target, aimPos)
            end
        else
            TargetLock:Reset()
            self:StopAiming()
        end
    else
        self:StopAiming()
    end
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================
function Aimbot:Toggle(enabled)
    Settings.AimbotActive = enabled
    if not enabled then
        self.Active = false
        TargetLock:Reset()
        self:StopAiming()
    end
end

function Aimbot:SetTargetMode(mode)
    Settings.TargetMode = mode
end

function Aimbot:SetAimOutsideFOV(enabled)
    Settings.AimOutsideFOV = enabled
end

function Aimbot:SetAimbotFOV(fov)
    Settings.AimbotFOV = fov
    Settings.FOV = fov
end

function Aimbot:GetCurrentTarget()
    return TargetLock:GetTarget()
end

function Aimbot:GetTargetPosition()
    local target = TargetLock:GetTarget()
    if not target then return nil end
    
    local aimPart = self:GetBestAimPart(target)
    if not aimPart then return nil end
    
    return self:PredictPosition(target, aimPart)
end

function Aimbot:ForceReset()
    self.Active = false
    TargetLock:Reset()
    self:StopAiming()
    self.PredictionHistory = {}
    self.LastPredUpdate = {}
    Utils.VisibilityCache:Clear()
    self.LastValidAimPos = nil
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================
function Aimbot:Initialize(deps)
    if self.Initialized then return self end
    
    -- Inject dependencies
    Utils = deps.Utils
    Settings = deps.Settings
    EventBus = deps.EventBus
    Hooks = deps.Hooks
    LocalPlayer = deps.LocalPlayer
    UserInputService = deps.UserInputService
    Players = deps.Players
    
    self:DetectMethods()
    
    -- Subscribe to events
    if EventBus then
        EventBus:On("target:killed", function(player)
            if Settings.AutoResetOnKill then
                self:HoldAndStop(0.18)
            end
        end)
    end
    
    self.Initialized = true
    
    return self
end

-- ============================================================================
-- EXPORT
-- ============================================================================
return {
    Aimbot = Aimbot,
    TargetLock = TargetLock,
}