-- ============================================================================
-- FORGEHUB - AIMBOT MODULE v3.0 (RAGE EDITION)
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
-- RAGE SETTINGS (Adiciona ao Settings global)
-- ============================================================================
Settings.RageMode = Settings.RageMode or false
Settings.UltraRageMode = Settings.UltraRageMode or false
Settings.SilentAim = Settings.SilentAim or false
Settings.AutoFire = Settings.AutoFire or false
Settings.AutoSwitch = Settings.AutoSwitch or false
Settings.TargetSwitchDelay = Settings.TargetSwitchDelay or 0.1
Settings.MultiPartAim = Settings.MultiPartAim or false
Settings.AimParts = Settings.AimParts or {"Head", "UpperTorso", "HumanoidRootPart"}
Settings.IgnoreWalls = Settings.IgnoreWalls or false
Settings.AntiAimDetection = Settings.AntiAimDetection or false
Settings.ShakeReduction = Settings.ShakeReduction or 0

-- Camera sempre atualizada
local function GetCamera()
    return workspace.CurrentCamera
end

-- ============================================================================
-- SAFE CALL WRAPPER
-- ============================================================================
local function SafeCall(func, name)
    local success, err = pcall(func)
    if not success then
        warn("[Aimbot] Erro em " .. (name or "unknown") .. ": " .. tostring(err))
    end
    return success
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
-- VISIBILITY CACHE
-- ============================================================================
local VisibilityCache = {
    Data = {},
    Frame = 0,
    MaxAge = 2,
}

function VisibilityCache:NextFrame()
    self.Frame = self.Frame + 1
    if self.Frame % 5 == 0 then
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
        return data.visible, true
    end
    return nil, false
end

function VisibilityCache:Set(player, visible)
    self.Data[player] = {visible = visible, frame = self.Frame}
end

function VisibilityCache:Clear()
    self.Data = {}
    self.Frame = 0
end

-- ============================================================================
-- PLAYER DATA HELPER
-- ============================================================================
local function GetPlayerData(player)
    if not player then return nil end
    
    local SemanticEngine = Core.SemanticEngine
    if SemanticEngine and SemanticEngine.GetCachedPlayerData then
        local data = SemanticEngine:GetCachedPlayerData(player)
        if data and data.isValid then return data end
    end
    
    local character = player.Character
    if not character then return nil end
    
    local anchor = character:FindFirstChild("HumanoidRootPart")
                or character:FindFirstChild("Torso")
                or character:FindFirstChild("Head")
    
    if not anchor or not anchor:IsDescendantOf(workspace) then return nil end
    
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    return {
        isValid = true,
        model = character,
        anchor = anchor,
        humanoid = humanoid,
    }
end

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
-- GET AIM PART (RAGE VERSION - MULTIPLE PARTS)
-- ============================================================================
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

-- Multi-part aim: retorna a melhor parte visível
local function GetBestAimPart(player)
    local data = GetPlayerData(player)
    if not data or not data.model then return nil end
    
    if not Settings.MultiPartAim then
        return GetAimPart(player, Settings.AimPart)
    end
    
    local Camera = GetCamera()
    local camPos = Camera.CFrame.Position
    local mousePos = UserInputService:GetMouseLocation()
    
    local bestPart = nil
    local bestScore = math.huge
    
    local partsToCheck = Settings.AimParts or {"Head", "UpperTorso", "HumanoidRootPart"}
    
    for _, partName in ipairs(partsToCheck) do
        local part = GetAimPart(player, partName)
        if part then
            local screenPos, onScreen = Camera:WorldToViewportPoint(part.Position)
            if onScreen then
                local distToMouse = (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude
                
                -- Prioriza cabeça
                local priority = 1
                if partName == "Head" then priority = 0.7 end
                
                local score = distToMouse * priority
                
                if score < bestScore then
                    -- Verifica visibilidade se não estiver em rage mode
                    local visible = true
                    if not Settings.IgnoreWalls then
                        UpdateRayParams()
                        local direction = part.Position - camPos
                        local ray = Workspace:Raycast(camPos, direction, RayParams)
                        if ray and ray.Instance and not ray.Instance:IsDescendantOf(data.model) then
                            visible = false
                        end
                    end
                    
                    if visible then
                        bestScore = score
                        bestPart = part
                    end
                end
            end
        end
    end
    
    return bestPart or GetAimPart(player, Settings.AimPart)
end

-- ============================================================================
-- RAGE PREDICTION SYSTEM
-- ============================================================================
local PredictionHistory = {}
local MAX_HISTORY = 8

local function UpdatePredictionHistory(player, position)
    if not PredictionHistory[player] then
        PredictionHistory[player] = {}
    end
    
    local history = PredictionHistory[player]
    table.insert(history, {position = position, time = tick()})
    
    while #history > MAX_HISTORY do
        table.remove(history, 1)
    end
end

local function CalculateVelocity(player, anchor)
    if anchor.AssemblyLinearVelocity then
        local vel = anchor.AssemblyLinearVelocity
        if vel.Magnitude > 0.1 then return vel end
    end
    
    if anchor.Velocity then
        local vel = anchor.Velocity
        if vel.Magnitude > 0.1 then return vel end
    end
    
    local history = PredictionHistory[player]
    if history and #history >= 2 then
        local newest = history[#history]
        local oldest = history[1]
        local deltaTime = newest.time - oldest.time
        
        if deltaTime > 0.03 then
            local deltaPos = newest.position - oldest.position
            return deltaPos / deltaTime
        end
    end
    
    return Vector3.zero
end

local function PredictPosition(player, targetPart)
    if not Settings.UsePrediction or not targetPart then
        return targetPart.Position
    end
    
    local data = GetPlayerData(player)
    if not data or not data.anchor then
        return targetPart.Position
    end
    
    local velocity = CalculateVelocity(player, data.anchor)
    
    -- Em Rage mode, predição mais agressiva
    local yMultiplier = 0.3
    if Settings.RageMode or Settings.UltraRageMode then
        yMultiplier = 0.5
    end
    
    if velocity.Y > 0 then
        velocity = Vector3.new(velocity.X, velocity.Y * yMultiplier, velocity.Z)
    end
    
    local Camera = GetCamera()
    local distance = (targetPart.Position - Camera.CFrame.Position).Magnitude
    
    -- Tempo de resposta mais rápido em Rage
    local timeDiv = Settings.UltraRageMode and 600 or (Settings.RageMode and 700 or 800)
    local timeToTarget = math.clamp(distance / timeDiv, 0.01, 0.25)
    
    -- Multiplicador de predição mais alto em Rage
    local multiplier = Settings.PredictionMultiplier or 0.135
    if Settings.UltraRageMode then
        multiplier = multiplier * 1.5
    elseif Settings.RageMode then
        multiplier = multiplier * 1.2
    end
    
    local predictedPos = targetPart.Position + (velocity * multiplier * timeToTarget)
    
    UpdatePredictionHistory(player, data.anchor.Position)
    
    return predictedPos
end

-- ============================================================================
-- VISIBILITY CHECK (RAGE CAN IGNORE)
-- ============================================================================
local function IsVisible(player, targetPart)
    -- Rage modes podem ignorar paredes
    if Settings.IgnoreWalls then
        return true
    end
    
    if not Settings.VisibleCheck then
        return true
    end
    
    local cached, hit = VisibilityCache:Get(player)
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
    
    VisibilityCache:Set(player, visible)
    return visible
end

-- ============================================================================
-- RAGE TARGET LOCK SYSTEM
-- ============================================================================
local TargetLock = {
    CurrentTarget = nil,
    LockTime = 0,
    LastScore = math.huge,
    LastKill = 0,
    KillCount = 0,
    
    -- Rage settings
    MinLockDuration = 0.1,
    MaxLockDuration = 1.5,
    ImprovementThreshold = 0.6,
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
    
    -- Em Ultra Rage, distância máxima é muito maior
    local maxDist = Settings.MaxDistance or 800
    if Settings.UltraRageMode then
        maxDist = maxDist * 2
    elseif Settings.RageMode then
        maxDist = maxDist * 1.5
    end
    
    if distance > maxDist then return false end
    
    local screenPos, onScreen = Camera:WorldToViewportPoint(data.anchor.Position)
    if not onScreen then return false end
    
    return true
end

function TargetLock:TryLock(candidate, score)
    if not candidate then return end
    
    local now = tick()
    
    -- Auto Switch: troca mais rapidamente
    if Settings.AutoSwitch then
        self.MaxLockDuration = Settings.TargetSwitchDelay or 0.3
        self.ImprovementThreshold = 0.5
    elseif Settings.UltraRageMode then
        self.MaxLockDuration = 0.5
        self.ImprovementThreshold = 0.4
    elseif Settings.RageMode then
        self.MaxLockDuration = 0.8
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
-- RAGE AIM CONTROLLER
-- ============================================================================
local AimController = {
    IsAiming = false,
    OriginalCFrame = nil,
    HasMouseMoveRel = false,
    
    -- Shake reduction
    LastAimPos = nil,
    AimHistory = {},
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
    
    pcall(function()
        local Camera = GetCamera()
        if LocalPlayer.Character then
            local hum = LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
            if hum then Camera.CameraSubject = hum end
        end
    end)
end

function AimController:CalculateSmoothFactor(smoothing)
    -- ULTRA RAGE: Sem suavização
    if Settings.UltraRageMode then
        return 1.0
    end
    
    -- RAGE MODE: Suavização mínima
    if Settings.RageMode then
        if not smoothing or smoothing <= 2 then
            return 1.0
        else
            return math.clamp(0.95 - (smoothing * 0.03), 0.5, 0.95)
        end
    end
    
    -- NORMAL: Suavização completa
    if not smoothing or smoothing <= 0 then
        return 1.0
    end
    
    if smoothing <= 1 then
        return 0.9
    elseif smoothing <= 3 then
        return 0.6
    elseif smoothing <= 5 then
        return 0.4
    elseif smoothing <= 8 then
        return 0.25
    elseif smoothing <= 12 then
        return 0.15
    else
        return math.clamp(0.8 / smoothing, 0.02, 0.1)
    end
end

-- Shake reduction: suaviza micro-movimentos
function AimController:ApplyShakeReduction(targetPos)
    if Settings.ShakeReduction <= 0 then
        return targetPos
    end
    
    table.insert(self.AimHistory, targetPos)
    while #self.AimHistory > Settings.ShakeReduction do
        table.remove(self.AimHistory, 1)
    end
    
    if #self.AimHistory < 2 then
        return targetPos
    end
    
    local avgPos = Vector3.zero
    for _, pos in ipairs(self.AimHistory) do
        avgPos = avgPos + pos
    end
    return avgPos / #self.AimHistory
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
    if Settings.UseDeadzone and not Settings.RageMode and not Settings.UltraRageMode then
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
        
        if direction.Magnitude < 0.01 then return end
        
        local targetCFrame = CFrame.lookAt(camPos, targetPosition)
        
        -- Em Ultra Rage, snap instantâneo
        if Settings.UltraRageMode or smoothFactor >= 0.98 then
            Camera.CFrame = targetCFrame
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
        
        if not onScreen then return end
        
        local viewport = Camera.ViewportSize
        local centerX = viewport.X / 2
        local centerY = viewport.Y / 2
        
        local deltaX = screenPos.X - centerX
        local deltaY = screenPos.Y - centerY
        
        -- Em Ultra Rage, movimento instantâneo
        local moveX, moveY
        if Settings.UltraRageMode then
            moveX = deltaX
            moveY = deltaY
        else
            moveX = deltaX * smoothFactor
            moveY = deltaY * smoothFactor
        end
        
        if math.abs(moveX) < 0.2 and math.abs(moveY) < 0.2 then
            return
        end
        
        mousemoverel(moveX, moveY)
    end)
    
    return success
end

-- ============================================================================
-- SILENT AIM (Se suportado pelo executor)
-- ============================================================================
local SilentAim = {
    Enabled = false,
    OriginalMouse = nil,
    HookedNamecall = false,
}

function SilentAim:GetTargetPosition()
    local target = TargetLock:GetTarget()
    if not target then return nil end
    
    local aimPart = GetBestAimPart(target)
    if not aimPart then return nil end
    
    return PredictPosition(target, aimPart)
end

function SilentAim:Initialize()
    if self.HookedNamecall then return end
    
    -- Tenta hook via metatable (pode não funcionar em todos os executores)
    SafeCall(function()
        if type(getrawmetatable) ~= "function" then return end
        if type(hookfunction) ~= "function" and type(hookmetamethod) ~= "function" then return end
        
        local mt = getrawmetatable(game)
        if not mt then return end
        
        local oldNamecall = mt.__namecall
        
        local hookFunc = function(self, ...)
            local method = getnamecallmethod()
            
            if SilentAim.Enabled and Settings.SilentAim then
                -- Hook para métodos de raycast/mouse
                if method == "FindPartOnRay" or method == "FindPartOnRayWithIgnoreList" then
                    local targetPos = SilentAim:GetTargetPosition()
                    if targetPos then
                        -- Modifica o ray para apontar para o alvo
                        local args = {...}
                        local origin = typeof(args[1]) == "Ray" and args[1].Origin or args[1]
                        if origin then
                            local newRay = Ray.new(origin, (targetPos - origin).Unit * 1000)
                            args[1] = newRay
                            return oldNamecall(self, unpack(args))
                        end
                    end
                end
            end
            
            return oldNamecall(self, ...)
        end
        
        if type(hookmetamethod) == "function" then
            hookmetamethod(game, "__namecall", hookFunc)
        end
        
        self.HookedNamecall = true
    end, "SilentAim:Initialize")
end

function SilentAim:Enable()
    self.Enabled = true
    self:Initialize()
end

function SilentAim:Disable()
    self.Enabled = false
end

-- ============================================================================
-- RAGE TARGET FINDER
-- ============================================================================
local function FindBestTarget()
    local Camera = GetCamera()
    local camPos = Camera.CFrame.Position
    local camLook = Camera.CFrame.LookVector
    local mousePos = UserInputService:GetMouseLocation()
    
    local candidates = {}
    local allPlayers = Players:GetPlayers()
    
    -- FOV ajustado para Rage
    local currentFOV = Settings.FOV or 180
    if Settings.UltraRageMode then
        currentFOV = 9999 -- FOV infinito
    elseif Settings.RageMode then
        currentFOV = currentFOV * 2
    end
    
    -- Distância ajustada para Rage
    local maxDist = Settings.MaxDistance or 800
    if Settings.UltraRageMode then
        maxDist = maxDist * 3
    elseif Settings.RageMode then
        maxDist = maxDist * 1.5
    end
    
    for _, player in ipairs(allPlayers) do
        if player == LocalPlayer then continue end
        
        local data = nil
        
        local SemanticEngine = Core.SemanticEngine
        if SemanticEngine and SemanticEngine.GetCachedPlayerData then
            data = SemanticEngine:GetCachedPlayerData(player)
        end
        
        if not data or not data.isValid then
            local character = player.Character
            if character then
                local anchor = character:FindFirstChild("HumanoidRootPart")
                            or character:FindFirstChild("Torso")
                            or character:FindFirstChild("Head")
                
                if anchor and anchor:IsDescendantOf(workspace) then
                    local humanoid = character:FindFirstChildOfClass("Humanoid")
                    data = {
                        isValid = true,
                        model = character,
                        anchor = anchor,
                        humanoid = humanoid,
                    }
                end
            end
        end
        
        if not data or not data.isValid or not data.anchor then continue end
        if not data.anchor:IsDescendantOf(workspace) then continue end
        if data.humanoid and data.humanoid.Health <= 0 then continue end
        
        if Settings.IgnoreTeamAimbot then
            local sameTeam = false
            if SemanticEngine and SemanticEngine.AreSameTeam then
                sameTeam = SemanticEngine:AreSameTeam(LocalPlayer, player)
            else
                sameTeam = LocalPlayer.Team and player.Team and LocalPlayer.Team == player.Team
            end
            if sameTeam then continue end
        end
        
        local distance = (data.anchor.Position - camPos).Magnitude
        if distance > maxDist then continue end
        
        local screenPos, onScreen = Camera:WorldToViewportPoint(data.anchor.Position)
        
        -- Em Ultra Rage, ignora se está na tela
        if not Settings.UltraRageMode and not onScreen then continue end
        
        local distToMouse = onScreen and (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude or 9999
        
        if Settings.UseAimbotFOV and distToMouse > currentFOV then continue end
        
        -- Verifica direção (menos restritivo em Rage)
        local dirToTarget = (data.anchor.Position - camPos).Unit
        local dot = camLook:Dot(dirToTarget)
        local minDot = Settings.UltraRageMode and -0.5 or (Settings.RageMode and 0 or 0.1)
        if dot < minDot then continue end
        
        -- Score: em Rage, prioriza distância 3D; em Normal, prioriza mouse
        local score
        if Settings.UltraRageMode then
            score = distance * 0.5 + distToMouse * 0.1
        elseif Settings.RageMode then
            score = distance * 0.3 + distToMouse * 0.5
        else
            score = distToMouse * 1.0 + distance * 0.1
        end
        
        -- Prioriza alvos com menos vida em Rage
        if Settings.RageMode or Settings.UltraRageMode then
            if data.humanoid then
                local healthPercent = data.humanoid.Health / data.humanoid.MaxHealth
                score = score * (0.5 + healthPercent * 0.5)
            end
        end
        
        table.insert(candidates, {
            player = player,
            data = data,
            score = score,
            distance = distance,
            distToMouse = distToMouse,
        })
    end
    
    table.sort(candidates, function(a, b) return a.score < b.score end)
    
    -- Verifica visibilidade (menos checks em Rage)
    local maxChecks = Settings.UltraRageMode and 1 or (Settings.RageMode and 3 or 5)
    local checked = 0
    
    for _, candidate in ipairs(candidates) do
        if checked >= maxChecks then break end
        
        local aimPart = GetBestAimPart(candidate.player)
        if not aimPart then continue end
        
        checked = checked + 1
        
        -- Em Rage modes, pode ignorar visibilidade
        if Settings.IgnoreWalls or not Settings.VisibleCheck then
            return candidate.player, candidate.score
        end
        
        if IsVisible(candidate.player, aimPart) then
            return candidate.player, candidate.score
        end
    end
    
    -- Fallback
    if (Settings.IgnoreWalls or not Settings.VisibleCheck) and #candidates > 0 then
        return candidates[1].player, candidates[1].score
    end
    
    return nil, math.huge
end

-- ============================================================================
-- AUTO FIRE (Clique automático)
-- ============================================================================
local AutoFire = {
    LastFire = 0,
    FireRate = 0.1,
}

function AutoFire:TryFire()
    if not Settings.AutoFire then return end
    
    local now = tick()
    if now - self.LastFire < self.FireRate then return end
    
    local target = TargetLock:GetTarget()
    if not target then return end
    
    -- Simula clique
    SafeCall(function()
        if mouse1click then
            mouse1click()
            self.LastFire = now
        elseif type(Input) == "table" and Input.MouseButton1Click then
            Input.MouseButton1Click()
            self.LastFire = now
        end
    end, "AutoFire")
end

-- ============================================================================
-- AIMBOT STATE MACHINE
-- ============================================================================
local AimbotState = {
    Active = false,
    LastUpdate = 0,
    ErrorCount = 0,
    MaxErrors = 10,
}

function AimbotState:Reset()
    self.Active = false
    self.ErrorCount = 0
    TargetLock:Reset()
    AimController:StopAiming()
    VisibilityCache:Clear()
    PredictionHistory = {}
    SilentAim:Disable()
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
}

function Aimbot:Update()
    VisibilityCache:NextFrame()
    
    local shouldBeActive = Settings.AimbotActive and State.MouseHold
    
    if not shouldBeActive then
        if AimbotState.Active then
            AimbotState.Active = false
            TargetLock:Reset()
            AimController:StopAiming()
            SilentAim:Disable()
        end
        return
    end
    
    AimbotState.Active = true
    
    -- Silent Aim
    if Settings.SilentAim then
        SilentAim:Enable()
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
            
            local data = GetPlayerData(target)
            local baseSm = Settings.SmoothingFactor or 5
            local smoothing = baseSm
            
            -- Rage modes: suavização mínima ou zero
            if Settings.UltraRageMode then
                smoothing = 0
            elseif Settings.RageMode then
                smoothing = math.min(baseSm, 2)
            elseif Settings.UseAdaptiveSmoothing and data and data.anchor then
                local Camera = GetCamera()
                local dist = (data.anchor.Position - Camera.CFrame.Position).Magnitude
                
                if dist < 50 then
                    smoothing = baseSm * 1.3
                elseif dist > 300 then
                    smoothing = baseSm * 0.7
                end
            end
            
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
    
    -- Em Rage mode, usa RenderStepped para resposta mais rápida
    local event = (Settings.RageMode or Settings.UltraRageMode) 
                  and RunService.RenderStepped 
                  or RunService.Heartbeat
    
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
    end
    
    -- Reinicia loop com novo evento
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
    end
    
    -- Reinicia loop com novo evento
    if self.Initialized then
        self:StopLoop()
        self:StartLoop()
    end
    
    if Notify then
        Notify("Aimbot", "ULTRA RAGE " .. (enabled and "ATIVADO ⚡🔥⚡" or "DESATIVADO"))
    end
end

function Aimbot:Initialize()
    if self.Initialized then return end
    
    AimController:DetectMethods()
    SilentAim:Initialize()
    self:StartLoop()
    
    -- Watchdog
    task.spawn(function()
        while true do
            task.wait(2)
            if self.Initialized and not self.Connection then
                warn("[Aimbot] Loop morreu, reiniciando...")
                self:StartLoop()
            end
        end
    end)
    
    self.Initialized = true
    
    print("[Aimbot] Inicializado - RAGE EDITION!")
    print("[Aimbot] MouseMoveRel: " .. (AimController.HasMouseMoveRel and "OK" or "N/A"))
    print("[Aimbot] SilentAim: " .. (SilentAim.HookedNamecall and "OK" or "N/A"))
end

function Aimbot:Debug()
    print("\n========== AIMBOT RAGE DEBUG ==========")
    print("Initialized: " .. tostring(self.Initialized))
    print("Connection: " .. tostring(self.Connection ~= nil))
    
    print("\n--- RAGE STATUS ---")
    print("  RageMode: " .. tostring(Settings.RageMode))
    print("  UltraRageMode: " .. tostring(Settings.UltraRageMode))
    print("  SilentAim: " .. tostring(Settings.SilentAim))
    print("  AutoFire: " .. tostring(Settings.AutoFire))
    print("  AutoSwitch: " .. tostring(Settings.AutoSwitch))
    print("  IgnoreWalls: " .. tostring(Settings.IgnoreWalls))
    print("  MultiPartAim: " .. tostring(Settings.MultiPartAim))
    
    print("\n--- Target ---")
    local target = TargetLock:GetTarget()
    print("  Current: " .. (target and target.Name or "None"))
    print("  Kills: " .. TargetLock.KillCount)
    
    print("\n--- Test ---")
    local t, s = FindBestTarget()
    print("  Best: " .. (t and (t.Name .. " score:" .. string.format("%.1f", s)) or "None"))
    
    print("=========================================\n")
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
    AutoFire = AutoFire,
    
    -- Funções públicas
    Update = function() Aimbot:Update() end,
    Initialize = function() Aimbot:Initialize() end,
    Toggle = function(enabled) Aimbot:Toggle(enabled) end,
    SetRageMode = function(enabled) Aimbot:SetRageMode(enabled) end,
    SetUltraRageMode = function(enabled) Aimbot:SetUltraRageMode(enabled) end,
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