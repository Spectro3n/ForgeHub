-- ============================================================================
-- MODULE DEFINITION
-- ============================================================================
local SemanticEngineModule = {}
SemanticEngineModule.__index = SemanticEngineModule

-- ============================================================================
-- CONSTANTS
-- ============================================================================
local VERSION = "3.1.0"
local MODULE_NAME = "SemanticEngine"

local LOG_LEVELS = {
    NONE = 0,
    ERROR = 1,
    WARN = 2,
    INFO = 3,
    DEBUG = 4,
    TRACE = 5,
}

-- ============================================================================
-- UTILITY: DEFENSIVE HELPERS
-- ============================================================================
local Defensive = {}

function Defensive.IsInstance(value)
    return typeof(value) == "Instance"
end

function Defensive.IsPlayer(value)
    return Defensive.IsInstance(value) and value:IsA("Player")
end

function Defensive.IsModel(value)
    return Defensive.IsInstance(value) and value:IsA("Model")
end

function Defensive.IsBasePart(value)
    return Defensive.IsInstance(value) and value:IsA("BasePart")
end

function Defensive.IsValid(instance)
    if not Defensive.IsInstance(instance) then return false end
    local ok, result = pcall(function()
        return instance.Parent ~= nil
    end)
    return ok and result == true
end

function Defensive.IsDescendantOf(instance, ancestor)
    if not Defensive.IsInstance(instance) then return false end
    if not Defensive.IsInstance(ancestor) then return false end
    local ok, result = pcall(function()
        return instance:IsDescendantOf(ancestor)
    end)
    return ok and result == true
end

function Defensive.GetName(instance)
    if not Defensive.IsInstance(instance) then return "nil" end
    local ok, name = pcall(function() return instance.Name end)
    return ok and name or "unknown"
end

function Defensive.SafeGet(instance, property)
    if not Defensive.IsInstance(instance) then return nil end
    local ok, value = pcall(function() return instance[property] end)
    return ok and value or nil
end

function Defensive.SafeCall(instance, method, ...)
    if not Defensive.IsInstance(instance) then return nil end
    local fn = Defensive.SafeGet(instance, method)
    if type(fn) ~= "function" then return nil end
    local args = {...}
    local ok, result = pcall(function() return fn(instance, unpack(args)) end)
    return ok and result or nil
end

-- ============================================================================
-- UTILITY: LEVENSHTEIN DISTANCE (FUZZY STRING MATCHING)
-- ============================================================================
local function Levenshtein(a, b)
    if a == nil or b == nil then return math.huge end
    a = tostring(a):lower()
    b = tostring(b):lower()
    local la, lb = #a, #b
    if la == 0 then return lb end
    if lb == 0 then return la end
    
    local prev = {}
    for j = 0, lb do prev[j] = j end
    
    for i = 1, la do
        local cur = { [0] = i }
        for j = 1, lb do
            local cost = (a:sub(i,i) == b:sub(j,j)) and 0 or 1
            cur[j] = math.min(prev[j] + 1, cur[j-1] + 1, prev[j-1] + cost)
        end
        prev = cur
    end
    return prev[lb]
end

-- Normalized similarity (0 to 1, where 1 = identical)
local function FuzzySimilarity(a, b)
    if not a or not b then return 0 end
    local distance = Levenshtein(a, b)
    local maxLen = math.max(#tostring(a), #tostring(b))
    if maxLen == 0 then return 1 end
    return 1 - (distance / maxLen)
end

-- Find best fuzzy match from a list
local function FuzzyFindBest(target, candidates, threshold)
    threshold = threshold or 0.7
    local bestMatch, bestScore = nil, 0
    
    for _, candidate in ipairs(candidates) do
        local name = type(candidate) == "string" and candidate or Defensive.GetName(candidate)
        local score = FuzzySimilarity(target, name)
        if score > bestScore and score >= threshold then
            bestScore = score
            bestMatch = candidate
        end
    end
    
    return bestMatch, bestScore
end

-- ============================================================================
-- UTILITY: WEAK TABLES
-- ============================================================================
local function WeakKeys()
    return setmetatable({}, { __mode = "k" })
end

local function WeakValues()
    return setmetatable({}, { __mode = "v" })
end

-- ============================================================================
-- UTILITY: RATE LIMITER
-- ============================================================================
local RateLimiter = {}
RateLimiter.__index = RateLimiter

function RateLimiter.new(minInterval)
    return setmetatable({
        minInterval = minInterval or 0.1,
        lastCall = 0,
        callCount = 0,
    }, RateLimiter)
end

function RateLimiter:CanCall(now)
    now = now or tick()
    return (now - self.lastCall) >= self.minInterval
end

function RateLimiter:Call(now)
    now = now or tick()
    self.lastCall = now
    self.callCount = self.callCount + 1
end

function RateLimiter:Reset()
    self.lastCall = 0
    self.callCount = 0
end

-- ============================================================================
-- UTILITY: THROTTLE/DEBOUNCE
-- ============================================================================
local Throttle = {}

function Throttle.new(interval, timeProvider)
    return {
        interval = interval,
        lastExec = 0,
        timeProvider = timeProvider or tick,
    }
end

function Throttle.execute(state, fn)
    local now = state.timeProvider()
    if (now - state.lastExec) >= state.interval then
        state.lastExec = now
        return fn()
    end
    return nil
end

-- ============================================================================
-- UTILITY: VECTOR MATH HELPERS
-- ============================================================================
local VectorUtils = {}

function VectorUtils.Distance3D(pos1, pos2)
    if not pos1 or not pos2 then return math.huge end
    
    local x1, y1, z1, x2, y2, z2
    
    -- Handle Vector3 or table
    if typeof(pos1) == "Vector3" then
        x1, y1, z1 = pos1.X, pos1.Y, pos1.Z
    elseif type(pos1) == "table" then
        x1, y1, z1 = pos1.X or pos1[1] or 0, pos1.Y or pos1[2] or 0, pos1.Z or pos1[3] or 0
    else
        return math.huge
    end
    
    if typeof(pos2) == "Vector3" then
        x2, y2, z2 = pos2.X, pos2.Y, pos2.Z
    elseif type(pos2) == "table" then
        x2, y2, z2 = pos2.X or pos2[1] or 0, pos2.Y or pos2[2] or 0, pos2.Z or pos2[3] or 0
    else
        return math.huge
    end
    
    return math.sqrt((x2-x1)^2 + (y2-y1)^2 + (z2-z1)^2)
end

function VectorUtils.DistanceSquared3D(pos1, pos2)
    if not pos1 or not pos2 then return math.huge end
    
    local x1, y1, z1, x2, y2, z2
    
    if typeof(pos1) == "Vector3" then
        x1, y1, z1 = pos1.X, pos1.Y, pos1.Z
    elseif type(pos1) == "table" then
        x1, y1, z1 = pos1.X or 0, pos1.Y or 0, pos1.Z or 0
    else
        return math.huge
    end
    
    if typeof(pos2) == "Vector3" then
        x2, y2, z2 = pos2.X, pos2.Y, pos2.Z
    elseif type(pos2) == "table" then
        x2, y2, z2 = pos2.X or 0, pos2.Y or 0, pos2.Z or 0
    else
        return math.huge
    end
    
    return (x2-x1)^2 + (y2-y1)^2 + (z2-z1)^2
end

-- ============================================================================
-- ADAPTERS: INTERFACE DEFINITIONS
-- ============================================================================
local AdapterInterface = {
    GetPlayers = function() end,
    GetLocalPlayer = function() end,
    GetWorkspace = function() end,
    FindFirstChild = function() end,
    GetChildren = function() end,
    GetDescendants = function() end,
    IsA = function() end,
    GetAttribute = function() end,
    ConnectEvent = function() end,
    Now = function() end,
    Wait = function() end,
    Spawn = function() end,
    Delay = function() end,
}

-- ============================================================================
-- ADAPTER: ROBLOX (DEFAULT)
-- ============================================================================
local RobloxAdapter = {}
RobloxAdapter.__index = RobloxAdapter

function RobloxAdapter.new(overrides)
    local self = setmetatable({}, RobloxAdapter)
    
    overrides = overrides or {}
    
    self._Players = overrides.Players or game:GetService("Players")
    self._Workspace = overrides.Workspace or game:GetService("Workspace")
    self._RunService = overrides.RunService or game:GetService("RunService")
    self._Teams = nil
    
    return self
end

function RobloxAdapter:GetPlayers()
    local ok, players = pcall(function()
        return self._Players:GetPlayers()
    end)
    return ok and players or {}
end

function RobloxAdapter:GetLocalPlayer()
    local ok, player = pcall(function()
        return self._Players.LocalPlayer
    end)
    return ok and player or nil
end

function RobloxAdapter:GetWorkspace()
    return self._Workspace
end

function RobloxAdapter:GetTeams()
    if not self._Teams then
        local ok, teams = pcall(function()
            return game:GetService("Teams")
        end)
        self._Teams = ok and teams or nil
    end
    return self._Teams
end

function RobloxAdapter:FindFirstChild(parent, name, recursive)
    if not Defensive.IsInstance(parent) then return nil end
    local ok, child = pcall(function()
        return parent:FindFirstChild(name, recursive or false)
    end)
    return ok and child or nil
end

function RobloxAdapter:FindFirstChildOfClass(parent, className)
    if not Defensive.IsInstance(parent) then return nil end
    local ok, child = pcall(function()
        return parent:FindFirstChildOfClass(className)
    end)
    return ok and child or nil
end

function RobloxAdapter:GetChildren(instance)
    if not Defensive.IsInstance(instance) then return {} end
    local ok, children = pcall(function()
        return instance:GetChildren()
    end)
    return ok and children or {}
end

function RobloxAdapter:GetDescendants(instance)
    if not Defensive.IsInstance(instance) then return {} end
    local ok, descendants = pcall(function()
        return instance:GetDescendants()
    end)
    return ok and descendants or {}
end

function RobloxAdapter:IsA(instance, className)
    if not Defensive.IsInstance(instance) then return false end
    local ok, result = pcall(function()
        return instance:IsA(className)
    end)
    return ok and result or false
end

function RobloxAdapter:GetAttribute(instance, name)
    if not Defensive.IsInstance(instance) then return nil end
    local ok, value = pcall(function()
        return instance:GetAttribute(name)
    end)
    return ok and value or nil
end

function RobloxAdapter:ConnectEvent(event, callback)
    if not event or type(callback) ~= "function" then return nil end
    local ok, connection = pcall(function()
        return event:Connect(callback)
    end)
    return ok and connection or nil
end

function RobloxAdapter:Now()
    return tick()
end

function RobloxAdapter:Wait(seconds)
    task.wait(seconds or 0)
end

function RobloxAdapter:Spawn(fn)
    if type(fn) == "function" then
        task.spawn(fn)
    end
end

function RobloxAdapter:Delay(seconds, fn)
    if type(fn) == "function" then
        task.delay(seconds or 0, fn)
    end
end

function RobloxAdapter:CreateBindableEvent()
    local ok, event = pcall(function()
        return Instance.new("BindableEvent")
    end)
    return ok and event or nil
end

-- ============================================================================
-- ADAPTER: MOCK (FOR TESTING)
-- ============================================================================
local MockAdapter = {}
MockAdapter.__index = MockAdapter

function MockAdapter.new(config)
    local self = setmetatable({}, MockAdapter)
    
    config = config or {}
    
    self._time = config.startTime or 0
    self._players = config.players or {}
    self._localPlayer = config.localPlayer or nil
    self._workspace = config.workspace or { Name = "Workspace", Parent = true }
    self._events = {}
    self._spawnedFunctions = {}
    self._delayedFunctions = {}
    
    return self
end

function MockAdapter:GetPlayers()
    return self._players
end

function MockAdapter:GetLocalPlayer()
    return self._localPlayer
end

function MockAdapter:GetWorkspace()
    return self._workspace
end

function MockAdapter:GetTeams()
    return nil
end

function MockAdapter:FindFirstChild(parent, name, recursive)
    if not parent or not parent.Children then return nil end
    for _, child in ipairs(parent.Children or {}) do
        if child.Name == name then
            return child
        end
        if recursive and child.Children then
            local found = self:FindFirstChild(child, name, true)
            if found then return found end
        end
    end
    return nil
end

function MockAdapter:FindFirstChildOfClass(parent, className)
    if not parent or not parent.Children then return nil end
    for _, child in ipairs(parent.Children or {}) do
        if child.ClassName == className then
            return child
        end
    end
    return nil
end

function MockAdapter:GetChildren(instance)
    return instance and instance.Children or {}
end

function MockAdapter:GetDescendants(instance)
    local result = {}
    local function collect(inst)
        for _, child in ipairs(inst.Children or {}) do
            table.insert(result, child)
            collect(child)
        end
    end
    if instance then collect(instance) end
    return result
end

function MockAdapter:IsA(instance, className)
    if not instance then return false end
    return instance.ClassName == className or instance.IsA == className
end

function MockAdapter:GetAttribute(instance, name)
    if not instance or not instance.Attributes then return nil end
    return instance.Attributes[name]
end

function MockAdapter:ConnectEvent(event, callback)
    local id = #self._events + 1
    self._events[id] = { event = event, callback = callback, connected = true }
    return {
        Disconnect = function()
            if self._events[id] then
                self._events[id].connected = false
            end
        end
    }
end

function MockAdapter:Now()
    return self._time
end

function MockAdapter:SetTime(t)
    self._time = t
end

function MockAdapter:AdvanceTime(delta)
    self._time = self._time + delta
    local toExecute = {}
    for i, item in ipairs(self._delayedFunctions) do
        if item.executeAt <= self._time then
            table.insert(toExecute, item)
            self._delayedFunctions[i] = nil
        end
    end
    for _, item in ipairs(toExecute) do
        item.fn()
    end
end

function MockAdapter:Wait(seconds)
    self._time = self._time + (seconds or 0)
end

function MockAdapter:Spawn(fn)
    if type(fn) == "function" then
        table.insert(self._spawnedFunctions, fn)
    end
end

function MockAdapter:Delay(seconds, fn)
    if type(fn) == "function" then
        table.insert(self._delayedFunctions, {
            executeAt = self._time + (seconds or 0),
            fn = fn,
        })
    end
end

function MockAdapter:ExecuteSpawned()
    local fns = self._spawnedFunctions
    self._spawnedFunctions = {}
    for _, fn in ipairs(fns) do
        fn()
    end
end

function MockAdapter:CreateBindableEvent()
    local callbacks = {}
    return {
        Event = {
            Connect = function(_, cb)
                table.insert(callbacks, cb)
                return { Disconnect = function() end }
            end
        },
        Fire = function(_, ...)
            for _, cb in ipairs(callbacks) do
                cb(...)
            end
        end,
        Destroy = function() callbacks = {} end,
    }
end

function MockAdapter.CreateMockPlayer(config)
    config = config or {}
    return {
        Name = config.Name or "MockPlayer",
        DisplayName = config.DisplayName or config.Name or "MockPlayer",
        UserId = config.UserId or math.random(1, 999999),
        Team = config.Team,
        TeamColor = config.TeamColor,
        Character = config.Character,
        Attributes = config.Attributes or {},
        ClassName = "Player",
        IsA = "Player",
        Parent = true,
        GetAttribute = function(self, name)
            return self.Attributes[name]
        end,
        CharacterAdded = {
            Connect = function(_, cb)
                return { Disconnect = function() end }
            end
        },
    }
end

function MockAdapter.CreateMockCharacter(config)
    config = config or {}
    
    local humanoid = {
        Name = "Humanoid",
        ClassName = "Humanoid",
        Health = config.Health or 100,
        MaxHealth = config.MaxHealth or 100,
        RootPart = nil,
        Died = { Connect = function(_, cb) return { Disconnect = function() end } end },
    }
    
    local rootPart = {
        Name = "HumanoidRootPart",
        ClassName = "BasePart",
        IsA = "BasePart",
        Size = { X = 2, Y = 2, Z = 1 },
        Position = config.Position or { X = 0, Y = 5, Z = 0 },
        Parent = true,
    }
    
    humanoid.RootPart = rootPart
    
    local character = {
        Name = config.Name or "MockCharacter",
        ClassName = "Model",
        IsA = "Model",
        Parent = true,
        PrimaryPart = rootPart,
        Children = {
            humanoid,
            rootPart,
            { Name = "Head", ClassName = "BasePart", IsA = "BasePart", Size = { X = 1, Y = 1, Z = 1 }, Parent = true },
            { Name = "Torso", ClassName = "BasePart", IsA = "BasePart", Size = { X = 2, Y = 2, Z = 1 }, Parent = true },
        },
        AncestryChanged = { Connect = function(_, cb) return { Disconnect = function() end } end },
    }
    
    for _, child in ipairs(character.Children) do
        child.Parent = character
    end
    
    return character, humanoid, rootPart
end

-- ============================================================================
-- LOGGER: STRUCTURED LOGGING
-- ============================================================================
local Logger = {}
Logger.__index = Logger

function Logger.new(config)
    local self = setmetatable({}, Logger)
    
    config = config or {}
    
    self.level = config.level or LOG_LEVELS.WARN
    self.prefix = config.prefix or "[Semantic]"
    self.history = {}
    self.maxHistory = config.maxHistory or 100
    self.outputFn = config.outputFn or print
    self.warnFn = config.warnFn or warn
    
    return self
end

function Logger:SetLevel(level)
    if type(level) == "string" then
        self.level = LOG_LEVELS[level:upper()] or LOG_LEVELS.WARN
    else
        self.level = level or LOG_LEVELS.WARN
    end
end

function Logger:_log(level, levelName, ...)
    if level > self.level then return end
    
    local message = table.concat({...}, " ")
    local entry = {
        time = os.time(),
        level = levelName,
        message = message,
    }
    
    table.insert(self.history, entry)
    if #self.history > self.maxHistory then
        table.remove(self.history, 1)
    end
    
    local formatted = string.format("%s [%s] %s", self.prefix, levelName, message)
    if level <= LOG_LEVELS.WARN then
        self.warnFn(formatted)
    else
        self.outputFn(formatted)
    end
end

function Logger:Error(...) self:_log(LOG_LEVELS.ERROR, "ERROR", ...) end
function Logger:Warn(...) self:_log(LOG_LEVELS.WARN, "WARN", ...) end
function Logger:Info(...) self:_log(LOG_LEVELS.INFO, "INFO", ...) end
function Logger:Debug(...) self:_log(LOG_LEVELS.DEBUG, "DEBUG", ...) end
function Logger:Trace(...) self:_log(LOG_LEVELS.TRACE, "TRACE", ...) end

function Logger:GetHistory()
    return self.history
end

function Logger:Clear()
    self.history = {}
end

-- ============================================================================
-- METRICS: PERFORMANCE & STATISTICS
-- ============================================================================
local Metrics = {}
Metrics.__index = Metrics

function Metrics.new()
    local self = setmetatable({}, Metrics)
    
    self.counters = {}
    self.gauges = {}
    self.timers = {}
    self.errors = {}
    self.startTime = tick()
    
    return self
end

function Metrics:Increment(name, amount)
    amount = amount or 1
    self.counters[name] = (self.counters[name] or 0) + amount
end

function Metrics:Decrement(name, amount)
    amount = amount or 1
    self.counters[name] = (self.counters[name] or 0) - amount
end

function Metrics:Set(name, value)
    self.gauges[name] = value
end

function Metrics:Get(name)
    return self.counters[name] or self.gauges[name] or 0
end

function Metrics:StartTimer(name)
    self.timers[name] = tick()
end

function Metrics:StopTimer(name)
    if self.timers[name] then
        local elapsed = tick() - self.timers[name]
        self.timers[name] = nil
        return elapsed
    end
    return 0
end

function Metrics:RecordError(name, err)
    self.errors[name] = self.errors[name] or { count = 0, lastError = nil, lastTime = 0 }
    self.errors[name].count = self.errors[name].count + 1
    self.errors[name].lastError = tostring(err):sub(1, 200)
    self.errors[name].lastTime = tick()
end

function Metrics:GetAll()
    return {
        counters = self.counters,
        gauges = self.gauges,
        errors = self.errors,
        uptime = tick() - self.startTime,
    }
end

function Metrics:Reset()
    self.counters = {}
    self.gauges = {}
    self.timers = {}
    self.errors = {}
end

-- ============================================================================
-- PLAYER CACHE (IMPROVED)
-- ============================================================================
local PlayerCache = {}
PlayerCache.__index = PlayerCache

function PlayerCache.new(config)
    local self = setmetatable({}, PlayerCache)
    
    config = config or {}
    
    self.data = WeakKeys()
    self.staggerOffset = WeakKeys()
    self.baseCacheTime = config.baseCacheTime or 0.15
    self.maxCacheTime = config.maxCacheTime or 0.5
    self.timeProvider = config.timeProvider or tick
    self.playerCountProvider = config.playerCountProvider or function() return 0 end
    
    self.stats = {
        hits = 0,
        misses = 0,
    }
    
    return self
end

function PlayerCache:GetStagger(player)
    if not player then return 0 end
    
    if not self.staggerOffset[player] then
        local id = 0
        if type(player) == "table" and player.UserId then
            id = player.UserId
        elseif Defensive.IsInstance(player) then
            local ok, userId = pcall(function() return player.UserId end)
            id = ok and userId or 0
        end
        self.staggerOffset[player] = (id % 100) / 1000
    end
    return self.staggerOffset[player]
end

function PlayerCache:GetAdaptiveCacheTime()
    local playerCount = self.playerCountProvider()
    local adaptive = self.baseCacheTime + math.clamp(playerCount / 100, 0, self.maxCacheTime - self.baseCacheTime)
    return adaptive
end

function PlayerCache:Get(player)
    if not player then return nil end
    
    local now = self.timeProvider()
    local cached = self.data[player]
    
    if not cached then
        self.stats.misses = self.stats.misses + 1
        return nil
    end
    
    local stagger = self:GetStagger(player)
    local cacheTime = self:GetAdaptiveCacheTime()
    
    if (now - cached.lastUpdate) < (cacheTime + stagger) then
        self.stats.hits = self.stats.hits + 1
        return cached
    end
    
    self.stats.misses = self.stats.misses + 1
    return nil
end

function PlayerCache:Set(player, data)
    if not player or not data then return end
    self.data[player] = data
end

function PlayerCache:Clear(player)
    if player then
        self.data[player] = nil
        self.staggerOffset[player] = nil
    else
        self:ClearAll()
    end
end

function PlayerCache:ClearAll()
    self.data = WeakKeys()
    self.staggerOffset = WeakKeys()
end

function PlayerCache:GetStats()
    local total = self.stats.hits + self.stats.misses
    return {
        hits = self.stats.hits,
        misses = self.stats.misses,
        hitRate = total > 0 and (self.stats.hits / total) or 0,
    }
end

-- ============================================================================
-- CONTAINER MANAGER (ENHANCED WITH RESOLVERS & HEURISTICS)
-- ============================================================================
local ContainerManager = {}
ContainerManager.__index = ContainerManager

function ContainerManager.new(config)
    local self = setmetatable({}, ContainerManager)
    
    config = config or {}
    
    self.adapter = config.adapter
    self.logger = config.logger
    self.metrics = config.metrics
    self.timeProvider = config.timeProvider or tick
    
    self.knownContainers = WeakKeys()
    self.registeredContainers = WeakKeys()
    self.lastScan = 0
    self.scanInterval = config.scanInterval or 5
    self.rateLimiter = RateLimiter.new(self.scanInterval)
    
    -- NEW: Container resolvers with weights
    self.containerResolvers = {} -- { {fn=fn, weight=number}, ... }
    self.minContainerScore = config.minContainerScore or 1.0
    self.fuzzyMatchThreshold = config.fuzzyMatchThreshold or 0.75
    
    self.containerNames = config.containerNames or {
        "Characters", "Players", "Entities", "Alive", "InGame", 
        "ActivePlayers", "NPCs", "Enemies", "Bots", "Units", 
        "Team1", "Team2", "Arena", "Combatants", "Fighters",
        "SpawnedPlayers", "GamePlayers", "AliveFolder",
    }
    
    return self
end

-- NEW: Register resolver with weight
function ContainerManager:RegisterResolver(fn, weight)
    if type(fn) ~= "function" then return false end
    weight = tonumber(weight) or 1
    
    table.insert(self.containerResolvers, { fn = fn, weight = weight })
    
    if self.logger then 
        self.logger:Debug("Container resolver registered, weight:", weight, "total:", #self.containerResolvers) 
    end
    
    if self.metrics then
        self.metrics:Increment("container_resolvers_registered")
    end
    
    return true
end

function ContainerManager:Register(container)
    if not container then return false end
    
    local name = "unknown"
    if type(container) == "string" then
        local workspace = self.adapter:GetWorkspace()
        container = self.adapter:FindFirstChild(workspace, container, true)
        if not container then return false end
    end
    
    if Defensive.IsInstance(container) then
        name = Defensive.GetName(container)
    elseif type(container) == "table" and container.Name then
        name = container.Name
    end
    
    self.registeredContainers[container] = {
        name = name,
        registered = self.timeProvider(),
    }
    
    if self.logger then
        self.logger:Debug("Container registered:", name)
    end
    
    return true
end

-- NEW: Heuristic container scoring
function ContainerManager:_scoreContainer(candidate)
    local score = 0
    local children = self.adapter:GetChildren(candidate)
    local modelCount = 0
    local humanoidCount = 0
    local entityAttributeCount = 0
    
    for _, c in ipairs(children) do
        if self.adapter:IsA(c, "Model") then 
            modelCount = modelCount + 1 
            
            -- Check for humanoid inside model
            local humanoid = self.adapter:FindFirstChildOfClass(c, "Humanoid")
            if humanoid then
                humanoidCount = humanoidCount + 1
            end
        end
        
        -- Attribute heuristics
        if self.adapter:GetAttribute(c, "IsPlayer") or 
           self.adapter:GetAttribute(c, "IsEntity") or
           self.adapter:GetAttribute(c, "IsCharacter") then
            entityAttributeCount = entityAttributeCount + 1
        end
    end
    
    -- Scoring formula
    score = score + (modelCount * 0.3)
    score = score + (humanoidCount * 1.0)
    score = score + (entityAttributeCount * 2.0)
    
    -- Name-based boost
    local name = Defensive.GetName(candidate):lower()
    local nameBoosts = {
        { pattern = "player", boost = 1.5 },
        { pattern = "character", boost = 1.5 },
        { pattern = "entit", boost = 1.0 },
        { pattern = "alive", boost = 1.0 },
        { pattern = "active", boost = 0.5 },
        { pattern = "spawn", boost = 0.5 },
        { pattern = "npc", boost = 0.8 },
        { pattern = "enemy", boost = 0.8 },
        { pattern = "team", boost = 0.5 },
    }
    
    for _, boost in ipairs(nameBoosts) do
        if name:find(boost.pattern) then
            score = score + boost.boost
        end
    end
    
    return score, modelCount, humanoidCount
end

function ContainerManager:Scan(force)
    local now = self.timeProvider()
    
    if not force and not self.rateLimiter:CanCall(now) then
        return
    end
    
    self.rateLimiter:Call(now)
    
    if self.metrics then
        self.metrics:StartTimer("container_scan")
    end
    
    local workspace = self.adapter:GetWorkspace()
    
    -- Check registered containers
    for container, info in pairs(self.registeredContainers) do
        if Defensive.IsValid(container) or (type(container) == "table" and container.Parent) then
            local children = self.adapter:GetChildren(container)
            local modelCount = 0
            for _, child in ipairs(children) do
                if self.adapter:IsA(child, "Model") then
                    modelCount = modelCount + 1
                end
            end
            
            if modelCount > 0 then
                self.knownContainers[container] = {
                    name = info.name,
                    found = now,
                    childCount = modelCount,
                    score = 100, -- Registered containers get high score
                    source = "registered",
                }
            end
        end
    end
    
    -- Scan by known names
    for _, name in ipairs(self.containerNames) do
        local ok, err = pcall(function()
            local container = self.adapter:FindFirstChild(workspace, name, true)
            if container then
                local isFolder = self.adapter:IsA(container, "Folder")
                local isModel = self.adapter:IsA(container, "Model")
                
                if isFolder or isModel then
                    local children = self.adapter:GetChildren(container)
                    local hasModels = false
                    for _, child in ipairs(children) do
                        if self.adapter:IsA(child, "Model") then
                            hasModels = true
                            break
                        end
                    end
                    
                    if hasModels then
                        local score = self:_scoreContainer(container)
                        self.knownContainers[container] = {
                            name = name,
                            found = now,
                            score = score,
                            source = "named",
                        }
                        
                        if self.metrics then
                            self.metrics:Increment("containers_found")
                        end
                        
                        if self.logger then
                            self.logger:Debug("Named container found:", name, "score:", score)
                        end
                    end
                end
            end
        end)
        
        if not ok and self.metrics then
            self.metrics:RecordError("container_scan_named", err)
        end
    end
    
    -- NEW: Heuristic global scan (top-level workspace children)
    local candidates = self.adapter:GetChildren(workspace)
    for _, candidate in ipairs(candidates) do
        -- Skip if already known
        if not self.knownContainers[candidate] then
            local isFolder = self.adapter:IsA(candidate, "Folder")
            local isModel = self.adapter:IsA(candidate, "Model")
            
            if isFolder or isModel then
                local ok, score, modelCount, humanoidCount = pcall(function()
                    return self:_scoreContainer(candidate)
                end)
                
                if ok and score and score >= self.minContainerScore then
                    self.knownContainers[candidate] = {
                        name = Defensive.GetName(candidate),
                        found = now,
                        score = score,
                        childCount = modelCount,
                        humanoidCount = humanoidCount,
                        source = "heuristic",
                    }
                    
                    if self.metrics then 
                        self.metrics:Increment("containers_found_heuristic") 
                    end
                    
                    if self.logger then 
                        self.logger:Debug("Heuristic container found:", Defensive.GetName(candidate), "score:", score) 
                    end
                end
            end
        end
    end
    
    -- NEW: Run custom resolvers
    for idx, entry in ipairs(self.containerResolvers) do
        local ok, result = pcall(function()
            return entry.fn(self.adapter)
        end)
        
        if ok and result then
            local function processResult(item, baseWeight)
                if type(item) == "table" and item.instance then
                    local inst = item.instance
                    local sc = tonumber(item.score) or baseWeight
                    if inst and (Defensive.IsValid(inst) or (type(inst) == "table" and inst.Parent)) then
                        self.knownContainers[inst] = { 
                            name = Defensive.GetName(inst), 
                            found = now, 
                            score = sc,
                            source = "resolver_" .. idx,
                        }
                    end
                elseif Defensive.IsInstance(item) or (type(item) == "table" and item.Parent) then
                    self.knownContainers[item] = { 
                        name = Defensive.GetName(item), 
                        found = now, 
                        score = baseWeight,
                        source = "resolver_" .. idx,
                    }
                end
            end
            
            if type(result) == "table" then
                if result.instance then
                    -- Single result with instance key
                    processResult(result, entry.weight)
                elseif #result > 0 then
                    -- Array of results
                    for _, item in ipairs(result) do
                        processResult(item, entry.weight)
                    end
                end
            elseif Defensive.IsInstance(result) then
                processResult(result, entry.weight)
            end
            
            if self.metrics then
                self.metrics:Increment("container_resolver_success")
            end
        elseif not ok then
            if self.metrics then
                self.metrics:RecordError("container_resolver_" .. idx, result)
            end
        end
    end
    
    if self.metrics then
        self.metrics:StopTimer("container_scan")
        self.metrics:Set("known_containers", self:GetContainerCount())
    end
end

function ContainerManager:GetContainerCount()
    local count = 0
    for _ in pairs(self.knownContainers) do
        count = count + 1
    end
    return count
end

function ContainerManager:GetKnown()
    return self.knownContainers
end

-- NEW: Find with fuzzy matching
function ContainerManager:FindInContainers(name, useFuzzy)
    if not name then return nil end
    
    useFuzzy = useFuzzy ~= false -- Default to true
    
    -- Check registered first (exact)
    for container, _ in pairs(self.registeredContainers) do
        if Defensive.IsValid(container) or (type(container) == "table" and container.Parent) then
            local found = self.adapter:FindFirstChild(container, name)
            if found and self.adapter:IsA(found, "Model") then
                return found
            end
        end
    end
    
    -- Check known (exact)
    for container, _ in pairs(self.knownContainers) do
        if Defensive.IsValid(container) or (type(container) == "table" and container.Parent) then
            local found = self.adapter:FindFirstChild(container, name)
            if found and self.adapter:IsA(found, "Model") then
                return found
            end
        end
    end
    
    -- Fuzzy matching
    if useFuzzy then
        for container, _ in pairs(self.knownContainers) do
            if Defensive.IsValid(container) or (type(container) == "table" and container.Parent) then
                local children = self.adapter:GetChildren(container)
                local modelChildren = {}
                
                for _, child in ipairs(children) do
                    if self.adapter:IsA(child, "Model") then
                        table.insert(modelChildren, child)
                    end
                end
                
                local bestMatch, bestScore = FuzzyFindBest(name, modelChildren, self.fuzzyMatchThreshold)
                if bestMatch then
                    if self.logger then
                        self.logger:Debug("Fuzzy matched:", name, "->", Defensive.GetName(bestMatch), "score:", bestScore)
                    end
                    return bestMatch
                end
            end
        end
    end
    
    return nil
end

function ContainerManager:Clear()
    self.knownContainers = WeakKeys()
    self.registeredContainers = WeakKeys()
end

-- ============================================================================
-- PROXIMITY CLUSTERING (DBSCAN-LIKE)
-- ============================================================================
local ProximityClustering = {}

function ProximityClustering.Cluster(anchors, radius)
    radius = radius or 15
    local radiusSquared = radius * radius
    
    local clusters = {}
    local visited = {}
    local playerList = {}
    
    -- Build player list
    for player, _ in pairs(anchors) do
        table.insert(playerList, player)
    end
    
    local function getNeighbors(player)
        local neighbors = {}
        local pos = anchors[player]
        if not pos then return neighbors end
        
        for other, otherPos in pairs(anchors) do
            if player ~= other and otherPos then
                local distSq = VectorUtils.DistanceSquared3D(pos, otherPos)
                if distSq <= radiusSquared then
                    table.insert(neighbors, other)
                end
            end
        end
        return neighbors
    end
    
    local clusterIndex = 0
    
    for _, player in ipairs(playerList) do
        if not visited[player] then
            visited[player] = true
            clusterIndex = clusterIndex + 1
            local clusterId = "proximity_" .. clusterIndex
            
            clusters[clusterId] = clusters[clusterId] or {}
            table.insert(clusters[clusterId], player)
            
            -- Flood-fill neighbors
            local queue = getNeighbors(player)
            local queueIndex = 1
            
            while queueIndex <= #queue do
                local neighbor = queue[queueIndex]
                queueIndex = queueIndex + 1
                
                if not visited[neighbor] then
                    visited[neighbor] = true
                    table.insert(clusters[clusterId], neighbor)
                    
                    -- Add neighbor's neighbors to queue
                    for _, nn in ipairs(getNeighbors(neighbor)) do
                        if not visited[nn] then
                            table.insert(queue, nn)
                        end
                    end
                end
            end
        end
    end
    
    -- Convert to partition map
    local partition = {}
    for clusterId, members in pairs(clusters) do
        for _, player in ipairs(members) do
            partition[player] = clusterId
        end
    end
    
    return partition, clusterIndex
end

-- ============================================================================
-- TEAM SYSTEM MANAGER (ENHANCED WITH WEIGHTED RESOLVERS & PROXIMITY)
-- ============================================================================
local TeamSystemManager = {}
TeamSystemManager.__index = TeamSystemManager

function TeamSystemManager.new(config)
    local self = setmetatable({}, TeamSystemManager)
    
    config = config or {}
    
    self.adapter = config.adapter
    self.logger = config.logger
    self.metrics = config.metrics
    self.timeProvider = config.timeProvider or tick
    
    self.method = "Unknown"
    self.currentPartition = {}
    self.forceFFA = false
    self.autoDetected = false
    self.lastCheck = 0
    self.checkInterval = config.checkInterval or 3
    self.rateLimiter = RateLimiter.new(self.checkInterval)
    
    -- NEW: Weighted resolvers
    self.customResolvers = {} -- { {fn=fn, weight=number}, ... }
    
    -- NEW: Strategy weights
    self.strategyWeights = config.strategyWeights or {
        RobloxTeam = 2.0,
        TeamColor = 1.5,
        Attribute = 1.8,
        Proximity = 1.0,
        CustomResolver = 1.5,
    }
    
    -- NEW: Proximity clustering config
    self.proximityRadius = config.proximityRadius or 15
    self.enableProximityClustering = config.enableProximityClustering ~= false
    
    -- Reference to heuristics manager (for anchor resolution)
    self._heuristics = config.heuristics
    
    return self
end

-- NEW: Register resolver with weight
function TeamSystemManager:RegisterResolver(fn, weight)
    if type(fn) ~= "function" then return false end
    weight = tonumber(weight) or 1
    
    table.insert(self.customResolvers, { fn = fn, weight = weight })
    
    if self.logger then 
        self.logger:Debug("Team resolver registered, weight:", weight, "total:", #self.customResolvers) 
    end
    
    if self.metrics then
        self.metrics:Increment("team_resolvers_registered")
    end
    
    return true
end

-- Set heuristics reference (for proximity clustering anchor lookup)
function TeamSystemManager:SetHeuristics(heuristics)
    self._heuristics = heuristics
end

-- Get player anchor position
function TeamSystemManager:_getPlayerPosition(player)
    if not player then return nil end
    
    -- Try character
    local character = Defensive.SafeGet(player, "Character")
    if character then
        -- Try heuristics if available
        if self._heuristics then
            local anchor = self._heuristics:GetAnchorPart(character)
            if anchor then
                local pos = Defensive.SafeGet(anchor, "Position")
                if pos then return pos end
            end
        end
        
        -- Fallback: PrimaryPart
        local primaryPart = Defensive.SafeGet(character, "PrimaryPart")
        if primaryPart then
            local pos = Defensive.SafeGet(primaryPart, "Position")
            if pos then return pos end
        end
        
        -- Fallback: HumanoidRootPart
        local hrp = self.adapter:FindFirstChild(character, "HumanoidRootPart")
        if hrp then
            local pos = Defensive.SafeGet(hrp, "Position")
            if pos then return pos end
        end
    end
    
    return nil
end

function TeamSystemManager:DetectWithVoting(players)
    if not players then
        players = self.adapter:GetPlayers()
    end
    
    if #players < 2 then
        self.method = "FFA"
        self.forceFFA = true
        self.autoDetected = true
        return
    end
    
    if self.metrics then
        self.metrics:StartTimer("team_detection")
    end
    
    local partitionScores = {} -- { [method] = { partition = {}, score = 0, weight = 1 } }
    
    -- Method 1: Roblox Teams
    pcall(function()
        local teams = self.adapter:GetTeams()
        if teams then
            local teamList = self.adapter:GetChildren(teams)
            if #teamList > 0 then
                local partition = {}
                for _, p in ipairs(players) do
                    local team = Defensive.SafeGet(p, "Team")
                    if team then
                        partition[p] = Defensive.GetName(team)
                    else
                        partition[p] = "__nil"
                    end
                end
                
                local score = self:ScorePartition(partition)
                partitionScores.RobloxTeam = {
                    partition = partition,
                    score = score,
                    weight = self.strategyWeights.RobloxTeam or 2.0,
                }
            end
        end
    end)
    
    -- Method 2: TeamColor
    local teamColorPartition = {}
    for _, p in ipairs(players) do
        local teamColor = Defensive.SafeGet(p, "TeamColor")
        if teamColor and tostring(teamColor) ~= "White" then
            teamColorPartition[p] = tostring(teamColor)
        else
            teamColorPartition[p] = "__nil"
        end
    end
    partitionScores.TeamColor = {
        partition = teamColorPartition,
        score = self:ScorePartition(teamColorPartition),
        weight = self.strategyWeights.TeamColor or 1.5,
    }
    
    -- Method 3: Attributes
    local attrPartition = {}
    local attrNames = {"Team", "TeamName", "Faction", "Side", "Squad", "Group", "Alliance", "Party"}
    for _, p in ipairs(players) do
        local value = "__nil"
        for _, attr in ipairs(attrNames) do
            local attrVal = self.adapter:GetAttribute(p, attr)
            if attrVal ~= nil then
                value = tostring(attrVal)
                break
            end
        end
        attrPartition[p] = value
    end
    partitionScores.Attribute = {
        partition = attrPartition,
        score = self:ScorePartition(attrPartition),
        weight = self.strategyWeights.Attribute or 1.8,
    }
    
    -- Method 4: Proximity Clustering (NEW)
    if self.enableProximityClustering then
        local ok, proxPartition = pcall(function()
            -- Gather positions
            local anchors = {}
            for _, p in ipairs(players) do
                local pos = self:_getPlayerPosition(p)
                if pos then
                    anchors[p] = pos
                end
            end
            
            -- Only cluster if we have enough anchors
            if next(anchors) then
                local partition, clusterCount = ProximityClustering.Cluster(anchors, self.proximityRadius)
                return partition, clusterCount
            end
            return nil
        end)
        
        if ok and proxPartition and next(proxPartition) then
            partitionScores.Proximity = {
                partition = proxPartition,
                score = self:ScorePartition(proxPartition),
                weight = self.strategyWeights.Proximity or 1.0,
            }
            
            if self.logger then
                self.logger:Debug("Proximity clustering detected partitions")
            end
        end
    end
    
    -- Method 5: Custom resolvers (with individual weights)
    for idx, entry in ipairs(self.customResolvers) do
        local ok, result = pcall(function()
            return entry.fn(players)
        end)
        
        if ok and type(result) == "table" and next(result) then
            local key = "CustomResolver_" .. tostring(idx)
            partitionScores[key] = {
                partition = result,
                score = self:ScorePartition(result),
                weight = entry.weight or self.strategyWeights.CustomResolver or 1.5,
            }
        elseif not ok and self.metrics then
            self.metrics:RecordError("team_resolver_" .. idx, result)
        end
    end
    
    -- Weighted voting to find best partition
    local bestMethod = nil
    local bestWeightedScore = 0
    local bestPartition = nil
    
    for method, info in pairs(partitionScores) do
        local weightedScore = (info.score or 0) * (info.weight or 1)
        
        if self.logger then
            self.logger:Trace("Team method:", method, "raw:", info.score, "weight:", info.weight, "weighted:", weightedScore)
        end
        
        if weightedScore > bestWeightedScore then
            bestWeightedScore = weightedScore
            bestMethod = method
            bestPartition = info.partition
        end
    end
    
    -- Dynamic threshold based on player count
    local threshold = 10 + (#players * 0.5)
    
    if bestMethod and bestWeightedScore > threshold then
        self.method = bestMethod
        self.currentPartition = bestPartition
        self.forceFFA = false
        
        if self.logger then
            self.logger:Debug("Team system detected:", bestMethod, "weighted score:", bestWeightedScore)
        end
    else
        self.method = "FFA"
        self.currentPartition = {}
        self.forceFFA = true
        
        if self.logger then
            self.logger:Debug("FFA mode (no valid team system, best score:", bestWeightedScore, "threshold:", threshold, ")")
        end
    end
    
    self.autoDetected = true
    self.lastCheck = self.timeProvider()
    
    if self.metrics then
        self.metrics:StopTimer("team_detection")
        self.metrics:Set("team_method", self.method)
        self.metrics:Set("team_score", bestWeightedScore)
    end
end

function TeamSystemManager:ScorePartition(partition)
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
    
    -- Reject invalid partitions
    if groupCount < 2 or groupCount > 10 then
        return 0
    end
    
    -- Calculate entropy (more balanced = higher score)
    local balance = minSize / math.max(maxSize, 1)
    local coverage = (playerCount - nilCount) / math.max(playerCount, 1)
    
    -- Bonus for reasonable team counts
    local teamBonus = 1.0
    if groupCount >= 2 and groupCount <= 4 then
        teamBonus = 1.2
    end
    
    return groupCount * balance * coverage * teamBonus * 100
end

function TeamSystemManager:AutoDetect()
    local now = self.timeProvider()
    if not self.rateLimiter:CanCall(now) then
        return
    end
    
    self:DetectWithVoting()
end

function TeamSystemManager:GetPlayerTeam(player)
    if not player then return nil end
    if self.forceFFA then return nil end
    
    if not self.autoDetected then
        self:DetectWithVoting()
    end
    
    if self.currentPartition then
        local team = self.currentPartition[player]
        if team and team ~= "__nil" then
            return team
        end
    end
    
    -- Fallback
    local playerTeam = Defensive.SafeGet(player, "Team")
    if playerTeam then
        return Defensive.GetName(playerTeam)
    end
    
    return nil
end

function TeamSystemManager:AreSameTeam(player1, player2)
    if not player1 or not player2 then return false end
    if player1 == player2 then return true end
    if self.forceFFA then return false end
    
    local team1 = self:GetPlayerTeam(player1)
    local team2 = self:GetPlayerTeam(player2)
    
    if not team1 or not team2 then
        local p1Team = Defensive.SafeGet(player1, "Team")
        local p2Team = Defensive.SafeGet(player2, "Team")
        if p1Team and p2Team then
            return p1Team == p2Team
        end
        return false
    end
    
    return tostring(team1):lower() == tostring(team2):lower()
end

function TeamSystemManager:Clear()
    self.currentPartition = {}
    self.autoDetected = false
    self.lastCheck = 0
end

-- ============================================================================
-- HEURISTICS MANAGER (ENHANCED WITH VOLUME-BASED HITBOX CLASSIFIER)
-- ============================================================================
local HeuristicsManager = {}
HeuristicsManager.__index = HeuristicsManager

function HeuristicsManager.new(config)
    local self = setmetatable({}, HeuristicsManager)
    
    config = config or {}
    
    self.adapter = config.adapter
    self.logger = config.logger
    self.metrics = config.metrics
    
    self.anchorResolvers = {}
    self.hitboxClassifiers = {}
    
    self.hitboxPatterns = config.hitboxPatterns or {
        "head", "hit", "hurt", "hitbox", "target", "weak", "crit",
    }
    
    self.anchorCandidates = config.anchorCandidates or {
        "HumanoidRootPart", "Torso", "UpperTorso", "LowerTorso",
        "Root", "RootPart", "Head",
    }
    
    -- NEW: Volume-based hitbox detection config
    self.hitboxVolumeThreshold = config.hitboxVolumeThreshold or 2.5
    self.minHitboxVolume = config.minHitboxVolume or 0.1
    
    self.hitboxCache = WeakKeys()
    self.anchorCache = WeakKeys()
    self.anchorCacheTime = config.anchorCacheTime or 1.0
    
    -- Register default volume-based classifier
    self:_registerDefaultClassifiers()
    
    return self
end

-- NEW: Register default hitbox classifiers
function HeuristicsManager:_registerDefaultClassifiers()
    -- Volume-based classifier
    self:RegisterHitboxClassifier(function(part)
        if not part then return nil end
        
        local name = Defensive.GetName(part):lower()
        
        -- Strong positive signals
        if name:find("head") or name:find("hitbox") or name:find("hurtbox") then 
            return true 
        end
        
        -- Check volume (smaller parts more likely to be hitboxes)
        local size = Defensive.SafeGet(part, "Size")
        if size then
            local vol
            if typeof(size) == "Vector3" then
                vol = size.X * size.Y * size.Z
            elseif type(size) == "table" then
                vol = (size.X or 1) * (size.Y or 1) * (size.Z or 1)
            end
            
            if vol and vol > self.minHitboxVolume and vol < self.hitboxVolumeThreshold then
                -- Small parts with specific names
                if name:find("target") or name:find("weak") or name:find("crit") then
                    return true
                end
            end
        end
        
        return nil -- Let other classifiers decide
    end)
    
    -- Attribute-based classifier
    self:RegisterHitboxClassifier(function(part)
        if not part then return nil end
        
        if self.adapter:GetAttribute(part, "IsHitbox") then
            return true
        end
        
        if self.adapter:GetAttribute(part, "DamageMultiplier") then
            return true
        end
        
        return nil
    end)
end

function HeuristicsManager:RegisterAnchorResolver(fn)
    if type(fn) == "function" then
        table.insert(self.anchorResolvers, fn)
        if self.logger then
            self.logger:Debug("Anchor resolver registered, total:", #self.anchorResolvers)
        end
    end
end

function HeuristicsManager:RegisterHitboxClassifier(fn)
    if type(fn) == "function" then
        table.insert(self.hitboxClassifiers, fn)
        if self.logger then
            self.logger:Debug("Hitbox classifier registered, total:", #self.hitboxClassifiers)
        end
    end
end

function HeuristicsManager:GetAnchorPart(model)
    if not model then return nil end
    
    -- Check cache
    local cached = self.anchorCache[model]
    if cached and (tick() - cached.time) < self.anchorCacheTime then
        if cached.anchor and (Defensive.IsValid(cached.anchor) or (type(cached.anchor) == "table" and cached.anchor.Parent)) then
            return cached.anchor
        end
    end
    
    local workspace = self.adapter:GetWorkspace()
    local result = nil
    
    -- 1. Custom resolvers
    for _, resolver in ipairs(self.anchorResolvers) do
        local ok, anchor = pcall(function()
            return resolver(model)
        end)
        
        if ok and anchor then
            local isBasePart = self.adapter:IsA(anchor, "BasePart")
            local isDescendant = Defensive.IsDescendantOf(anchor, workspace) or
                                 (type(anchor) == "table" and anchor.Parent)
            
            if isBasePart and isDescendant then
                result = anchor
                break
            end
        elseif not ok and self.metrics then
            self.metrics:RecordError("anchor_resolver", anchor)
        end
    end
    
    -- 2. Named candidates
    if not result then
        for _, name in ipairs(self.anchorCandidates) do
            local part = self.adapter:FindFirstChild(model, name)
            if part then
                local isBasePart = self.adapter:IsA(part, "BasePart")
                local isDescendant = Defensive.IsDescendantOf(part, workspace) or
                                     (type(part) == "table" and part.Parent)
                
                if isBasePart and isDescendant then
                    result = part
                    break
                end
            end
        end
    end
    
    -- 3. PrimaryPart
    if not result then
        local primaryPart = Defensive.SafeGet(model, "PrimaryPart")
        if primaryPart then
            local isDescendant = Defensive.IsDescendantOf(primaryPart, workspace) or
                                 (type(primaryPart) == "table" and primaryPart.Parent)
            if isDescendant then
                result = primaryPart
            end
        end
    end
    
    -- 4. Humanoid.RootPart
    if not result then
        local humanoid = self.adapter:FindFirstChildOfClass(model, "Humanoid")
        if humanoid then
            local rootPart = Defensive.SafeGet(humanoid, "RootPart")
            if rootPart then
                local isDescendant = Defensive.IsDescendantOf(rootPart, workspace) or
                                     (type(rootPart) == "table" and rootPart.Parent)
                if isDescendant then
                    result = rootPart
                end
            end
        end
    end
    
    -- 5. Attribute-marked
    if not result then
        local descendants = self.adapter:GetDescendants(model)
        for _, child in ipairs(descendants) do
            if self.adapter:IsA(child, "BasePart") then
                if self.adapter:GetAttribute(child, "IsAnchor") then
                    result = child
                    break
                end
            end
        end
    end
    
    -- 6. Largest BasePart fallback
    if not result then
        local best, bestVol = nil, 0
        local children = self.adapter:GetChildren(model)
        for _, child in ipairs(children) do
            if self.adapter:IsA(child, "BasePart") then
                local size = Defensive.SafeGet(child, "Size")
                if size then
                    local vol
                    if typeof(size) == "Vector3" then
                        vol = size.X * size.Y * size.Z
                    elseif type(size) == "table" then
                        vol = (size.X or 1) * (size.Y or 1) * (size.Z or 1)
                    else
                        vol = 0
                    end
                    
                    if vol > bestVol then
                        best, bestVol = child, vol
                    end
                end
            end
        end
        result = best
    end
    
    -- Cache result
    self.anchorCache[model] = {
        anchor = result,
        time = tick(),
    }
    
    return result
end

function HeuristicsManager:IsHitboxPart(part)
    if not part then return false end
    
    -- Check cache
    if self.hitboxCache[part] ~= nil then
        return self.hitboxCache[part]
    end
    
    -- 1. Custom classifiers
    for _, classifier in ipairs(self.hitboxClassifiers) do
        local ok, result = pcall(function()
            return classifier(part)
        end)
        
        if ok then
            if result == true then
                self.hitboxCache[part] = true
                return true
            elseif result == false then
                self.hitboxCache[part] = false
                return false
            end
        elseif self.metrics then
            self.metrics:RecordError("hitbox_classifier", result)
        end
    end
    
    -- 2. Name patterns
    local partName = Defensive.GetName(part):lower()
    for _, pattern in ipairs(self.hitboxPatterns) do
        if partName:find(pattern, 1, true) then
            self.hitboxCache[part] = true
            return true
        end
    end
    
    -- 3. Attribute
    if self.adapter:GetAttribute(part, "IsHitbox") then
        self.hitboxCache[part] = true
        return true
    end
    
    self.hitboxCache[part] = false
    return false
end

-- NEW: Get all hitbox parts in a model
function HeuristicsManager:GetHitboxParts(model)
    if not model then return {} end
    
    local hitboxes = {}
    local descendants = self.adapter:GetDescendants(model)
    
    for _, part in ipairs(descendants) do
        if self.adapter:IsA(part, "BasePart") then
            if self:IsHitboxPart(part) then
                table.insert(hitboxes, part)
            end
        end
    end
    
    return hitboxes
end

function HeuristicsManager:ClearCache()
    self.hitboxCache = WeakKeys()
    self.anchorCache = WeakKeys()
end

-- ============================================================================
-- EVENT EMITTER
-- ============================================================================
local EventEmitter = {}
EventEmitter.__index = EventEmitter

function EventEmitter.new(adapter)
    local self = setmetatable({}, EventEmitter)
    
    self.adapter = adapter
    self.events = {}
    
    return self
end

function EventEmitter:CreateEvent(name)
    if self.events[name] then return self.events[name] end
    
    local event = self.adapter:CreateBindableEvent()
    self.events[name] = event
    return event
end

function EventEmitter:Fire(name, ...)
    local event = self.events[name]
    if event then
        local ok, err = pcall(function()
            event:Fire(...)
        end)
        if not ok then
            -- Silent fail for events
        end
    end
end

function EventEmitter:GetEvent(name)
    return self.events[name]
end

function EventEmitter:Destroy()
    for name, event in pairs(self.events) do
        if event and event.Destroy then
            pcall(event.Destroy, event)
        end
    end
    self.events = {}
end

-- ============================================================================
-- CONNECTION MANAGER
-- ============================================================================
local ConnectionManager = {}
ConnectionManager.__index = ConnectionManager

function ConnectionManager.new()
    local self = setmetatable({}, ConnectionManager)
    
    self.globalConnections = {}
    self.playerConnections = WeakKeys()
    
    return self
end

function ConnectionManager:AddGlobal(connection)
    if connection then
        table.insert(self.globalConnections, connection)
    end
end

function ConnectionManager:AddForPlayer(player, connection)
    if not player or not connection then return end
    
    self.playerConnections[player] = self.playerConnections[player] or {}
    table.insert(self.playerConnections[player], connection)
end

function ConnectionManager:ClearPlayer(player)
    if not player then return end
    
    local conns = self.playerConnections[player]
    if conns then
        for _, conn in ipairs(conns) do
            if conn and conn.Disconnect then
                pcall(conn.Disconnect, conn)
            end
        end
    end
    self.playerConnections[player] = nil
end

function ConnectionManager:ClearAll()
    for player, _ in pairs(self.playerConnections) do
        self:ClearPlayer(player)
    end
    
    for _, conn in ipairs(self.globalConnections) do
        if conn and conn.Disconnect then
            pcall(conn.Disconnect, conn)
        end
    end
    
    self.globalConnections = {}
    self.playerConnections = WeakKeys()
end

function ConnectionManager:GetStats()
    local playerConnCount = 0
    for _, conns in pairs(self.playerConnections) do
        playerConnCount = playerConnCount + #conns
    end
    
    return {
        global = #self.globalConnections,
        perPlayer = playerConnCount,
    }
end

-- ============================================================================
-- SEMANTIC ENGINE (MAIN CLASS)
-- ============================================================================
function SemanticEngineModule.new(dependencies)
    local self = setmetatable({}, SemanticEngineModule)
    
    dependencies = dependencies or {}
    
    self.Version = VERSION
    
    self.Config = {
        CacheTime = 0.15,
        MaxCacheTime = 0.5,
        ContainerScanInterval = 5,
        TeamCheckInterval = 3,
        MaxPlayersTracked = 64,
        Debug = false,
        LogLevel = "WARN",
        
        -- NEW: Fuzzy matching
        FuzzyMatchThreshold = 0.75,
        
        -- NEW: Proximity clustering
        EnableProximityClustering = true,
        ProximityRadius = 15,
        
        -- NEW: Container heuristic
        MinContainerScore = 1.0,
        
        -- NEW: Hitbox volume
        HitboxVolumeThreshold = 2.5,
        
        HitboxNamePatterns = {
            "head", "hit", "hurt", "hitbox", "target", "weak", "crit",
        },
        
        ContainerNames = {
            "Characters", "Players", "Entities", "Alive", "InGame", 
            "ActivePlayers", "NPCs", "Enemies", "Bots", "Units", 
            "Team1", "Team2", "Arena", "Combatants", "Fighters",
            "SpawnedPlayers", "GamePlayers", "AliveFolder",
        },
        
        AnchorCandidates = {
            "HumanoidRootPart", "Torso", "UpperTorso", "LowerTorso",
            "Root", "RootPart", "Head",
        },
        
        -- NEW: Team strategy weights
        TeamStrategyWeights = {
            RobloxTeam = 2.0,
            TeamColor = 1.5,
            Attribute = 1.8,
            Proximity = 1.0,
            CustomResolver = 1.5,
        },
    }
    
    self._adapter = dependencies.adapter or RobloxAdapter.new(dependencies)
    self._timeProvider = dependencies.timeProvider or function() return self._adapter:Now() end
    
    self._logger = Logger.new({
        level = LOG_LEVELS[self.Config.LogLevel] or LOG_LEVELS.WARN,
        prefix = "[Semantic]",
    })
    
    self._metrics = Metrics.new()
    
    self._cache = PlayerCache.new({
        baseCacheTime = self.Config.CacheTime,
        maxCacheTime = self.Config.MaxCacheTime,
        timeProvider = self._timeProvider,
        playerCountProvider = function()
            return #self._adapter:GetPlayers()
        end,
    })
    
    self._containerManager = ContainerManager.new({
        adapter = self._adapter,
        logger = self._logger,
        metrics = self._metrics,
        timeProvider = self._timeProvider,
        scanInterval = self.Config.ContainerScanInterval,
        containerNames = self.Config.ContainerNames,
        minContainerScore = self.Config.MinContainerScore,
        fuzzyMatchThreshold = self.Config.FuzzyMatchThreshold,
    })
    
    self._heuristics = HeuristicsManager.new({
        adapter = self._adapter,
        logger = self._logger,
        metrics = self._metrics,
        hitboxPatterns = self.Config.HitboxNamePatterns,
        anchorCandidates = self.Config.AnchorCandidates,
        hitboxVolumeThreshold = self.Config.HitboxVolumeThreshold,
    })
    
    self._teamManager = TeamSystemManager.new({
        adapter = self._adapter,
        logger = self._logger,
        metrics = self._metrics,
        timeProvider = self._timeProvider,
        checkInterval = self.Config.TeamCheckInterval,
        heuristics = self._heuristics,
        strategyWeights = self.Config.TeamStrategyWeights,
        proximityRadius = self.Config.ProximityRadius,
        enableProximityClustering = self.Config.EnableProximityClustering,
    })
    
    self._eventEmitter = EventEmitter.new(self._adapter)
    self._connectionManager = ConnectionManager.new()
    
    self.TargetDefinitions = {
        HitboxParts = WeakKeys(),
        CombatModels = WeakKeys(),
        EntityToPlayer = WeakKeys(),
        PlayerToEntity = WeakKeys(),
    }
    
    self.Stats = {
        DamageEventsDetected = 0,
        EntitiesLearned = 0,
        ContainersFound = 0,
        PlayersTracked = 0,
    }
    
    self.TeamSystem = {
        Method = "Unknown",
        CurrentPartition = {},
        ForceFFA = false,
        AutoDetected = false,
        LastCheck = 0,
        CheckInterval = 3,
    }
    
    self.ContainerSystem = {
        KnownContainers = self._containerManager.knownContainers,
        RegisteredContainers = self._containerManager.registeredContainers,
        LastScan = 0,
        ScanInterval = 5,
    }
    
    self.Heuristics = {
        AnchorResolvers = self._heuristics.anchorResolvers,
        TeamResolvers = self._teamManager.customResolvers,
        HitboxClassifiers = self._heuristics.hitboxClassifiers,
    }
    
    self.Events = {}
    
    self._initialized = false
    self._maintenanceErrorStreak = 0
    self._localPlayer = nil
    
    self._connections = {}
    self._playerConnections = WeakKeys()
    
    return self
end

function SemanticEngineModule.Create(dependencies)
    return SemanticEngineModule.new(dependencies)
end

function SemanticEngineModule:GetAdapter()
    return self._adapter
end

function SemanticEngineModule:SetAdapter(adapter)
    self._adapter = adapter
    self._containerManager.adapter = adapter
    self._teamManager.adapter = adapter
    self._heuristics.adapter = adapter
end

-- ============================================================================
-- PUBLIC API: REGISTRATION (ENHANCED WITH WEIGHTS)
-- ============================================================================
function SemanticEngineModule:RegisterAnchorHeuristic(fn)
    self._heuristics:RegisterAnchorResolver(fn)
end

function SemanticEngineModule:RegisterTeamResolver(fn)
    -- Backward compatible (weight = 1)
    self._teamManager:RegisterResolver(fn, 1)
end

-- NEW: Register team resolver with weight
function SemanticEngineModule:RegisterTeamResolverWeighted(fn, weight)
    return self._teamManager:RegisterResolver(fn, weight)
end

function SemanticEngineModule:RegisterHitboxClassifier(fn)
    self._heuristics:RegisterHitboxClassifier(fn)
end

function SemanticEngineModule:RegisterContainer(container)
    return self._containerManager:Register(container)
end

-- NEW: Register container resolver with weight
function SemanticEngineModule:RegisterContainerResolver(fn, weight)
    return self._containerManager:RegisterResolver(fn, weight)
end

-- ============================================================================
-- PUBLIC API: PLAYER TRACKING
-- ============================================================================
function SemanticEngineModule:TrackPlayer(player)
    if not player then return end
    if player == self._localPlayer then return end
    
    self._logger:Debug("Tracking player:", Defensive.GetName(player))
    
    self._connectionManager:ClearPlayer(player)
    self._cache:Clear(player)
    self.TargetDefinitions.PlayerToEntity[player] = nil
    
    local entity = self:FindEntityForPlayer(player)
    if entity then
        self:LinkPlayerToEntity(player, entity)
    end
    
    local character = Defensive.SafeGet(player, "Character")
    if character then
        self:_setupCharacterTracking(player, character)
    end
    
    local charAddedEvent = Defensive.SafeGet(player, "CharacterAdded")
    if charAddedEvent then
        local conn = self._adapter:ConnectEvent(charAddedEvent, function(newCharacter)
            self._adapter:Wait(0.1)
            self._cache:Clear(player)
            self:_setupCharacterTracking(player, newCharacter)
            self:LinkPlayerToEntity(player, newCharacter)
        end)
        
        if conn then
            self._connectionManager:AddForPlayer(player, conn)
            self._connectionManager:AddGlobal(conn)
        end
    end
    
    self.Stats.PlayersTracked = self.Stats.PlayersTracked + 1
    self._metrics:Increment("players_tracked")
    self._eventEmitter:Fire("PlayerTracked", player, entity)
end

function SemanticEngineModule:_setupCharacterTracking(player, character)
    if not character then return end
    
    local ancestryEvent = Defensive.SafeGet(character, "AncestryChanged")
    if ancestryEvent then
        local conn = self._adapter:ConnectEvent(ancestryEvent, function(_, parent)
            if not parent then
                self._cache:Clear(player)
                self.TargetDefinitions.EntityToPlayer[character] = nil
                self.TargetDefinitions.PlayerToEntity[player] = nil
                self._logger:Debug("Character removed for:", Defensive.GetName(player))
            end
        end)
        
        if conn then
            self._connectionManager:AddForPlayer(player, conn)
        end
    end
    
    local humanoid = self._adapter:FindFirstChildOfClass(character, "Humanoid")
    if humanoid then
        local diedEvent = Defensive.SafeGet(humanoid, "Died")
        if diedEvent then
            local conn = self._adapter:ConnectEvent(diedEvent, function()
                self._logger:Debug("Player died:", Defensive.GetName(player))
            end)
            
            if conn then
                self._connectionManager:AddForPlayer(player, conn)
            end
        end
    end
end

function SemanticEngineModule:UntrackPlayer(player)
    if not player then return end
    
    self._logger:Debug("Untracking player:", Defensive.GetName(player))
    
    self._connectionManager:ClearPlayer(player)
    self._cache:Clear(player)
    
    local entity = self.TargetDefinitions.PlayerToEntity[player]
    if entity then
        self.TargetDefinitions.EntityToPlayer[entity] = nil
    end
    self.TargetDefinitions.PlayerToEntity[player] = nil
    
    if self._teamManager.currentPartition then
        self._teamManager.currentPartition[player] = nil
    end
    
    self._eventEmitter:Fire("PlayerUntracked", player)
end

function SemanticEngineModule:LinkPlayerToEntity(player, entity)
    if not player or not entity then return end
    
    self._logger:Debug("Linking", Defensive.GetName(player), "to", Defensive.GetName(entity))
    
    self.TargetDefinitions.EntityToPlayer[entity] = player
    self.TargetDefinitions.PlayerToEntity[player] = entity
    self.TargetDefinitions.CombatModels[entity] = true
    self.Stats.EntitiesLearned = self.Stats.EntitiesLearned + 1
    self._metrics:Increment("entities_learned")
    
    self._eventEmitter:Fire("EntityLinked", player, entity)
end

-- ============================================================================
-- PUBLIC API: ENTITY FINDING (ENHANCED WITH FUZZY MATCHING)
-- ============================================================================
function SemanticEngineModule:FindEntityForPlayer(player, useFuzzy)
    if not player then return nil end
    
    useFuzzy = useFuzzy ~= false -- Default to true
    
    -- 1. Direct mapping
    local mapped = self.TargetDefinitions.PlayerToEntity[player]
    if mapped and Defensive.IsValid(mapped) then
        return mapped
    end
    
    -- 2. Character
    local character = Defensive.SafeGet(player, "Character")
    if character and Defensive.IsValid(character) then
        return character
    end
    
    local playerName = Defensive.GetName(player)
    
    -- 3. Containers (with fuzzy support)
    local containerResult = self._containerManager:FindInContainers(playerName, useFuzzy)
    if containerResult then
        return containerResult
    end
    
    -- 4. Workspace direct
    local workspace = self._adapter:GetWorkspace()
    local wsChild = self._adapter:FindFirstChild(workspace, playerName)
    if wsChild and self._adapter:IsA(wsChild, "Model") then
        return wsChild
    end
    
    -- 5. DisplayName
    local displayName = Defensive.SafeGet(player, "DisplayName")
    if displayName and displayName ~= playerName then
        local displayChild = self._adapter:FindFirstChild(workspace, displayName)
        if displayChild and self._adapter:IsA(displayChild, "Model") then
            return displayChild
        end
        
        -- Try containers with display name
        local containerDisplayResult = self._containerManager:FindInContainers(displayName, useFuzzy)
        if containerDisplayResult then
            return containerDisplayResult
        end
    end
    
    -- 6. Fuzzy search in workspace (last resort)
    if useFuzzy then
        local workspaceChildren = self._adapter:GetChildren(workspace)
        local models = {}
        for _, child in ipairs(workspaceChildren) do
            if self._adapter:IsA(child, "Model") then
                table.insert(models, child)
            end
        end
        
        local bestMatch = FuzzyFindBest(playerName, models, self.Config.FuzzyMatchThreshold)
        if bestMatch then
            if self._logger then
                self._logger:Debug("Fuzzy workspace match:", playerName, "->", Defensive.GetName(bestMatch))
            end
            return bestMatch
        end
    end
    
    return nil
end

-- ============================================================================
-- PUBLIC API: CACHED PLAYER DATA
-- ============================================================================
function SemanticEngineModule:GetCachedPlayerData(player)
    if not player then
        return { isValid = false }
    end
    
    local cached = self._cache:Get(player)
    if cached then
        return cached
    end
    
    local data = self:BuildPlayerData(player)
    self._cache:Set(player, data)
    
    return data
end

function SemanticEngineModule:BuildPlayerData(player)
    local now = self._timeProvider()
    
    local model = self:FindEntityForPlayer(player)
    
    if not model then
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
    
    local isValidModel = Defensive.IsValid(model) or (type(model) == "table" and model.Parent)
    
    if not isValidModel then
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
    
    local anchor = self:GetAnchorPart(model)
    local humanoid = self._adapter:FindFirstChildOfClass(model, "Humanoid")
    local team = self:GetPlayerTeam(player)
    
    local health = 0
    local maxHealth = 100
    
    if humanoid then
        health = Defensive.SafeGet(humanoid, "Health") or 0
        maxHealth = Defensive.SafeGet(humanoid, "MaxHealth") or 100
    end
    
    if model then
        self:LinkPlayerToEntity(player, model)
    end
    
    local workspace = self._adapter:GetWorkspace()
    local anchorValid = anchor ~= nil and (
        Defensive.IsDescendantOf(anchor, workspace) or
        (type(anchor) == "table" and anchor.Parent)
    )
    
    return {
        isValid = anchorValid,
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
-- PUBLIC API: ANCHOR & HITBOX
-- ============================================================================
function SemanticEngineModule:GetAnchorPart(model)
    return self._heuristics:GetAnchorPart(model)
end

function SemanticEngineModule:IsHitboxPart(part)
    return self._heuristics:IsHitboxPart(part)
end

-- NEW: Get all hitbox parts in a model
function SemanticEngineModule:GetHitboxParts(model)
    return self._heuristics:GetHitboxParts(model)
end

-- ============================================================================
-- PUBLIC API: CACHE MANAGEMENT
-- ============================================================================
function SemanticEngineModule:ClearPlayerCache(player)
    self._cache:Clear(player)
end

function SemanticEngineModule:ClearAllCache()
    self._cache:ClearAll()
    self._heuristics:ClearCache()
end

-- ============================================================================
-- PUBLIC API: TEAM SYSTEM
-- ============================================================================
function SemanticEngineModule:DetectTeamSystemWithVoting()
    self._teamManager:DetectWithVoting()
    
    self.TeamSystem.Method = self._teamManager.method
    self.TeamSystem.CurrentPartition = self._teamManager.currentPartition
    self.TeamSystem.ForceFFA = self._teamManager.forceFFA
    self.TeamSystem.AutoDetected = self._teamManager.autoDetected
    self.TeamSystem.LastCheck = self._teamManager.lastCheck
end

function SemanticEngineModule:ScorePartition(partition)
    return self._teamManager:ScorePartition(partition)
end

function SemanticEngineModule:AutoDetectTeamSystem()
    self._teamManager:AutoDetect()
    
    self.TeamSystem.Method = self._teamManager.method
    self.TeamSystem.CurrentPartition = self._teamManager.currentPartition
    self.TeamSystem.ForceFFA = self._teamManager.forceFFA
    self.TeamSystem.AutoDetected = self._teamManager.autoDetected
end

function SemanticEngineModule:GetPlayerTeam(player)
    return self._teamManager:GetPlayerTeam(player)
end

function SemanticEngineModule:AreSameTeam(player1, player2)
    return self._teamManager:AreSameTeam(player1, player2)
end

-- ============================================================================
-- PUBLIC API: CONTAINER SCANNING
-- ============================================================================
function SemanticEngineModule:ScanForContainers()
    self._containerManager:Scan()
    
    self.ContainerSystem.KnownContainers = self._containerManager.knownContainers
    self.ContainerSystem.LastScan = self._containerManager.lastScan
    self.Stats.ContainersFound = self._metrics:Get("containers_found") + self._metrics:Get("containers_found_heuristic")
end

-- ============================================================================
-- PUBLIC API: REFRESH & HELPERS
-- ============================================================================
function SemanticEngineModule:RefreshAllPlayers()
    self._logger:Debug("Refreshing all players...")
    
    self._cache:ClearAll()
    
    local players = self._adapter:GetPlayers()
    for _, player in ipairs(players) do
        if player ~= self._localPlayer then
            self:TrackPlayer(player)
        end
    end
    
    self:DetectTeamSystemWithVoting()
end

function SemanticEngineModule:GetAllValidPlayers()
    local validPlayers = {}
    
    local players = self._adapter:GetPlayers()
    for _, player in ipairs(players) do
        if player ~= self._localPlayer then
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
-- PUBLIC API: METRICS & OBSERVABILITY (ENHANCED)
-- ============================================================================
function SemanticEngineModule:GetMetrics()
    local cacheStats = self._cache:GetStats()
    local connStats = self._connectionManager:GetStats()
    local allMetrics = self._metrics:GetAll()
    
    return {
        version = self.Version,
        initialized = self._initialized,
        uptime = allMetrics.uptime,
        
        cache = {
            hits = cacheStats.hits,
            misses = cacheStats.misses,
            hitRate = cacheStats.hitRate,
        },
        
        connections = connStats,
        
        counters = allMetrics.counters,
        gauges = allMetrics.gauges,
        errors = allMetrics.errors,
        
        stats = self.Stats,
        
        teamSystem = {
            method = self._teamManager.method,
            forceFFA = self._teamManager.forceFFA,
            resolverCount = #self._teamManager.customResolvers,
        },
        
        containers = {
            known = self._containerManager:GetContainerCount(),
            resolverCount = #self._containerManager.containerResolvers,
        },
        
        heuristics = {
            anchorResolvers = #self._heuristics.anchorResolvers,
            hitboxClassifiers = #self._heuristics.hitboxClassifiers,
        },
    }
end

function SemanticEngineModule:GetLogs()
    return self._logger:GetHistory()
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================
function SemanticEngineModule:Initialize(overrides)
    if self._initialized then
        self._logger:Warn("Already initialized. Call Destroy() first to reinitialize.")
        return self
    end
    
    overrides = overrides or {}
    
    if overrides.adapter then
        self:SetAdapter(overrides.adapter)
    end
    
    if overrides.timeProvider then
        self._timeProvider = overrides.timeProvider
    end
    
    self._logger:SetLevel(self.Config.LogLevel)
    
    self._logger:Info("Initializing Semantic Engine v" .. self.Version)
    
    self._localPlayer = self._adapter:GetLocalPlayer()
    
    self.Events = {
        PlayerTracked = self._eventEmitter:CreateEvent("PlayerTracked"),
        PlayerUntracked = self._eventEmitter:CreateEvent("PlayerUntracked"),
        ContainerFound = self._eventEmitter:CreateEvent("ContainerFound"),
        TeamDetected = self._eventEmitter:CreateEvent("TeamDetected"),
        EntityLinked = self._eventEmitter:CreateEvent("EntityLinked"),
    }
    
    self:ScanForContainers()
    self:DetectTeamSystemWithVoting()
    
    local players = self._adapter:GetPlayers()
    for _, player in ipairs(players) do
        if player ~= self._localPlayer then
            self:TrackPlayer(player)
        end
    end
    
    local playersService = self._adapter._Players or game:GetService("Players")
    
    if playersService then
        local addedEvent = Defensive.SafeGet(playersService, "PlayerAdded")
        if addedEvent then
            local conn = self._adapter:ConnectEvent(addedEvent, function(player)
                self._adapter:Wait(0.5)
                self:TrackPlayer(player)
                self._adapter:Delay(1, function()
                    self:DetectTeamSystemWithVoting()
                end)
            end)
            if conn then
                self._connectionManager:AddGlobal(conn)
            end
        end
        
        local removingEvent = Defensive.SafeGet(playersService, "PlayerRemoving")
        if removingEvent then
            local conn = self._adapter:ConnectEvent(removingEvent, function(player)
                self:UntrackPlayer(player)
            end)
            if conn then
                self._connectionManager:AddGlobal(conn)
            end
        end
    end
    
    self._adapter:Spawn(function()
        while self._initialized do
            local ok, err = pcall(function()
                local players = self._adapter:GetPlayers()
                for _, player in ipairs(players) do
                    if player ~= self._localPlayer then
                        local data = self._cache:Get(player)
                        if not data or not data.isValid then
                            self._cache:Clear(player)
                            local newData = self:BuildPlayerData(player)
                            if newData.isValid then
                                self._cache:Set(player, newData)
                            end
                        end
                    end
                end
                
                self:ScanForContainers()
                self:AutoDetectTeamSystem()
            end)
            
            if not ok then
                self._maintenanceErrorStreak = self._maintenanceErrorStreak + 1
                self._metrics:RecordError("maintenance", err)
                local delay = math.min(10, 2 * (2 ^ self._maintenanceErrorStreak))
                self._logger:Warn("Maintenance error, backing off for", delay, "seconds")
                self._adapter:Wait(delay)
            else
                self._maintenanceErrorStreak = 0
                self._adapter:Wait(2)
            end
        end
    end)
    
    self._initialized = true
    self._logger:Info("Initialized - Tracking", #players, "players")
    
    return self
end

-- ============================================================================
-- DESTROY
-- ============================================================================
function SemanticEngineModule:Destroy()
    self._logger:Info("Destroying Semantic Engine...")
    
    self._initialized = false
    
    self._connectionManager:ClearAll()
    
    self._cache:ClearAll()
    self._heuristics:ClearCache()
    self._containerManager:Clear()
    self._teamManager:Clear()
    
    self.TargetDefinitions = {
        HitboxParts = WeakKeys(),
        CombatModels = WeakKeys(),
        EntityToPlayer = WeakKeys(),
        PlayerToEntity = WeakKeys(),
    }
    
    self._eventEmitter:Destroy()
    self.Events = {}
    
    self._metrics:Reset()
    self._maintenanceErrorStreak = 0
    
    self._logger:Info("Destroyed")
end

-- ============================================================================
-- DEBUG (ENHANCED)
-- ============================================================================
function SemanticEngineModule:Debug()
    print("\n========== SEMANTIC ENGINE v" .. self.Version .. " DEBUG ==========")
    print("Initialized: " .. tostring(self._initialized))
    print("Debug Mode: " .. tostring(self.Config.Debug))
    print("Log Level: " .. self.Config.LogLevel)
    
    print("\n--- Adapter ---")
    print("  Type: " .. (self._adapter and getmetatable(self._adapter).__index == RobloxAdapter and "Roblox" or "Custom/Mock"))
    
    print("\n--- Config ---")
    for k, v in pairs(self.Config) do
        if type(v) ~= "table" then
            print("  " .. k .. ": " .. tostring(v))
        end
    end
    
    print("\n--- Team System ---")
    print("  Method: " .. self._teamManager.method)
    print("  ForceFFA: " .. tostring(self._teamManager.forceFFA))
    print("  AutoDetected: " .. tostring(self._teamManager.autoDetected))
    print("  Custom Resolvers: " .. #self._teamManager.customResolvers)
    print("  Proximity Enabled: " .. tostring(self._teamManager.enableProximityClustering))
    
    print("\n--- Containers ---")
    local containerCount = 0
    for container, info in pairs(self._containerManager.knownContainers) do
        containerCount = containerCount + 1
        local valid = Defensive.IsValid(container) or (type(container) == "table" and container.Parent)
        local source = info.source or "unknown"
        local score = info.score or 0
        print(string.format("  %s (valid: %s, source: %s, score: %.1f)", info.name, tostring(valid), source, score))
    end
    print("  Total Known: " .. containerCount)
    print("  Container Resolvers: " .. #self._containerManager.containerResolvers)
    
    print("\n--- Heuristics ---")
    print("  Anchor Resolvers: " .. #self._heuristics.anchorResolvers)
    print("  Team Resolvers: " .. #self._teamManager.customResolvers)
    print("  Hitbox Classifiers: " .. #self._heuristics.hitboxClassifiers)
    print("  Hitbox Volume Threshold: " .. self._heuristics.hitboxVolumeThreshold)
    
    print("\n--- Player Mappings ---")
    local mappingCount = 0
    for player, entity in pairs(self.TargetDefinitions.PlayerToEntity) do
        mappingCount = mappingCount + 1
        local valid = Defensive.IsValid(entity) or (type(entity) == "table" and entity.Parent)
        print("  " .. Defensive.GetName(player) .. " -> " .. Defensive.GetName(entity) .. " (valid: " .. tostring(valid) .. ")")
    end
    print("  Total Mappings: " .. mappingCount)
    
    print("\n--- Cache ---")
    local cacheStats = self._cache:GetStats()
    print("  Hits: " .. cacheStats.hits)
    print("  Misses: " .. cacheStats.misses)
    print("  Hit Rate: " .. string.format("%.2f%%", cacheStats.hitRate * 100))
    
    print("\n--- Connections ---")
    local connStats = self._connectionManager:GetStats()
    print("  Global: " .. connStats.global)
    print("  Per-Player: " .. connStats.perPlayer)
    
    print("\n--- Stats ---")
    for k, v in pairs(self.Stats) do
        print("  " .. k .. ": " .. tostring(v))
    end
    
    print("\n--- Errors ---")
    local allMetrics = self._metrics:GetAll()
    for name, info in pairs(allMetrics.errors) do
        print(string.format("  %s: count=%d, last=%s", name, info.count, info.lastError or "nil"))
    end
    
    print("=============================================\n")
end

-- ============================================================================
-- DUMP STATE (FOR UI)
-- ============================================================================
function SemanticEngineModule:DumpState()
    local playerMappings = {}
    for player, entity in pairs(self.TargetDefinitions.PlayerToEntity) do
        table.insert(playerMappings, {
            playerName = Defensive.GetName(player),
            entityName = Defensive.GetName(entity),
            valid = Defensive.IsValid(entity) or (type(entity) == "table" and entity.Parent),
        })
    end
    
    local containers = {}
    for container, info in pairs(self._containerManager.knownContainers) do
        table.insert(containers, {
            name = info.name,
            valid = Defensive.IsValid(container) or (type(container) == "table" and container.Parent),
            score = info.score or 0,
            source = info.source or "unknown",
        })
    end
    
    return {
        version = self.Version,
        initialized = self._initialized,
        teamMethod = self._teamManager.method,
        forceFFA = self._teamManager.forceFFA,
        playerMappings = playerMappings,
        containers = containers,
        stats = self.Stats,
        heuristics = {
            anchorResolvers = #self._heuristics.anchorResolvers,
            teamResolvers = #self._teamManager.customResolvers,
            hitboxClassifiers = #self._heuristics.hitboxClassifiers,
        },
        resolvers = {
            containerResolvers = #self._containerManager.containerResolvers,
            teamResolvers = #self._teamManager.customResolvers,
        },
    }
end

-- ============================================================================
-- COMPATIBILITY REPORT
-- ============================================================================
function SemanticEngineModule:CompatibilityReport()
    return {
        version = self.Version,
        breakingChanges = {},
        newFeatures = {
            "Dependency Injection (Create(dependencies))",
            "Adapter pattern (RobloxAdapter, MockAdapter)",
            "Time provider injection for deterministic testing",
            "Structured logging with levels",
            "Comprehensive metrics (GetMetrics())",
            "Rate limiting and backoff",
            "Defensive programming throughout",
            "Unit test support with mocks",
            "Destroy() for complete cleanup",
            "All heuristics are extensible",
            -- NEW in v3.1.0
            "Levenshtein fuzzy string matching",
            "Container resolvers with weights",
            "Heuristic container detection",
            "Team resolvers with weights",
            "Proximity clustering for team detection",
            "Volume-based hitbox classification",
            "Enhanced container scoring",
            "Weighted ensemble voting for teams",
        },
        deprecatedFeatures = {},
        maintainedFunctions = {
            "TrackPlayer", "UntrackPlayer", "LinkPlayerToEntity",
            "FindEntityForPlayer", "GetCachedPlayerData", "BuildPlayerData",
            "GetAnchorPart", "ClearPlayerCache", "ClearAllCache",
            "DetectTeamSystemWithVoting", "ScorePartition", "AutoDetectTeamSystem",
            "GetPlayerTeam", "AreSameTeam", "ScanForContainers",
            "RefreshAllPlayers", "GetAllValidPlayers", "Initialize", "Debug",
            "RegisterAnchorHeuristic", "RegisterTeamResolver",
            "RegisterHitboxClassifier", "RegisterContainer",
            "IsHitboxPart", "DumpState", "CompatibilityReport",
            -- NEW
            "RegisterTeamResolverWeighted", "RegisterContainerResolver",
            "GetHitboxParts",
        },
    }
end

-- ============================================================================
-- UNIT TESTS (ENHANCED)
-- ============================================================================
SemanticEngineModule.Tests = {}

function SemanticEngineModule.Tests.RunAll()
    local results = {
        passed = 0,
        failed = 0,
        errors = {},
    }
    
    local function test(name, fn)
        local ok, err = pcall(fn)
        if ok then
            results.passed = results.passed + 1
            print("  ✓ " .. name)
        else
            results.failed = results.failed + 1
            table.insert(results.errors, { name = name, error = err })
            print("  ✗ " .. name .. ": " .. tostring(err))
        end
    end
    
    print("\n========== SEMANTIC ENGINE TESTS ==========")
    
    local mockAdapter = MockAdapter.new({
        startTime = 1000,
    })
    
    local localPlayer = MockAdapter.CreateMockPlayer({ Name = "LocalPlayer", UserId = 1 })
    mockAdapter._localPlayer = localPlayer
    
    local player1Char, player1Humanoid, player1Root = MockAdapter.CreateMockCharacter({ 
        Name = "Player1",
        Position = { X = 0, Y = 5, Z = 0 },
    })
    local player1 = MockAdapter.CreateMockPlayer({
        Name = "Player1",
        UserId = 12345,
        Character = player1Char,
        Team = { Name = "Red" },
    })
    
    local player2Char, player2Humanoid, player2Root = MockAdapter.CreateMockCharacter({ 
        Name = "Player2",
        Position = { X = 100, Y = 5, Z = 100 },
    })
    local player2 = MockAdapter.CreateMockPlayer({
        Name = "Player2",
        UserId = 67890,
        Character = player2Char,
        Team = { Name = "Blue" },
    })
    
    mockAdapter._players = { localPlayer, player1, player2 }
    
    local engine = SemanticEngineModule.Create({
        adapter = mockAdapter,
        timeProvider = function() return mockAdapter:Now() end,
    })
    
    engine.Config.Debug = false
    
    -- Basic Tests
    test("Engine creates successfully", function()
        assert(engine ~= nil, "Engine should be created")
        assert(engine.Version == VERSION, "Version should match")
    end)
    
    test("Engine initializes", function()
        engine:Initialize()
        assert(engine._initialized == true, "Should be initialized")
    end)
    
    test("GetAnchorPart finds HumanoidRootPart", function()
        local anchor = engine:GetAnchorPart(player1Char)
        assert(anchor ~= nil, "Should find anchor")
        assert(anchor.Name == "HumanoidRootPart", "Should be HumanoidRootPart")
    end)
    
    -- Levenshtein Tests
    test("Levenshtein distance calculation", function()
        assert(Levenshtein("hello", "hello") == 0, "Same strings should be 0")
        assert(Levenshtein("hello", "hallo") == 1, "One char diff should be 1")
        assert(Levenshtein("", "hello") == 5, "Empty to string should be length")
    end)
    
    test("Fuzzy similarity works", function()
        local sim = FuzzySimilarity("Player1", "Player1")
        assert(sim == 1, "Identical should be 1")
        
        local sim2 = FuzzySimilarity("Player1", "Player2")
        assert(sim2 > 0.5 and sim2 < 1, "Similar should be between 0.5 and 1")
    end)
    
    -- Weighted Resolver Tests
    test("Container resolver with weight", function()
        local resolved = false
        engine:RegisterContainerResolver(function(adapter)
            resolved = true
            return nil
        end, 5.0)
        
        assert(#engine._containerManager.containerResolvers >= 1, "Should have resolver")
        engine:ScanForContainers()
        assert(resolved, "Resolver should have been called")
    end)
    
    test("Team resolver with weight", function()
        local called = false
        engine:RegisterTeamResolverWeighted(function(players)
            called = true
            local partition = {}
            for _, p in ipairs(players) do
                partition[p] = "TestTeam"
            end
            return partition
        end, 10.0)
        
        assert(#engine._teamManager.customResolvers >= 1, "Should have resolver")
        engine:DetectTeamSystemWithVoting()
        assert(called, "Resolver should have been called")
    end)
    
    -- Hitbox Tests
    test("IsHitboxPart classifies correctly", function()
        local headPart = { Name = "Head", ClassName = "BasePart", IsA = "BasePart", Parent = true }
        local hitboxPart = { Name = "Hitbox", ClassName = "BasePart", IsA = "BasePart", Parent = true }
        local normalPart = { Name = "Arm", ClassName = "BasePart", IsA = "BasePart", Parent = true }
        
        assert(engine:IsHitboxPart(headPart) == true, "Head should be hitbox")
        assert(engine:IsHitboxPart(hitboxPart) == true, "Hitbox should be hitbox")
        assert(engine:IsHitboxPart(normalPart) == false, "Arm should not be hitbox")
    end)
    
    test("GetHitboxParts returns array", function()
        local parts = engine:GetHitboxParts(player1Char)
        assert(type(parts) == "table", "Should return table")
    end)
    
    -- Team Detection Tests
    test("Team detection identifies different teams", function()
        engine:DetectTeamSystemWithVoting()
        local areSame = engine:AreSameTeam(player1, player2)
        assert(areSame == false, "Players on different teams should not be same team")
    end)
    
    -- Metrics Tests
    test("Metrics tracking enhanced", function()
        local metrics = engine:GetMetrics()
        assert(metrics ~= nil, "Should get metrics")
        assert(metrics.containers ~= nil, "Should have containers metrics")
        assert(metrics.teamSystem.resolverCount ~= nil, "Should have resolver count")
    end)
    
    -- Cleanup
    test("Destroy cleans up properly", function()
        engine:Destroy()
        assert(engine._initialized == false, "Should be uninitialized")
        
        local connStats = engine._connectionManager:GetStats()
        assert(connStats.global == 0, "Should have no global connections")
    end)
    
    -- Summary
    print("\n--- Results ---")
    print("  Passed: " .. results.passed)
    print("  Failed: " .. results.failed)
    
    if results.failed > 0 then
        print("\n--- Failures ---")
        for _, err in ipairs(results.errors) do
            print("  " .. err.name .. ": " .. tostring(err.error))
        end
    end
    
    print("=============================================\n")
    
    return results
end

-- ============================================================================
-- BACKWARD COMPATIBILITY WRAPPER
-- ============================================================================
local function CreateBackwardCompatibleWrapper()
    local Core = _G.ForgeHubCore
    if not Core then
        warn("[Semantic] ForgeHubCore not found. Module loaded but not attached to Core.")
        return SemanticEngineModule
    end
    
    local instance = SemanticEngineModule.Create({
        Players = Core.Players,
        Workspace = Core.Workspace,
        RunService = Core.RunService,
    })
    
    instance._localPlayer = Core.LocalPlayer
    
    Core.SemanticEngine = instance
    Core.PlayerCache = instance._cache
    
    Core.SemanticEngineModule = SemanticEngineModule
    Core.SemanticAdapters = {
        Roblox = RobloxAdapter,
        Mock = MockAdapter,
    }
    
    return instance
end

-- ============================================================================
-- EXPORTS
-- ============================================================================
SemanticEngineModule.Adapters = {
    Roblox = RobloxAdapter,
    Mock = MockAdapter,
}

SemanticEngineModule.Utils = {
    Defensive = Defensive,
    RateLimiter = RateLimiter,
    Throttle = Throttle,
    Logger = Logger,
    Metrics = Metrics,
    WeakKeys = WeakKeys,
    WeakValues = WeakValues,
    Levenshtein = Levenshtein,
    FuzzySimilarity = FuzzySimilarity,
    FuzzyFindBest = FuzzyFindBest,
    VectorUtils = VectorUtils,
    ProximityClustering = ProximityClustering,
}

SemanticEngineModule.LOG_LEVELS = LOG_LEVELS

local instance = CreateBackwardCompatibleWrapper()

return instance or SemanticEngineModule