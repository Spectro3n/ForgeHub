-- ============================================================================
-- FORGEHUB - AIMBOT MODULE v2.0 (ROBUST REWRITE)
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

-- Atualiza quando character muda
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
    MaxAge = 3, -- frames
}

function VisibilityCache:NextFrame()
    self.Frame = self.Frame + 1
    
    -- Limpa cache antigo
    if self.Frame % 10 == 0 then
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
    self.Data[player] = {
        visible = visible,
        frame = self.Frame
    }
end

function VisibilityCache:Clear()
    self.Data = {}
    self.Frame = 0
end

-- ============================================================================
-- PLAYER DATA HELPER (COM FALLBACK)
-- ============================================================================
local function GetPlayerData(player)
    if not player then return nil end
    
    -- Tenta usar SemanticEngine
    local SemanticEngine = Core.SemanticEngine
    if SemanticEngine and SemanticEngine.GetCachedPlayerData then
        local data = SemanticEngine:GetCachedPlayerData(player)
        if data and data.isValid then
            return data
        end
    end
    
    -- Fallback: obtém dados diretamente
    local character = player.Character
    if not character then return nil end
    
    local anchor = character:FindFirstChild("HumanoidRootPart")
                or character:FindFirstChild("Torso")
                or character:FindFirstChild("Head")
    
    if not anchor or not anchor:IsDescendantOf(workspace) then
        return nil
    end
    
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    
    return {
        isValid = true,
        model = character,
        anchor = anchor,
        humanoid = humanoid,
    }
end

-- ============================================================================
-- TEAM CHECK (COM FALLBACK)
-- ============================================================================
local function AreSameTeam(player1, player2)
    if not player1 or not player2 then return false end
    
    -- Tenta usar SemanticEngine
    local SemanticEngine = Core.SemanticEngine
    if SemanticEngine and SemanticEngine.AreSameTeam then
        local success, result = pcall(function()
            return SemanticEngine:AreSameTeam(player1, player2)
        end)
        if success then
            return result
        end
    end
    
    -- Fallback: verifica Team padrão
    if player1.Team and player2.Team then
        return player1.Team == player2.Team
    end
    
    -- Fallback 2: TeamColor
    if player1.TeamColor and player2.TeamColor then
        return player1.TeamColor == player2.TeamColor
    end
    
    return false
end

-- ============================================================================
-- GET AIM PART
-- ============================================================================
local function GetAimPart(player, partName)
    local data = GetPlayerData(player)
    if not data or not data.model then return nil end
    
    local model = data.model
    partName = partName or "Head"
    
    -- Normaliza nome
    if type(partName) == "table" then
        partName = partName[1] or "Head"
    end
    
    if partName == "Head" then
        return model:FindFirstChild("Head") or data.anchor
        
    elseif partName == "Torso" then
        return model:FindFirstChild("UpperTorso")
            or model:FindFirstChild("Torso")
            or data.anchor
            
    elseif partName == "Root" or partName == "HumanoidRootPart" then
        return data.anchor
    end
    
    return data.anchor
end

-- ============================================================================
-- PREDICTION SYSTEM
-- ============================================================================
local PredictionHistory = {}
local MAX_HISTORY = 5

local function UpdatePredictionHistory(player, position)
    if not PredictionHistory[player] then
        PredictionHistory[player] = {}
    end
    
    local history = PredictionHistory[player]
    table.insert(history, {
        position = position,
        time = tick()
    })
    
    -- Mantém apenas últimos N registros
    while #history > MAX_HISTORY do
        table.remove(history, 1)
    end
end

local function CalculateVelocity(player, anchor)
    -- Método 1: AssemblyLinearVelocity
    if anchor.AssemblyLinearVelocity then
        local vel = anchor.AssemblyLinearVelocity
        if vel.Magnitude > 0.1 then
            return vel
        end
    end
    
    -- Método 2: Velocity (deprecated mas funciona)
    if anchor.Velocity then
        local vel = anchor.Velocity
        if vel.Magnitude > 0.1 then
            return vel
        end
    end
    
    -- Método 3: Histórico de posições
    local history = PredictionHistory[player]
    if history and #history >= 2 then
        local newest = history[#history]
        local oldest = history[1]
        local deltaTime = newest.time - oldest.time
        
        if deltaTime > 0.05 then
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
    
    -- Reduz velocidade Y (pulos)
    if velocity.Y > 0 then
        velocity = Vector3.new(velocity.X, velocity.Y * 0.3, velocity.Z)
    end
    
    -- Calcula tempo até o alvo
    local Camera = GetCamera()
    local distance = (targetPart.Position - Camera.CFrame.Position).Magnitude
    local timeToTarget = math.clamp(distance / 800, 0.01, 0.2)
    
    -- Aplica predição
    local multiplier = Settings.PredictionMultiplier or 0.135
    local predictedPos = targetPart.Position + (velocity * multiplier * timeToTarget)
    
    -- Atualiza histórico
    UpdatePredictionHistory(player, data.anchor.Position)
    
    return predictedPos
end

-- ============================================================================
-- VISIBILITY CHECK
-- ============================================================================
local function IsVisible(player, targetPart)
    if not Settings.VisibleCheck then
        return true
    end
    
    -- Verifica cache
    local cached, hit = VisibilityCache:Get(player)
    if hit then
        return cached
    end
    
    local Camera = GetCamera()
    local data = GetPlayerData(player)
    if not data then return false end
    
    local origin = Camera.CFrame.Position
    local direction = targetPart.Position - origin
    
    -- Atualiza filtro
    UpdateRayParams()
    
    local ray = Workspace:Raycast(origin, direction, RayParams)
    
    local visible = true
    if ray and ray.Instance then
        -- Verifica se bateu no personagem do alvo
        if not ray.Instance:IsDescendantOf(data.model) then
            visible = false
        end
    end
    
    VisibilityCache:Set(player, visible)
    return visible
end

-- ============================================================================
-- TARGET LOCK SYSTEM (REWRITTEN)
-- ============================================================================
local TargetLock = {
    CurrentTarget = nil,
    LockTime = 0,
    LastScore = math.huge,
    
    -- Configurações
    MinLockDuration = 0.15,
    MaxLockDuration = 2.0,
    ImprovementThreshold = 0.7,
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
    
    -- Verifica se está vivo
    if data.humanoid and data.humanoid.Health <= 0 then
        return false
    end
    
    -- Verifica distância
    local Camera = GetCamera()
    local distance = (data.anchor.Position - Camera.CFrame.Position).Magnitude
    if distance > (Settings.MaxDistance or 800) then
        return false
    end
    
    -- Verifica se ainda está na tela
    local screenPos, onScreen = Camera:WorldToViewportPoint(data.anchor.Position)
    if not onScreen then
        return false
    end
    
    return true
end

function TargetLock:TryLock(candidate, score)
    if not candidate then return end
    
    local now = tick()
    
    -- Se não tem alvo, trava imediatamente
    if not self.CurrentTarget then
        self.CurrentTarget = candidate
        self.LockTime = now
        self.LastScore = score
        return
    end
    
    -- Se é o mesmo alvo, atualiza
    if self.CurrentTarget == candidate then
        self.LastScore = score
        return
    end
    
    -- Verifica se alvo atual ainda é válido
    if not self:IsValid() then
        self.CurrentTarget = candidate
        self.LockTime = now
        self.LastScore = score
        return
    end
    
    -- Verifica tempo de lock
    local lockDuration = now - self.LockTime
    
    -- Se passou do tempo máximo, permite trocar
    if lockDuration > (Settings.MaxLockTime or self.MaxLockDuration) then
        self.CurrentTarget = candidate
        self.LockTime = now
        self.LastScore = score
        return
    end
    
    -- Se novo alvo é significativamente melhor, troca
    local threshold = Settings.LockImprovementThreshold or self.ImprovementThreshold
    if score < self.LastScore * threshold then
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
-- AIM METHODS
-- ============================================================================
local AimController = {
    IsAiming = false,
    OriginalCFrame = nil,
    
    -- Detecção de métodos
    HasMouseMoveRel = false,
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
    
    -- Restaura camera subject
    pcall(function()
        local Camera = GetCamera()
        if LocalPlayer.Character then
            local hum = LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
            if hum then
                Camera.CameraSubject = hum
            end
        end
    end)
end

function AimController:CalculateSmoothFactor(smoothing)
    if not smoothing or smoothing <= 0 then
        return 1.0
    end
    
    -- Mapeamento mais suave
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

function AimController:ApplyAim(targetPosition, smoothing)
    if not targetPosition then return false end
    
    local Camera = GetCamera()
    if not Camera then return false end
    
    local method = Settings.AimMethod or "Camera"
    local smoothFactor = self:CalculateSmoothFactor(smoothing)
    
    -- Deadzone check
    if Settings.UseDeadzone then
        local screenPos, onScreen = Camera:WorldToViewportPoint(targetPosition)
        if onScreen then
            local mousePos = UserInputService:GetMouseLocation()
            local dist = (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude
            
            local deadzone = Settings.DeadzoneRadius or 2
            if dist < deadzone then
                return true -- Já está no alvo
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
        
        if smoothFactor >= 0.95 then
            Camera.CFrame = targetCFrame
        else
            -- Interpolação suave
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
        
        -- Aplica suavização
        local moveX = deltaX * smoothFactor
        local moveY = deltaY * smoothFactor
        
        -- Ignora movimentos muito pequenos
        if math.abs(moveX) < 0.5 and math.abs(moveY) < 0.5 then
            return
        end
        
        mousemoverel(moveX, moveY)
    end)
    
    return success
end

-- ============================================================================
-- TARGET FINDER
-- ============================================================================
local function FindBestTarget()
    local Camera = GetCamera()
    local camPos = Camera.CFrame.Position
    local camLook = Camera.CFrame.LookVector
    local mousePos = UserInputService:GetMouseLocation()
    
    local bestTarget = nil
    local bestScore = math.huge
    
    local candidates = {}
    
    -- Coleta candidatos válidos
    for _, player in ipairs(Players:GetPlayers()) do
        if player == LocalPlayer then continue end
        
        local data = GetPlayerData(player)
        if not data or not data.isValid or not data.anchor then continue end
        
        -- Verifica se está vivo
        if data.humanoid and data.humanoid.Health <= 0 then continue end
        
        -- Verifica team
        if Settings.IgnoreTeamAimbot and AreSameTeam(LocalPlayer, player) then continue end
        
        -- Verifica distância 3D
        local distance = (data.anchor.Position - camPos).Magnitude
        if distance > (Settings.MaxDistance or 800) then continue end
        
        -- Verifica se está na tela
        local screenPos, onScreen = Camera:WorldToViewportPoint(data.anchor.Position)
        if not onScreen then continue end
        
        -- Calcula distância ao mouse
        local distToMouse = (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude
        
        -- Verifica FOV
        if Settings.UseAimbotFOV and distToMouse > (Settings.FOV or 180) then continue end
        
        -- Verifica se está olhando na direção certa (evita 180°)
        local dirToTarget = (data.anchor.Position - camPos).Unit
        local dot = camLook:Dot(dirToTarget)
        if dot < 0.1 then continue end -- Menos de ~85° do centro
        
        -- Calcula score (menor = melhor)
        -- Peso maior para distância ao mouse, menor para distância 3D
        local score = distToMouse * 1.0 + distance * 0.1
        
        table.insert(candidates, {
            player = player,
            data = data,
            score = score,
            distance = distance,
            distToMouse = distToMouse,
        })
    end
    
    -- Ordena por score
    table.sort(candidates, function(a, b)
        return a.score < b.score
    end)
    
    -- Verifica visibilidade dos melhores candidatos
    local maxChecks = 5
    local checked = 0
    
    for _, candidate in ipairs(candidates) do
        if checked >= maxChecks then break end
        
        local aimPart = GetAimPart(candidate.player, Settings.AimPart)
        if not aimPart then continue end
        
        checked = checked + 1
        
        -- Verifica visibilidade
        if IsVisible(candidate.player, aimPart) then
            return candidate.player, candidate.score
        end
    end
    
    -- Se nenhum visível, retorna o melhor sem check (se visiblecheck desativado)
    if not Settings.VisibleCheck and #candidates > 0 then
        return candidates[1].player, candidates[1].score
    end
    
    return nil, math.huge
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
end

function AimbotState:OnError()
    self.ErrorCount = self.ErrorCount + 1
    
    if self.ErrorCount >= self.MaxErrors then
        warn("[Aimbot] Muitos erros, resetando estado...")
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
    -- Atualiza cache de visibilidade
    VisibilityCache:NextFrame()
    
    -- Verifica se deve estar ativo
    local shouldBeActive = Settings.AimbotActive and State.MouseHold
    
    -- Se estado mudou para inativo
    if not shouldBeActive then
        if AimbotState.Active then
            AimbotState.Active = false
            TargetLock:Reset()
            AimController:StopAiming()
        end
        return
    end
    
    AimbotState.Active = true
    
    -- Verifica alvo atual
    local currentTarget = TargetLock:GetTarget()
    
    -- Busca novo/melhor alvo
    local bestTarget, bestScore = FindBestTarget()
    
    if bestTarget then
        TargetLock:TryLock(bestTarget, bestScore)
    end
    
    -- Obtém alvo final (pode ser o mesmo ou novo)
    local target = TargetLock:GetTarget()
    
    if target then
        local aimPart = GetAimPart(target, Settings.AimPart)
        
        if aimPart then
            -- Calcula posição predita
            local aimPos = PredictPosition(target, aimPart)
            
            -- Calcula suavização adaptativa
            local data = GetPlayerData(target)
            local baseSm = Settings.SmoothingFactor or 5
            local smoothing = baseSm
            
            if Settings.UseAdaptiveSmoothing and data and data.anchor then
                local Camera = GetCamera()
                local dist = (data.anchor.Position - Camera.CFrame.Position).Magnitude
                
                if dist < 50 then
                    smoothing = baseSm * 1.3 -- Mais suave de perto
                elseif dist > 300 then
                    smoothing = baseSm * 0.7 -- Mais rápido de longe
                end
            end
            
            -- Aplica aim
            AimController:ApplyAim(aimPos, smoothing)
        else
            -- Não conseguiu obter parte, reseta
            TargetLock:Reset()
            AimController:StopAiming()
        end
    else
        -- Sem alvo, para de mirar
        AimController:StopAiming()
    end
end

function Aimbot:StartLoop()
    if self.Connection then
        self.Connection:Disconnect()
        self.Connection = nil
    end
    
    self.Connection = RunService.Heartbeat:Connect(function()
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

function Aimbot:Initialize()
    if self.Initialized then return end
    
    -- Detecta métodos disponíveis
    AimController:DetectMethods()
    
    -- Inicia loop
    self:StartLoop()
    
    -- Watchdog: reinicia loop se morrer
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
    
    print("[Aimbot] Inicializado com sucesso!")
    print("[Aimbot] MouseMoveRel: " .. (AimController.HasMouseMoveRel and "Disponível" or "Não disponível"))
end

function Aimbot:Debug()
    print("\n========== AIMBOT DEBUG ==========")
    print("Initialized: " .. tostring(self.Initialized))
    print("Connection alive: " .. tostring(self.Connection ~= nil))
    print("State.Active: " .. tostring(AimbotState.Active))
    print("State.ErrorCount: " .. tostring(AimbotState.ErrorCount))
    
    print("\n--- Settings ---")
    print("  AimbotActive: " .. tostring(Settings.AimbotActive))
    print("  MouseHold: " .. tostring(State.MouseHold))
    print("  AimMethod: " .. tostring(Settings.AimMethod))
    print("  AimPart: " .. tostring(Settings.AimPart))
    print("  SmoothingFactor: " .. tostring(Settings.SmoothingFactor))
    print("  MaxDistance: " .. tostring(Settings.MaxDistance))
    print("  FOV: " .. tostring(Settings.FOV))
    print("  VisibleCheck: " .. tostring(Settings.VisibleCheck))
    print("  UsePrediction: " .. tostring(Settings.UsePrediction))
    
    print("\n--- Target Lock ---")
    print("  CurrentTarget: " .. tostring(TargetLock.CurrentTarget and TargetLock.CurrentTarget.Name or "None"))
    print("  LockTime: " .. string.format("%.2f", TargetLock.LockTime))
    print("  LastScore: " .. string.format("%.2f", TargetLock.LastScore))
    print("  IsValid: " .. tostring(TargetLock:IsValid()))
    
    print("\n--- Aim Controller ---")
    print("  IsAiming: " .. tostring(AimController.IsAiming))
    print("  HasMouseMoveRel: " .. tostring(AimController.HasMouseMoveRel))
    
    print("\n--- Cache ---")
    local cacheCount = 0
    for _ in pairs(VisibilityCache.Data) do
        cacheCount = cacheCount + 1
    end
    print("  VisibilityCache entries: " .. cacheCount)
    print("  VisibilityCache frame: " .. VisibilityCache.Frame)
    
    print("\n--- Test Target Finding ---")
    local target, score = FindBestTarget()
    if target then
        print("  Best target: " .. target.Name .. " (score: " .. string.format("%.2f", score) .. ")")
    else
        print("  No valid target found")
    end
    
    print("===================================\n")
end

-- ============================================================================
-- FORCE RESET (Para uso externo)
-- ============================================================================
function Aimbot:ForceReset()
    print("[Aimbot] Force reset chamado")
    AimbotState:Reset()
    self:StopLoop()
    task.wait(0.1)
    self:StartLoop()
    print("[Aimbot] Reset completo")
end

-- ============================================================================
-- EXPORT
-- ============================================================================
Core.Aimbot = {
    Main = Aimbot,
    TargetLock = TargetLock,
    AimController = AimController,
    
    -- Funções públicas
    Update = function() Aimbot:Update() end,
    Initialize = function() Aimbot:Initialize() end,
    Toggle = function(enabled) Aimbot:Toggle(enabled) end,
    Debug = function() Aimbot:Debug() end,
    ForceReset = function() Aimbot:ForceReset() end,
    
    -- Para compatibilidade
    CameraBypass = {
        GetLockedTarget = function()
            return TargetLock:GetTarget()
        end,
        ClearLock = function()
            TargetLock:Reset()
        end,
    },
    
    GetClosestPlayer = FindBestTarget,
    AimMethods = AimController,
}

return Aimbot