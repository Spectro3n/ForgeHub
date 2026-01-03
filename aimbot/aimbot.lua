-- ============================================================================
-- FORGEHUB - AIMBOT LEGIT MODULE v4.6
-- Apenas funcionalidades legit/normais - Adaptado ao Settings
-- ============================================================================

local AimbotLegit = {
    _init = false,
    _active = false,
    _origCF = nil,
    _hasMMR = false,
    _lastPos = nil,
    _validPos = nil,
    _history = {},
    _smoothHist = {},
    _maxHist = 5,
    
    -- Controle
    _holdUntil = nil,
    _controlled = false,
    _prevType = nil,
    _prevSubject = nil,
    _prevCF = nil,
    _lerpConn = nil,
    
    -- Fallback
    _failCount = {},
    _maxFails = 3,
    
    -- Prediction
    _predHistory = {},
    _lastPredUpdate = {},
}

-- ============================================================================
-- SERVIÇOS COM LAZY LOADING
-- ============================================================================
local ServiceCache = {}

local function GetService(name)
    if ServiceCache[name] then return ServiceCache[name] end
    local success, service = pcall(function() return game:GetService(name) end)
    if success and service then ServiceCache[name] = service end
    return service
end

local function GetRunService() return GetService("RunService") end
local function GetPlayers() return GetService("Players") end
local function GetUIS() return GetService("UserInputService") end

-- ============================================================================
-- DEPENDENCIES
-- ============================================================================
local Utils = nil
local Settings = nil
local EventBus = nil
local Hooks = nil
local LocalPlayer = nil

-- ============================================================================
-- EXECUTOR FUNCTIONS
-- ============================================================================
local ExecutorFuncs = {
    mouseMove = nil,
    isAvailable = false
}

local function InitExecutorFuncs()
    local mmrCheck = {"mousemoverel", "mouse_moverel", "Input.MouseMove"}
    
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
    if not ExecutorFuncs.isAvailable then return false end
    return pcall(function() ExecutorFuncs.mouseMove(dx, dy) end)
end

-- ============================================================================
-- HELPER - SYNC SETTINGS
-- ============================================================================
local function SyncSettings()
    if not Settings then return end
    
    -- Sincroniza aliases se existirem
    if Settings.IgnoreTeamAimbot ~= nil then
        Settings.IgnoreTeam = Settings.IgnoreTeamAimbot
    end
    
    if Settings.AimbotFOV then
        Settings.FOV = Settings.AimbotFOV
    end
end

-- ============================================================================
-- TARGET LOCK (LEGIT)
-- ============================================================================
local Lock = {
    Current = nil,
    Time = 0,
    Score = math.huge,
    LastKill = 0,
    Kills = 0,
    MinDur = 0.1,
    MaxDur = 1.5,
    Threshold = 0.7,
    ValidPos = nil,
    DeathFlag = false,
}

function Lock:Clear()
    if self.Current then
        if AimbotLegit._predHistory then
            AimbotLegit._predHistory[self.Current] = nil
        end
        if AimbotLegit._failCount then
            AimbotLegit._failCount[self.Current] = nil
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
        pcall(function() EventBus:Emit("target:lost", self.Current) end)
    end
end

function Lock:IsAlive()
    if not self.Current or not Utils then return false end
    
    local data = Utils.GetPlayerData(self.Current)
    if not data or not data.isValid then return false end
    if not data.anchor or not data.anchor.Parent then return false end
    
    if data.humanoid then
        local success, health = pcall(function() return data.humanoid.Health end)
        if success and health <= 0 then return false end
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
                pcall(function() EventBus:Emit("target:killed", self.Current) end) 
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
    
    if distSq > maxDist * maxDist then return false end
    
    self.ValidPos = data.anchor.Position
    return true
end

function Lock:TryAcquire(candidate, score)
    if not candidate or not Utils then return end
    
    local data = Utils.GetPlayerData(candidate)
    if not data or not data.isValid then return end
    
    if data.humanoid then
        local success, health = pcall(function() return data.humanoid.Health end)
        if success and health <= 0 then return end
    end
    
    local now = tick()
    
    -- Configura thresholds baseado em settings
    self.MaxDur = Settings.MaxLockTime or 1.5
    self.Threshold = Settings.LockImprovementThreshold or 0.7
    
    -- Primeiro alvo
    if not self.Current then
        self.Current = candidate
        self.Time = now
        self.Score = score
        self.DeathFlag = false
        if EventBus then 
            pcall(function() EventBus:Emit("target:locked", candidate, score) end) 
        end
        return
    end
    
    -- Mesmo alvo
    if self.Current == candidate then
        self.Score = score
        return
    end
    
    -- Alvo atual inválido
    if not self:Validate() then
        self.Current = candidate
        self.Time = now
        self.Score = score
        self.DeathFlag = false
        return
    end
    
    local lockDur = now - self.Time
    
    -- AutoSwitch
    if Settings.AutoSwitch and lockDur > (Settings.SwitchDelay or Settings.TargetSwitchDelay or 0.3) then
        self.Current = candidate
        self.Time = now
        self.Score = score
        return
    end
    
    -- Tempo máximo
    if lockDur > self.MaxDur then
        self.Current = candidate
        self.Time = now
        self.Score = score
        return
    end
    
    -- Score muito melhor
    if score < self.Score * self.Threshold then
        self.Current = candidate
        self.Time = now
        self.Score = score
    end
end

function Lock:Get()
    if self:Validate() then return self.Current end
    self:Clear()
    return nil
end

-- ============================================================================
-- PREDICTION (LEGIT)
-- ============================================================================
local PRED_HISTORY_SIZE = 6
local PRED_INTERVAL = 1/25

function AimbotLegit:UpdatePredHistory(player, pos, vel)
    local now = tick()
    local lastUpdate = self._lastPredUpdate[player]
    if lastUpdate and (now - lastUpdate) < PRED_INTERVAL then return end
    self._lastPredUpdate[player] = now
    
    if not self._predHistory[player] then
        self._predHistory[player] = {positions = {}, velocities = {}}
    end
    
    local hist = self._predHistory[player]
    table.insert(hist.positions, {pos = pos, t = now})
    if vel then table.insert(hist.velocities, {vel = vel, t = now}) end
    
    while #hist.positions > PRED_HISTORY_SIZE do table.remove(hist.positions, 1) end
    while #hist.velocities > PRED_HISTORY_SIZE do table.remove(hist.velocities, 1) end
end

function AimbotLegit:ClearPredHistory(player)
    self._predHistory[player] = nil
    self._lastPredUpdate[player] = nil
    self._failCount[player] = nil
end

function AimbotLegit:CalcVelocity(player, anchor)
    if not anchor or not anchor.Parent then return Vector3.zero end
    
    local vel
    local success = pcall(function()
        vel = anchor.AssemblyLinearVelocity or anchor.Velocity
    end)
    
    if success and vel and vel.Magnitude > 0.5 then return vel end
    
    local hist = self._predHistory[player]
    if hist and #hist.positions >= 2 then
        local newest = hist.positions[#hist.positions]
        local oldest = hist.positions[1]
        local dt = newest.t - oldest.t
        if dt > 0.03 then
            return (newest.pos - oldest.pos) / dt
        end
    end
    
    return Vector3.zero
end

function AimbotLegit:Predict(player, part)
    if not part or not part.Parent then return nil end
    
    local basePos = part.Position
    if not Utils.IsValidAimPosition(basePos, Settings) then return nil end
    
    -- Verificar se prediction está ativado
    if not Settings.UsePrediction then return basePos end
    
    local data = Utils.GetPlayerData(player)
    if not data or not data.anchor or not data.anchor.Parent then return basePos end
    
    local vel = self:CalcVelocity(player, data.anchor)
    
    -- Legit: reduz bastante a vertical
    if vel.Y > 0 then
        vel = Vector3.new(vel.X, vel.Y * 0.3, vel.Z)
    end
    
    local Camera = Utils.GetCamera()
    if not Camera then return basePos end
    
    local dist = (part.Position - Camera.CFrame.Position).Magnitude
    local timeToTarget = math.clamp(dist / 800, 0.01, 0.3)
    
    -- Usa o multiplicador do settings
    local mult = Settings.PredictionMultiplier or 0.12
    local predicted = basePos + (vel * mult * timeToTarget)
    
    if not Utils.IsValidAimPosition(predicted, Settings) then
        self._failCount[player] = (self._failCount[player] or 0) + 1
        if self._failCount[player] >= self._maxFails then
            self._failCount[player] = 0
            return nil
        end
        return basePos
    end
    
    self._failCount[player] = 0
    self:UpdatePredHistory(player, data.anchor.Position, vel)
    return predicted
end

-- ============================================================================
-- AIM PARTS
-- ============================================================================
function AimbotLegit:GetPart(player, partName)
    local data = Utils.GetPlayerData(player)
    if not data or not data.model or not data.model.Parent then return nil end
    
    partName = partName or Settings.AimPart or "Head"
    if type(partName) == "table" then partName = partName[1] or "Head" end
    
    local cache = Utils.GetPartCache(player)
    if cache then
        local candidates = Utils.PART_MAP[partName] or {partName}
        for i = 1, #candidates do
            local part = cache[candidates[i]]
            if part and part.Parent then return part end
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
    
    return data.anchor and data.anchor.Parent and data.anchor or nil
end

function AimbotLegit:GetBestPart(player)
    local data = Utils.GetPlayerData(player)
    if not data or not data.model or not data.model.Parent then return nil end
    
    -- Legit: usa parte configurada nos settings
    if not Settings.MultiPartAim then
        return self:GetPart(player, Settings.AimPart)
    end
    
    -- Multi-part: encontra melhor parte visível
    local Camera = Utils.GetCamera()
    if not Camera then return self:GetPart(player, Settings.AimPart) end
    
    local UIS = GetUIS()
    if not UIS then return self:GetPart(player, Settings.AimPart) end
    
    local mousePos = UIS:GetMouseLocation()
    local camPos = Camera.CFrame.Position
    
    local bestPart = nil
    local bestScore = math.huge
    
    local partsToCheck = Settings.AimParts or {"Head", "UpperTorso", "HumanoidRootPart"}
    
    for _, partName in ipairs(partsToCheck) do
        local part = self:GetPart(player, partName)
        if part and part.Parent then
            local success, screenPos, onScreen = pcall(function()
                return Camera:WorldToViewportPoint(part.Position)
            end)
            
            if success and onScreen then
                local distToMouse = (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude
                local score = distToMouse
                
                -- Prioridade para Head
                if partName == "Head" then
                    score = score * 0.5
                end
                
                if score < bestScore then
                    -- Check visibilidade se necessário
                    if Settings.VisibleCheck and not Settings.IgnoreWalls then
                        if self:CheckVisible(player, part) then
                            bestScore = score
                            bestPart = part
                        end
                    else
                        bestScore = score
                        bestPart = part
                    end
                end
            end
        end
    end
    
    return bestPart or self:GetPart(player, Settings.AimPart)
end

-- ============================================================================
-- TARGET FINDING (LEGIT)
-- ============================================================================
local CachedPlayers = {}
local LastCacheUpdate = 0
local CACHE_TTL = 0.35

local function GetCachedPlayers()
    local now = tick()
    if now - LastCacheUpdate > CACHE_TTL then
        local Players = GetPlayers()
        if Players then CachedPlayers = Players:GetPlayers() end
        LastCacheUpdate = now
    end
    return CachedPlayers
end

function AimbotLegit:GetLocalVelocity()
    if not LocalPlayer or not LocalPlayer.Character then return Vector3.zero end
    
    local success, vel = pcall(function()
        local hrp = LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if not hrp then return Vector3.zero end
        return hrp.AssemblyLinearVelocity or hrp.Velocity or Vector3.zero
    end)
    
    return success and vel or Vector3.zero
end

function AimbotLegit:FindBest()
    SyncSettings()
    
    local Camera = Utils.GetCamera()
    if not Camera then return nil, math.huge end
    
    local camPos = Camera.CFrame.Position
    local camLook = Camera.CFrame.LookVector
    
    local UIS = GetUIS()
    if not UIS then return nil, math.huge end
    
    local mousePos = UIS:GetMouseLocation()
    local targetMode = Settings.TargetMode or "FOV"
    
    local currentFOV = Settings.AimbotFOV or Settings.FOV or 180
    local cosThreshold = Utils.CalculateFOVCosThreshold(currentFOV)
    local currentFOVSq = currentFOV * currentFOV
    
    local maxDist = Settings.MaxDistance or 2000
    local maxDistSq = maxDist * maxDist
    
    local candidates = {}
    local allPlayers = GetCachedPlayers()
    
    for i = 1, #allPlayers do
        local player = allPlayers[i]
        if player == LocalPlayer then continue end
        
        local data = Utils.GetPlayerData(player)
        if not data or not data.isValid or not data.anchor then continue end
        if not data.anchor.Parent then continue end
        
        if data.humanoid then
            local success, health = pcall(function() return data.humanoid.Health end)
            if success and health <= 0 then continue end
        end
        
        -- Verificar time
        local ignoreTeam = Settings.IgnoreTeam or Settings.IgnoreTeamAimbot
        if ignoreTeam and Utils.AreSameTeam(LocalPlayer, player) then continue end
        
        local distSq = Utils.DistanceSquared(data.anchor.Position, camPos)
        if distSq > maxDistSq then continue end
        
        local aimPart = self:GetBestPart(player)
        if not aimPart or not aimPart.Parent then continue end
        
        local success, screenPos, onScreen = pcall(function()
            return Camera:WorldToViewportPoint(aimPart.Position)
        end)
        
        if not success then continue end
        
        -- Legit: requer onScreen (exceto se AimOutsideFOV)
        if not onScreen and not Settings.AimOutsideFOV then continue end
        
        local dirToTarget = (aimPart.Position - camPos).Unit
        local dot = camLook:Dot(dirToTarget)
        
        if dot < cosThreshold and not Settings.AimOutsideFOV then continue end
        
        local distance = math.sqrt(distSq)
        
        -- Verificar altura mínima
        local minHeight = Settings.MinAimHeightBelowCamera or 50
        local heightDiff = camPos.Y - aimPart.Position.Y
        if heightDiff > minHeight then continue end
        
        local distToMouse = onScreen and (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude or 9999
        local distToMouseSq = distToMouse * distToMouse
        
        if Settings.UseAimbotFOV and distToMouseSq > currentFOVSq then continue end
        
        local score
        if targetMode == "Closest" then
            local ang = 1 - dot
            score = distance * 0.2 + distToMouse * 0.15 + (ang * 5)
        else
            score = distToMouse * 1.2 + distance * 0.1
            local angPenalty = (1 - dot) * 10
            score = score + angPenalty
        end
        
        candidates[#candidates + 1] = {
            player = player,
            data = data,
            score = score,
            distance = distance,
            aimPart = aimPart,
        }
    end
    
    if #candidates == 0 then return nil, math.huge end
    
    table.sort(candidates, function(a, b) return a.score < b.score end)
    
    -- Legit: verificar visibilidade
    for i = 1, math.min(5, #candidates) do
        local cand = candidates[i]
        
        if Settings.IgnoreWalls or not Settings.VisibleCheck then
            return cand.player, cand.score
        end
        
        if self:CheckVisible(cand.player, cand.aimPart) then
            return cand.player, cand.score
        end
    end
    
    if Settings.IgnoreWalls or not Settings.VisibleCheck then
        return candidates[1].player, candidates[1].score
    end
    
    return nil, math.huge
end

function AimbotLegit:CheckVisible(player, targetPart)
    if Settings.IgnoreWalls then return true end
    if not Settings.VisibleCheck then return true end
    
    local cached, _, hit = Utils.VisibilityCache:Get(player)
    if hit then return cached end
    
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
-- AIM CONTROLLER (LEGIT)
-- ============================================================================
function AimbotLegit:DetectMethods()
    InitExecutorFuncs()
    
    local caps = nil
    if Hooks then pcall(function() caps = Hooks:GetCapabilities() end) end
    
    if caps then
        self._hasMMR = caps.HasMouseMoveRel or ExecutorFuncs.isAvailable
    else
        self._hasMMR = ExecutorFuncs.isAvailable
    end
end

function AimbotLegit:StartAiming()
    if self._active then return end
    self._active = true
    self._controlled = true
    
    local Camera = Utils.GetCamera()
    if not Camera then return end
    
    self._prevType = Camera.CameraType
    self._prevSubject = Camera.CameraSubject
    self._prevCF = Camera.CFrame
    self._origCF = Camera.CFrame
    
    if EventBus then pcall(function() EventBus:Emit("aim:start") end) end
end

function AimbotLegit:StopAiming()
    if not self._active then return end
    self._active = false
    
    if self._lerpConn then
        pcall(function() self._lerpConn:Disconnect() end)
        self._lerpConn = nil
    end
    
    self._origCF = nil
    self._lastPos = nil
    self._validPos = nil
    self._history = {}
    self._controlled = false
    
    -- Restaurar camera
    Utils.SafeCall(function()
        local Camera = Utils.GetCamera()
        if Camera and LocalPlayer and LocalPlayer.Character then
            local hum = LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
            if hum then Camera.CameraSubject = hum end
            
            if self._prevType then
                Camera.CameraType = self._prevType
            end
        end
    end, "StopAiming")
    
    if EventBus then pcall(function() EventBus:Emit("aim:stop") end) end
end

function AimbotLegit:HoldAndStop(seconds)
    seconds = seconds or 0.2
    self._holdUntil = tick() + seconds
end

function AimbotLegit:CalcSmooth(smoothing)
    -- Usa SmoothingFactor do settings
    smoothing = smoothing or Settings.SmoothingFactor or 5
    
    if not smoothing or smoothing <= 0 then return 1.0 end
    if smoothing <= 1 then return 0.75 end
    if smoothing <= 3 then return 0.45 end
    if smoothing <= 5 then return 0.3 end
    if smoothing <= 8 then return 0.18 end
    if smoothing <= 12 then return 0.1 end
    return Utils.Clamp(0.6 / smoothing, 0.02, 0.08)
end

function AimbotLegit:ApplyShakeReduction(targetPos)
    local shakeReduction = Settings.ShakeReduction or 0
    if shakeReduction <= 0 then return targetPos end
    
    table.insert(self._history, targetPos)
    while #self._history > shakeReduction + 2 do
        table.remove(self._history, 1)
    end
    
    if #self._history < 2 then return targetPos end
    
    local avgPos = Vector3.zero
    local totalWeight = 0
    
    for i, pos in ipairs(self._history) do
        local weight = i * i
        avgPos = avgPos + pos * weight
        totalWeight = totalWeight + weight
    end
    
    return avgPos / totalWeight
end

function AimbotLegit:ApplyAim(targetPos, smoothing)
    if not targetPos then return false end
    
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
    
    -- Deadzone check
    if Settings.UseDeadzone then
        local success, screenPos, onScreen = pcall(function()
            return Camera:WorldToViewportPoint(targetPos)
        end)
        
        if success and onScreen then
            local UIS = GetUIS()
            if UIS then
                local mousePos = UIS:GetMouseLocation()
                local dist = (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude
                local deadzone = Settings.DeadzoneRadius or 2
                if dist < deadzone then return true end
            end
        end
    end
    
    if method == "MouseMoveRel" and self._hasMMR then
        return self:Method_MMR(targetPos, smoothFactor)
    else
        return self:Method_Cam(targetPos, smoothFactor)
    end
end

function AimbotLegit:Method_Cam(targetPos, smoothFactor)
    local success = pcall(function()
        self:StartAiming()
        
        local Camera = Utils.GetCamera()
        local camPos = Camera.CFrame.Position
        local dir = targetPos - camPos
        
        if dir.Magnitude < 0.001 then return end
        
        local targetCF = CFrame.lookAt(camPos, targetPos)
        
        -- Legit: sempre lerp suave
        local currentRot = Camera.CFrame.Rotation
        local targetRot = targetCF.Rotation
        local smoothedRot = currentRot:Lerp(targetRot, smoothFactor)
        Camera.CFrame = CFrame.new(camPos) * smoothedRot
    end)
    
    return success
end

function AimbotLegit:Method_MMR(targetPos, smoothFactor)
    if not self._hasMMR then
        return self:Method_Cam(targetPos, smoothFactor)
    end
    
    local success = pcall(function()
        self._active = true
        
        local Camera = Utils.GetCamera()
        
        local success2, screenPos, onScreen = pcall(function()
            return Camera:WorldToViewportPoint(targetPos)
        end)
        
        if not success2 or not onScreen then return end
        
        local viewport = Camera.ViewportSize
        local centerX = viewport.X / 2
        local centerY = viewport.Y / 2
        
        local deltaX = screenPos.X - centerX
        local deltaY = screenPos.Y - centerY
        
        local moveX = deltaX * smoothFactor
        local moveY = deltaY * smoothFactor
        
        if math.abs(moveX) < 0.1 and math.abs(moveY) < 0.1 then return end
        
        SafeMouseMove(moveX, moveY)
    end)
    
    return success
end

-- ============================================================================
-- MAIN UPDATE
-- ============================================================================
function AimbotLegit:Update(mouseHold)
    if not self._init then return end
    
    SyncSettings()
    
    pcall(function() Utils.VisibilityCache:NextFrame() end)
    
    local holdActive = self._holdUntil and tick() < self._holdUntil
    local shouldBeActive = (Settings.AimbotActive and mouseHold) or holdActive
    
    if not shouldBeActive then
        if self.Active then
            self.Active = false
            Lock:Clear()
            if not holdActive then self:StopAiming() end
        end
        
        if self._holdUntil and tick() >= self._holdUntil then
            self._holdUntil = nil
            self:StopAiming()
        end
        return
    end
    
    self.Active = true
    
    local bestTarget, bestScore = self:FindBest()
    if bestTarget then Lock:TryAcquire(bestTarget, bestScore) end
    
    local target = Lock:Get()
    
    if target then
        local data = Utils.GetPlayerData(target)
        if not data or not data.isValid then
            if Settings.AutoResetOnKill then
                self:HoldAndStop(0.2)
            else
                self:StopAiming()
            end
            Lock:Clear()
            return
        end
        
        if data.humanoid then
            local success, health = pcall(function() return data.humanoid.Health end)
            if success and health <= 0 then
                if Settings.AutoResetOnKill then
                    self:HoldAndStop(0.2)
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
            
            local smoothing = Settings.SmoothingFactor or 5
            
            -- Adaptive smoothing
            if Settings.UseAdaptiveSmoothing then
                local Camera = Utils.GetCamera()
                if Camera then
                    local distSq = Utils.DistanceSquared(data.anchor.Position, Camera.CFrame.Position)
                    if distSq < 2500 then
                        smoothing = smoothing * 1.5
                    elseif distSq > 90000 then
                        smoothing = smoothing * 0.6
                    end
                end
            end
            
            self:ApplyAim(aimPos, smoothing)
            
            if EventBus then
                pcall(function() EventBus:Emit("aim:applied", target, aimPos) end)
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
-- PUBLIC API
-- ============================================================================
function AimbotLegit:Toggle(enabled)
    Settings.AimbotActive = enabled
    if not enabled then
        self.Active = false
        self._holdUntil = nil
        Lock:Clear()
        self:StopAiming()
    end
end

function AimbotLegit:SetTargetMode(mode)
    Settings.TargetMode = mode
end

function AimbotLegit:SetAimOutsideFOV(enabled)
    Settings.AimOutsideFOV = enabled
end

function AimbotLegit:SetAimbotFOV(fov)
    Settings.AimbotFOV = fov
    Settings.FOV = fov
end

function AimbotLegit:GetCurrentTarget()
    return Lock:Get()
end

function AimbotLegit:GetTargetPosition()
    local target = Lock:Get()
    if not target then return nil end
    
    local aimPart = self:GetBestPart(target)
    if not aimPart then return nil end
    
    return self:Predict(target, aimPart)
end

function AimbotLegit:ForceReset()
    self.Active = false
    self._holdUntil = nil
    Lock:Clear()
    self:StopAiming()
    self._predHistory = {}
    self._lastPredUpdate = {}
    self._failCount = {}
    self._validPos = nil
    
    pcall(function() Utils.VisibilityCache:Clear() end)
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================
function AimbotLegit:Initialize(deps)
    if self._init then return self end
    
    if not deps then
        warn("[AimbotLegit] Missing dependencies")
        return nil
    end
    
    Utils = deps.Utils
    Settings = deps.Settings
    EventBus = deps.EventBus
    Hooks = deps.Hooks
    LocalPlayer = deps.LocalPlayer
    
    if not Utils then
        warn("[AimbotLegit] Utils not available")
        return nil
    end
    
    SyncSettings()
    self:DetectMethods()
    
    if EventBus then
        pcall(function()
            EventBus:On("target:killed", function()
                if Settings.AutoResetOnKill then
                    self:HoldAndStop(0.2)
                end
            end)
        end)
    end
    
    self._init = true
    return self
end

-- ============================================================================
-- EXPORT
-- ============================================================================
return {
    Aimbot = AimbotLegit,
    TargetLock = Lock,
    Type = "Legit",
}