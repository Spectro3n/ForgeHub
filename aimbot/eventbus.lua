-- ============================================================================
-- FORGEHUB - EVENT BUS v1.0
-- Comunicação desacoplada entre módulos
-- ============================================================================

local EventBus = {
    _listeners = {},
    _once = {},
}

-- ============================================================================
-- EVENTOS DISPONÍVEIS
-- ============================================================================
--[[
    "target:locked"       -> (player, score)
    "target:lost"         -> (player)
    "target:killed"       -> (player)
    "aim:start"           -> ()
    "aim:stop"            -> ()
    "aim:applied"         -> (position)
    "trigger:fire"        -> ()
    "trigger:burst_start" -> ()
    "trigger:burst_end"   -> ()
    "silent:hit"          -> (player, position)
    "magic:redirect"      -> (projectile, target)
    "hook:installed"      -> (hookName)
    "hook:failed"         -> (hookName, error)
    "rage:enabled"        -> (mode)
    "rage:disabled"       -> ()
    "settings:changed"    -> (key, value)
]]

-- ============================================================================
-- CORE METHODS
-- ============================================================================
function EventBus:On(event, callback)
    if not event or type(callback) ~= "function" then return end
    
    if not self._listeners[event] then
        self._listeners[event] = {}
    end
    
    table.insert(self._listeners[event], callback)
    
    -- Retorna função para desconectar
    return function()
        self:Off(event, callback)
    end
end

function EventBus:Once(event, callback)
    if not event or type(callback) ~= "function" then return end
    
    if not self._once[event] then
        self._once[event] = {}
    end
    
    table.insert(self._once[event], callback)
end

function EventBus:Off(event, callback)
    if not event then return end
    
    if callback then
        -- Remove callback específico
        local listeners = self._listeners[event]
        if listeners then
            for i = #listeners, 1, -1 do
                if listeners[i] == callback then
                    table.remove(listeners, i)
                    break
                end
            end
        end
    else
        -- Remove todos os listeners do evento
        self._listeners[event] = nil
        self._once[event] = nil
    end
end

function EventBus:Emit(event, ...)
    if not event then return end
    
    -- Listeners permanentes
    local listeners = self._listeners[event]
    if listeners then
        for i = 1, #listeners do
            local success, err = pcall(listeners[i], ...)
            if not success then
                warn("[EventBus] Error in listener for '" .. event .. "': " .. tostring(err))
            end
        end
    end
    
    -- Listeners únicos
    local once = self._once[event]
    if once then
        self._once[event] = nil
        for i = 1, #once do
            local success, err = pcall(once[i], ...)
            if not success then
                warn("[EventBus] Error in once listener for '" .. event .. "': " .. tostring(err))
            end
        end
    end
end

function EventBus:Clear()
    self._listeners = {}
    self._once = {}
end

function EventBus:GetListenerCount(event)
    local count = 0
    
    if self._listeners[event] then
        count = count + #self._listeners[event]
    end
    
    if self._once[event] then
        count = count + #self._once[event]
    end
    
    return count
end

-- ============================================================================
-- DEBUG
-- ============================================================================
function EventBus:Debug()
    print("\n═══════════ EVENT BUS DEBUG ═══════════")
    
    print("\n─── Permanent Listeners ───")
    for event, listeners in pairs(self._listeners) do
        print("  " .. event .. ": " .. #listeners .. " listeners")
    end
    
    print("\n─── Once Listeners ───")
    for event, listeners in pairs(self._once) do
        print("  " .. event .. ": " .. #listeners .. " listeners")
    end
    
    print("════════════════════════════════════════\n")
end

return EventBus