-- ============================================================================
-- FORGEHUB - SEMANTIC ENGINE MODULE v2.1 (ENHANCED)
-- ============================================================================
-- Changelog v2.1:
--   • Tabelas fracas para GC automático
--   • Limpeza de conexões por player
--   • Cache determinístico e adaptativo
--   • APIs de extensão (Register*)
--   • Sistema de eventos públicos
--   • Config table exposta
--   • Método Destroy() para cleanup
--   • Loop de manutenção com backoff
--   • Heurísticas extensíveis
-- ============================================================================

local Core = _G.ForgeHubCore
if not Core then
    error("ForgeHubCore não encontrado! Carregue main.lua primeiro.")
end

-- ============================================================================
-- IMPORTS
-- ============================================================================
local Players = Core.Players
local Workspace = Core.Workspace
local LocalPlayer = Core.LocalPlayer
local RunService = Core.RunService

-- ============================================================================
-- UTILITY: WEAK TABLE CONSTRUCTOR
-- ============================================================================
local function WeakKeys()
    return setmetatable({}, { __mode = "k" })
end

local function WeakValues()
    return setmetatable({}, { __mode = "v" })
end

local function WeakBoth()
    return setmetatable({}, { __mode = "kv" })
end

-- ============================================================================
-- SAFE CALL (MELHORADO)
-- ============================================================================
local function SafeCall(func, name)
    local success, result = pcall(func)
    if not success then
        warn("[Semantic] Erro em " .. (name or "unknown") .. ": " .. tostring(result))
        return nil, result
    end
    return success, result
end

local function SafeCallReturn(func, name)
    local success, result = pcall(func)
    if not success then
        warn("[Semantic] Erro em " .. (name or "unknown") .. ": " .. tostring(result))
        return nil
    end
    return result
end

-- ============================================================================
-- PLAYER CACHE (MELHORADO - TABELAS FRACAS + DETERMINÍSTICO)
-- ============================================================================
local PlayerCache = {
    Data = WeakKeys(),           -- Chaves fracas (players)
    StaggerOffset = WeakKeys(),  -- Chaves fracas
    BaseCacheTime = 0.15,
}

-- Stagger DETERMINÍSTICO baseado em UserId
function PlayerCache:GetStagger(player)
    if not player then return 0 end
    
    if not self.StaggerOffset[player] then
        local id = player.UserId or 0
        -- Determinístico: entre 0 e 0.099 baseado no UserId
        self.StaggerOffset[player] = (id % 100) / 1000
    end
    return self.StaggerOffset[player]
end

-- Cache Time ADAPTATIVO baseado em número de jogadores
function PlayerCache:GetAdaptiveCacheTime()
    local playerCount = #Players:GetPlayers()
    local config = Core.SemanticEngine and Core.SemanticEngine.Config or {}
    local baseTime = config.CacheTime or self.BaseCacheTime
    
    -- Aumenta TTL com mais jogadores (até +0.3s para 30+ players)
    local adaptive = baseTime + math.clamp(playerCount / 100, 0, 0.3)
    return adaptive
end

function PlayerCache:Get(player)
    if not player then return nil end
    
    local now = tick()
    local data = self.Data[player]
    
    if not data then return nil end
    
    local stagger = self:GetStagger(player)
    local cacheTime = self:GetAdaptiveCacheTime()
    
    -- Cache válido?
    if (now - data.lastUpdate) < (cacheTime + stagger) then
        return data
    end
    
    return nil
end

function PlayerCache:Set(player, data)
    if not player or not data then return end
    self.Data[player] = data
end

function PlayerCache:Clear(player)
    if player then
        self.Data[player] = nil
        self.StaggerOffset[player] = nil
    else
        self:ClearAll()
    end
end

function PlayerCache:ClearAll()
    self.Data = WeakKeys()
    self.StaggerOffset = WeakKeys()
end

-- ============================================================================
-- SEMANTIC ENGINE
-- ============================================================================
local SemanticEngine = {
    -- Versão para compatibilidade
    Version = "2.1",
    
    -- CONFIGURAÇÃO PÚBLICA (outros scripts podem modificar)
    Config = {
        CacheTime = 0.15,
        ContainerScanInterval = 5,
        TeamCheckInterval = 3,
        MaxPlayersTracked = 64,
        Debug = false,
        
        -- Padrões de nomes para hitbox
        HitboxNamePatterns = {
            "head", "hit", "hurt", "hitbox", "target", "weak",
        },
        
        -- Nomes de containers para scan
        ContainerNames = {
            "Characters", "Players", "Entities", "Alive", "InGame", 
            "ActivePlayers", "NPCs", "Enemies", "Bots", "Units", 
            "Team1", "Team2", "Arena", "Combatants", "Fighters",
            "SpawnedPlayers", "GamePlayers", "AliveFolder",
        },
    },
    
    -- Definições aprendidas (TABELAS FRACAS)
    TargetDefinitions = {
        HitboxParts = WeakKeys(),
        CombatModels = WeakKeys(),
        EntityToPlayer = WeakKeys(),
        PlayerToEntity = WeakKeys(),
    },
    
    -- Sistema de times
    TeamSystem = {
        Method = "Unknown",
        CurrentPartition = {},
        ForceFFA = false,
        AutoDetected = false,
        LastCheck = 0,
        CheckInterval = 3,
    },
    
    -- Containers conhecidos
    ContainerSystem = {
        KnownContainers = WeakKeys(),
        RegisteredContainers = WeakKeys(),
        LastScan = 0,
        ScanInterval = 5,
    },
    
    -- HEURÍSTICAS CUSTOMIZÁVEIS
    Heuristics = {
        AnchorResolvers = {},      -- funções customizadas para encontrar anchor
        TeamResolvers = {},        -- funções customizadas para resolver times
        HitboxClassifiers = {},    -- funções customizadas para classificar hitboxes
    },
    
    -- EVENTOS PÚBLICOS (para hooks de outros módulos)
    Events = {},
    
    -- Estatísticas
    Stats = {
        DamageEventsDetected = 0,
        EntitiesLearned = 0,
        ContainersFound = 0,
        PlayersTracked = 0,
        CacheHits = 0,
        CacheMisses = 0,
        Errors = 0,
        LastError = nil,
    },
    
    -- Estado interno
    _initialized = false,
    _connections = {},
    _playerConnections = WeakKeys(),  -- Conexões por player (para cleanup)
    _maintenanceErrorStreak = 0,
}

-- ============================================================================
-- INICIALIZAÇÃO DE EVENTOS
-- ============================================================================
local function CreateEvents()
    SemanticEngine.Events = {
        PlayerTracked = Instance.new("BindableEvent"),
        PlayerUntracked = Instance.new("BindableEvent"),
        ContainerFound = Instance.new("BindableEvent"),
        TeamDetected = Instance.new("BindableEvent"),
        EntityLinked = Instance.new("BindableEvent"),
    }
end

local function FireEvent(eventName, ...)
    if SemanticEngine.Events[eventName] then
        SafeCall(function()
            SemanticEngine.Events[eventName]:Fire(...)
        end, "FireEvent_" .. eventName)
    end
end

-- ============================================================================
-- DEBUG LOGGING
-- ============================================================================
local function DebugLog(...)
    if SemanticEngine.Config.Debug then
        print("[Semantic Debug]", ...)
    end
end

local function DebugWarn(...)
    if SemanticEngine.Config.Debug then
        warn("[Semantic Debug]", ...)
    end
end

-- ============================================================================
-- CONEXÃO MANAGEMENT (POR PLAYER)
-- ============================================================================
local function AddPlayerConnection(player, connection)
    if not player or not connection then return end
    
    SemanticEngine._playerConnections[player] = SemanticEngine._playerConnections[player] or {}
    table.insert(SemanticEngine._playerConnections[player], connection)
end

local function ClearPlayerConnections(player)
    if not player then return end
    
    local conns = SemanticEngine._playerConnections[player]
    if conns then
        for _, conn in ipairs(conns) do
            if conn and conn.Disconnect then
                pcall(conn.Disconnect, conn)
            end
        end
    end
    SemanticEngine._playerConnections[player] = nil
end

-- ============================================================================
-- API DE EXTENSÃO: REGISTRAR HEURÍSTICAS
-- ============================================================================

-- Registra uma função customizada para encontrar anchor parts
-- fn(model) -> BasePart ou nil
function SemanticEngine:RegisterAnchorHeuristic(fn)
    if type(fn) == "function" then
        table.insert(self.Heuristics.AnchorResolvers, fn)
        DebugLog("Anchor heuristic registered, total:", #self.Heuristics.AnchorResolvers)
    end
end

-- Registra uma função customizada para resolver times
-- fn(players) -> partition table {player = teamKey} ou nil
function SemanticEngine:RegisterTeamResolver(fn)
    if type(fn) == "function" then
        table.insert(self.Heuristics.TeamResolvers, fn)
        DebugLog("Team resolver registered, total:", #self.Heuristics.TeamResolvers)
    end
end

-- Registra uma função customizada para classificar hitboxes
-- fn(part) -> boolean (é hitbox?)
function SemanticEngine:RegisterHitboxClassifier(fn)
    if type(fn) == "function" then
        table.insert(self.Heuristics.HitboxClassifiers, fn)
        DebugLog("Hitbox classifier registered, total:", #self.Heuristics.HitboxClassifiers)
    end
end

-- Registra um container manualmente
function SemanticEngine:RegisterContainer(container)
    if not container then return false end
    
    if typeof(container) == "Instance" then
        self.ContainerSystem.RegisteredContainers[container] = {
            name = container.Name,
            registered = tick(),
        }
        DebugLog("Container registered:", container.Name)
        return true
    elseif type(container) == "string" then
        -- Busca por nome
        local found = Workspace:FindFirstChild(container, true)
        if found then
            self.ContainerSystem.RegisteredContainers[found] = {
                name = container,
                registered = tick(),
            }
            DebugLog("Container registered by name:", container)
            return true
        end
    end
    
    return false
end

-- ============================================================================
-- PLAYER TRACKING (MELHORADO COM CONEXÕES)
-- ============================================================================
function SemanticEngine:TrackPlayer(player)
    if not player or player == LocalPlayer then return end
    
    DebugLog("Tracking player:", player.Name)
    
    -- Limpa estado anterior
    ClearPlayerConnections(player)
    PlayerCache:Clear(player)
    self.TargetDefinitions.PlayerToEntity[player] = nil
    
    -- Procura entidade existente
    local entity = self:FindEntityForPlayer(player)
    if entity then
        self:LinkPlayerToEntity(player, entity)
    end
    
    -- Observa Character
    if player.Character then
        self:_setupCharacterTracking(player, player.Character)
    end
    
    -- Aguarda Character futuro
    local charAddedConn = player.CharacterAdded:Connect(function(character)
        task.wait(0.1) -- Aguarda character inicializar
        PlayerCache:Clear(player)
        self:_setupCharacterTracking(player, character)
        self:LinkPlayerToEntity(player, character)
    end)
    AddPlayerConnection(player, charAddedConn)
    table.insert(self._connections, charAddedConn)
    
    self.Stats.PlayersTracked = self.Stats.PlayersTracked + 1
    FireEvent("PlayerTracked", player, entity)
end

function SemanticEngine:_setupCharacterTracking(player, character)
    if not character then return end
    
    -- Observa quando character é destruído/removido
    local ancestryConn = character.AncestryChanged:Connect(function(_, parent)
        if not parent then
            PlayerCache:Clear(player)
            self.TargetDefinitions.EntityToPlayer[character] = nil
            self.TargetDefinitions.PlayerToEntity[player] = nil
            DebugLog("Character removed for:", player.Name)
        end
    end)
    AddPlayerConnection(player, ancestryConn)
    
    -- Observa Humanoid para detectar morte
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if humanoid then
        local diedConn = humanoid.Died:Connect(function()
            DebugLog("Player died:", player.Name)
            -- Não limpa cache imediatamente, respawn vai triggerar CharacterAdded
        end)
        AddPlayerConnection(player, diedConn)
    end
end

function SemanticEngine:UntrackPlayer(player)
    if not player then return end
    
    DebugLog("Untracking player:", player.Name)
    
    -- Limpa conexões
    ClearPlayerConnections(player)
    
    -- Limpa cache
    PlayerCache:Clear(player)
    
    -- Remove mapeamentos
    local entity = self.TargetDefinitions.PlayerToEntity[player]
    if entity then
        self.TargetDefinitions.EntityToPlayer[entity] = nil
    end
    self.TargetDefinitions.PlayerToEntity[player] = nil
    
    -- Remove do TeamSystem
    if self.TeamSystem.CurrentPartition then
        self.TeamSystem.CurrentPartition[player] = nil
    end
    
    FireEvent("PlayerUntracked", player)
end

function SemanticEngine:LinkPlayerToEntity(player, entity)
    if not player or not entity then return end
    
    DebugLog("Linking", player.Name, "to", entity.Name)
    
    self.TargetDefinitions.EntityToPlayer[entity] = player
    self.TargetDefinitions.PlayerToEntity[player] = entity
    self.TargetDefinitions.CombatModels[entity] = true
    self.Stats.EntitiesLearned = self.Stats.EntitiesLearned + 1
    
    FireEvent("EntityLinked", player, entity)
end

-- ============================================================================
-- FIND ENTITY FOR PLAYER (MELHORADO)
-- ============================================================================
function SemanticEngine:FindEntityForPlayer(player)
    if not player then return nil end
    
    -- 1. Mapeamento direto existente
    local mapped = self.TargetDefinitions.PlayerToEntity[player]
    if mapped and mapped.Parent then
        return mapped
    end
    
    -- 2. Character padrão
    if player.Character and player.Character.Parent then
        return player.Character
    end
    
    -- 3. Busca em containers registrados primeiro
    for container, _ in pairs(self.ContainerSystem.RegisteredContainers) do
        if container and container.Parent then
            local found = container:FindFirstChild(player.Name)
            if found and found:IsA("Model") then
                return found
            end
        end
    end
    
    -- 4. Busca em containers conhecidos
    for container, _ in pairs(self.ContainerSystem.KnownContainers) do
        if container and container.Parent then
            local found = container:FindFirstChild(player.Name)
            if found and found:IsA("Model") then
                return found
            end
        end
    end
    
    -- 5. Busca direta no Workspace
    local wsChild = Workspace:FindFirstChild(player.Name)
    if wsChild and wsChild:IsA("Model") then
        return wsChild
    end
    
    -- 6. Busca por DisplayName
    if player.DisplayName and player.DisplayName ~= player.Name then
        local displayChild = Workspace:FindFirstChild(player.DisplayName)
        if displayChild and displayChild:IsA("Model") then
            return displayChild
        end
    end
    
    return nil
end

-- ============================================================================
-- GET CACHED PLAYER DATA (MANTIDO COMPATÍVEL)
-- ============================================================================
function SemanticEngine:GetCachedPlayerData(player)
    if not player then
        return { isValid = false }
    end
    
    -- Verifica cache
    local cached = PlayerCache:Get(player)
    if cached then
        self.Stats.CacheHits = self.Stats.CacheHits + 1
        return cached
    end
    
    self.Stats.CacheMisses = self.Stats.CacheMisses + 1
    
    -- Constrói dados frescos
    local data = self:BuildPlayerData(player)
    
    -- Salva no cache
    PlayerCache:Set(player, data)
    
    return data
end

function SemanticEngine:BuildPlayerData(player)
    local now = tick()
    
    -- Encontra modelo/entidade
    local model = self:FindEntityForPlayer(player)
    
    if not model or not model.Parent then
        return {
            isValid = false,
            model = nil,
            anchor = nil,
            humanoid = nil,
            team = nil,
            health = 0,
            maxHealth = 0,
            lastUpdate = now,
        }
    end
    
    -- Encontra anchor (root part)
    local anchor = self:GetAnchorPart(model)
    
    -- Encontra humanoid
    local humanoid = model:FindFirstChildOfClass("Humanoid")
    
    -- Obtém time
    local team = self:GetPlayerTeam(player)
    
    -- Health info
    local health = humanoid and humanoid.Health or 0
    local maxHealth = humanoid and humanoid.MaxHealth or 100
    
    -- Atualiza mapeamento
    if model then
        self:LinkPlayerToEntity(player, model)
    end
    
    return {
        isValid = anchor ~= nil and anchor:IsDescendantOf(workspace),
        model = model,
        anchor = anchor,
        humanoid = humanoid,
        team = team,
        health = health,
        maxHealth = maxHealth,
        lastUpdate = now,
    }
end

-- ============================================================================
-- GET ANCHOR PART (MELHORADO COM HEURÍSTICAS)
-- ============================================================================
function SemanticEngine:GetAnchorPart(model)
    if not model then return nil end
    
    -- 1. Tenta heurísticas customizadas primeiro
    for _, heuristic in ipairs(self.Heuristics.AnchorResolvers) do
        local result = SafeCallReturn(function()
            return heuristic(model)
        end, "AnchorHeuristic")
        
        if result and result:IsA("BasePart") and result:IsDescendantOf(workspace) then
            return result
        end
    end
    
    -- 2. Lista de nomes padrão (ordem de prioridade)
    local candidates = {
        "HumanoidRootPart",
        "Torso",
        "UpperTorso",
        "LowerTorso",
        "Root",
        "RootPart",
        "Head",
    }
    
    for _, name in ipairs(candidates) do
        local part = model:FindFirstChild(name)
        if part and part:IsA("BasePart") and part:IsDescendantOf(workspace) then
            return part
        end
    end
    
    -- 3. PrimaryPart do modelo
    if model.PrimaryPart and model.PrimaryPart:IsDescendantOf(workspace) then
        return model.PrimaryPart
    end
    
    -- 4. Humanoid.RootPart
    local humanoid = model:FindFirstChildOfClass("Humanoid")
    if humanoid and humanoid.RootPart and humanoid.RootPart:IsDescendantOf(workspace) then
        return humanoid.RootPart
    end
    
    -- 5. Busca por atributo customizado
    for _, child in ipairs(model:GetDescendants()) do
        if child:IsA("BasePart") and child:GetAttribute("IsAnchor") then
            return child
        end
    end
    
    -- 6. Fallback: maior BasePart por volume (heurística)
    local best, bestVol = nil, 0
    for _, child in ipairs(model:GetChildren()) do
        if child:IsA("BasePart") and child:IsDescendantOf(workspace) then
            local vol = child.Size.X * child.Size.Y * child.Size.Z
            if vol > bestVol then
                best, bestVol = child, vol
            end
        end
    end
    
    return best
end

-- ============================================================================
-- CLEAR PLAYER CACHE (PÚBLICO - MANTIDO)
-- ============================================================================
function SemanticEngine:ClearPlayerCache(player)
    PlayerCache:Clear(player)
end

function SemanticEngine:ClearAllCache()
    PlayerCache:ClearAll()
end

-- ============================================================================
-- TEAM SYSTEM (MELHORADO COM RESOLVERS)
-- ============================================================================
function SemanticEngine:DetectTeamSystemWithVoting()
    local players = Players:GetPlayers()
    if #players < 2 then
        self.TeamSystem.Method = "FFA"
        self.TeamSystem.ForceFFA = true
        self.TeamSystem.AutoDetected = true
        return
    end
    
    local partitions = {}
    
    -- Método 1: Roblox Teams
    SafeCall(function()
        local Teams = game:GetService("Teams")
        local teams = Teams:GetChildren()
        
        if #teams > 0 then
            partitions.RobloxTeam = {}
            for _, p in ipairs(players) do
                if p.Team then
                    partitions.RobloxTeam[p] = p.Team.Name
                else
                    partitions.RobloxTeam[p] = "__nil"
                end
            end
        end
    end, "DetectRobloxTeams")
    
    -- Método 2: TeamColor
    partitions.TeamColor = {}
    for _, p in ipairs(players) do
        if p.TeamColor and p.TeamColor ~= BrickColor.new("White") then
            partitions.TeamColor[p] = tostring(p.TeamColor)
        else
            partitions.TeamColor[p] = "__nil"
        end
    end
    
    -- Método 3: Attributes
    partitions.Attribute = {}
    local attrNames = {"Team", "TeamName", "Faction", "Side", "Squad", "Group", "Alliance"}
    for _, p in ipairs(players) do
        local value = "__nil"
        for _, attr in ipairs(attrNames) do
            local attrVal = p:GetAttribute(attr)
            if attrVal ~= nil then
                value = tostring(attrVal)
                break
            end
        end
        partitions.Attribute[p] = value
    end
    
    -- Método 4: Team Resolvers customizados
    for idx, resolver in ipairs(self.Heuristics.TeamResolvers) do
        local result = SafeCallReturn(function()
            return resolver(players)
        end, "TeamResolver_" .. idx)
        
        if result and type(result) == "table" then
            partitions["CustomResolver_" .. idx] = result
        end
    end
    
    -- Avalia cada método
    local bestMethod = nil
    local bestScore = 0
    local bestPartition = nil
    
    for method, partition in pairs(partitions) do
        local score = self:ScorePartition(partition)
        if score > bestScore then
            bestScore = score
            bestMethod = method
            bestPartition = partition
        end
    end
    
    -- Threshold dinâmico baseado em número de jogadores
    local threshold = 10 + (#players * 0.5)
    
    if bestMethod and bestScore > threshold then
        self.TeamSystem.Method = bestMethod
        self.TeamSystem.CurrentPartition = bestPartition
        self.TeamSystem.ForceFFA = false
        DebugLog("Team system detected:", bestMethod, "score:", bestScore)
    else
        self.TeamSystem.Method = "FFA"
        self.TeamSystem.CurrentPartition = {}
        self.TeamSystem.ForceFFA = true
        DebugLog("FFA mode (no valid team system)")
    end
    
    self.TeamSystem.AutoDetected = true
    self.TeamSystem.LastCheck = tick()
    
    FireEvent("TeamDetected", self.TeamSystem.Method, self.TeamSystem.ForceFFA)
end

function SemanticEngine:ScorePartition(partition)
    local groups = {}
    local playerCount = 0
    local nilCount = 0
    
    for player, key in pairs(partition) do
        playerCount = playerCount + 1
        if key == "__nil" then
            nilCount = nilCount + 1
        else
            groups[key] = (groups[key] or 0) + 1
        end
    end
    
    local groupCount = 0
    local maxSize = 0
    local minSize = math.huge
    
    for _, count in pairs(groups) do
        groupCount = groupCount + 1
        maxSize = math.max(maxSize, count)
        minSize = math.min(minSize, count)
    end
    
    -- Precisa de 2-8 grupos
    if groupCount < 2 or groupCount > 8 then
        return 0
    end
    
    -- Score baseado em balanceamento e cobertura
    local balance = minSize / math.max(maxSize, 1)
    local coverage = (playerCount - nilCount) / math.max(playerCount, 1)
    
    return groupCount * balance * coverage * 100
end

function SemanticEngine:AutoDetectTeamSystem()
    local now = tick()
    local interval = self.Config.TeamCheckInterval or self.TeamSystem.CheckInterval
    
    if (now - self.TeamSystem.LastCheck) < interval then
        return
    end
    
    self:DetectTeamSystemWithVoting()
end

function SemanticEngine:GetPlayerTeam(player)
    if not player then return nil end
    
    if self.TeamSystem.ForceFFA then
        return nil
    end
    
    -- Atualiza se necessário
    if not self.TeamSystem.AutoDetected then
        self:DetectTeamSystemWithVoting()
    end
    
    if self.TeamSystem.CurrentPartition then
        local team = self.TeamSystem.CurrentPartition[player]
        if team and team ~= "__nil" then
            return team
        end
    end
    
    -- Fallback: Team padrão
    if player.Team then
        return player.Team.Name
    end
    
    return nil
end

function SemanticEngine:AreSameTeam(player1, player2)
    if not player1 or not player2 then return false end
    if player1 == player2 then return true end
    
    if self.TeamSystem.ForceFFA then
        return false
    end
    
    local team1 = self:GetPlayerTeam(player1)
    local team2 = self:GetPlayerTeam(player2)
    
    if not team1 or not team2 then
        -- Fallback: Roblox Team
        if player1.Team and player2.Team then
            return player1.Team == player2.Team
        end
        return false
    end
    
    return tostring(team1):lower() == tostring(team2):lower()
end

-- ============================================================================
-- CONTAINER SCANNING (MELHORADO)
-- ============================================================================
function SemanticEngine:ScanForContainers()
    local now = tick()
    local interval = self.Config.ContainerScanInterval or self.ContainerSystem.ScanInterval
    
    if (now - self.ContainerSystem.LastScan) < interval then
        return
    end
    
    self.ContainerSystem.LastScan = now
    
    -- 1. Valida containers registrados manualmente
    for container, info in pairs(self.ContainerSystem.RegisteredContainers) do
        if container and container.Parent then
            -- Valida: tem modelos com humanoids?
            local validChildren = 0
            for _, child in ipairs(container:GetChildren()) do
                if child:IsA("Model") then
                    validChildren = validChildren + 1
                end
            end
            
            if validChildren > 0 then
                self.ContainerSystem.KnownContainers[container] = {
                    name = info.name,
                    found = now,
                    childCount = validChildren,
                }
            end
        end
    end
    
    -- 2. Scan por nomes conhecidos
    local containerNames = self.Config.ContainerNames or {}
    
    for _, name in ipairs(containerNames) do
        SafeCall(function()
            local container = Workspace:FindFirstChild(name, true)
            if container and (container:IsA("Folder") or container:IsA("Model")) then
                if not self.ContainerSystem.KnownContainers[container] then
                    -- Heurística: tem pelo menos 1 model filho?
                    local hasModels = false
                    for _, child in ipairs(container:GetChildren()) do
                        if child:IsA("Model") then
                            hasModels = true
                            break
                        end
                    end
                    
                    if hasModels then
                        self.ContainerSystem.KnownContainers[container] = {
                            name = name,
                            found = now,
                        }
                        self.Stats.ContainersFound = self.Stats.ContainersFound + 1
                        FireEvent("ContainerFound", container, name)
                        DebugLog("Container found:", name)
                    end
                end
            end
        end, "ScanContainer_" .. name)
    end
end

-- ============================================================================
-- REFRESH ALL PLAYERS (MANTIDO)
-- ============================================================================
function SemanticEngine:RefreshAllPlayers()
    DebugLog("Refreshing all players...")
    
    -- Limpa caches antigos
    PlayerCache:ClearAll()
    
    -- Re-track todos os jogadores
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            self:TrackPlayer(player)
        end
    end
    
    -- Atualiza times
    self:DetectTeamSystemWithVoting()
end

-- ============================================================================
-- GET ALL VALID PLAYERS (HELPER PARA AIMBOT - MANTIDO)
-- ============================================================================
function SemanticEngine:GetAllValidPlayers()
    local validPlayers = {}
    
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            local data = self:GetCachedPlayerData(player)
            if data and data.isValid then
                table.insert(validPlayers, {
                    player = player,
                    data = data,
                })
            end
        end
    end
    
    return validPlayers
end

-- ============================================================================
-- HITBOX CLASSIFICATION (NOVO)
-- ============================================================================
function SemanticEngine:IsHitboxPart(part)
    if not part or not part:IsA("BasePart") then return false end
    
    -- Cache hit
    if self.TargetDefinitions.HitboxParts[part] ~= nil then
        return self.TargetDefinitions.HitboxParts[part]
    end
    
    -- 1. Classifiers customizados
    for _, classifier in ipairs(self.Heuristics.HitboxClassifiers) do
        local result = SafeCallReturn(function()
            return classifier(part)
        end, "HitboxClassifier")
        
        if result == true then
            self.TargetDefinitions.HitboxParts[part] = true
            return true
        elseif result == false then
            self.TargetDefinitions.HitboxParts[part] = false
            return false
        end
    end
    
    -- 2. Padrões de nome
    local partName = part.Name:lower()
    for _, pattern in ipairs(self.Config.HitboxNamePatterns) do
        if partName:find(pattern, 1, true) then
            self.TargetDefinitions.HitboxParts[part] = true
            return true
        end
    end
    
    -- 3. Atributo customizado
    if part:GetAttribute("IsHitbox") then
        self.TargetDefinitions.HitboxParts[part] = true
        return true
    end
    
    -- Default: não é hitbox
    self.TargetDefinitions.HitboxParts[part] = false
    return false
end

-- ============================================================================
-- INITIALIZATION (MELHORADO)
-- ============================================================================
function SemanticEngine:Initialize()
    if self._initialized then 
        DebugWarn("Already initialized, call Destroy() first to reinitialize")
        return 
    end
    
    DebugLog("Initializing Semantic Engine v" .. self.Version)
    
    -- Cria eventos
    CreateEvents()
    
    -- Reinicializa tabelas fracas
    PlayerCache:ClearAll()
    self.TargetDefinitions.EntityToPlayer = WeakKeys()
    self.TargetDefinitions.PlayerToEntity = WeakKeys()
    self.TargetDefinitions.HitboxParts = WeakKeys()
    self.TargetDefinitions.CombatModels = WeakKeys()
    self._playerConnections = WeakKeys()
    
    -- Scan inicial de containers
    self:ScanForContainers()
    
    -- Detecta sistema de times
    self:DetectTeamSystemWithVoting()
    
    -- Tracka todos os jogadores existentes
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            self:TrackPlayer(player)
        end
    end
    
    -- Conecta eventos de jogadores
    local addedConn = Players.PlayerAdded:Connect(function(player)
        task.wait(0.5) -- Aguarda jogador inicializar
        self:TrackPlayer(player)
        
        -- Re-avalia times após delay
        task.delay(1, function()
            self:DetectTeamSystemWithVoting()
        end)
    end)
    table.insert(self._connections, addedConn)
    
    local removingConn = Players.PlayerRemoving:Connect(function(player)
        self:UntrackPlayer(player)
    end)
    table.insert(self._connections, removingConn)
    
    -- Loop de manutenção COM BACKOFF
    task.spawn(function()
        while self._initialized do
            local ok = SafeCall(function()
                -- Verifica jogadores que podem ter Character agora
                for _, player in ipairs(Players:GetPlayers()) do
                    if player ~= LocalPlayer then
                        local data = PlayerCache:Get(player)
                        
                        -- Se não tem dados válidos, tenta novamente
                        if not data or not data.isValid then
                            PlayerCache:Clear(player)
                            local newData = self:BuildPlayerData(player)
                            if newData.isValid then
                                PlayerCache:Set(player, newData)
                            end
                        end
                    end
                end
                
                -- Scan de containers
                self:ScanForContainers()
                
                -- Atualiza times
                self:AutoDetectTeamSystem()
            end, "MaintenanceLoop")
            
            -- Backoff exponencial em caso de erros
            if not ok then
                self._maintenanceErrorStreak = self._maintenanceErrorStreak + 1
                self.Stats.Errors = self.Stats.Errors + 1
                local delay = math.min(10, 2 * (2 ^ self._maintenanceErrorStreak))
                DebugWarn("Maintenance error, backing off for", delay, "seconds")
                task.wait(delay)
            else
                self._maintenanceErrorStreak = 0
                task.wait(2)
            end
        end
    end)
    
    self._initialized = true
    print("[Semantic] v" .. self.Version .. " Inicializado - Tracking " .. #Players:GetPlayers() .. " jogadores")
end

-- ============================================================================
-- DESTROY (NOVO - CLEANUP COMPLETO)
-- ============================================================================
function SemanticEngine:Destroy()
    DebugLog("Destroying Semantic Engine...")
    
    self._initialized = false
    
    -- Desconecta todas as conexões por player
    for player, _ in pairs(self._playerConnections) do
        ClearPlayerConnections(player)
    end
    self._playerConnections = WeakKeys()
    
    -- Desconecta conexões globais
    for _, conn in ipairs(self._connections) do
        if conn and conn.Disconnect then
            pcall(conn.Disconnect, conn)
        end
    end
    self._connections = {}
    
    -- Limpa caches
    PlayerCache:ClearAll()
    
    -- Limpa target definitions
    self.TargetDefinitions = {
        HitboxParts = WeakKeys(),
        CombatModels = WeakKeys(),
        EntityToPlayer = WeakKeys(),
        PlayerToEntity = WeakKeys(),
    }
    
    -- Limpa containers
    self.ContainerSystem.KnownContainers = WeakKeys()
    self.ContainerSystem.RegisteredContainers = WeakKeys()
    
    -- Limpa team system
    self.TeamSystem.CurrentPartition = {}
    self.TeamSystem.AutoDetected = false
    
    -- Destroy eventos
    for name, event in pairs(self.Events) do
        if event and event.Destroy then
            pcall(event.Destroy, event)
        end
    end
    self.Events = {}
    
    -- Reset stats
    self.Stats.Errors = 0
    self._maintenanceErrorStreak = 0
    
    print("[Semantic] Destroyed")
end

-- ============================================================================
-- DEBUG (MELHORADO)
-- ============================================================================
function SemanticEngine:Debug()
    print("\n========== SEMANTIC ENGINE v" .. self.Version .. " DEBUG ==========")
    print("Initialized: " .. tostring(self._initialized))
    print("Debug Mode: " .. tostring(self.Config.Debug))
    
    print("\n--- Config ---")
    for k, v in pairs(self.Config) do
        if type(v) ~= "table" then
            print("  " .. k .. ": " .. tostring(v))
        end
    end
    
    print("\n--- Team System ---")
    print("  Method: " .. self.TeamSystem.Method)
    print("  ForceFFA: " .. tostring(self.TeamSystem.ForceFFA))
    print("  AutoDetected: " .. tostring(self.TeamSystem.AutoDetected))
    
    print("\n--- Containers ---")
    local containerCount = 0
    for container, info in pairs(self.ContainerSystem.KnownContainers) do
        containerCount = containerCount + 1
        print("  " .. info.name .. " (valid: " .. tostring(container.Parent ~= nil) .. ")")
    end
    print("  Registered: " .. tostring(next(self.ContainerSystem.RegisteredContainers) ~= nil))
    print("  Total Known: " .. containerCount)
    
    print("\n--- Heuristics ---")
    print("  Anchor Resolvers: " .. #self.Heuristics.AnchorResolvers)
    print("  Team Resolvers: " .. #self.Heuristics.TeamResolvers)
    print("  Hitbox Classifiers: " .. #self.Heuristics.HitboxClassifiers)
    
    print("\n--- Player Mappings ---")
    local mappingCount = 0
    for player, entity in pairs(self.TargetDefinitions.PlayerToEntity) do
        mappingCount = mappingCount + 1
        local valid = entity and entity.Parent ~= nil
        print("  " .. player.Name .. " -> " .. (entity and entity.Name or "nil") .. " (valid: " .. tostring(valid) .. ")")
    end
    print("  Total Mappings: " .. mappingCount)
    
    print("\n--- Cached Player Data ---")
    local cacheCount = 0
    for player, data in pairs(PlayerCache.Data) do
        cacheCount = cacheCount + 1
        print(string.format("  %s: valid=%s, anchor=%s, age=%.2fs",
            player.Name,
            tostring(data.isValid),
            data.anchor and data.anchor.Name or "nil",
            tick() - data.lastUpdate
        ))
    end
    print("  Total Cached: " .. cacheCount)
    
    print("\n--- Stats ---")
    print("  Entities Learned: " .. self.Stats.EntitiesLearned)
    print("  Containers Found: " .. self.Stats.ContainersFound)
    print("  Players Tracked: " .. self.Stats.PlayersTracked)
    print("  Cache Hits: " .. self.Stats.CacheHits)
    print("  Cache Misses: " .. self.Stats.CacheMisses)
    print("  Errors: " .. self.Stats.Errors)
    
    print("\n--- Connections ---")
    print("  Global: " .. #self._connections)
    local playerConnCount = 0
    for _, conns in pairs(self._playerConnections) do
        playerConnCount = playerConnCount + #conns
    end
    print("  Per-Player: " .. playerConnCount)
    
    print("=============================================\n")
end

-- ============================================================================
-- DUMP STATE (NOVO - RETORNA TABELA PARA UI)
-- ============================================================================
function SemanticEngine:DumpState()
    local playerMappings = {}
    for player, entity in pairs(self.TargetDefinitions.PlayerToEntity) do
        table.insert(playerMappings, {
            playerName = player.Name,
            entityName = entity and entity.Name or "nil",
            valid = entity and entity.Parent ~= nil,
        })
    end
    
    local containers = {}
    for container, info in pairs(self.ContainerSystem.KnownContainers) do
        table.insert(containers, {
            name = info.name,
            valid = container.Parent ~= nil,
        })
    end
    
    return {
        version = self.Version,
        initialized = self._initialized,
        teamMethod = self.TeamSystem.Method,
        forceFFA = self.TeamSystem.ForceFFA,
        playerMappings = playerMappings,
        containers = containers,
        stats = {
            entitiesLearned = self.Stats.EntitiesLearned,
            containersFound = self.Stats.ContainersFound,
            playersTracked = self.Stats.PlayersTracked,
            cacheHits = self.Stats.CacheHits,
            cacheMisses = self.Stats.CacheMisses,
            errors = self.Stats.Errors,
        },
        heuristics = {
            anchorResolvers = #self.Heuristics.AnchorResolvers,
            teamResolvers = #self.Heuristics.TeamResolvers,
            hitboxClassifiers = #self.Heuristics.HitboxClassifiers,
        },
    }
end

-- ============================================================================
-- COMPATIBILITY REPORT (NOVO)
-- ============================================================================
function SemanticEngine:CompatibilityReport()
    return {
        version = self.Version,
        breakingChanges = {},
        newFeatures = {
            "Destroy() method for cleanup",
            "RegisterAnchorHeuristic(fn) API",
            "RegisterTeamResolver(fn) API",
            "RegisterHitboxClassifier(fn) API",
            "RegisterContainer(container) API",
            "Config table for runtime configuration",
            "Events table for hooks (PlayerTracked, PlayerUntracked, etc)",
            "DumpState() returns table for UI",
            "IsHitboxPart(part) classifier",
            "Weak tables for automatic GC",
            "Adaptive cache TTL",
            "Deterministic stagger",
            "Exponential backoff on errors",
        },
        deprecatedFeatures = {},
        maintainedFunctions = {
            "TrackPlayer", "UntrackPlayer", "LinkPlayerToEntity",
            "FindEntityForPlayer", "GetCachedPlayerData", "BuildPlayerData",
            "GetAnchorPart", "ClearPlayerCache", "ClearAllCache",
            "DetectTeamSystemWithVoting", "ScorePartition", "AutoDetectTeamSystem",
            "GetPlayerTeam", "AreSameTeam", "ScanForContainers",
            "RefreshAllPlayers", "GetAllValidPlayers", "Initialize", "Debug",
        },
    }
end

-- ============================================================================
-- EXPORT
-- ============================================================================
Core.SemanticEngine = SemanticEngine
Core.PlayerCache = PlayerCache

return SemanticEngine