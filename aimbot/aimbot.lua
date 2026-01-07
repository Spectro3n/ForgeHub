-- ============================================================================
-- FORGEHUB - AIMBOT LEGIT MODULE v5.0 (NO MouseMoveRel)
-- Versão limpa sem getgenv/MouseMoveRel - Usa apenas Camera manipulation
-- Suporta jogos que usam mouse-lock através de simulação via Camera
-- ============================================================================

local AimbotLegit = {
    _init = false,
    _active = false,
    Active = false,
    _validPos = nil,
    _history = {},
    
    _holdUntil = nil,
    _prevType = nil,
    _prevCF = nil,
    
    _failCount = {},
    _maxFails = 3,
    _consecutiveErrors = 0,
    _maxConsecutiveErrors = 10,
    
    _predHistory = {},
    _lastPredUpdate = {},
    _lastPredCleanup = 0,
    
    -- Mouse simulation state
    _mouseAccumX = 0,
    _mouseAccumY = 0,
    _lastMouseUpdate = 0,
    
    -- Debug
    _debugMode = false,
    _lastDebug = 0,
}

-- ============================================================================
-- SERVICES
-- ============================================================================
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

-- ============================================================================
-- DEPENDENCIES (serão preenchidas em Initialize)
-- ============================================================================
local Utils = nil
local Settings = nil
local LocalPlayer = nil
local Camera = nil

-- ============================================================================
-- DEBUG FUNCTION
-- ============================================================================
local function DebugPrint(...)
    if AimbotLegit._debugMode then
        print("[Aimbot Debug]", ...)
    end
end

-- ============================================================================
-- INTERNAL HELPERS
-- ============================================================================

local function GetCamera()
    Camera = Workspace.CurrentCamera
    return Camera
end

local function InternalGetPlayerData(player)
    if not player then return nil end
    
    local character = player.Character
    if not character or not character.Parent then return nil end
    
    local anchor = character:FindFirstChild("HumanoidRootPart")
                or character:FindFirstChild("Torso")
                or character:FindFirstChild("UpperTorso")
                or character:FindFirstChild("Head")
                or character.PrimaryPart
    
    if not anchor or not anchor.Parent then return nil end
    
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    
    if humanoid then
        local success, health = pcall(function() return humanoid.Health end)
        if success and health <= 0 then return nil end
    end
    
    return {
        isValid = true,
        model = character,
        anchor = anchor,
        humanoid = humanoid,
        player = player,
    }
end

local function GetPlayerData(player)
    if Utils and Utils.GetPlayerData then
        local success, data = pcall(function()
            return Utils.GetPlayerData(player)
        end)
        if success and data and data.isValid then 
            return data 
        end
    end
    
    return InternalGetPlayerData(player)
end

local function InternalAreSameTeam(player1, player2)
    if not player1 or not player2 then return false end
    
    if player1.Team and player2.Team then
        return player1.Team == player2.Team
    end
    
    if player1.TeamColor and player2.TeamColor then
        return player1.TeamColor == player2.TeamColor
    end
    
    if player1.Neutral or player2.Neutral then
        return false
    end
    
    return false
end

local function AreSameTeam(player1, player2)
    if Utils and Utils.AreSameTeam then
        local success, result = pcall(function()
            return Utils.AreSameTeam(player1, player2)
        end)
        if success then return result end
    end
    
    return InternalAreSameTeam(player1, player2)
end

local function IsValidPosition(pos)
    if not pos then return false end
    if typeof(pos) ~= "Vector3" then return false end
    
    if pos.X ~= pos.X or pos.Y ~= pos.Y or pos.Z ~= pos.Z then
        return false
    end
    
    if math.abs(pos.X) > 1e6 or math.abs(pos.Y) > 1e6 or math.abs(pos.Z) > 1e6 then
        return false
    end
    
    return true
end

local function DistanceSquared(pos1, pos2)
    local delta = pos1 - pos2
    return delta.X * delta.X + delta.Y * delta.Y + delta.Z * delta.Z
end

-- ============================================================================
-- HUMANIZATION HELPERS
-- ============================================================================

local function AddMicroJitter(value, intensity)
    intensity = intensity or 0.1
    return value + (math.random() - 0.5) * intensity
end

local function EaseOutQuad(t)
    return 1 - (1 - t) * (1 - t)
end

local function EaseInOutQuad(t)
    if t < 0.5 then
        return 2 * t * t
    else
        return 1 - math.pow(-2 * t + 2, 2) / 2
    end
end

-- ============================================================================
-- DEBUG FUNCTIONS
-- ============================================================================
function AimbotLegit:EnableDebug(enabled)
    self._debugMode = enabled
    print("[Aimbot] Debug mode:", enabled and "ON" or "OFF")
end

function AimbotLegit:PrintDebugInfo()
    local now = tick()
    if now - self._lastDebug < 1 then return end
    self._lastDebug = now
    
    print("\n========== AIMBOT DEBUG ==========")
    print("Initialized:", self._init)
    print("Active:", self.Active)
    print("Settings.AimbotActive:", Settings and Settings.AimbotActive)
    print("Settings.AimbotToggleOnly:", Settings and Settings.AimbotToggleOnly)
    print("LocalPlayer:", LocalPlayer and LocalPlayer.Name or "nil")
    
    local cam = GetCamera()
    print("Camera:", cam and "OK" or "nil")
    print("AimMethod:", Settings and Settings.AimMethod or "nil")
    
    local playerCount = 0
    local validTargets = 0
    
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            playerCount = playerCount + 1
            local data = GetPlayerData(player)
            if data and data.isValid then
                validTargets = validTargets + 1
            end
        end
    end
    
    print("Total players:", playerCount)
    print("Valid targets:", validTargets)
    print("IgnoreTeam:", Settings and (Settings.IgnoreTeam or Settings.IgnoreTeamAimbot))
    print("VisibleCheck:", Settings and Settings.VisibleCheck)
    print("===================================\n")
end

-- ============================================================================
-- PREDICTION HISTORY CLEANUP
-- ============================================================================
function AimbotLegit:CleanupPredHistory()
    local now = tick()
    if now - self._lastPredCleanup < 5 then return end
    self._lastPredCleanup = now
    
    for playerId, lastUpdate in pairs(self._lastPredUpdate) do
        if now - lastUpdate > 5 then
            self._predHistory[playerId] = nil
            self._lastPredUpdate[playerId] = nil
        end
    end
end

-- ============================================================================
-- TARGET LOCK
-- ============================================================================
local Lock = {
    Current = nil,
    Time = 0,
    Score = math.huge,
    Kills = 0,
    _updating = false,
}

function Lock:Clear()
    self.Current = nil
    self.Time = 0
    self.Score = math.huge
end

function Lock:IsAlive()
    if not self.Current then return false end
    
    local data = GetPlayerData(self.Current)
    if not data or not data.isValid then return false end
    if not data.anchor or not data.anchor.Parent then return false end
    
    return true
end

function Lock:Validate()
    if not self.Current then return false end
    if not self:IsAlive() then return false end
    
    local data = GetPlayerData(self.Current)
    if not data then return false end
    
    local cam = GetCamera()
    if not cam then return false end
    
    local distSq = DistanceSquared(data.anchor.Position, cam.CFrame.Position)
    local maxDist = Settings.MaxDistance or 2000
    
    if distSq > maxDist * maxDist then return false end
    
    return true
end

function Lock:TryAcquire(candidate, score)
    if not candidate then return end
    if self._updating then return end
    
    self._updating = true
    
    local data = GetPlayerData(candidate)
    if not data or not data.isValid then 
        self._updating = false
        return 
    end
    
    local now = tick()
    local maxDur = Settings.MaxLockTime or 1.5
    local threshold = Settings.LockImprovementThreshold or 0.7
    
    if not self.Current then
        self.Current = candidate
        self.Time = now
        self.Score = score
        DebugPrint("Locked:", candidate.Name, "Score:", score)
        self._updating = false
        return
    end
    
    if self.Current == candidate then
        self.Score = score
        self._updating = false
        return
    end
    
    if not self:Validate() then
        self.Current = candidate
        self.Time = now
        self.Score = score
        DebugPrint("Switched (invalid):", candidate.Name)
        self._updating = false
        return
    end
    
    local lockDur = now - self.Time
    
    if Settings.AutoSwitch and lockDur > (Settings.TargetSwitchDelay or 0.3) then
        self.Current = candidate
        self.Time = now
        self.Score = score
        self._updating = false
        return
    end
    
    if lockDur > maxDur then
        self.Current = candidate
        self.Time = now
        self.Score = score
        self._updating = false
        return
    end
    
    if score < self.Score * threshold then
        self.Current = candidate
        self.Time = now
        self.Score = score
        DebugPrint("Switched (better):", candidate.Name)
    end
    
    self._updating = false
end

function Lock:Get()
    if self:Validate() then return self.Current end
    self:Clear()
    return nil
end

-- ============================================================================
-- AIM PARTS
-- ============================================================================
local PART_ALIASES = {
    Head = {"Head"},
    Torso = {"UpperTorso", "Torso", "HumanoidRootPart"},
    Root = {"HumanoidRootPart", "Torso", "UpperTorso"},
}

function AimbotLegit:GetPart(player, partName)
    local data = GetPlayerData(player)
    if not data or not data.model then return nil end
    
    partName = partName or Settings.AimPart or "Head"
    local model = data.model
    
    local candidates = PART_ALIASES[partName] or {partName}
    
    for _, name in ipairs(candidates) do
        local part = model:FindFirstChild(name)
        if part and part:IsA("BasePart") and part.Parent then
            return part
        end
    end
    
    return data.anchor
end

-- ============================================================================
-- VISIBILITY CHECK
-- ============================================================================
local RayParams = RaycastParams.new()
RayParams.FilterType = Enum.RaycastFilterType.Exclude

function AimbotLegit:UpdateRayParams()
    local filter = {}
    
    local cam = GetCamera()
    if cam then
        table.insert(filter, cam)
    end
    
    if LocalPlayer and LocalPlayer.Character then
        table.insert(filter, LocalPlayer.Character)
    end
    
    RayParams.FilterDescendantsInstances = filter
end

function AimbotLegit:CheckVisible(player, targetPart)
    if Settings.IgnoreWalls then return true end
    if not Settings.VisibleCheck then return true end
    
    local cam = GetCamera()
    if not cam then return false end
    
    local data = GetPlayerData(player)
    if not data or not data.model then return false end
    
    self:UpdateRayParams()
    
    local origin = cam.CFrame.Position
    local target = targetPart.Position
    local direction = target - origin
    
    local success, result = pcall(function()
        return Workspace:Raycast(origin, direction, RayParams)
    end)
    
    if not success then return true end
    
    if result and result.Instance then
        if result.Instance:IsDescendantOf(data.model) then
            return true
        end
        return false
    end
    
    return true
end

-- ============================================================================
-- TARGET FINDING
-- ============================================================================
function AimbotLegit:FindBest()
    local cam = GetCamera()
    if not cam then 
        DebugPrint("FindBest: No camera")
        return nil, math.huge 
    end
    
    local camPos = cam.CFrame.Position
    local camLook = cam.CFrame.LookVector
    
    local success, mousePos = pcall(function()
        return UserInputService:GetMouseLocation()
    end)
    
    if not success then
        DebugPrint("FindBest: Failed to get mouse position")
        return nil, math.huge
    end
    
    local currentFOV = Settings.AimbotFOV or Settings.FOV or 180
    local currentFOVSq = currentFOV * currentFOV
    local maxDist = Settings.MaxDistance or 2000
    local maxDistSq = maxDist * maxDist
    
    local candidates = {}
    local allPlayers = Players:GetPlayers()
    
    DebugPrint("Scanning", #allPlayers - 1, "players")
    
    for _, player in ipairs(allPlayers) do
        if player == LocalPlayer then continue end
        
        local data = GetPlayerData(player)
        if not data or not data.isValid then 
            DebugPrint("  Skip", player.Name, "- invalid data")
            continue 
        end
        
        if not data.anchor or not data.anchor.Parent then
            DebugPrint("  Skip", player.Name, "- no anchor")
            continue
        end
        
        local ignoreTeam = Settings.IgnoreTeam or Settings.IgnoreTeamAimbot
        if ignoreTeam and AreSameTeam(LocalPlayer, player) then
            DebugPrint("  Skip", player.Name, "- same team")
            continue
        end
        
        local distSq = DistanceSquared(data.anchor.Position, camPos)
        if distSq > maxDistSq then
            DebugPrint("  Skip", player.Name, "- too far")
            continue
        end
        
        local aimPart = self:GetPart(player, Settings.AimPart)
        if not aimPart or not aimPart.Parent then
            DebugPrint("  Skip", player.Name, "- no aim part")
            continue
        end
        
        local screenPos, onScreen
        local screenSuccess = pcall(function()
            screenPos, onScreen = cam:WorldToViewportPoint(aimPart.Position)
        end)
        
        if not screenSuccess then continue end
        
        if not onScreen and not Settings.AimOutsideFOV then
            DebugPrint("  Skip", player.Name, "- off screen")
            continue
        end
        
        local distance = math.sqrt(distSq)
        local distToMouse = onScreen and (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude or 9999
        
        if Settings.UseAimbotFOV and distToMouse * distToMouse > currentFOVSq then
            DebugPrint("  Skip", player.Name, "- outside FOV")
            continue
        end
        
        local targetMode = Settings.TargetMode or "FOV"
        local score
        
        if targetMode == "Closest" then
            score = distance
        else
            score = distToMouse + distance * 0.1
        end
        
        DebugPrint("  Candidate:", player.Name, "Score:", math.floor(score))
        
        candidates[#candidates + 1] = {
            player = player,
            score = score,
            aimPart = aimPart,
            distance = distance,
        }
    end
    
    if #candidates == 0 then 
        DebugPrint("No candidates found")
        return nil, math.huge 
    end
    
    table.sort(candidates, function(a, b) return a.score < b.score end)
    
    for i = 1, math.min(5, #candidates) do
        local cand = candidates[i]
        
        if self:CheckVisible(cand.player, cand.aimPart) then
            DebugPrint("Selected:", cand.player.Name)
            return cand.player, cand.score
        else
            DebugPrint("  Not visible:", cand.player.Name)
        end
    end
    
    if Settings.IgnoreWalls then
        return candidates[1].player, candidates[1].score
    end
    
    return nil, math.huge
end

-- ============================================================================
-- PREDICTION
-- ============================================================================
function AimbotLegit:Predict(player, part)
    if not part or not part.Parent then return nil end
    
    local basePos = part.Position
    if not IsValidPosition(basePos) then return nil end
    
    if not Settings.UsePrediction then return basePos end
    
    local data = GetPlayerData(player)
    if not data or not data.anchor then return basePos end
    
    local vel = Vector3.zero
    pcall(function()
        vel = data.anchor.AssemblyLinearVelocity or data.anchor.Velocity or Vector3.zero
    end)
    
    if vel.Magnitude < 0.5 then return basePos end
    
    if vel.Y > 0 then
        vel = Vector3.new(vel.X, vel.Y * 0.3, vel.Z)
    end
    
    local cam = GetCamera()
    if not cam then return basePos end
    
    local dist = (part.Position - cam.CFrame.Position).Magnitude
    local timeToTarget = math.clamp(dist / 800, 0.01, 0.3)
    
    local mult = Settings.PredictionMultiplier or 0.12
    local predicted = basePos + (vel * mult * timeToTarget)
    
    if not IsValidPosition(predicted) then
        return basePos
    end
    
    -- Update prediction history
    local playerId = player.UserId
    self._predHistory[playerId] = predicted
    self._lastPredUpdate[playerId] = tick()
    
    return predicted
end

-- ============================================================================
-- SMOOTHING CALCULATION
-- ============================================================================
function AimbotLegit:CalcSmooth(smoothing)
    smoothing = smoothing or Settings.SmoothingFactor or 5
    
    if not smoothing or smoothing <= 0 then return 1.0 end
    if smoothing <= 1 then return 0.75 end
    if smoothing <= 3 then return 0.45 end
    if smoothing <= 5 then return 0.3 end
    if smoothing <= 8 then return 0.18 end
    if smoothing <= 12 then return 0.1 end
    return math.clamp(0.6 / smoothing, 0.02, 0.08)
end

function AimbotLegit:CalculateAdaptiveSmoothing(data)
    local smoothing = Settings.SmoothingFactor or 5
    
    if not Settings.UseAdaptiveSmoothing then
        return smoothing
    end
    
    local cam = GetCamera()
    if not cam or not data or not data.anchor then return smoothing end
    
    local distSq = DistanceSquared(data.anchor.Position, cam.CFrame.Position)
    
    if distSq < 2500 then -- < 50 studs
        return smoothing * 1.5
    elseif distSq > 90000 then -- > 300 studs
        return smoothing * 0.6
    end
    
    return smoothing
end

-- ============================================================================
-- AIM APPLICATION - CAMERA METHOD (PRIMARY)
-- ============================================================================
function AimbotLegit:Method_Camera(targetPos, smoothFactor)
    local success = pcall(function()
        self._active = true
        
        local cam = GetCamera()
        if not cam then 
            error("Camera is nil")
        end
        
        local camPos = cam.CFrame.Position
        local dir = targetPos - camPos
        
        if dir.Magnitude < 0.001 then return end
        
        local targetCF = CFrame.lookAt(camPos, targetPos)
        local currentRot = cam.CFrame.Rotation
        local targetRot = targetCF.Rotation
        
        -- Use easing for more human-like movement
        local easedFactor = smoothFactor
        if Settings.AimSafety then
            easedFactor = EaseOutQuad(smoothFactor) * 0.8
        end
        
        local smoothedRot = currentRot:Lerp(targetRot, easedFactor)
        
        -- Add micro-jitter if AimSafety is on
        if Settings.AimSafety then
            local jitterX = AddMicroJitter(0, 0.001)
            local jitterY = AddMicroJitter(0, 0.001)
            smoothedRot = smoothedRot * CFrame.Angles(jitterY, jitterX, 0)
        end
        
        local newCFrame = CFrame.new(camPos) * smoothedRot
        cam.CFrame = newCFrame
    end)
    
    if not success then
        self._consecutiveErrors = (self._consecutiveErrors or 0) + 1
        
        if self._debugMode then
            warn("[Aimbot] Method_Camera error")
        end
        
        if self._consecutiveErrors > self._maxConsecutiveErrors then
            DebugPrint("Method_Camera: Too many errors, resetting...")
            self:ForceReset()
            
            task.delay(0.5, function()
                self._consecutiveErrors = 0
            end)
        end
        
        return false
    end
    
    self._consecutiveErrors = 0
    return true
end

-- ============================================================================
-- AIM APPLICATION - MOUSE SIMULATION VIA CAMERA (ALTERNATIVE)
-- Simulates mouse movement by calculating screen-space deltas
-- Works for games that use mouse-lock or first-person mechanics
-- ============================================================================
function AimbotLegit:Method_MouseSim(targetPos, smoothFactor)
    local success = pcall(function()
        self._active = true
        
        local cam = GetCamera()
        if not cam then return end
        
        -- Get screen position of target
        local screenPos, onScreen = cam:WorldToViewportPoint(targetPos)
        if not onScreen then 
            -- Target off screen - use camera method instead
            return self:Method_Camera(targetPos, smoothFactor)
        end
        
        local viewport = cam.ViewportSize
        local centerX = viewport.X / 2
        local centerY = viewport.Y / 2
        
        -- Calculate delta from screen center to target
        local deltaX = screenPos.X - centerX
        local deltaY = screenPos.Y - centerY
        
        -- Check deadzone
        local deltaMagnitude = math.sqrt(deltaX * deltaX + deltaY * deltaY)
        local deadzone = Settings.DeadzoneRadius or 2
        
        if deltaMagnitude < deadzone then
            return true -- Already on target
        end
        
        -- Apply smoothing with easing
        local easedFactor = smoothFactor
        if Settings.AimSafety then
            easedFactor = EaseInOutQuad(smoothFactor) * 0.7
        end
        
        -- Convert screen delta to camera rotation
        -- This simulates what mouse movement would do
        local sensitivity = 0.002 -- Base sensitivity multiplier
        local rotX = -deltaY * sensitivity * easedFactor
        local rotY = -deltaX * sensitivity * easedFactor
        
        -- Add humanization
        if Settings.AimSafety then
            rotX = AddMicroJitter(rotX, 0.0005)
            rotY = AddMicroJitter(rotY, 0.0005)
        end
        
        -- Apply rotation to camera
        local currentCF = cam.CFrame
        local newCF = currentCF * CFrame.Angles(rotX, rotY, 0)
        
        -- Clamp vertical rotation to prevent camera flip
        local _, currentY, _ = currentCF:ToEulerAnglesYXZ()
        local newX, newY, newZ = newCF:ToEulerAnglesYXZ()
        
        -- Limit pitch (up/down)
        newX = math.clamp(newX, -math.rad(89), math.rad(89))
        
        cam.CFrame = CFrame.new(currentCF.Position) * CFrame.Angles(newX, newY, newZ)
    end)
    
    return success
end

-- ============================================================================
-- MAIN AIM APPLICATION
-- ============================================================================
function AimbotLegit:ApplyAim(targetPos, smoothing)
    if not targetPos then return false end
    if not IsValidPosition(targetPos) then return false end
    
    local cam = GetCamera()
    if not cam then return false end
    
    local method = Settings.AimMethod or "Camera"
    local smoothFactor = self:CalcSmooth(smoothing)
    
    -- Deadzone check
    if Settings.UseDeadzone then
        local screenPos, onScreen
        local success = pcall(function()
            screenPos, onScreen = cam:WorldToViewportPoint(targetPos)
        end)
        
        if success and onScreen and screenPos then
            local mousePos
            local mouseSuccess = pcall(function()
                mousePos = UserInputService:GetMouseLocation()
            end)
            
            if mouseSuccess and mousePos then
                local dist = (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude
                local deadzone = Settings.DeadzoneRadius or 2
                if dist < deadzone then return true end
            end
        end
    end
    
    -- Choose method
    if method == "Mouse" then
        return self:Method_MouseSim(targetPos, smoothFactor)
    else
        -- Default: Camera method
        return self:Method_Camera(targetPos, smoothFactor)
    end
end

-- ============================================================================
-- DEACTIVATION
-- ============================================================================
function AimbotLegit:Deactivate()
    self.Active = false
    self._active = false
    Lock:Clear()
    
    if self._holdUntil and tick() >= self._holdUntil then
        self._holdUntil = nil
    end
end

-- ============================================================================
-- MAIN UPDATE
-- ============================================================================
function AimbotLegit:Update(mouseHold)
    if not self._init then 
        DebugPrint("Not initialized!")
        return 
    end
    
    -- Debug periódico
    if self._debugMode then
        self:PrintDebugInfo()
    end
    
    -- Cleanup prediction history periodically
    self:CleanupPredHistory()
    
    local holdActive = self._holdUntil and tick() < self._holdUntil
    
    -- Determine if should be active
    local shouldBeActive = false
    
    if holdActive then
        shouldBeActive = true
    elseif Settings.AimbotActive then
        if Settings.AimbotToggleOnly then
            shouldBeActive = true
        else
            shouldBeActive = mouseHold
        end
    end
    
    if not shouldBeActive then
        if self.Active then
            self:Deactivate()
        end
        return
    end
    
    self.Active = true
    
    -- Find best target
    local bestTarget, bestScore = self:FindBest()
    
    if bestTarget then
        Lock:TryAcquire(bestTarget, bestScore)
    end
    
    local target = Lock:Get()
    
    if not target then return end
    
    local data = GetPlayerData(target)
    if not data or not data.isValid then
        Lock:Clear()
        return
    end
    
    local aimPart = self:GetPart(target, Settings.AimPart)
    
    if not aimPart or not aimPart.Parent then
        Lock:Clear()
        return
    end
    
    local aimPos = self:Predict(target, aimPart) or aimPart.Position
    
    if IsValidPosition(aimPos) then
        local smoothing = self:CalculateAdaptiveSmoothing(data)
        self:ApplyAim(aimPos, smoothing)
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
        self._active = false
    end
end

function AimbotLegit:GetCurrentTarget()
    return Lock:Get()
end

function AimbotLegit:ForceReset()
    self.Active = false
    self._active = false
    self._holdUntil = nil
    self._consecutiveErrors = 0
    self._mouseAccumX = 0
    self._mouseAccumY = 0
    Lock:Clear()
    self._predHistory = {}
    self._lastPredUpdate = {}
    self._failCount = {}
    self._validPos = nil
    DebugPrint("ForceReset completed")
end

function AimbotLegit:HoldAndStop(seconds)
    seconds = seconds or 0.2
    self._holdUntil = tick() + seconds
end

function AimbotLegit:GetDebugInfo()
    return {
        init = self._init,
        active = self.Active,
        currentTarget = Lock.Current and Lock.Current.Name or nil,
        consecutiveErrors = self._consecutiveErrors,
        aimMethod = Settings and Settings.AimMethod or "Camera",
    }
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================
function AimbotLegit:Initialize(deps)
    if self._init then 
        print("[AimbotLegit] Already initialized")
        return self 
    end
    
    print("[AimbotLegit] Initializing v5.0 (No MouseMoveRel)...")
    
    if not deps then
        warn("[AimbotLegit] No dependencies provided!")
        return nil
    end
    
    -- Store dependencies
    Utils = deps.Utils
    Settings = deps.Settings
    LocalPlayer = deps.LocalPlayer or Players.LocalPlayer
    
    if deps.Camera then
        Camera = deps.Camera
    else
        GetCamera()
    end
    
    if not Settings then
        warn("[AimbotLegit] Settings not provided!")
        return nil
    end
    
    -- Ensure defaults
    if Settings.AimbotToggleOnly == nil then
        Settings.AimbotToggleOnly = false
    end
    
    if Settings.AimMethod == nil then
        Settings.AimMethod = "Camera"
    end
    
    -- Remove MouseMoveRel option from AimMethod if set
    if Settings.AimMethod == "MouseMoveRel" then
        Settings.AimMethod = "Camera"
        print("[AimbotLegit] MouseMoveRel não suportado, usando Camera")
    end
    
    self._init = true
    self._consecutiveErrors = 0
    
    print("[AimbotLegit] ✓ Initialized successfully")
    print("[AimbotLegit] AimMethod:", Settings.AimMethod)
    print("[AimbotLegit] Utils:", Utils and "Loaded" or "Using fallbacks")
    print("[AimbotLegit] Camera:", Camera and "OK" or "nil")
    print("[AimbotLegit] AimbotToggleOnly:", Settings.AimbotToggleOnly and "ON" or "OFF")
    
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