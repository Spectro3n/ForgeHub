-- ============================================================================
-- FORGEHUB - RAGE MODULE v4.7 (FIXED)
-- Usa Settings global passado pelo main
-- ============================================================================

local RageModule = {
    _init = false,
    _active = false,
    _lastSnap = 0,
    _snapCD = 0.06,
    _snapDur = 0.04,
    
    _predHistory = {},
    _lastPredUpdate = {},
    _failCount = {},
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
local function GetUIS() return GetService("UserInputService") end

-- ============================================================================
-- DEPENDENCIES (PASSADAS PELO MAIN)
-- ============================================================================
local Utils = nil
local Settings = nil  -- SETTINGS GLOBAL DO MAIN
local LocalPlayer = nil
local BaseAimbot = nil

-- ============================================================================
-- EXECUTOR FUNCTIONS
-- ============================================================================
local ExecutorFuncs = { mouseMove = nil, isAvailable = false }

local function InitExecutorFuncs()
    local mmrCheck = {"mousemoverel", "mouse_moverel"}
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
end

local function SafeMouseMove(dx, dy)
    if not ExecutorFuncs.isAvailable then return false end
    return pcall(function() ExecutorFuncs.mouseMove(dx, dy) end)
end

-- ============================================================================
-- HELPER - GET RAGE LEVEL (USA SETTINGS GLOBAL)
-- ============================================================================
local function GetRageLevel()
    if not Settings then return 0 end
    if Settings.GodRageMode then return 3 end
    if Settings.UltraRageMode then return 2 end
    if Settings.RageMode then return 1 end
    return 0
end

local function IsRageActive()
    if not Settings then return false end
    return Settings.RageMode or Settings.UltraRageMode or Settings.GodRageMode
end

-- ============================================================================
-- RAGE TARGET LOCK
-- ============================================================================
local RageLock = {
    Current = nil,
    Time = 0,
    Score = math.huge,
    Kills = 0,
}

function RageLock:Clear()
    self.Current = nil
    self.Time = 0
    self.Score = math.huge
end

function RageLock:IsAlive()
    if not self.Current or not Utils then return false end
    local data = Utils.GetPlayerData(self.Current)
    if not data or not data.isValid then return false end
    if not data.anchor or not data.anchor.Parent then return false end
    
    if data.humanoid then
        local s, h = pcall(function() return data.humanoid.Health end)
        if s and h <= 0 then return false end
    end
    return true
end

function RageLock:Validate()
    if not self.Current then return false end
    if not self:IsAlive() then
        self.Kills = self.Kills + 1
        return false
    end
    return true
end

function RageLock:TryAcquire(candidate, score)
    if not candidate then return end
    
    local now = tick()
    local rageLevel = GetRageLevel()
    
    if rageLevel >= 3 then
        self.Current = candidate
        self.Time = now
        self.Score = score
        return
    end
    
    if rageLevel >= 2 then
        if not self.Current or not self:Validate() or (now - self.Time) > 0.08 then
            self.Current = candidate
            self.Time = now
            self.Score = score
        elseif score < self.Score * 0.15 then
            self.Current = candidate
            self.Time = now
            self.Score = score
        end
        return
    end
    
    if not self.Current or not self:Validate() or (now - self.Time) > 0.15 then
        self.Current = candidate
        self.Time = now
        self.Score = score
    elseif score < self.Score * 0.25 then
        self.Current = candidate
        self.Time = now
        self.Score = score
    end
end

function RageLock:Get()
    if self:Validate() then return self.Current end
    self:Clear()
    return nil
end

-- ============================================================================
-- RAGE PREDICTION
-- ============================================================================
local PRED_HISTORY_SIZE = 10

function RageModule:CalcVelocity(player, anchor)
    if not anchor or not anchor.Parent then return Vector3.zero end
    
    local vel
    pcall(function() vel = anchor.AssemblyLinearVelocity or anchor.Velocity end)
    if vel and vel.Magnitude > 0.3 then return vel end
    
    return Vector3.zero
end

function RageModule:CalcAccel(player)
    local hist = self._predHistory[player]
    if not hist or #hist < 3 then return Vector3.zero end
    
    local newest = hist[#hist]
    local oldest = hist[#hist - 2]
    local dt = newest.t - oldest.t
    
    if dt > 0.02 then
        return (newest.vel - oldest.vel) / dt
    end
    
    return Vector3.zero
end

function RageModule:Predict(player, part)
    if not part or not part.Parent then return nil end
    
    local basePos = part.Position
    local data = Utils.GetPlayerData(player)
    if not data or not data.anchor then return basePos end
    
    if not Settings.UsePrediction then return basePos end
    
    local vel = self:CalcVelocity(player, data.anchor)
    local accel = Vector3.zero
    
    local rageLevel = GetRageLevel()
    
    if rageLevel >= 2 then
        accel = self:CalcAccel(player)
    end
    
    local yMult = rageLevel >= 3 and 0.8 or (rageLevel >= 2 and 0.7 or 0.55)
    if vel.Y > 0 then
        vel = Vector3.new(vel.X, vel.Y * yMult, vel.Z)
    end
    
    local Camera = Utils.GetCamera()
    if not Camera then return basePos end
    
    local dist = (part.Position - Camera.CFrame.Position).Magnitude
    
    local timeDiv = rageLevel >= 3 and 280 or (rageLevel >= 2 and 320 or 400)
    local timeToTarget = math.clamp(dist / timeDiv, 0.01, 0.5)
    
    local mult = Settings.PredictionMultiplier or 0.15
    if rageLevel >= 3 then
        mult = mult * 3.5
    elseif rageLevel >= 2 then
        mult = mult * 2.5
    else
        mult = mult * 1.8
    end
    
    local predicted = basePos + (vel * mult * timeToTarget)
    
    if accel.Magnitude > 0.1 then
        predicted = predicted + (accel * 0.6 * timeToTarget * timeToTarget)
    end
    
    if not self._predHistory[player] then
        self._predHistory[player] = {}
    end
    
    table.insert(self._predHistory[player], {pos = basePos, vel = vel, t = tick()})
    while #self._predHistory[player] > PRED_HISTORY_SIZE do
        table.remove(self._predHistory[player], 1)
    end
    
    return predicted
end

-- ============================================================================
-- RAGE AIM PARTS
-- ============================================================================
function RageModule:GetBestPart(player)
    local data = Utils.GetPlayerData(player)
    if not data or not data.model or not data.model.Parent then return nil end
    
    local rageLevel = GetRageLevel()
    local headOnly = Settings.RageHeadOnly
    
    if headOnly or rageLevel >= 2 then
        local head = data.model:FindFirstChild("Head")
        if head and head.Parent then return head end
    end
    
    if BaseAimbot and BaseAimbot.GetPart then
        return BaseAimbot:GetPart(player, Settings.AimPart)
    end
    
    return data.anchor
end

-- ============================================================================
-- RAGE TARGET FINDING
-- ============================================================================
local CachedPlayers = {}
local LastCacheUpdate = 0

local function GetCachedPlayers()
    local now = tick()
    if now - LastCacheUpdate > 0.15 then
        local Players = GetPlayers()
        if Players then CachedPlayers = Players:GetPlayers() end
        LastCacheUpdate = now
    end
    return CachedPlayers
end

function RageModule:FindBest()
    local Camera = Utils.GetCamera()
    if not Camera then return nil, math.huge end
    
    local camPos = Camera.CFrame.Position
    
    local UIS = GetUIS()
    local mousePos = UIS and UIS:GetMouseLocation() or Vector2.new(0, 0)
    
    local rageLevel = GetRageLevel()
    
    local baseFOV = Settings.AimbotFOV or Settings.FOV or 180
    local maxFOV = rageLevel >= 3 and 99999 or 
                   (rageLevel >= 2 and baseFOV * 5 or baseFOV * 3)
    
    local baseDist = Settings.MaxDistance or 2000
    local maxDist = rageLevel >= 3 and 99999 or 
                    (rageLevel >= 2 and baseDist * 4 or baseDist * 2)
    
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
            local s, h = pcall(function() return data.humanoid.Health end)
            if s and h <= 0 then continue end
        end
        
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
        
        local allowOutside = rageLevel >= 3 or Settings.AimOutsideFOV
        if not onScreen and not allowOutside then continue end
        
        local distance = math.sqrt(distSq)
        local distToMouse = onScreen and (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude or 9999
        
        if rageLevel < 3 and distToMouse > maxFOV then continue end
        
        local healthMult = 1
        if data.humanoid then
            local s, hp = pcall(function() return data.humanoid.Health / data.humanoid.MaxHealth end)
            if s then healthMult = 0.2 + hp * 0.8 end
        end
        
        local score
        if rageLevel >= 3 then
            score = distance * 0.15 * healthMult
        elseif rageLevel >= 2 then
            score = distance * 0.2 + distToMouse * 0.08
        else
            score = distance * 0.25 + distToMouse * 0.2
        end
        
        score = score * healthMult
        
        candidates[#candidates + 1] = {
            player = player,
            score = score,
            aimPart = aimPart,
            distance = distance,
        }
    end
    
    if #candidates == 0 then return nil, math.huge end
    
    table.sort(candidates, function(a, b) return a.score < b.score end)
    
    local maxChecks = rageLevel >= 3 and 1 or (rageLevel >= 2 and 1 or 2)
    
    for i = 1, math.min(maxChecks, #candidates) do
        local cand = candidates[i]
        
        if rageLevel >= 3 or Settings.IgnoreWalls then
            return cand.player, cand.score
        end
        
        if BaseAimbot and BaseAimbot.CheckVisible then
            if BaseAimbot:CheckVisible(cand.player, cand.aimPart) then
                return cand.player, cand.score
            end
        else
            return cand.player, cand.score
        end
    end
    
    if rageLevel >= 3 or Settings.IgnoreWalls then
        return candidates[1].player, candidates[1].score
    end
    
    return nil, math.huge
end

-- ============================================================================
-- RAGE AIM APPLICATION
-- ============================================================================
function RageModule:ApplyAim(targetPos)
    if not targetPos then return false end
    
    local Camera = Utils.GetCamera()
    if not Camera then return false end
    
    local method = Settings.AimMethod or "Camera"
    
    if method == "MouseMoveRel" and ExecutorFuncs.isAvailable then
        return self:Method_MMR_Rage(targetPos)
    else
        return self:Method_Cam_Rage(targetPos)
    end
end

function RageModule:Method_Cam_Rage(targetPos)
    local success = pcall(function()
        local Camera = Utils.GetCamera()
        local camPos = Camera.CFrame.Position
        local targetCF = CFrame.lookAt(camPos, targetPos)
        
        local now = tick()
        local rageLevel = GetRageLevel()
        
        if rageLevel >= 3 then
            Camera.CFrame = targetCF
        elseif rageLevel >= 2 then
            if (now - self._lastSnap) >= 0.02 then
                Camera.CFrame = targetCF
                self._lastSnap = now
            else
                Camera.CFrame = Camera.CFrame:Lerp(targetCF, 0.98)
            end
        else
            if (now - self._lastSnap) >= self._snapCD then
                Camera.CFrame = Camera.CFrame:Lerp(targetCF, 0.95)
                self._lastSnap = now
            else
                Camera.CFrame = Camera.CFrame:Lerp(targetCF, 0.88)
            end
        end
    end)
    
    return success
end

function RageModule:Method_MMR_Rage(targetPos)
    local success = pcall(function()
        local Camera = Utils.GetCamera()
        
        local s, screenPos, onScreen = pcall(function()
            return Camera:WorldToViewportPoint(targetPos)
        end)
        
        if not s then return end
        
        local rageLevel = GetRageLevel()
        if not onScreen and rageLevel < 3 then return end
        
        local viewport = Camera.ViewportSize
        local centerX = viewport.X / 2
        local centerY = viewport.Y / 2
        
        local deltaX = screenPos.X - centerX
        local deltaY = screenPos.Y - centerY
        
        local mult = rageLevel >= 3 and 1.1 or (rageLevel >= 2 and 1.05 or 0.98)
        
        SafeMouseMove(deltaX * mult, deltaY * mult)
    end)
    
    return success
end

-- ============================================================================
-- RAGE UPDATE
-- ============================================================================
function RageModule:Update(mouseHold)
    if not self._init then return false end
    
    -- Verificar se algum modo rage está ativo (USA SETTINGS GLOBAL)
    if not IsRageActive() then
        return false
    end
    
    if not Settings.AimbotActive or not mouseHold then
        if self._active then
            self._active = false
            RageLock:Clear()
        end
        return true
    end
    
    self._active = true
    
    local bestTarget, bestScore = self:FindBest()
    if bestTarget then
        RageLock:TryAcquire(bestTarget, bestScore)
    end
    
    local target = RageLock:Get()
    
    if target then
        local aimPart = self:GetBestPart(target)
        
        if aimPart and aimPart.Parent then
            local aimPos = self:Predict(target, aimPart)
            
            if aimPos then
                self:ApplyAim(aimPos)
            end
        else
            RageLock:Clear()
        end
    end
    
    return true
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================
function RageModule:IsActive()
    return IsRageActive()
end

function RageModule:GetRageLevel()
    return GetRageLevel()
end

function RageModule:GetCurrentTarget()
    return RageLock:Get()
end

function RageModule:SetRageMode(enabled)
    Settings.RageMode = enabled
    if not enabled then
        Settings.UltraRageMode = false
        Settings.GodRageMode = false
        RageLock:Clear()
        self._active = false
    end
end

function RageModule:SetUltraRageMode(enabled)
    Settings.UltraRageMode = enabled
    if enabled then
        Settings.RageMode = true
    end
    if not enabled then
        Settings.GodRageMode = false
        RageLock:Clear()
    end
end

function RageModule:SetGodRageMode(enabled)
    Settings.GodRageMode = enabled
    if enabled then
        Settings.RageMode = true
        Settings.UltraRageMode = true
    end
    if not enabled then
        RageLock:Clear()
    end
end

function RageModule:ForceReset()
    self._active = false
    RageLock:Clear()
    self._predHistory = {}
    self._lastSnap = 0
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================
function RageModule:Initialize(deps)
    if self._init then return self end
    
    if not deps then
        warn("[RageModule] Missing dependencies")
        return nil
    end
    
    Utils = deps.Utils
    Settings = deps.Settings  -- USA O SETTINGS DO MAIN!
    LocalPlayer = deps.LocalPlayer
    BaseAimbot = deps.Aimbot
    
    if not Utils then
        warn("[RageModule] Utils not available")
        return nil
    end
    
    if not Settings then
        warn("[RageModule] Settings not available")
        return nil
    end
    
    InitExecutorFuncs()
    
    self._init = true
    print("[RageModule] Initialized with global Settings")
    return self
end

-- ============================================================================
-- EXPORT
-- ============================================================================
return {
    Rage = RageModule,
    RageLock = RageLock,
    Type = "Rage",
}