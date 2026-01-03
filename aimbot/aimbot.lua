-- ============================================================================
-- FORGEHUB - AIMBOT LEGIT MODULE v4.9 (FIXED)
-- Versão com todas as correções aplicadas
-- ============================================================================

local AimbotLegit = {
    _init = false,
    _active = false,
    Active = false,
    _hasMMR = false,
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
-- DEBUG FUNCTION (CORRIGIDO - ERA O BUG CRÍTICO)
-- ============================================================================
local function DebugPrint(...)
    if AimbotLegit._debugMode then
        print("[Aimbot Debug]", ...)
    end
end

-- ============================================================================
-- INTERNAL HELPERS (FALLBACKS)
-- ============================================================================

-- Atualiza referência da câmera
local function GetCamera()
    Camera = Workspace.CurrentCamera
    return Camera
end

-- Fallback: Obter dados do jogador internamente
local function InternalGetPlayerData(player)
    if not player then return nil end
    
    local character = player.Character
    if not character or not character.Parent then return nil end
    
    -- Encontrar HumanoidRootPart ou alternativas
    local anchor = character:FindFirstChild("HumanoidRootPart")
                or character:FindFirstChild("Torso")
                or character:FindFirstChild("UpperTorso")
                or character:FindFirstChild("Head")
                or character.PrimaryPart
    
    if not anchor or not anchor.Parent then return nil end
    
    -- Encontrar Humanoid
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    
    -- Verificar se está vivo
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

-- Wrapper: Tenta Utils primeiro, depois fallback
local function GetPlayerData(player)
    -- Tenta Utils se disponível
    if Utils and Utils.GetPlayerData then
        local success, data = pcall(function()
            return Utils.GetPlayerData(player)
        end)
        if success and data and data.isValid then 
            return data 
        end
    end
    
    -- Fallback interno
    return InternalGetPlayerData(player)
end

-- Fallback: Verificar se são do mesmo time
local function InternalAreSameTeam(player1, player2)
    if not player1 or not player2 then return false end
    
    -- Método 1: Team property
    if player1.Team and player2.Team then
        return player1.Team == player2.Team
    end
    
    -- Método 2: TeamColor
    if player1.TeamColor and player2.TeamColor then
        return player1.TeamColor == player2.TeamColor
    end
    
    -- Método 3: Neutral (sem time = não são do mesmo time)
    if player1.Neutral or player2.Neutral then
        return false
    end
    
    return false
end

-- Wrapper: Tenta Utils primeiro, depois fallback
local function AreSameTeam(player1, player2)
    if Utils and Utils.AreSameTeam then
        local success, result = pcall(function()
            return Utils.AreSameTeam(player1, player2)
        end)
        if success then return result end
    end
    
    return InternalAreSameTeam(player1, player2)
end

-- Fallback: Verificar posição válida (mais permissivo)
local function IsValidPosition(pos)
    if not pos then return false end
    if typeof(pos) ~= "Vector3" then return false end
    
    -- Verificar NaN
    if pos.X ~= pos.X or pos.Y ~= pos.Y or pos.Z ~= pos.Z then
        return false
    end
    
    -- Verificar infinito
    if math.abs(pos.X) > 1e6 or math.abs(pos.Y) > 1e6 or math.abs(pos.Z) > 1e6 then
        return false
    end
    
    return true
end

-- Distância ao quadrado
local function DistanceSquared(pos1, pos2)
    local delta = pos1 - pos2
    return delta.X * delta.X + delta.Y * delta.Y + delta.Z * delta.Z
end

-- ============================================================================
-- EXECUTOR FUNCTIONS (MELHORADO)
-- ============================================================================
local ExecutorFuncs = {
    mouseMove = nil,
    isAvailable = false
}

local function InitExecutorFuncs()
    -- Lista expandida de nomes possíveis
    local mmrCheck = {
        "mousemoverel", 
        "mouse_moverel", 
        "MouseMoveRel",
        "Input.MouseMove",
        "movemouserel",
    }
    
    -- Tentar getgenv primeiro (mais comum em exploits)
    if getgenv then
        for _, name in ipairs(mmrCheck) do
            local success, func = pcall(function()
                return getgenv()[name]
            end)
            
            if success and type(func) == "function" then
                ExecutorFuncs.mouseMove = func
                ExecutorFuncs.isAvailable = true
                DebugPrint("MouseMoveRel encontrado via getgenv:", name)
                return true
            end
        end
    end
    
    -- Tentar _G
    for _, name in ipairs(mmrCheck) do
        local success, func = pcall(function()
            return _G[name]
        end)
        
        if success and type(func) == "function" then
            ExecutorFuncs.mouseMove = func
            ExecutorFuncs.isAvailable = true
            DebugPrint("MouseMoveRel encontrado via _G:", name)
            return true
        end
    end
    
    -- Tentar getfenv
    for _, name in ipairs(mmrCheck) do
        local success, func = pcall(function()
            return getfenv()[name]
        end)
        
        if success and type(func) == "function" then
            ExecutorFuncs.mouseMove = func
            ExecutorFuncs.isAvailable = true
            DebugPrint("MouseMoveRel encontrado via getfenv:", name)
            return true
        end
    end
    
    -- Tentar shared
    if shared then
        for _, name in ipairs(mmrCheck) do
            local success, func = pcall(function()
                return shared[name]
            end)
            
            if success and type(func) == "function" then
                ExecutorFuncs.mouseMove = func
                ExecutorFuncs.isAvailable = true
                DebugPrint("MouseMoveRel encontrado via shared:", name)
                return true
            end
        end
    end
    
    DebugPrint("MouseMoveRel NÃO encontrado, usando Camera method")
    return false
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
    print("HasMMR:", self._hasMMR)
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
-- TARGET LOCK
-- ============================================================================
local Lock = {
    Current = nil,
    Time = 0,
    Score = math.huge,
    Kills = 0,
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
    
    local data = GetPlayerData(candidate)
    if not data or not data.isValid then return end
    
    local now = tick()
    local maxDur = Settings.MaxLockTime or 1.5
    local threshold = Settings.LockImprovementThreshold or 0.7
    
    -- Primeiro alvo
    if not self.Current then
        self.Current = candidate
        self.Time = now
        self.Score = score
        DebugPrint("Locked:", candidate.Name, "Score:", score)
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
        DebugPrint("Switched (invalid):", candidate.Name)
        return
    end
    
    local lockDur = now - self.Time
    
    -- AutoSwitch
    if Settings.AutoSwitch and lockDur > (Settings.TargetSwitchDelay or 0.3) then
        self.Current = candidate
        self.Time = now
        self.Score = score
        return
    end
    
    -- Tempo máximo
    if lockDur > maxDur then
        self.Current = candidate
        self.Time = now
        self.Score = score
        return
    end
    
    -- Score muito melhor
    if score < self.Score * threshold then
        self.Current = candidate
        self.Time = now
        self.Score = score
        DebugPrint("Switched (better):", candidate.Name)
    end
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
    
    -- Tentar aliases
    local candidates = PART_ALIASES[partName] or {partName}
    
    for _, name in ipairs(candidates) do
        local part = model:FindFirstChild(name)
        if part and part:IsA("BasePart") and part.Parent then
            return part
        end
    end
    
    -- Fallback para anchor
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
    -- Se IgnoreWalls está ativo, sempre visível
    if Settings.IgnoreWalls then return true end
    
    -- Se VisibleCheck está desativado, sempre visível
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
    
    if not success then return true end -- Em caso de erro, assume visível
    
    if result and result.Instance then
        -- Verificar se o hit é parte do alvo
        if result.Instance:IsDescendantOf(data.model) then
            return true
        end
        return false
    end
    
    return true -- Sem hit = visível
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
        -- Pular LocalPlayer
        if player == LocalPlayer then continue end
        
        -- Obter dados do jogador
        local data = GetPlayerData(player)
        if not data or not data.isValid then 
            DebugPrint("  Skip", player.Name, "- invalid data")
            continue 
        end
        
        if not data.anchor or not data.anchor.Parent then
            DebugPrint("  Skip", player.Name, "- no anchor")
            continue
        end
        
        -- Verificar time (CORRIGIDO: verifica ambos settings)
        local ignoreTeam = Settings.IgnoreTeam or Settings.IgnoreTeamAimbot
        if ignoreTeam and AreSameTeam(LocalPlayer, player) then
            DebugPrint("  Skip", player.Name, "- same team")
            continue
        end
        
        -- Verificar distância
        local distSq = DistanceSquared(data.anchor.Position, camPos)
        if distSq > maxDistSq then
            DebugPrint("  Skip", player.Name, "- too far")
            continue
        end
        
        -- Obter parte para mirar
        local aimPart = self:GetPart(player, Settings.AimPart)
        if not aimPart or not aimPart.Parent then
            DebugPrint("  Skip", player.Name, "- no aim part")
            continue
        end
        
        -- Converter para tela
        local screenSuccess, screenPos, onScreen = pcall(function()
            local pos, visible = cam:WorldToViewportPoint(aimPart.Position)
            return pos, visible
        end)
        
        if not screenSuccess then continue end
        
        -- Verificar se está na tela (a menos que AimOutsideFOV)
        if not onScreen and not Settings.AimOutsideFOV then
            DebugPrint("  Skip", player.Name, "- off screen")
            continue
        end
        
        local distance = math.sqrt(distSq)
        local distToMouse = onScreen and (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude or 9999
        
        -- Verificar FOV (se UseAimbotFOV está ativo)
        if Settings.UseAimbotFOV and distToMouse * distToMouse > currentFOVSq then
            DebugPrint("  Skip", player.Name, "- outside FOV")
            continue
        end
        
        -- Calcular score
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
    
    -- Ordenar por score
    table.sort(candidates, function(a, b) return a.score < b.score end)
    
    -- Verificar visibilidade
    for i = 1, math.min(5, #candidates) do
        local cand = candidates[i]
        
        if self:CheckVisible(cand.player, cand.aimPart) then
            DebugPrint("Selected:", cand.player.Name)
            return cand.player, cand.score
        else
            DebugPrint("  Not visible:", cand.player.Name)
        end
    end
    
    -- Se IgnoreWalls, retorna o melhor mesmo sem visibilidade
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
    
    -- Se prediction desativado
    if not Settings.UsePrediction then return basePos end
    
    local data = GetPlayerData(player)
    if not data or not data.anchor then return basePos end
    
    -- Obter velocidade
    local vel = Vector3.zero
    pcall(function()
        vel = data.anchor.AssemblyLinearVelocity or data.anchor.Velocity or Vector3.zero
    end)
    
    if vel.Magnitude < 0.5 then return basePos end
    
    -- Reduzir componente vertical
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
    
    return predicted
end

-- ============================================================================
-- AIM APPLICATION
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

function AimbotLegit:ApplyAim(targetPos, smoothing)
    if not targetPos then return false end
    if not IsValidPosition(targetPos) then return false end
    
    local cam = GetCamera()
    if not cam then return false end
    
    local method = Settings.AimMethod or "Camera"
    local smoothFactor = self:CalcSmooth(smoothing)
    
    -- Deadzone check
    if Settings.UseDeadzone then
        local success, screenPos, onScreen = pcall(function()
            local pos, vis = cam:WorldToViewportPoint(targetPos)
            return pos, vis
        end)
        
        if success and onScreen then
            local mouseSuccess, mousePos = pcall(function()
                return UserInputService:GetMouseLocation()
            end)
            
            if mouseSuccess then
                local dist = (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude
                local deadzone = Settings.DeadzoneRadius or 2
                if dist < deadzone then return true end
            end
        end
    end
    
    -- Preferir MouseMoveRel se disponível e configurado
    if method == "MouseMoveRel" and self._hasMMR then
        return self:Method_MMR(targetPos, smoothFactor)
    else
        return self:Method_Cam(targetPos, smoothFactor)
    end
end

function AimbotLegit:Method_Cam(targetPos, smoothFactor)
    local success = pcall(function()
        self._active = true
        
        local cam = GetCamera()
        if not cam then return end
        
        local camPos = cam.CFrame.Position
        local dir = targetPos - camPos
        
        if dir.Magnitude < 0.001 then return end
        
        local targetCF = CFrame.lookAt(camPos, targetPos)
        
        local currentRot = cam.CFrame.Rotation
        local targetRot = targetCF.Rotation
        local smoothedRot = currentRot:Lerp(targetRot, smoothFactor)
        
        -- CORREÇÃO: Verificar se a câmera pode ser modificada
        local newCFrame = CFrame.new(camPos) * smoothedRot
        cam.CFrame = newCFrame
    end)
    
    if not success then
        self._consecutiveErrors = (self._consecutiveErrors or 0) + 1
        if self._consecutiveErrors > self._maxConsecutiveErrors then
            DebugPrint("Method_Cam: Too many errors, resetting...")
            self:ForceReset()
        end
    else
        self._consecutiveErrors = 0
    end
    
    return success
end

function AimbotLegit:Method_MMR(targetPos, smoothFactor)
    if not self._hasMMR then
        return self:Method_Cam(targetPos, smoothFactor)
    end
    
    local success = pcall(function()
        self._active = true
        
        local cam = GetCamera()
        if not cam then return end
        
        local screenSuccess, screenPos, onScreen = pcall(function()
            local pos, vis = cam:WorldToViewportPoint(targetPos)
            return pos, vis
        end)
        
        if not screenSuccess or not onScreen then return end
        
        local viewport = cam.ViewportSize
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
-- MAIN UPDATE (CORRIGIDO: Toggle-only option)
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
    
    local holdActive = self._holdUntil and tick() < self._holdUntil
    
    -- CORREÇÃO: Suporte para AimbotToggleOnly
    -- Se AimbotToggleOnly == true, basta Settings.AimbotActive estar true
    -- Se AimbotToggleOnly == false (padrão), precisa de toggle + hold
    local shouldBeActive
    if Settings.AimbotToggleOnly then
        -- Toggle-only: basta o aimbot estar ativado (não precisa segurar)
        shouldBeActive = Settings.AimbotActive or holdActive
    else
        -- Comportamento padrão: precisa de toggle + hold
        shouldBeActive = (Settings.AimbotActive and mouseHold) or holdActive
    end
    
    if not shouldBeActive then
        if self.Active then
            self.Active = false
            Lock:Clear()
            self._active = false
        end
        
        if self._holdUntil and tick() >= self._holdUntil then
            self._holdUntil = nil
        end
        return
    end
    
    self.Active = true
    
    -- Encontrar melhor alvo
    local bestTarget, bestScore = self:FindBest()
    
    if bestTarget then
        Lock:TryAcquire(bestTarget, bestScore)
    end
    
    local target = Lock:Get()
    
    if target then
        local data = GetPlayerData(target)
        if not data or not data.isValid then
            Lock:Clear()
            return
        end
        
        local aimPart = self:GetPart(target, Settings.AimPart)
        
        if aimPart and aimPart.Parent then
            local aimPos = self:Predict(target, aimPart)
            
            if not aimPos then
                aimPos = aimPart.Position
            end
            
            if IsValidPosition(aimPos) then
                local smoothing = Settings.SmoothingFactor or 5
                
                -- Adaptive smoothing
                if Settings.UseAdaptiveSmoothing then
                    local cam = GetCamera()
                    if cam then
                        local distSq = DistanceSquared(data.anchor.Position, cam.CFrame.Position)
                        if distSq < 2500 then
                            smoothing = smoothing * 1.5
                        elseif distSq > 90000 then
                            smoothing = smoothing * 0.6
                        end
                    end
                end
                
                self:ApplyAim(aimPos, smoothing)
            end
        else
            Lock:Clear()
        end
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
    Lock:Clear()
    self._predHistory = {}
    self._failCount = {}
    self._validPos = nil
    DebugPrint("ForceReset completed")
end

function AimbotLegit:HoldAndStop(seconds)
    seconds = seconds or 0.2
    self._holdUntil = tick() + seconds
end

function AimbotLegit:HasMMR()
    return self._hasMMR
end

function AimbotLegit:GetDebugInfo()
    return {
        init = self._init,
        active = self.Active,
        hasMMR = self._hasMMR,
        currentTarget = Lock.Current and Lock.Current.Name or nil,
        consecutiveErrors = self._consecutiveErrors,
    }
end

-- ============================================================================
-- INITIALIZATION (CORRIGIDO: salva deps.Camera e deps.MouseMoveRel)
-- ============================================================================
function AimbotLegit:Initialize(deps)
    if self._init then 
        print("[AimbotLegit] Already initialized")
        return self 
    end
    
    print("[AimbotLegit] Initializing v4.9...")
    
    if not deps then
        warn("[AimbotLegit] No dependencies provided!")
        return nil
    end
    
    -- Armazenar dependências
    Utils = deps.Utils
    Settings = deps.Settings
    LocalPlayer = deps.LocalPlayer or Players.LocalPlayer
    
    -- CORREÇÃO: Usar deps.Camera se fornecido
    if deps.Camera then
        Camera = deps.Camera
    else
        GetCamera()
    end
    
    -- Verificar Settings
    if not Settings then
        warn("[AimbotLegit] Settings not provided!")
        return nil
    end
    
    -- Garantir defaults para novas configurações
    if Settings.AimbotToggleOnly == nil then
        Settings.AimbotToggleOnly = false
    end
    
    -- CORREÇÃO: Usar deps.MouseMoveRel se fornecido
    if deps.MouseMoveRel and type(deps.MouseMoveRel) == "function" then
        ExecutorFuncs.mouseMove = deps.MouseMoveRel
        ExecutorFuncs.isAvailable = true
        self._hasMMR = true
        print("[AimbotLegit] ✓ MouseMoveRel fornecido via deps")
    else
        -- Detectar MouseMoveRel automaticamente
        InitExecutorFuncs()
        self._hasMMR = ExecutorFuncs.isAvailable
    end
    
    self._init = true
    self._consecutiveErrors = 0
    
    print("[AimbotLegit] ✓ Initialized successfully")
    print("[AimbotLegit] MouseMoveRel:", self._hasMMR and "Available" or "Not available (using Camera)")
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