-- ============================================================================
-- FORGEHUB - AIMBOT LEGIT MODULE v5.0 (FULLY FIXED)
-- Versão com todas as correções de segurança e performance
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
    _lastPredCleanup = 0,
    
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
-- INTERNAL HELPERS (FALLBACKS)
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
-- EXECUTOR FUNCTIONS (MELHORADO COM SAFETY)
-- ============================================================================
local ExecutorFuncs = {
    mouseMove = nil,
    isAvailable = false,
    validated = false,
}

-- Rate limiting para MouseMoveRel
local LastMouseMove = 0
local MouseMoveInterval = 1/200 -- ~200 chamadas/s máximo

local function InitExecutorFuncs()
    local mmrCheck = {
        "mousemoverel", 
        "mouse_moverel", 
        "MouseMoveRel",
        "Input.MouseMove",
        "movemouserel",
    }
    
    -- Tentar getgenv primeiro
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

-- NOVO: Inicialização com respeito ao AimSafety
local function TryInitExecutor()
    local ok = InitExecutorFuncs()
    
    -- Forçar fallback se AimSafety ativado
    if ok and Settings and Settings.AimSafety then
        DebugPrint("AimSafety ON -> desativando MouseMoveRel por segurança")
        ok = false
        ExecutorFuncs.mouseMove = nil
        ExecutorFuncs.isAvailable = false
    end
    
    -- Validar com teste mínimo (handshake)
    if ok and ExecutorFuncs.mouseMove then
        local testOk = pcall(function()
            ExecutorFuncs.mouseMove(0, 0) -- Teste sem movimento
        end)
        
        if not testOk then
            DebugPrint("MouseMoveRel falhou no teste, desativando")
            ok = false
            ExecutorFuncs.mouseMove = nil
            ExecutorFuncs.isAvailable = false
        else
            ExecutorFuncs.validated = true
            DebugPrint("MouseMoveRel validado com sucesso")
        end
    end
    
    AimbotLegit._hasMMR = ok
    return ok
end

-- NOVO: SafeMouseMove com rate-limit, jitter, e fallback
local function SafeMouseMove(dx, dy)
    if not ExecutorFuncs.isAvailable or not ExecutorFuncs.mouseMove then
        return false
    end
    
    -- Rate limiting
    local now = tick()
    if now - LastMouseMove < MouseMoveInterval then
        return false
    end
    LastMouseMove = now
    
    dx = tonumber(dx) or 0
    dy = tonumber(dy) or 0
    
    -- Se AimSafety ativado, reduzir intensidade e adicionar micro-jitter
    if Settings and Settings.AimSafety then
        local jitterX = (math.random() - 0.5) * 0.4 -- +-0.2
        local jitterY = (math.random() - 0.5) * 0.4
        dx = dx * 0.6 + jitterX
        dy = dy * 0.6 + jitterY
    end
    
    -- Limite máximo de movimento por frame (anti-snap)
    local maxMove = Settings and Settings.MaxMouseMovePerFrame or 50
    dx = math.clamp(dx, -maxMove, maxMove)
    dy = math.clamp(dy, -maxMove, maxMove)
    
    -- Tentar com float primeiro, depois integer como fallback
    local ok = pcall(function() 
        ExecutorFuncs.mouseMove(dx, dy) 
    end)
    
    if not ok then
        ok = pcall(function() 
            ExecutorFuncs.mouseMove(math.floor(dx), math.floor(dy)) 
        end)
    end
    
    return ok
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
    print("Settings.AimSafety:", Settings and Settings.AimSafety)
    print("LocalPlayer:", LocalPlayer and LocalPlayer.Name or "nil")
    
    local cam = GetCamera()
    print("Camera:", cam and "OK" or "nil")
    print("HasMMR:", self._hasMMR)
    print("MMR Validated:", ExecutorFuncs.validated)
    print("AimMethod:", Settings and Settings.AimMethod or "nil")
    print("ChosenMethod:", self:ChooseAimMethod())
    
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
    print("ConsecutiveErrors:", self._consecutiveErrors)
    print("===================================\n")
end

-- ============================================================================
-- TARGET LOCK (COM PROTEÇÃO CONTRA RACE CONDITION)
-- ============================================================================
local Lock = {
    Current = nil,
    Time = 0,
    Score = math.huge,
    Kills = 0,
    _updating = false, -- Flag de proteção
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
    -- Proteção contra race condition
    if self._updating then return end
    self._updating = true
    
    local success, err = pcall(function()
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
    end)
    
    self._updating = false
    
    if not success then
        DebugPrint("Lock:TryAcquire error:", err)
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
-- PREDICTION (COM CLEANUP DE MEMÓRIA)
-- ============================================================================
function AimbotLegit:CleanupPredHistory()
    local now = tick()
    
    -- Limpar a cada 5 segundos
    if now - self._lastPredCleanup < 5 then return end
    self._lastPredCleanup = now
    
    local toRemove = {}
    
    for playerId, lastUpdate in pairs(self._lastPredUpdate) do
        if now - lastUpdate > 5 then
            table.insert(toRemove, playerId)
        end
    end
    
    for _, playerId in ipairs(toRemove) do
        self._predHistory[playerId] = nil
        self._lastPredUpdate[playerId] = nil
    end
    
    if #toRemove > 0 then
        DebugPrint("Cleaned up", #toRemove, "prediction entries")
    end
end

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
    
    -- Atualizar histórico
    local playerId = player.UserId
    self._predHistory[playerId] = predicted
    self._lastPredUpdate[playerId] = tick()
    
    return predicted
end

-- ============================================================================
-- AIM METHOD SELECTION (NOVO - CONTROLE CENTRALIZADO)
-- ============================================================================
function AimbotLegit:ChooseAimMethod()
    -- Preferir Camera se:
    -- 1. MMR não disponível
    -- 2. AimSafety ativado
    -- 3. AimMethod não é MouseMoveRel
    
    if not self._hasMMR then
        return "CAM"
    end
    
    if Settings and Settings.AimSafety then
        return "CAM"
    end
    
    if Settings and Settings.AimMethod == "MouseMoveRel" then
        return "MMR"
    end
    
    return "CAM"
end

-- ============================================================================
-- AIM APPLICATION (MELHORADO)
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

-- NOVO: Easing exponencial para movimentos mais naturais
local function EaseOutExpo(t)
    return t == 1 and 1 or 1 - math.pow(2, -10 * t)
end

local function EaseInOutQuad(t)
    return t < 0.5 and 2 * t * t or 1 - math.pow(-2 * t + 2, 2) / 2
end

function AimbotLegit:CalculateAdaptiveSmoothing(data)
    local smoothing = Settings.SmoothingFactor or 5
    
    if not Settings.UseAdaptiveSmoothing then
        return smoothing
    end
    
    local cam = GetCamera()
    if not cam or not data or not data.anchor then return smoothing end
    
    local distSq = DistanceSquared(data.anchor.Position, cam.CFrame.Position)
    
    -- Perto: mais suave (maior smoothing)
    if distSq < 2500 then -- < 50 studs
        return smoothing * 1.5
    -- Longe: mais rápido (menor smoothing)
    elseif distSq > 90000 then -- > 300 studs
        return smoothing * 0.6
    end
    
    return smoothing
end

function AimbotLegit:ApplyAim(targetPos, smoothing)
    if not targetPos then return false end
    if not IsValidPosition(targetPos) then return false end
    
    local cam = GetCamera()
    if not cam then return false end
    
    local smoothFactor = self:CalcSmooth(smoothing)
    
    -- Deadzone check ANTES de qualquer movimento
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
                if dist < deadzone then 
                    return true -- Já no alvo, não precisa mover
                end
            end
        end
    end
    
    -- Escolher método
    local method = self:ChooseAimMethod()
    
    if method == "MMR" then
        return self:Method_MMR(targetPos, smoothFactor)
    else
        return self:Method_Cam(targetPos, smoothFactor)
    end
end

function AimbotLegit:Method_Cam(targetPos, smoothFactor)
    local success, errorMsg = pcall(function()
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
        
        -- Aplicar easing para movimento mais natural
        local easedFactor = smoothFactor
        if Settings.AimSafety then
            -- Usar easing exponencial para parecer mais humano
            easedFactor = EaseOutExpo(smoothFactor) * 0.8
        end
        
        local smoothedRot = currentRot:Lerp(targetRot, easedFactor)
        
        -- Adicionar micro-jitter se AimSafety ativo
        if Settings.AimSafety then
            local jitter = CFrame.Angles(
                (math.random() - 0.5) * 0.001,
                (math.random() - 0.5) * 0.001,
                0
            )
            smoothedRot = smoothedRot * jitter
        end
        
        local newCFrame = CFrame.new(camPos) * smoothedRot
        cam.CFrame = newCFrame
    end)
    
    if not success then
        self._consecutiveErrors = (self._consecutiveErrors or 0) + 1
        
        if self._debugMode then
            warn("[Aimbot] Method_Cam error:", errorMsg)
        end
        
        if self._consecutiveErrors > self._maxConsecutiveErrors then
            DebugPrint("Method_Cam: Too many errors, resetting...")
            self:ForceReset()
            
            -- Recuperar após delay
            task.delay(0.5, function()
                self._consecutiveErrors = 0
            end)
        end
        
        return false
    end
    
    self._consecutiveErrors = 0
    return true
end

function AimbotLegit:Method_MMR(targetPos, smoothFactor)
    if not self._hasMMR then
        return self:Method_Cam(targetPos, smoothFactor)
    end
    
    local success = pcall(function()
        self._active = true
        
        local cam = GetCamera()
        if not cam then return end
        
        local screenPos, onScreen
        local screenSuccess = pcall(function()
            screenPos, onScreen = cam:WorldToViewportPoint(targetPos)
        end)
        
        if not screenSuccess or not onScreen then return end
        
        local viewport = cam.ViewportSize
        local centerX = viewport.X / 2
        local centerY = viewport.Y / 2
        
        local deltaX = screenPos.X - centerX
        local deltaY = screenPos.Y - centerY
        
        local moveX = deltaX * smoothFactor
        local moveY = deltaY * smoothFactor
        
        -- Deadzone para MMR também
        if math.abs(moveX) < 0.1 and math.abs(moveY) < 0.1 then return end
        
        SafeMouseMove(moveX, moveY)
    end)
    
    return success
end

-- ============================================================================
-- MAIN UPDATE (REFATORADO)
-- ============================================================================
function AimbotLegit:Deactivate()
    self.Active = false
    self._active = false
    Lock:Clear()
    
    if self._holdUntil and tick() >= self._holdUntil then
        self._holdUntil = nil
    end
end

function AimbotLegit:ProcessAim()
    -- Cleanup periódico
    self:CleanupPredHistory()
    
    -- Encontrar melhor alvo
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
    
    -- Determinar se deve estar ativo
    local shouldBeActive = false
    
    if holdActive then
        shouldBeActive = true
    elseif Settings.AimbotActive then
        if Settings.AimbotToggleOnly then
            -- Toggle-only: sempre ativo quando ligado
            shouldBeActive = true
        else
            -- Normal: precisa segurar botão
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
    self:ProcessAim()
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================
function AimbotLegit:Toggle(enabled)
    Settings.AimbotActive = enabled
    if not enabled then
        self:Deactivate()
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
    self._lastPredUpdate = {}
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
        mmrValidated = ExecutorFuncs.validated,
        currentTarget = Lock.Current and Lock.Current.Name or nil,
        consecutiveErrors = self._consecutiveErrors,
        aimMethod = self:ChooseAimMethod(),
        aimSafety = Settings and Settings.AimSafety or false,
    }
end

-- NOVO: Revalidar MMR (útil após mudança de settings)
function AimbotLegit:RevalidateMMR()
    DebugPrint("Revalidating MouseMoveRel...")
    TryInitExecutor()
    return self._hasMMR
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================
function AimbotLegit:Initialize(deps)
    if self._init then 
        print("[AimbotLegit] Already initialized")
        return self 
    end
    
    print("[AimbotLegit] Initializing v5.0 FIXED...")
    
    if not deps then
        warn("[AimbotLegit] No dependencies provided!")
        return nil
    end
    
    -- Armazenar dependências
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
    
    -- Garantir defaults
    if Settings.AimbotToggleOnly == nil then
        Settings.AimbotToggleOnly = false
    end
    
    if Settings.AimSafety == nil then
        Settings.AimSafety = false
    end
    
    if Settings.MaxMouseMovePerFrame == nil then
        Settings.MaxMouseMovePerFrame = 50
    end
    
    -- Usar deps.MouseMoveRel se fornecido
    if deps.MouseMoveRel and type(deps.MouseMoveRel) == "function" then
        ExecutorFuncs.mouseMove = deps.MouseMoveRel
        ExecutorFuncs.isAvailable = true
        print("[AimbotLegit] ✓ MouseMoveRel fornecido via deps")
        
        -- Ainda respeitar AimSafety
        if Settings.AimSafety then
            ExecutorFuncs.mouseMove = nil
            ExecutorFuncs.isAvailable = false
            self._hasMMR = false
            print("[AimbotLegit] ⚠ AimSafety ativo, MMR desativado")
        else
            -- Validar
            local testOk = pcall(function()
                deps.MouseMoveRel(0, 0)
            end)
            
            if testOk then
                ExecutorFuncs.validated = true
                self._hasMMR = true
            else
                ExecutorFuncs.mouseMove = nil
                ExecutorFuncs.isAvailable = false
                self._hasMMR = false
            end
        end
    else
        -- Detectar automaticamente com respeito ao AimSafety
        TryInitExecutor()
    end
    
    self._init = true
    self._consecutiveErrors = 0
    self._lastPredCleanup = tick()
    
    print("[AimbotLegit] ✓ Initialized successfully")
    print("[AimbotLegit] MouseMoveRel:", self._hasMMR and "Available" or "Not available (using Camera)")
    print("[AimbotLegit] MMR Validated:", ExecutorFuncs.validated and "Yes" or "No")
    print("[AimbotLegit] AimSafety:", Settings.AimSafety and "ON" or "OFF")
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