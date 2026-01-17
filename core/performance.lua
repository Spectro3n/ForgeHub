-- ============================================================================
-- FORGEHUB - PERFORMANCE MODULE v2.0 (FULLY OPTIMIZED)
-- ============================================================================

local Core = _G.ForgeHubCore
if not Core then
    error("ForgeHubCore não encontrado! Carregue main.lua primeiro.")
end

-- ============================================================================
-- LOCALIZED FUNCTIONS (Prioridade 8 - micro-otimização)
-- ============================================================================
local tick = tick
local pcall = pcall
local pairs = pairs
local ipairs = ipairs
local type = type
local math_min = math.min
local math_max = math.max
local math_floor = math.floor
local math_clamp = math.clamp
local table_insert = table.insert
local table_remove = table.remove
local tostring = tostring
local warn = warn
local string_format = string.format

-- ============================================================================
-- ERROR LOG SYSTEM (Ring Buffer - Prioridade 10)
-- ============================================================================
local ErrorLog = {
    Count = 0,
    Buffer = {},
    BufferSize = 50,
    WriteIndex = 1,
}

-- Ring buffer para erros - nunca cresce, sempre O(1)
local function LogError(context, err)
    ErrorLog.Count = ErrorLog.Count + 1
    ErrorLog.Buffer[ErrorLog.WriteIndex] = {
        context = context or "Unknown",
        error = tostring(err),
        time = tick()
    }
    ErrorLog.WriteIndex = (ErrorLog.WriteIndex % ErrorLog.BufferSize) + 1
end

-- SafeCall otimizado - usar apenas onde necessário (Prioridade 7)
local function SafeCall(fn, context)
    local ok, err = pcall(fn)
    if not ok then
        LogError(context, err)
        warn(string_format("[ForgeHub ERROR] %s: %s", context or "Unknown", err))
    end
    return ok
end

-- SafeCall leve - sem logging, para hot paths
local function SafeCallLight(fn)
    local ok = pcall(fn)
    return ok
end

-- ============================================================================
-- ADAPTIVE PERFORMANCE MANAGER (Prioridades 1, 2, 3)
-- ============================================================================
local PerformanceManager = {
    -- FPS com EMA (Prioridade 1)
    currentFPS = 60,
    targetFPS = 60,
    lastTick = tick(),
    emaAlpha = 0.3, -- 0.25-0.6 para reatividade
    
    -- Panic system
    panicLevel = 0,
    panicStartTime = 0,
    lastPanicCheck = 0,
    
    -- ESP settings adaptivos
    espInterval = 0.033,
    espSlices = 3,
    
    -- Token Bucket para Raycasts (Prioridade 3)
    raycastTokens = 6,
    raycastMaxTokens = 10,
    raycastRefillRate = 8, -- tokens por segundo
    lastTokenRefill = tick(),
    
    -- Budgets por panic level
    budgets = {
        [0] = { espInterval = 0.033, espSlices = 3, raycastMax = 10, refillRate = 10 },
        [1] = { espInterval = 0.1,   espSlices = 5, raycastMax = 6,  refillRate = 6 },
        [2] = { espInterval = 0.2,   espSlices = 8, raycastMax = 4,  refillRate = 4 },
        [3] = { espInterval = 0.3,   espSlices = 10, raycastMax = 2, refillRate = 2 },
    },
    
    -- Frame tracking
    frameCount = 0,
    lastSecondMark = tick(),
    instantFPS = 60,
}

-- EMA FPS Update - chamado todo frame (Prioridade 1)
function PerformanceManager:UpdateFPS()
    local now = tick()
    local dt = now - self.lastTick
    self.lastTick = now
    
    -- Evita divisão por zero e valores absurdos
    if dt > 0 and dt < 1 then
        local instantFPS = 1 / dt
        -- EMA: fps = alpha * instantFPS + (1-alpha) * fps
        self.currentFPS = self.emaAlpha * instantFPS + (1 - self.emaAlpha) * self.currentFPS
        self.currentFPS = math_clamp(self.currentFPS, 1, 240)
    end
    
    -- Contagem para stats (opcional)
    self.frameCount = self.frameCount + 1
    if now - self.lastSecondMark >= 1 then
        self.instantFPS = self.frameCount
        self.frameCount = 0
        self.lastSecondMark = now
    end
    
    return dt
end

-- Force Sample - recalcula imediatamente (Prioridade 1)
function PerformanceManager:ForceSample()
    self:UpdateFPS()
    self:AdjustForFPS()
    self:RefillTokens()
end

-- Ajusta budgets baseado no FPS
function PerformanceManager:AdjustForFPS()
    local fps = self.currentFPS
    local oldPanic = self.panicLevel
    
    if fps < 20 then
        self.panicLevel = 3
    elseif fps < 30 then
        self.panicLevel = 2
    elseif fps < 45 then
        self.panicLevel = 1
    else
        self.panicLevel = 0
    end
    
    -- Aplicar budgets
    local budget = self.budgets[self.panicLevel]
    if budget then
        self.espInterval = budget.espInterval
        self.espSlices = budget.espSlices
        self.raycastMaxTokens = budget.raycastMax
        self.raycastRefillRate = budget.refillRate
    end
    
    -- Track panic start
    if self.panicLevel >= 2 and oldPanic < 2 then
        self.panicStartTime = tick()
    elseif self.panicLevel < 2 then
        self.panicStartTime = 0
    end
end

-- Token Bucket: Refill (Prioridade 3)
function PerformanceManager:RefillTokens()
    local now = tick()
    local dt = now - self.lastTokenRefill
    self.lastTokenRefill = now
    
    -- Adiciona tokens baseado no tempo passado
    self.raycastTokens = math_min(
        self.raycastMaxTokens,
        self.raycastTokens + (self.raycastRefillRate * dt)
    )
end

-- Token Bucket: Consume (Prioridade 3)
function PerformanceManager:CanRaycast()
    -- Refill primeiro
    self:RefillTokens()
    
    if self.raycastTokens >= 1 then
        self.raycastTokens = self.raycastTokens - 1
        return true
    end
    return false
end

-- Consume múltiplos tokens (para operações pesadas)
function PerformanceManager:ConsumeTokens(amount)
    self:RefillTokens()
    
    if self.raycastTokens >= amount then
        self.raycastTokens = self.raycastTokens - amount
        return true
    end
    return false
end

-- Update principal - leve, chamado todo frame
function PerformanceManager:Update()
    local dt = self:UpdateFPS()
    
    -- Ajusta budgets a cada ~100ms para não sobrecarregar
    local now = tick()
    if now - self.lastPanicCheck >= 0.1 then
        self:AdjustForFPS()
        self.lastPanicCheck = now
    end
    
    return dt
end

-- Reset raycast counter (legacy compatibility)
function PerformanceManager:ResetRaycastCounter()
    -- Token bucket auto-gerencia, mas força refill
    self:RefillTokens()
end

-- ============================================================================
-- ENTITY DIRTY SYSTEM (Prioridade 2, 6)
-- ============================================================================
local EntityTracker = {
    entities = {}, -- [player] = { dirty = bool, lastUpdate = tick, priority = "high"|"medium"|"low", version = int }
    dirtyQueue = { high = {}, medium = {}, low = {} },
    dirtyCount = 0,
    globalVersion = 0,
}

function EntityTracker:Register(player)
    if not player then return end
    
    self.entities[player] = {
        dirty = true, -- Começa sujo para forçar primeiro update
        lastUpdate = 0,
        priority = "medium",
        version = 0,
        lastPosition = nil,
        lastHealth = nil,
    }
    
    self:MarkDirty(player, "high") -- Novo player = alta prioridade
end

function EntityTracker:Unregister(player)
    if not player then return end
    
    -- Remove das filas
    local data = self.entities[player]
    if data then
        for priority, queue in pairs(self.dirtyQueue) do
            for i, p in ipairs(queue) do
                if p == player then
                    table_remove(queue, i)
                    break
                end
            end
        end
    end
    
    self.entities[player] = nil
end

function EntityTracker:MarkDirty(player, priority)
    local data = self.entities[player]
    if not data then return end
    
    priority = priority or "medium"
    
    -- Se já está sujo com prioridade maior ou igual, ignora
    if data.dirty then
        local priorities = { high = 3, medium = 2, low = 1 }
        if priorities[data.priority] >= priorities[priority] then
            return
        end
        -- Remove da fila antiga
        local oldQueue = self.dirtyQueue[data.priority]
        for i, p in ipairs(oldQueue) do
            if p == player then
                table_remove(oldQueue, i)
                break
            end
        end
    end
    
    data.dirty = true
    data.priority = priority
    data.version = data.version + 1
    self.globalVersion = self.globalVersion + 1
    
    table_insert(self.dirtyQueue[priority], player)
    self.dirtyCount = self.dirtyCount + 1
end

function EntityTracker:ClearDirty(player)
    local data = self.entities[player]
    if not data or not data.dirty then return end
    
    -- Remove da fila
    local queue = self.dirtyQueue[data.priority]
    for i, p in ipairs(queue) do
        if p == player then
            table_remove(queue, i)
            break
        end
    end
    
    data.dirty = false
    data.lastUpdate = tick()
    self.dirtyCount = math_max(0, self.dirtyCount - 1)
end

-- Processa quota de entidades sujas por frame (Prioridade 4)
function EntityTracker:ProcessDirtyBatch(quotas)
    quotas = quotas or { high = 4, medium = 2, low = 1 }
    local processed = {}
    
    for priority, quota in pairs(quotas) do
        local queue = self.dirtyQueue[priority]
        local count = 0
        
        while count < quota and #queue > 0 do
            local player = table_remove(queue, 1)
            local data = self.entities[player]
            
            if data and data.dirty then
                table_insert(processed, { player = player, priority = priority })
                data.dirty = false
                data.lastUpdate = tick()
                self.dirtyCount = math_max(0, self.dirtyCount - 1)
                count = count + 1
            end
        end
    end
    
    return processed
end

-- Detecta mudanças (versioning) - Prioridade 6
function EntityTracker:CheckForChanges(player, position, health)
    local data = self.entities[player]
    if not data then return false end
    
    local changed = false
    local priority = "low"
    
    -- Check posição com tolerância
    if position and data.lastPosition then
        local delta = (position - data.lastPosition).Magnitude
        if delta > 2 then -- Tolerância de 2 studs
            changed = true
            priority = delta > 10 and "high" or "medium"
        end
    elseif position then
        changed = true
        priority = "high"
    end
    
    -- Check saúde
    if health and data.lastHealth then
        if math.abs(health - data.lastHealth) > 1 then
            changed = true
            priority = "high" -- Mudança de saúde é sempre alta prioridade
        end
    end
    
    -- Atualiza cache
    if position then data.lastPosition = position end
    if health then data.lastHealth = health end
    
    if changed then
        self:MarkDirty(player, priority)
    end
    
    return changed
end

function EntityTracker:GetData(player)
    return self.entities[player]
end

function EntityTracker:IsDirty(player)
    local data = self.entities[player]
    return data and data.dirty
end

-- ============================================================================
-- LRU CACHE (Prioridade 5)
-- ============================================================================
local function CreateLRUCache(maxSize)
    local cache = {
        maxSize = maxSize or 100,
        size = 0,
        head = nil, -- Most recently used
        tail = nil, -- Least recently used
        map = {},   -- key -> node
    }
    
    local function createNode(key, value)
        return {
            key = key,
            value = value,
            prev = nil,
            next = nil,
        }
    end
    
    local function removeNode(self, node)
        if node.prev then
            node.prev.next = node.next
        else
            self.head = node.next
        end
        
        if node.next then
            node.next.prev = node.prev
        else
            self.tail = node.prev
        end
        
        node.prev = nil
        node.next = nil
    end
    
    local function addToHead(self, node)
        node.next = self.head
        node.prev = nil
        
        if self.head then
            self.head.prev = node
        end
        
        self.head = node
        
        if not self.tail then
            self.tail = node
        end
    end
    
    function cache:Get(key)
        local node = self.map[key]
        if not node then
            return nil, false
        end
        
        -- Move to head (most recently used)
        removeNode(self, node)
        addToHead(self, node)
        
        return node.value, true
    end
    
    function cache:Set(key, value)
        local node = self.map[key]
        
        if node then
            -- Update existing
            node.value = value
            removeNode(self, node)
            addToHead(self, node)
        else
            -- Create new
            node = createNode(key, value)
            self.map[key] = node
            addToHead(self, node)
            self.size = self.size + 1
            
            -- Evict LRU if over capacity
            if self.size > self.maxSize then
                local lru = self.tail
                if lru then
                    removeNode(self, lru)
                    self.map[lru.key] = nil
                    self.size = self.size - 1
                end
            end
        end
    end
    
    function cache:Remove(key)
        local node = self.map[key]
        if node then
            removeNode(self, node)
            self.map[key] = nil
            self.size = self.size - 1
        end
    end
    
    function cache:Clear()
        self.map = {}
        self.head = nil
        self.tail = nil
        self.size = 0
    end
    
    -- Evicção gradual (Prioridade 11)
    function cache:EvictGradual(count)
        count = count or 5
        local evicted = 0
        
        while evicted < count and self.tail do
            local lru = self.tail
            removeNode(self, lru)
            self.map[lru.key] = nil
            self.size = self.size - 1
            evicted = evicted + 1
        end
        
        return evicted
    end
    
    return cache
end

-- ============================================================================
-- RAYCAST CACHE (usando LRU - Prioridade 5)
-- ============================================================================
local RaycastCache = {
    Cache = CreateLRUCache(150), -- LRU com 150 entradas
    CurrentFrameId = 0,
    FrameResults = {}, -- Cache rápido por frame
}

function RaycastCache:Get(key)
    -- Primeiro checa cache do frame atual (O(1))
    local frameResult = self.FrameResults[key]
    if frameResult then
        return frameResult, true
    end
    
    -- Depois checa LRU
    local cached, found = self.Cache:Get(key)
    if found and cached.frameId == self.CurrentFrameId then
        return cached.result, true
    end
    
    return nil, false
end

function RaycastCache:Set(key, result)
    if result == nil then return end
    
    -- Salva no cache do frame (acesso rápido)
    self.FrameResults[key] = result
    
    -- Salva no LRU
    self.Cache:Set(key, {
        result = result,
        frameId = self.CurrentFrameId
    })
end

function RaycastCache:NextFrame()
    self.CurrentFrameId = self.CurrentFrameId + 1
    self.FrameResults = {} -- Limpa cache do frame
    
    -- Evicção gradual a cada 30 frames
    if self.CurrentFrameId % 30 == 0 then
        self.Cache:EvictGradual(10)
    end
end

function RaycastCache:Clear()
    self.Cache:Clear()
    self.FrameResults = {}
end

-- ============================================================================
-- DRAWING POOL (Prioridade 9 - Pooling agressivo)
-- ============================================================================
local MAX_POOL_SIZE = 80
local PREALLOCATE_COUNT = 20

local DrawingPool = {
    Squares = {},
    Texts = {},
    Lines = {},
    Circles = {},
    
    Stats = {
        Created = 0,
        Reused = 0,
        Released = 0,
        Destroyed = 0,
        Preallocated = 0,
    },
    
    Initialized = false,
}

-- Pré-alocação (Prioridade 9)
function DrawingPool:Preallocate(countPerType)
    if not (Core.DrawingOK and Drawing) then return end
    
    countPerType = countPerType or PREALLOCATE_COUNT
    
    local types = {
        { name = "Square", pool = self.Squares },
        { name = "Text", pool = self.Texts },
        { name = "Line", pool = self.Lines },
        { name = "Circle", pool = self.Circles },
    }
    
    for _, typeInfo in ipairs(types) do
        for i = 1, countPerType do
            local success, obj = pcall(function()
                return Drawing.new(typeInfo.name)
            end)
            
            if success and obj then
                obj.Visible = false
                table_insert(typeInfo.pool, obj)
                self.Stats.Preallocated = self.Stats.Preallocated + 1
            end
        end
    end
    
    self.Initialized = true
end

-- Acquire sem pcall no hot path (Prioridade 7)
function DrawingPool:Acquire(drawType)
    if not (Core.DrawingOK and Drawing) then return nil end
    
    local pool = self[drawType .. "s"]
    if not pool then return nil end
    
    -- Tenta pegar do pool primeiro
    local obj = table_remove(pool)
    if obj then
        obj.Visible = false
        self.Stats.Reused = self.Stats.Reused + 1
        return obj
    end
    
    -- Cria novo (sem pcall para velocidade, assume Drawing está OK)
    local success, newObj = pcall(function()
        return Drawing.new(drawType)
    end)
    
    if success and newObj then
        self.Stats.Created = self.Stats.Created + 1
        return newObj
    end
    
    return nil
end

-- Release otimizado - reset mínimo (Prioridade 9)
function DrawingPool:Release(drawType, obj)
    if not obj then return end
    
    local pool = self[drawType .. "s"]
    if not pool then
        pcall(function() obj:Remove() end)
        self.Stats.Destroyed = self.Stats.Destroyed + 1
        return
    end
    
    -- Pool cheio? Destroi
    if #pool >= MAX_POOL_SIZE then
        pcall(function() obj:Remove() end)
        self.Stats.Destroyed = self.Stats.Destroyed + 1
        return
    end
    
    -- Reset mínimo - apenas Visible (Prioridade 9)
    obj.Visible = false
    table_insert(pool, obj)
    self.Stats.Released = self.Stats.Released + 1
end

-- Acquire batch (para ESP)
function DrawingPool:AcquireBatch(drawType, count)
    local objects = {}
    for i = 1, count do
        local obj = self:Acquire(drawType)
        if obj then
            table_insert(objects, obj)
        end
    end
    return objects
end

function DrawingPool:Clear()
    for poolName, pool in pairs(self) do
        if type(pool) == "table" and poolName ~= "Stats" then
            for _, obj in ipairs(pool) do
                pcall(function() obj:Remove() end)
            end
            self[poolName] = {}
        end
    end
    self.Stats.Destroyed = self.Stats.Destroyed + self.Stats.Created
end

-- ============================================================================
-- PROFILER (Ring Buffer - Prioridade 10)
-- ============================================================================
local Profiler = {
    -- Contadores do frame atual
    RaycastsThisFrame = 0,
    ESPUpdatesThisFrame = 0,
    
    -- Stats por segundo
    RaycastsPerSecond = 0,
    ESPUpdatesPerSecond = 0,
    
    -- Ring buffer para histórico (tamanho fixo)
    HistorySize = 60,
    HistoryIndex = 1,
    FPSHistory = {},
    RaycastHistory = {},
    
    LastSecond = tick(),
}

-- Inicializa ring buffers
for i = 1, Profiler.HistorySize do
    Profiler.FPSHistory[i] = 60
    Profiler.RaycastHistory[i] = 0
end

function Profiler:RecordRaycast()
    self.RaycastsThisFrame = self.RaycastsThisFrame + 1
end

function Profiler:RecordESPUpdate()
    self.ESPUpdatesThisFrame = self.ESPUpdatesThisFrame + 1
end

function Profiler:Update()
    local now = tick()
    
    if now - self.LastSecond >= 1 then
        -- Salva no ring buffer
        self.FPSHistory[self.HistoryIndex] = PerformanceManager.currentFPS
        self.RaycastHistory[self.HistoryIndex] = self.RaycastsThisFrame
        
        -- Avança índice (circular)
        self.HistoryIndex = (self.HistoryIndex % self.HistorySize) + 1
        
        -- Atualiza stats
        self.RaycastsPerSecond = self.RaycastsThisFrame
        self.ESPUpdatesPerSecond = self.ESPUpdatesThisFrame
        
        -- Reset contadores
        self.RaycastsThisFrame = 0
        self.ESPUpdatesThisFrame = 0
        self.LastSecond = now
    end
end

-- Calcula média do histórico
function Profiler:GetAverageFPS()
    local sum = 0
    for i = 1, self.HistorySize do
        sum = sum + self.FPSHistory[i]
    end
    return sum / self.HistorySize
end

function Profiler:GetStats()
    return {
        fps = PerformanceManager.currentFPS,
        avgFPS = self:GetAverageFPS(),
        raycastsPerSec = self.RaycastsPerSecond,
        espUpdatesPerSec = self.ESPUpdatesPerSecond,
        panicLevel = PerformanceManager.panicLevel,
        raycastTokens = PerformanceManager.raycastTokens,
        dirtyEntities = EntityTracker.dirtyCount,
        cacheSize = RaycastCache.Cache.size,
    }
end

-- ============================================================================
-- PRIORITY QUEUE PARA UPDATES (Prioridade 4)
-- ============================================================================
local UpdateQueue = {
    queues = {
        critical = {}, -- Deve processar imediatamente
        high = {},     -- Muito importante
        medium = {},   -- Normal
        low = {},      -- Pode esperar
    },
    
    -- Quotas adaptativas baseadas em panic level
    quotas = {
        [0] = { critical = 10, high = 6, medium = 4, low = 2 },
        [1] = { critical = 8,  high = 4, medium = 2, low = 1 },
        [2] = { critical = 5,  high = 3, medium = 1, low = 0 },
        [3] = { critical = 3,  high = 2, medium = 0, low = 0 },
    }
}

function UpdateQueue:Push(priority, item)
    local queue = self.queues[priority]
    if queue then
        table_insert(queue, item)
    end
end

function UpdateQueue:ProcessFrame()
    local panicLevel = PerformanceManager.panicLevel
    local quota = self.quotas[panicLevel] or self.quotas[0]
    local processed = {}
    
    for priority, limit in pairs(quota) do
        local queue = self.queues[priority]
        local count = 0
        
        while count < limit and #queue > 0 do
            local item = table_remove(queue, 1)
            table_insert(processed, { priority = priority, item = item })
            count = count + 1
        end
    end
    
    return processed
end

function UpdateQueue:Clear()
    for priority, queue in pairs(self.queues) do
        self.queues[priority] = {}
    end
end

function UpdateQueue:GetPendingCount()
    local total = 0
    for _, queue in pairs(self.queues) do
        total = total + #queue
    end
    return total
end

-- ============================================================================
-- FRAME MANAGER (Coordena todos os sistemas)
-- ============================================================================
local FrameManager = {
    lastUpdate = tick(),
    frameNumber = 0,
}

function FrameManager:BeginFrame()
    self.frameNumber = self.frameNumber + 1
    local dt = PerformanceManager:Update()
    RaycastCache:NextFrame()
    return dt
end

function FrameManager:EndFrame()
    Profiler:Update()
end

function FrameManager:GetFrameNumber()
    return self.frameNumber
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================
local function Initialize()
    -- Pré-aloca objetos Drawing
    if Core.DrawingOK then
        DrawingPool:Preallocate(PREALLOCATE_COUNT)
    end
    
    print("[Performance] Module v2.0 initialized")
    print(string_format("  - Preallocated: %d drawing objects", DrawingPool.Stats.Preallocated))
    print("  - LRU Cache: 150 entries")
    print("  - Token Bucket: enabled")
    print("  - Entity Tracking: enabled")
end

-- Auto-initialize
task.spawn(Initialize)

-- ============================================================================
-- EXPORT
-- ============================================================================
Core.SafeCall = SafeCall
Core.SafeCallLight = SafeCallLight
Core.ErrorLog = ErrorLog
Core.PerformanceManager = PerformanceManager
Core.DrawingPool = DrawingPool
Core.RaycastCache = RaycastCache
Core.Profiler = Profiler
Core.EntityTracker = EntityTracker
Core.UpdateQueue = UpdateQueue
Core.FrameManager = FrameManager
Core.CreateLRUCache = CreateLRUCache

return {
    SafeCall = SafeCall,
    SafeCallLight = SafeCallLight,
    ErrorLog = ErrorLog,
    PerformanceManager = PerformanceManager,
    DrawingPool = DrawingPool,
    RaycastCache = RaycastCache,
    Profiler = Profiler,
    EntityTracker = EntityTracker,
    UpdateQueue = UpdateQueue,
    FrameManager = FrameManager,
    CreateLRUCache = CreateLRUCache,
}