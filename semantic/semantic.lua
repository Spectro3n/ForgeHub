-- ============================================================================
-- FORGEHUB - SEMANTIC ENGINE MODULE v2.0 (FIXED)
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
-- SAFE CALL
-- ============================================================================
local function SafeCall(func, name)
    local success, err = pcall(func)
    if not success then
        warn("[Semantic] Erro em " .. (name or "unknown") .. ": " .. tostring(err))
    end
    return success
end

-- ============================================================================
-- PLAYER CACHE (MELHORADO)
-- ============================================================================
local PlayerCache = {
    Data = {},
    CacheTime = 0.15, -- Cache mais curto para detectar mudanças rápido
    StaggerOffset = {},
}

function PlayerCache:GetStagger(player)
    if not self.StaggerOffset[player] then
        self.StaggerOffset[player] = math.random() * 0.1
    end
    return self.StaggerOffset[player]
end

function PlayerCache:Get(player)
    if not player then return nil end
    
    local now = tick()
    local data = self.Data[player]
    local stagger = self:GetStagger(player)
    
    -- Cache válido?
    if data and (now - data.lastUpdate) < (self.CacheTime + stagger) then
        return data
    end
    
    return nil
end

function PlayerCache:Set(player, data)
    if not player then return end
    self.Data[player] = data
end

function PlayerCache:Clear(player)
    if player then
        self.Data[player] = nil
        self.StaggerOffset[player] = nil
    else
        self.Data = {}
        self.StaggerOffset = {}
    end
end

function PlayerCache:ClearAll()
    self.Data = {}
    self.StaggerOffset = {}
end

-- ============================================================================
-- SEMANTIC ENGINE
-- ============================================================================
local SemanticEngine = {
    -- Definições aprendidas
    TargetDefinitions = {
        HitboxParts = {},        -- part -> true
        CombatModels = {},       -- model -> true
        EntityToPlayer = {},     -- model -> player (IMPORTANTE!)
        PlayerToEntity = {},     -- player -> model (REVERSO!)
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
        KnownContainers = {},
        LastScan = 0,
        ScanInterval = 5,
    },
    
    -- Estatísticas
    Stats = {
        DamageEventsDetected = 0,
        EntitiesLearned = 0,
        ContainersFound = 0,
        PlayersTracked = 0,
    },
    
    -- Estado
    _initialized = false,
    _connections = {},
}

-- ============================================================================
-- PLAYER TRACKING (NOVO - CRUCIAL!)
-- ============================================================================
function SemanticEngine:TrackPlayer(player)
    if not player or player == LocalPlayer then return end
    
    -- Limpa cache antigo
    PlayerCache:Clear(player)
    
    -- Remove mapeamentos antigos
    self.TargetDefinitions.PlayerToEntity[player] = nil
    
    -- Procura entidade existente
    local entity = self:FindEntityForPlayer(player)
    if entity then
        self:LinkPlayerToEntity(player, entity)
    end
    
    -- Aguarda Character carregar
    if not player.Character then
        local conn
        conn = player.CharacterAdded:Connect(function(character)
            task.wait(0.1) -- Aguarda character inicializar
            PlayerCache:Clear(player)
            self:LinkPlayerToEntity(player, character)
            
            -- Observa quando character é destruído
            character.AncestryChanged:Connect(function(_, parent)
                if not parent then
                    PlayerCache:Clear(player)
                    self.TargetDefinitions.EntityToPlayer[character] = nil
                    self.TargetDefinitions.PlayerToEntity[player] = nil
                end
            end)
        end)
        table.insert(self._connections, conn)
    else
        self:LinkPlayerToEntity(player, player.Character)
    end
    
    self.Stats.PlayersTracked = self.Stats.PlayersTracked + 1
end

function SemanticEngine:UntrackPlayer(player)
    if not player then return end
    
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
end

function SemanticEngine:LinkPlayerToEntity(player, entity)
    if not player or not entity then return end
    
    self.TargetDefinitions.EntityToPlayer[entity] = player
    self.TargetDefinitions.PlayerToEntity[player] = entity
    self.TargetDefinitions.CombatModels[entity] = true
    self.Stats.EntitiesLearned = self.Stats.EntitiesLearned + 1
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
    
    -- 3. Busca em containers conhecidos
    for container, _ in pairs(self.ContainerSystem.KnownContainers) do
        if container and container.Parent then
            local found = container:FindFirstChild(player.Name)
            if found and found:IsA("Model") then
                return found
            end
        end
    end
    
    -- 4. Busca direta no Workspace
    local wsChild = Workspace:FindFirstChild(player.Name)
    if wsChild and wsChild:IsA("Model") then
        return wsChild
    end
    
    -- 5. Busca por DisplayName
    if player.DisplayName and player.DisplayName ~= player.Name then
        local displayChild = Workspace:FindFirstChild(player.DisplayName)
        if displayChild and displayChild:IsA("Model") then
            return displayChild
        end
    end
    
    return nil
end

-- ============================================================================
-- GET CACHED PLAYER DATA (REESCRITO)
-- ============================================================================
function SemanticEngine:GetCachedPlayerData(player)
    if not player then
        return { isValid = false }
    end
    
    -- Verifica cache
    local cached = PlayerCache:Get(player)
    if cached then
        return cached
    end
    
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
            lastUpdate = now,
        }
    end
    
    -- Encontra anchor (root part)
    local anchor = self:GetAnchorPart(model)
    
    -- Encontra humanoid
    local humanoid = model:FindFirstChildOfClass("Humanoid")
    
    -- Obtém time
    local team = self:GetPlayerTeam(player)
    
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
        lastUpdate = now,
    }
end

-- ============================================================================
-- GET ANCHOR PART (MELHORADO)
-- ============================================================================
function SemanticEngine:GetAnchorPart(model)
    if not model then return nil end
    
    -- Ordem de prioridade
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
    
    -- PrimaryPart
    if model.PrimaryPart and model.PrimaryPart:IsDescendantOf(workspace) then
        return model.PrimaryPart
    end
    
    -- Humanoid.RootPart
    local humanoid = model:FindFirstChildOfClass("Humanoid")
    if humanoid and humanoid.RootPart and humanoid.RootPart:IsDescendantOf(workspace) then
        return humanoid.RootPart
    end
    
    -- Qualquer BasePart
    for _, child in ipairs(model:GetChildren()) do
        if child:IsA("BasePart") and child:IsDescendantOf(workspace) then
            return child
        end
    end
    
    return nil
end

-- ============================================================================
-- CLEAR PLAYER CACHE (PÚBLICO)
-- ============================================================================
function SemanticEngine:ClearPlayerCache(player)
    PlayerCache:Clear(player)
end

function SemanticEngine:ClearAllCache()
    PlayerCache:ClearAll()
end

-- ============================================================================
-- TEAM SYSTEM
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
    local attrNames = {"Team", "TeamName", "Faction", "Side", "Squad", "Group"}
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
    
    if bestMethod and bestScore > 15 then
        self.TeamSystem.Method = bestMethod
        self.TeamSystem.CurrentPartition = bestPartition
        self.TeamSystem.ForceFFA = false
    else
        self.TeamSystem.Method = "FFA"
        self.TeamSystem.CurrentPartition = {}
        self.TeamSystem.ForceFFA = true
    end
    
    self.TeamSystem.AutoDetected = true
    self.TeamSystem.LastCheck = tick()
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
    
    -- Score baseado em balanceamento
    local balance = minSize / math.max(maxSize, 1)
    local coverage = (playerCount - nilCount) / math.max(playerCount, 1)
    
    return groupCount * balance * coverage * 100
end

function SemanticEngine:AutoDetectTeamSystem()
    local now = tick()
    if (now - self.TeamSystem.LastCheck) < self.TeamSystem.CheckInterval then
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
-- CONTAINER SCANNING
-- ============================================================================
function SemanticEngine:ScanForContainers()
    local now = tick()
    if (now - self.ContainerSystem.LastScan) < self.ContainerSystem.ScanInterval then
        return
    end
    
    self.ContainerSystem.LastScan = now
    
    local containerNames = {
        "Characters", "Players", "Entities", "Alive", "InGame", 
        "ActivePlayers", "NPCs", "Enemies", "Bots", "Units", 
        "Team1", "Team2", "Arena", "Combatants", "Fighters",
        "SpawnedPlayers", "GamePlayers", "AliveFolder",
    }
    
    for _, name in ipairs(containerNames) do
        SafeCall(function()
            local container = Workspace:FindFirstChild(name, true)
            if container and (container:IsA("Folder") or container:IsA("Model")) then
                if not self.ContainerSystem.KnownContainers[container] then
                    self.ContainerSystem.KnownContainers[container] = {
                        name = name,
                        found = now,
                    }
                    self.Stats.ContainersFound = self.Stats.ContainersFound + 1
                end
            end
        end, "ScanContainer_" .. name)
    end
end

-- ============================================================================
-- REFRESH ALL PLAYERS (NOVO!)
-- ============================================================================
function SemanticEngine:RefreshAllPlayers()
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
-- GET ALL VALID PLAYERS (HELPER PARA AIMBOT)
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
-- INITIALIZATION
-- ============================================================================
function SemanticEngine:Initialize()
    if self._initialized then return end
    
    -- Limpa estado anterior
    PlayerCache:ClearAll()
    self.TargetDefinitions.EntityToPlayer = {}
    self.TargetDefinitions.PlayerToEntity = {}
    
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
        
        -- Re-avalia times
        task.delay(1, function()
            self:DetectTeamSystemWithVoting()
        end)
    end)
    table.insert(self._connections, addedConn)
    
    local removingConn = Players.PlayerRemoving:Connect(function(player)
        self:UntrackPlayer(player)
    end)
    table.insert(self._connections, removingConn)
    
    -- Loop de manutenção
    task.spawn(function()
        while true do
            task.wait(2)
            
            SafeCall(function()
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
        end
    end)
    
    self._initialized = true
    print("[Semantic] Inicializado - Tracking " .. #Players:GetPlayers() .. " jogadores")
end

-- ============================================================================
-- DEBUG
-- ============================================================================
function SemanticEngine:Debug()
    print("\n========== SEMANTIC ENGINE DEBUG ==========")
    print("Initialized: " .. tostring(self._initialized))
    
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
    print("  Total: " .. containerCount)
    
    print("\n--- Player Mappings ---")
    for player, entity in pairs(self.TargetDefinitions.PlayerToEntity) do
        local valid = entity and entity.Parent ~= nil
        print("  " .. player.Name .. " -> " .. (entity and entity.Name or "nil") .. " (valid: " .. tostring(valid) .. ")")
    end
    
    print("\n--- Cached Player Data ---")
    for player, data in pairs(PlayerCache.Data) do
        print(string.format("  %s: valid=%s, anchor=%s, age=%.2fs",
            player.Name,
            tostring(data.isValid),
            data.anchor and data.anchor.Name or "nil",
            tick() - data.lastUpdate
        ))
    end
    
    print("\n--- Stats ---")
    print("  Entities Learned: " .. self.Stats.EntitiesLearned)
    print("  Containers Found: " .. self.Stats.ContainersFound)
    print("  Players Tracked: " .. self.Stats.PlayersTracked)
    
    print("=============================================\n")
end

-- ============================================================================
-- EXPORT
-- ============================================================================
Core.SemanticEngine = SemanticEngine
Core.PlayerCache = PlayerCache

return SemanticEngine