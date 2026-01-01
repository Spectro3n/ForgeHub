-- ============================================================================
-- FORGEHUB - SEMANTIC ENGINE MODULE
-- ============================================================================

local Core = _G.ForgeHubCore
if not Core then
    error("ForgeHubCore não encontrado! Carregue main.lua primeiro.")
end

local SafeCall = Core.SafeCall
local Players = Core.Players
local Workspace = Core.Workspace
local LocalPlayer = Core.LocalPlayer

-- ============================================================================
-- SEMANTIC ENGINE
-- ============================================================================
local SemanticEngine = {
    TargetDefinitions = {
        HitboxParts = {},
        CombatModels = {},
        EntityToPlayer = {},
    },
    
    TeamSystem = {
        Method = "Unknown",
        CurrentPartition = nil,
        ForceFFA = false,
        AutoDetected = false,
        LastCheck = 0,
    },
    
    ContainerSystem = {
        KnownContainers = {},
        LastScan = 0,
        ScanInterval = 5,
    },
    
    IncrementalScan = {
        Queue = {},
        ProcessedIndex = 0,
        ObjectsPerTick = 20,
        LastTick = 0,
        TickInterval = 0.1,
        Completed = false,
    },
    
    Stats = {
        DamageEventsDetected = 0,
        EntitiesLearned = 0,
        ContainersFound = 0,
        ScansCompleted = 0,
    },
    
    _initialized = false,
}

-- ============================================================================
-- PLAYER CACHE
-- ============================================================================
local PlayerCache = {}
local _cacheStagger = 0

function SemanticEngine:GetCachedPlayerData(player)
    local now = tick()
    local data = PlayerCache[player]
    
    if not data then
        _cacheStagger = (_cacheStagger + 0.1) % 1.0
    end
    
    local cacheTime = 0.25 + (_cacheStagger or 0)
    
    if data and now - data.lastUpdate < cacheTime then
        return data
    end
    
    local model = self:FindRealTarget(player)
    local anchor = nil
    local humanoid = nil
    local team = self:GetPlayerTeam(player)
    
    if model then
        anchor = self:GetPlayerAnchor(player, model)
        humanoid = model:FindFirstChildOfClass("Humanoid")
    end
    
    data = {
        model = model,
        anchor = anchor,
        team = team,
        humanoid = humanoid,
        lastUpdate = now,
        isValid = model ~= nil and anchor ~= nil,
    }
    
    PlayerCache[player] = data
    return data
end

function SemanticEngine:ClearPlayerCache(player)
    if not player then return end
    PlayerCache[player] = nil
end

-- ============================================================================
-- INCREMENTAL SCAN
-- ============================================================================
function SemanticEngine:InitializeIncrementalScan()
    self.IncrementalScan.Queue = {}
    self.IncrementalScan.ProcessedIndex = 0
    self.IncrementalScan.Completed = false
    
    local priorityContainers = {
        Workspace,
        game.ReplicatedStorage,
    }
    
    for _, container in ipairs(priorityContainers) do
        SafeCall(function()
            for _, child in ipairs(container:GetChildren()) do
                table.insert(self.IncrementalScan.Queue, child)
            end
        end, "InitScan")
    end
    
    for container, _ in pairs(self.ContainerSystem.KnownContainers) do
        if container and container.Parent then
            SafeCall(function()
                for _, child in ipairs(container:GetChildren()) do
                    table.insert(self.IncrementalScan.Queue, child)
                end
            end, "InitScan")
        end
    end
end

function SemanticEngine:ProcessIncrementalScan()
    local now = tick()
    if now - self.IncrementalScan.LastTick < self.IncrementalScan.TickInterval then
        return
    end
    
    self.IncrementalScan.LastTick = now
    
    local queue = self.IncrementalScan.Queue
    local startIndex = self.IncrementalScan.ProcessedIndex + 1
    local endIndex = math.min(startIndex + self.IncrementalScan.ObjectsPerTick - 1, #queue)
    
    if startIndex > #queue then
        if not self.IncrementalScan.Completed then
            self.IncrementalScan.Completed = true
            self.Stats.ScansCompleted = self.Stats.ScansCompleted + 1
        end
        return
    end
    
    for i = startIndex, endIndex do
        local obj = queue[i]
        if obj and obj.Parent then
            self:LearnFromObject(obj)
        end
    end
    
    self.IncrementalScan.ProcessedIndex = endIndex
end

function SemanticEngine:LearnFromObject(obj)
    SafeCall(function()
        if obj:IsA("Model") then
            local humanoid = obj:FindFirstChildOfClass("Humanoid")
            if humanoid then
                self.TargetDefinitions.CombatModels[obj] = true
                self.Stats.EntitiesLearned = self.Stats.EntitiesLearned + 1
                
                local linkedPlayer = self:GetPlayerFromModel(obj)
                if linkedPlayer then
                    self.TargetDefinitions.EntityToPlayer[obj] = linkedPlayer
                end
            end
        end
        
        if obj:IsA("BasePart") then
            local name = obj.Name:lower()
            if name:match("hitbox") or name:match("hit") or name:match("damage") then
                self.TargetDefinitions.HitboxParts[obj] = true
            end
        end
    end, "LearnFromObject")
end

-- ============================================================================
-- CONTINUOUS LEARNING
-- ============================================================================
function SemanticEngine:StartContinuousLearning()
    local connections = Core.State.Connections
    local remotes = {}
    local containers = {game.ReplicatedStorage}
    
    for _, container in ipairs(containers) do
        SafeCall(function()
            for _, obj in ipairs(container:GetDescendants()) do
                if obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction") then
                    local name = obj.Name:lower()
                    
                    if name:match("damage") or name:match("hit") or name:match("attack") 
                       or name:match("combat") or name:match("health") then
                        table.insert(remotes, obj)
                    end
                end
            end
        end, "FindRemotes")
    end
    
    for _, remote in ipairs(remotes) do
        SafeCall(function()
            if remote:IsA("RemoteEvent") then
                local connection = remote.OnClientEvent:Connect(function(...)
                    self:LearnFromCombatEvent(remote, {...})
                end)
                table.insert(connections, connection)
            end
        end, "ConnectRemote")
    end
end

function SemanticEngine:LearnFromCombatEvent(remote, args)
    self.Stats.DamageEventsDetected = self.Stats.DamageEventsDetected + 1
    
    for _, arg in ipairs(args) do
        if typeof(arg) == "Instance" then
            if arg:IsA("Model") then
                self.TargetDefinitions.CombatModels[arg] = true
                self.Stats.EntitiesLearned = self.Stats.EntitiesLearned + 1
                
                local linkedPlayer = self:GetPlayerFromModel(arg)
                if linkedPlayer then
                    self.TargetDefinitions.EntityToPlayer[arg] = linkedPlayer
                end
            end
            
            if arg:IsA("BasePart") then
                self.TargetDefinitions.HitboxParts[arg] = true
                
                local model = arg:FindFirstAncestorOfClass("Model")
                if model then
                    self.TargetDefinitions.CombatModels[model] = true
                    self.Stats.EntitiesLearned = self.Stats.EntitiesLearned + 1
                end
            end
        end
    end
end

-- ============================================================================
-- CONTAINER SCANNING
-- ============================================================================
function SemanticEngine:ScanForContainers()
    local now = tick()
    if now - self.ContainerSystem.LastScan < self.ContainerSystem.ScanInterval then
        return
    end
    
    self.ContainerSystem.LastScan = now
    
    local containerNames = {
        "Characters", "Players", "Entities", "Alive", "InGame", "ActivePlayers", 
        "NPCs", "Enemies", "Bots", "Units", "Team1", "Team2", "Arena"
    }
    
    for _, name in ipairs(containerNames) do
        SafeCall(function()
            local container = Workspace:FindFirstChild(name)
            if container and (container:IsA("Folder") or container:IsA("Model")) then
                if not self.ContainerSystem.KnownContainers[container] then
                    self.ContainerSystem.KnownContainers[container] = {
                        name = name,
                        found = now,
                    }
                    self.Stats.ContainersFound = self.Stats.ContainersFound + 1
                end
            end
        end, "ScanContainers")
    end
end

-- ============================================================================
-- TEAM SYSTEM
-- ============================================================================
function SemanticEngine:ScorePartition(partition)
    local groups = {}
    local playerCount = 0
    
    for player, key in pairs(partition) do
        if key ~= "__nil" then
            groups[key] = (groups[key] or 0) + 1
        end
        playerCount = playerCount + 1
    end
    
    local groupCount = 0
    local maxGroupSize = 0
    local minGroupSize = math.huge
    
    for k, count in pairs(groups) do
        groupCount = groupCount + 1
        maxGroupSize = math.max(maxGroupSize, count)
        minGroupSize = math.min(minGroupSize, count)
    end
    
    if groupCount < 2 or groupCount > 8 then
        return 0
    end
    
    local balance = minGroupSize / math.max(maxGroupSize, 1)
    local coverage = (playerCount - (groups["__nil"] or 0)) / math.max(playerCount, 1)
    
    return groupCount * balance * coverage * 100
end

function SemanticEngine:DetectTeamSystemWithVoting()
    local players = Core.CachedPlayers
    if #players < 2 then
        self.TeamSystem.Method = "FFA_AutoDetected"
        self.TeamSystem.ForceFFA = true
        return
    end
    
    local partitions = {}
    
    SafeCall(function()
        local Teams = game:GetService("Teams")
        if Teams and #Teams:GetChildren() > 0 then
            partitions.RobloxTeam = {}
            for _, p in ipairs(players) do
                partitions.RobloxTeam[p] = (p.Team and p.Team.Name) or "__nil"
            end
        end
    end, "DetectTeams")
    
    partitions.Attribute = {}
    for _, p in ipairs(players) do
        local value = "__nil"
        for _, attr in ipairs({"Team", "TeamName", "Faction", "Side"}) do
            local attrVal = p:GetAttribute(attr)
            if attrVal then
                value = tostring(attrVal)
                break
            end
        end
        partitions.Attribute[p] = value
    end
    
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
    
    if bestMethod and bestScore > 10 then
        self.TeamSystem.Method = bestMethod
        self.TeamSystem.CurrentPartition = bestPartition
        self.TeamSystem.ForceFFA = false
        self.TeamSystem.AutoDetected = true
    else
        self.TeamSystem.Method = "FFA_AutoDetected"
        self.TeamSystem.ForceFFA = true
        self.TeamSystem.AutoDetected = true
    end
end

function SemanticEngine:AutoDetectTeamSystem()
    local now = tick()
    if now - self.TeamSystem.LastCheck < 5 then
        return
    end
    
    self.TeamSystem.LastCheck = now
    self:DetectTeamSystemWithVoting()
end

function SemanticEngine:GetPlayerTeam(player)
    if not player or self.TeamSystem.ForceFFA then
        return nil
    end
    
    if self.TeamSystem.CurrentPartition then
        return self.TeamSystem.CurrentPartition[player]
    end
    
    return nil
end

function SemanticEngine:AreSameTeam(player1, player2)
    if self.TeamSystem.ForceFFA then
        return false
    end
    
    local team1 = self:GetPlayerTeam(player1)
    local team2 = self:GetPlayerTeam(player2)
    
    if not team1 or not team2 then
        return false
    end
    
    return tostring(team1):lower() == tostring(team2):lower()
end

-- ============================================================================
-- TARGET FINDING
-- ============================================================================
function SemanticEngine:FindRealTarget(player)
    for entity, linkedPlayer in pairs(self.TargetDefinitions.EntityToPlayer) do
        if entity and entity.Parent and linkedPlayer == player then
            return entity
        end
    end
    
    if player.Character and player.Character.Parent then
        return player.Character
    end
    
    for container, _ in pairs(self.ContainerSystem.KnownContainers) do
        if container and container.Parent then
            local model = container:FindFirstChild(player.Name)
            if model and model:IsA("Model") then
                self.TargetDefinitions.EntityToPlayer[model] = player
                return model
            end
        end
    end
    
    local possibleProxy = Workspace:FindFirstChild(player.Name)
    if possibleProxy and possibleProxy:IsA("Model") then
        self.TargetDefinitions.EntityToPlayer[possibleProxy] = player
        return possibleProxy
    end
    
    return nil
end

function SemanticEngine:GetPlayerFromModel(model)
    if not model then return nil end
    
    if self.TargetDefinitions.EntityToPlayer[model] then
        return self.TargetDefinitions.EntityToPlayer[model]
    end
    
    for _, player in ipairs(Core.CachedPlayers) do
        if player.Character == model then
            self.TargetDefinitions.EntityToPlayer[model] = player
            return player
        end
    end
    
    return nil
end

function SemanticEngine:FindRealHitbox(model)
    if not model then return nil end
    
    for part, _ in pairs(self.TargetDefinitions.HitboxParts) do
        if part and part:IsDescendantOf(model) then
            return part
        end
    end
    
    return self:FindRootPart(model)
end

function SemanticEngine:FindRootPart(model)
    if not model then return nil end
    
    local candidates = {
        "HumanoidRootPart",
        "Torso", 
        "UpperTorso",
        "Root",
    }
    
    for _, name in ipairs(candidates) do
        local part = model:FindFirstChild(name)
        if part and part:IsA("BasePart") then
            return part
        end
    end
    
    if model.PrimaryPart then
        return model.PrimaryPart
    end
    
    local humanoid = model:FindFirstChildOfClass("Humanoid")
    if humanoid and humanoid.RootPart then
        return humanoid.RootPart
    end
    
    return nil
end

function SemanticEngine:GetPlayerAnchor(player, model)
    model = model or self:FindRealTarget(player)
    if not model then return nil end
    
    local hitbox = self:FindRealHitbox(model)
    if hitbox and hitbox:IsA("BasePart") then
        return hitbox
    end
    
    local root = self:FindRootPart(model)
    if root and root:IsA("BasePart") then
        return root
    end
    
    return nil
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================
function SemanticEngine:Initialize()
    if self._initialized then return end
    
    SafeCall(function()
        self:InitializeIncrementalScan()
        self:StartContinuousLearning()
        self:DetectTeamSystemWithVoting()
        self:ScanForContainers()
        
        self._initialized = true
        
        -- Acelerar scan inicial
        local originalObjectsPerTick = self.IncrementalScan.ObjectsPerTick
        local originalTickInterval = self.IncrementalScan.TickInterval
        
        self.IncrementalScan.ObjectsPerTick = 200
        self.IncrementalScan.TickInterval = 0.02
        
        task.delay(2, function()
            self.IncrementalScan.ObjectsPerTick = originalObjectsPerTick
            self.IncrementalScan.TickInterval = originalTickInterval
        end)
    end, "SemanticEngine:Initialize")
end

-- ============================================================================
-- BACKGROUND LOOPS
-- ============================================================================
task.spawn(function()
    while wait(SemanticEngine.IncrementalScan.TickInterval) do
        SafeCall(function()
            SemanticEngine:ProcessIncrementalScan()
        end, "IncrementalScanLoop")
    end
end)

-- ============================================================================
-- EXPORT
-- ============================================================================
Core.SemanticEngine = SemanticEngine
Core.PlayerCache = PlayerCache

return SemanticEngine