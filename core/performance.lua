-- ============================================================================
-- FORGEHUB - PERFORMANCE MODULE
-- ============================================================================

local Core = _G.ForgeHubCore
if not Core then
    error("ForgeHubCore não encontrado! Carregue main.lua primeiro.")
end

-- ============================================================================
-- ERROR LOG SYSTEM
-- ============================================================================
local ErrorLog = {
    Count = 0,
    LastErrors = {},
    MaxLogSize = 50,
}

local function SafeCall(fn, context)
    local ok, err = pcall(fn)
    if not ok then
        ErrorLog.Count = ErrorLog.Count + 1
        table.insert(ErrorLog.LastErrors, 1, {
            context = context or "Unknown",
            error = tostring(err),
            time = tick()
        })
        
        if #ErrorLog.LastErrors > ErrorLog.MaxLogSize then
            table.remove(ErrorLog.LastErrors)
        end
        
        warn(string.format("[ForgeHub ERROR] %s: %s", context or "Unknown", err))
    end
    return ok
end

-- ============================================================================
-- ADAPTIVE PERFORMANCE MANAGER
-- ============================================================================
local PerformanceManager = {
    currentFPS = 60,
    targetFPS = 60,
    lastTick = tick(),
    frameCount = 0,
    fpsUpdateTime = tick(),
    
    panicLevel = 0,
    panicStartTime = 0,
    
    espInterval = 0.033,
    espSlices = 3,
    raycastBudget = 6,
    raycastsThisFrame = 0,
    
    originalSettings = {},
}

function PerformanceManager:Update()
    local now = tick()
    local dt = now - self.lastTick
    self.lastTick = now
    
    self.frameCount = self.frameCount + 1
    if now - self.fpsUpdateTime >= 1 then
        self.currentFPS = self.frameCount / (now - self.fpsUpdateTime)
        self.frameCount = 0
        self.fpsUpdateTime = now
        
        self:AdjustForFPS()
    end
end

function PerformanceManager:AdjustForFPS()
    local fps = self.currentFPS
    
    if fps < 20 then
        self.panicLevel = 3
    elseif fps < 30 then
        self.panicLevel = 2
    elseif fps < 45 then
        self.panicLevel = 1
    else
        self.panicLevel = 0
    end
    
    if self.panicLevel >= 2 then
        self.espInterval = 0.2
        self.espSlices = 8
        self.raycastBudget = 3
        
        if self.panicStartTime == 0 then
            self.panicStartTime = tick()
        end
    elseif self.panicLevel == 1 then
        self.espInterval = 0.1
        self.espSlices = 5
        self.raycastBudget = 4
    else
        self.espInterval = 0.033
        self.espSlices = 3
        self.raycastBudget = 6
        self.panicStartTime = 0
    end
end

function PerformanceManager:CanRaycast()
    if self.raycastsThisFrame >= self.raycastBudget then
        return false
    end
    self.raycastsThisFrame = self.raycastsThisFrame + 1
    return true
end

function PerformanceManager:ResetRaycastCounter()
    self.raycastsThisFrame = 0
end

-- ============================================================================
-- DRAWING POOL
-- ============================================================================
local MAX_POOL_SIZE = 60

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
    }
}

function DrawingPool:Acquire(type)
    if not (Core.DrawingOK and Drawing) then return nil end
    
    local pool = self[type .. "s"]
    if not pool then return nil end
    
    local obj = table.remove(pool)
    if obj then
        obj.Visible = false
        self.Stats.Reused = self.Stats.Reused + 1
        return obj
    end
    
    local success, newObj = pcall(function()
        return Drawing.new(type)
    end)
    
    if success and newObj then
        self.Stats.Created = self.Stats.Created + 1
        return newObj
    end
    
    return nil
end

function DrawingPool:Release(type, obj)
    if not obj then return end
    
    local pool = self[type .. "s"]
    if not pool then 
        SafeCall(function() obj:Remove() end, "DrawingPool:Release")
        self.Stats.Destroyed = self.Stats.Destroyed + 1
        return 
    end
    
    if #pool >= MAX_POOL_SIZE then
        SafeCall(function() obj:Remove() end, "DrawingPool:Release")
        self.Stats.Destroyed = self.Stats.Destroyed + 1
        return
    end
    
    SafeCall(function()
        obj.Visible = false
        obj.Transparency = 1
        table.insert(pool, obj)
        self.Stats.Released = self.Stats.Released + 1
    end, "DrawingPool:Release")
end

function DrawingPool:Clear()
    for poolName, pool in pairs(self) do
        if type(pool) == "table" and poolName ~= "Stats" then
            for _, obj in ipairs(pool) do
                SafeCall(function() obj:Remove() end, "DrawingPool:Clear")
            end
            self[poolName] = {}
        end
    end
end

-- ============================================================================
-- RAYCAST CACHE
-- ============================================================================
local RaycastCache = {
    Cache = {},
    CurrentFrameId = 0,
    MaxCacheSize = 50,
}

function RaycastCache:Get(key)
    local cached = self.Cache[key]
    if cached and cached.frameId == self.CurrentFrameId then
        return cached.result, true
    end
    return nil, false
end

function RaycastCache:Set(key, result)
    if result == nil then return end
    
    self.Cache[key] = {
        result = result,
        frameId = self.CurrentFrameId
    }
    
    local count = 0
    for k, v in pairs(self.Cache) do
        count = count + 1
        if count > self.MaxCacheSize then
            self.Cache[k] = nil
        end
    end
end

function RaycastCache:NextFrame()
    self.CurrentFrameId = self.CurrentFrameId + 1
    
    if self.CurrentFrameId % 60 == 0 then
        self.Cache = {}
    end
end

-- ============================================================================
-- PROFILER
-- ============================================================================
local Profiler = {
    RaycastsThisFrame = 0,
    RaycastsPerSecond = 0,
    ESPUpdatesThisFrame = 0,
    ESPUpdatesPerSecond = 0,
    LastSecond = tick(),
    FrameSamples = {},
    MaxSamples = 60,
}

function Profiler:RecordRaycast()
    self.RaycastsThisFrame = self.RaycastsThisFrame + 1
end

function Profiler:RecordESPUpdate()
    self.ESPUpdatesThisFrame = self.ESPUpdatesThisFrame + 1
end

function Profiler:Update()
    local now = tick()
    
    if now - self.LastSecond >= 1 then
        self.RaycastsPerSecond = self.RaycastsThisFrame
        self.ESPUpdatesPerSecond = self.ESPUpdatesThisFrame
        self.RaycastsThisFrame = 0
        self.ESPUpdatesThisFrame = 0
        self.LastSecond = now
    end
end

-- ============================================================================
-- EXPORT
-- ============================================================================
Core.SafeCall = SafeCall
Core.ErrorLog = ErrorLog
Core.PerformanceManager = PerformanceManager
Core.DrawingPool = DrawingPool
Core.RaycastCache = RaycastCache
Core.Profiler = Profiler

return {
    SafeCall = SafeCall,
    ErrorLog = ErrorLog,
    PerformanceManager = PerformanceManager,
    DrawingPool = DrawingPool,
    RaycastCache = RaycastCache,
    Profiler = Profiler,
}