-- ============================================================================
-- FORGEHUB - AIMBOT MODULE
-- ============================================================================

local Core = _G.ForgeHubCore
if not Core then
    error("ForgeHubCore não encontrado! Carregue main.lua primeiro.")
end

local SafeCall = Core.SafeCall
local Settings = Core.Settings
local State = Core.State
local SemanticEngine = Core.SemanticEngine
local RaycastCache = Core.RaycastCache
local Profiler = Core.Profiler
local PerformanceManager = Core.PerformanceManager
local Camera = Core.Camera
local Workspace = Core.Workspace
local UserInputService = Core.UserInputService
local LocalPlayer = Core.LocalPlayer

-- ============================================================================
-- CAMERA BYPASS
-- ============================================================================
local CameraBypass = {
    OriginalCFrame = nil,
    IsAiming = false,
    Hooked = false,
    
    LockedTarget = nil,
    LockStartTime = 0,
    MinLockTime = 0.15,
    _lastLockedDist = math.huge,
    _lastLockTime = 0,
}

function CameraBypass:Initialize()
    if self.Hooked then return end
    
    pcall(function()
        if type(getrawmetatable) ~= "function" then return end
        if type(setreadonly) ~= "function" then return end
        
        local mt = getrawmetatable(game)
        setreadonly(mt, false)
        
        local oldIndex = mt.__index
        local oldNewIndex = mt.__newindex
        
        local bypass = self
        
        local indexFunc = function(t, k)
            if t == workspace.CurrentCamera and k == "CFrame" and bypass.IsAiming then
                return bypass.OriginalCFrame or oldIndex(t, k)
            end
            return oldIndex(t, k)
        end
        
        local newindexFunc = function(t, k, v)
            if t == workspace.CurrentCamera and k == "CFrame" and not bypass.IsAiming then
                bypass.OriginalCFrame = v
            end
            return oldNewIndex(t, k, v)
        end
        
        if type(newcclosure) == "function" then
            mt.__index = newcclosure(indexFunc)
            mt.__newindex = newcclosure(newindexFunc)
        else
            mt.__index = indexFunc
            mt.__newindex = newindexFunc
        end
        
        setreadonly(mt, true)
        self.Hooked = true
    end)
end

function CameraBypass:SetAimingState(state)
    Camera = workspace.CurrentCamera
    
    if state and not self.IsAiming then
        self.IsAiming = true
        pcall(function()
            self.OriginalCFrame = Camera.CFrame
            Camera.CameraType = Enum.CameraType.Custom
        end)
    elseif not state and self.IsAiming then
        self.IsAiming = false
        self.LockedTarget = nil
        
        pcall(function()
            self.OriginalCFrame = nil
            if LocalPlayer.Character then
                local hum = LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
                if hum then Camera.CameraSubject = hum end
            end
        end)
    end
end

function CameraBypass:TryLock(candidate, distToMouse)
    if not candidate then return end
    local now = tick()
    
    if not self.LockedTarget then
        self.LockedTarget = candidate
        self._lastLockTime = now
        self._lastLockedDist = distToMouse
        self.LockStartTime = now
        return
    end
    
    if self.LockedTarget == candidate then
        self._lastLockTime = now
        self._lastLockedDist = distToMouse
        return
    end
    
    if now - self.LockStartTime > Settings.MaxLockTime then
        self.LockedTarget = candidate
        self._lastLockTime = now
        self._lastLockedDist = distToMouse
        self.LockStartTime = now
        return
    end
    
    local threshold = Settings.LockImprovementThreshold
    if distToMouse / self._lastLockedDist < threshold then
        self.LockedTarget = candidate
        self._lastLockTime = now
        self._lastLockedDist = distToMouse
        self.LockStartTime = now
    end
end

function CameraBypass:GetLockedTarget()
    return self.LockedTarget
end

function CameraBypass:ClearLock()
    self.LockedTarget = nil
    self.LockStartTime = 0
    self._lastLockedDist = math.huge
    self._lastLockTime = 0
end

-- ============================================================================
-- AIM METHODS
-- ============================================================================
local AimMethods = {
    Available = {
        Camera = true,
        CameraForce = true,
        MouseMoveRel = false,
    },
    
    CurrentMethod = "Camera",
}

function AimMethods:DetectMethods()
    self.Available.MouseMoveRel = type(mousemoverel) == "function"
    self.Available.Camera = true
    self.Available.CameraForce = true
end

function AimMethods:CalculateSmoothFactor(smoothing)
    if not smoothing or smoothing <= 0 then
        return 1
    elseif smoothing < 1 then
        return 0.95
    elseif smoothing <= 2 then
        return 0.7
    elseif smoothing <= 5 then
        return 0.4
    elseif smoothing <= 10 then
        return 0.2
    else
        return math.clamp(1 / smoothing, 0.02, 1)
    end
end

function AimMethods:ApplyAim(targetPosition, smoothing)
    if not targetPosition then return false end
    
    Camera = workspace.CurrentCamera
    if not Camera then return false end
    
    local method = Settings.AimMethod or "Camera"
    
    local smoothFactor = self:CalculateSmoothFactor(smoothing)
    
    local success = false
    
    if method == "Camera" or method == "CameraForce" then
        success = self:Method_Camera(targetPosition, smoothFactor)
    elseif method == "MouseMoveRel" or method == "Mouse" then
        if self.Available.MouseMoveRel then
            success = self:Method_MouseMoveRel(targetPosition, smoothFactor)
        else
            success = self:Method_Camera(targetPosition, smoothFactor)
        end
    end
    
    return success
end

function AimMethods:Method_Camera(targetPosition, smoothFactor)
    local success = pcall(function()
        CameraBypass:SetAimingState(true)
        
        local camPos = Camera.CFrame.Position
        local direction = targetPosition - camPos
        
        if direction.Magnitude < 0.05 then return end
        
        local targetCFrame = CFrame.lookAt(camPos, targetPosition)
        
        if smoothFactor >= 0.99 then
            Camera.CFrame = targetCFrame
        else
            local smoothedRotation = Camera.CFrame.Rotation:Lerp(targetCFrame.Rotation, smoothFactor)
            Camera.CFrame = CFrame.new(camPos) * smoothedRotation
        end
    end)
    
    return success
end

function AimMethods:Method_MouseMoveRel(targetPosition, smoothFactor)
    if type(mousemoverel) ~= "function" then
        return self:Method_Camera(targetPosition, smoothFactor)
    end
    
    local success = pcall(function()
        local screenPos, onScreen = Camera:WorldToViewportPoint(targetPosition)
        
        if not onScreen then return end
        
        local viewport = Camera.ViewportSize
        local centerX = viewport.X / 2
        local centerY = viewport.Y / 2
        
        local deltaX = screenPos.X - centerX
        local deltaY = screenPos.Y - centerY
        
        local distance = math.sqrt(deltaX * deltaX + deltaY * deltaY)
        
        local deadzoneRadius = Settings.DeadzoneRadius or 2
        if distance < deadzoneRadius then return end
        
        local moveX, moveY
        
        if smoothFactor >= 0.99 then
            moveX = deltaX
            moveY = deltaY
        else
            moveX = deltaX * smoothFactor
            moveY = deltaY * smoothFactor
        end
        
        if math.abs(moveX) < 0.3 and math.abs(moveY) < 0.3 then return end
        
        mousemoverel(moveX, moveY)
    end)
    
    return success
end

function AimMethods:Reset()
    CameraBypass:SetAimingState(false)
    CameraBypass:ClearLock()
end

-- ============================================================================
-- AIM UTILITIES
-- ============================================================================
local function getAimPartAdaptive(player, selection)
    local data = SemanticEngine:GetCachedPlayerData(player)
    if not data.isValid or not data.model then return nil end
    
    local model = data.model
    
    if type(selection) == "table" then selection = selection[1] end
    selection = selection or "Head"
    
    if selection == "Head" then
        return model:FindFirstChild("Head") or data.anchor
    elseif selection == "Torso" then
        return model:FindFirstChild("UpperTorso") or 
               model:FindFirstChild("Torso") or 
               data.anchor
    elseif selection == "Root" or selection == "HumanoidRootPart" then
        return data.anchor
    end
    
    return data.anchor
end

local function ComputeAdaptiveSmoothing(dist, base)
    if not Settings.UseAdaptiveSmoothing then
        return base
    end
    
    if dist < 50 then
        return base * 1.4
    elseif dist > 300 then
        return base * 0.75
    end
    return base
end

local function calculatePrediction(targetPart, player)
    if not Settings.UsePrediction or not targetPart then
        return targetPart.Position
    end
    
    local data = SemanticEngine:GetCachedPlayerData(player)
    local anchor = data.anchor or targetPart
    
    local velocity = anchor.AssemblyLinearVelocity or anchor.Velocity or Vector3.zero
    
    if velocity.Y > 0 then
        velocity = Vector3.new(velocity.X, velocity.Y * 0.4, velocity.Z)
    end
    
    local distance = (targetPart.Position - Camera.CFrame.Position).Magnitude
    local timeToTarget = distance / 1000
    
    local predictedPos = targetPart.Position + (velocity * Settings.PredictionMultiplier * timeToTarget)
    return predictedPos
end

-- ============================================================================
-- TARGET SELECTION
-- ============================================================================
local function GetClosestPlayerAdaptive()
    local target = nil
    local bestScore = math.huge
    local mousePos = UserInputService:GetMouseLocation()
    local camPos = Camera.CFrame.Position

    local function CalculateTargetScore(player, distToMouse, dist3D)
        return distToMouse * 0.6 + dist3D * 0.3
    end
    
    local candidates = {}

    for _, p in ipairs(Core.CachedPlayers) do
        if p ~= LocalPlayer then
            local isValid = true
            local data = SemanticEngine:GetCachedPlayerData(p)
            
            if not data or not data.isValid or not data.anchor then
                isValid = false
            end
            
            if isValid and data.humanoid and data.humanoid.Health <= 0 then
                isValid = false
            end
            
            if isValid and Settings.IgnoreTeamAimbot then
                if SemanticEngine:AreSameTeam(LocalPlayer, p) then
                    isValid = false
                end
            end
            
            if isValid then
                local distance = (data.anchor.Position - camPos).Magnitude
                if distance > Settings.MaxDistance then
                    isValid = false
                end
                
                if isValid then
                    local screenPos, onScreen = Camera:WorldToViewportPoint(data.anchor.Position)
                    if not onScreen then
                        isValid = false
                    else
                        local distToMouse = (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude
                        if Settings.UseAimbotFOV and distToMouse > Settings.FOV then
                            isValid = false
                        else
                            local dirToAnchor = (data.anchor.Position - camPos)
                            if Camera.CFrame.LookVector:Dot(dirToAnchor.Unit or Vector3.new(0,0,0)) < 0.2 then
                                isValid = false
                            else
                                local score = CalculateTargetScore(p, distToMouse, distance)
                                table.insert(candidates, {
                                    player = p,
                                    score = score,
                                    data = data,
                                    distance = distance
                                })
                            end
                        end
                    end
                end
            end
        end
    end
    
    table.sort(candidates, function(a, b) return a.score < b.score end)
    
    local raycastLimit = PerformanceManager.raycastBudget
    local checked = 0
    
    for _, candidate in ipairs(candidates) do
        if not Settings.VisibleCheck then
            return candidate.player, candidate.score
        end
        
        if not PerformanceManager:CanRaycast() then
            if target then
                return target, bestScore
            end
            break
        end
        
        checked = checked + 1
        
        local cacheKey = candidate.player
        local cached, hit = RaycastCache:Get(cacheKey)
        
        if hit then
            if cached then
                return candidate.player, candidate.score
            end
        else
            Profiler:RecordRaycast()
            
            local aimPart = getAimPartAdaptive(candidate.player, Settings.AimPart)
            if aimPart then
                local direction = aimPart.Position - camPos
                local ray = Workspace:Raycast(camPos, direction, Core._sharedRayParams)
                
                local visible = true
                if ray and ray.Instance and not ray.Instance:IsDescendantOf(candidate.data.model) then
                    visible = false
                end
                
                RaycastCache:Set(cacheKey, visible)
                
                if visible then
                    return candidate.player, candidate.score
                end
            end
        end
        
        if checked >= raycastLimit then
            break
        end
    end

    return target, bestScore
end

-- ============================================================================
-- AIMBOT MAIN
-- ============================================================================
local Aimbot = {}
local AimbotConnection = nil

function Aimbot:StartLoop()
    if AimbotConnection then return end
    
    AimbotConnection = Core.RunService.Heartbeat:Connect(function()
        SafeCall(function()
            self:Update()
        end, "AimbotLoop")
    end)
end

function Aimbot:Update()
    RaycastCache:NextFrame()
    PerformanceManager:ResetRaycastCounter()
    
    if not Settings.AimbotActive or not State.MouseHold then
        CameraBypass:SetAimingState(false)
        return
    end
    
    local lockedTarget = CameraBypass:GetLockedTarget()
    
    if lockedTarget then
        local data = SemanticEngine:GetCachedPlayerData(lockedTarget)
        local isValid = data and data.isValid and data.anchor
        
        if not isValid then
            CameraBypass:ClearLock()
            lockedTarget = nil
        elseif data.humanoid and data.humanoid.Health <= 0 then
            CameraBypass:ClearLock()
            lockedTarget = nil
        else
            local distance = (data.anchor.Position - Camera.CFrame.Position).Magnitude
            if distance > Settings.MaxDistance then
                CameraBypass:ClearLock()
                lockedTarget = nil
            end
        end
    end
    
    local candidate, candScore = GetClosestPlayerAdaptive()
    
    if candidate then
        CameraBypass:TryLock(candidate, candScore)
        lockedTarget = CameraBypass:GetLockedTarget()
    end
    
    if lockedTarget then
        local part = getAimPartAdaptive(lockedTarget, Settings.AimPart)
        if part then
            local aimPos = calculatePrediction(part, lockedTarget)
            local distance = (part.Position - Camera.CFrame.Position).Magnitude
            
            local baseSm = Settings.SmoothingFactor
            local adaptiveSm = ComputeAdaptiveSmoothing(distance, baseSm)
            
            AimMethods:ApplyAim(aimPos, adaptiveSm)
        end
    else
        CameraBypass:SetAimingState(false)
    end
end

function Aimbot:Initialize()
    CameraBypass:Initialize()
    AimMethods:DetectMethods()
    self:StartLoop()
    
    -- Update camera reference periodically
    task.spawn(function()
        while wait(1) do
            Camera = workspace.CurrentCamera
        end
    end)
end

-- ============================================================================
-- EXPORT
-- ============================================================================
Core.Aimbot = {
    CameraBypass = CameraBypass,
    AimMethods = AimMethods,
    GetClosestPlayer = GetClosestPlayerAdaptive,
    Main = Aimbot,
}

return Aimbot