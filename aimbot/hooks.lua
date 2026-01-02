-- ============================================================================
-- FORGEHUB - HOOKS MODULE v4.3
-- Gerencia todos os hooks do executor
-- ============================================================================

local Hooks = {
    Initialized = false,
    NamecallHooked = false,
    ActiveHooks = {},
    RemoteHooks = {},
    OriginalMethods = {},
}

-- ============================================================================
-- DEPENDENCIES (serão injetadas)
-- ============================================================================
local Utils = nil
local Settings = nil
local EventBus = nil

-- ============================================================================
-- CAPABILITY DETECTION
-- ============================================================================
local Capabilities = {
    HasHookMetamethod = false,
    HasHookFunction = false,
    HasGetRawMetatable = false,
    HasGetNamecallMethod = false,
    HasMouseMoveRel = false,
    HasMouse1Click = false,
    HasVirtualInput = false,
}

function Hooks:DetectCapabilities()
    Capabilities.HasHookMetamethod = type(hookmetamethod) == "function"
    Capabilities.HasHookFunction = type(hookfunction) == "function"
    Capabilities.HasGetRawMetatable = type(getrawmetatable) == "function"
    Capabilities.HasGetNamecallMethod = type(getnamecallmethod) == "function"
    Capabilities.HasMouseMoveRel = type(mousemoverel) == "function"
    Capabilities.HasMouse1Click = type(mouse1click) == "function"
    
    pcall(function()
        local vim = game:GetService("VirtualInputManager")
        Capabilities.HasVirtualInput = vim ~= nil
    end)
    
    return Capabilities
end

function Hooks:GetCapabilities()
    return Capabilities
end

-- ============================================================================
-- NAMECALL HOOK
-- ============================================================================
local NamecallHandlers = {}

function Hooks:RegisterNamecallHandler(method, handler)
    if not NamecallHandlers[method] then
        NamecallHandlers[method] = {}
    end
    table.insert(NamecallHandlers[method], handler)
end

function Hooks:UnregisterNamecallHandler(method, handler)
    if not NamecallHandlers[method] then return end
    
    for i = #NamecallHandlers[method], 1, -1 do
        if NamecallHandlers[method][i] == handler then
            table.remove(NamecallHandlers[method], i)
            break
        end
    end
end

function Hooks:HookNamecall()
    if self.NamecallHooked then return true end
    if not Capabilities.HasGetRawMetatable then return false end
    if not Capabilities.HasHookMetamethod then return false end
    if not Capabilities.HasGetNamecallMethod then return false end
    
    local success = pcall(function()
        local mt = getrawmetatable(game)
        if not mt then return end
        
        local oldNamecall = mt.__namecall
        self.OriginalMethods.__namecall = oldNamecall
        
        hookmetamethod(game, "__namecall", function(self, ...)
            local method = getnamecallmethod()
            
            -- Processa handlers registrados
            local handlers = NamecallHandlers[method]
            if handlers then
                for i = 1, #handlers do
                    local handler = handlers[i]
                    local shouldIntercept, newArgs = handler(self, method, ...)
                    
                    if shouldIntercept then
                        if newArgs then
                            return oldNamecall(self, unpack(newArgs))
                        else
                            return nil
                        end
                    end
                end
            end
            
            return oldNamecall(self, ...)
        end)
        
        self.NamecallHooked = true
    end)
    
    if success and EventBus then
        EventBus:Emit("hook:installed", "namecall")
    elseif not success and EventBus then
        EventBus:Emit("hook:failed", "namecall", "pcall failed")
    end
    
    return success and self.NamecallHooked
end

-- ============================================================================
-- REMOTE HOOKS
-- ============================================================================
function Hooks:HookRemote(remote, handler)
    if not remote then return false end
    if not Capabilities.HasHookFunction then return false end
    if self.RemoteHooks[remote] then return true end
    
    local success = pcall(function()
        if remote:IsA("RemoteEvent") then
            local oldFireServer = remote.FireServer
            self.RemoteHooks[remote] = {
                original = oldFireServer,
                handler = handler,
            }
            
            remote.FireServer = function(self, ...)
                local hookData = Hooks.RemoteHooks[remote]
                if hookData and hookData.handler then
                    local shouldIntercept, newArgs = hookData.handler(self, ...)
                    if shouldIntercept then
                        if newArgs then
                            return hookData.original(self, unpack(newArgs))
                        else
                            return nil
                        end
                    end
                end
                return hookData.original(self, ...)
            end
            
        elseif remote:IsA("RemoteFunction") then
            local oldInvokeServer = remote.InvokeServer
            self.RemoteHooks[remote] = {
                original = oldInvokeServer,
                handler = handler,
            }
            
            remote.InvokeServer = function(self, ...)
                local hookData = Hooks.RemoteHooks[remote]
                if hookData and hookData.handler then
                    local shouldIntercept, newArgs = hookData.handler(self, ...)
                    if shouldIntercept then
                        if newArgs then
                            return hookData.original(self, unpack(newArgs))
                        else
                            return nil
                        end
                    end
                end
                return hookData.original(self, ...)
            end
        end
    end)
    
    if success and EventBus then
        EventBus:Emit("hook:installed", "remote:" .. remote.Name)
    end
    
    return success
end

function Hooks:UnhookRemote(remote)
    local hookData = self.RemoteHooks[remote]
    if not hookData then return end
    
    pcall(function()
        if remote:IsA("RemoteEvent") then
            remote.FireServer = hookData.original
        elseif remote:IsA("RemoteFunction") then
            remote.InvokeServer = hookData.original
        end
    end)
    
    self.RemoteHooks[remote] = nil
end

-- ============================================================================
-- AUTO HOOK REMOTES
-- ============================================================================
function Hooks:AutoHookWeaponRemotes(handler)
    if not Utils then return end
    
    local containers = {workspace, game:GetService("ReplicatedStorage")}
    
    for _, container in ipairs(containers) do
        pcall(function()
            for _, desc in ipairs(container:GetDescendants()) do
                if (desc:IsA("RemoteEvent") or desc:IsA("RemoteFunction")) then
                    if Utils.IsWeaponRemote(desc.Name) then
                        self:HookRemote(desc, handler)
                    end
                end
            end
        end)
    end
    
    -- Hook novos remotes
    local connection = game.DescendantAdded:Connect(function(desc)
        if not (desc:IsA("RemoteEvent") or desc:IsA("RemoteFunction")) then return end
        if not Utils.IsWeaponRemote(desc.Name) then return end
        
        task.defer(function()
            self:HookRemote(desc, handler)
        end)
    end)
    
    self.ActiveHooks.autoWeaponRemotes = connection
end

-- ============================================================================
-- MOUSE FUNCTIONS
-- ============================================================================
function Hooks:MouseMoveRel(deltaX, deltaY)
    if Capabilities.HasMouseMoveRel then
        pcall(function()
            mousemoverel(deltaX, deltaY)
        end)
        return true
    end
    return false
end

function Hooks:MouseClick()
    if Capabilities.HasMouse1Click then
        pcall(function()
            mouse1click()
        end)
        return true
    end
    
    if Capabilities.HasVirtualInput then
        pcall(function()
            local vim = game:GetService("VirtualInputManager")
            vim:SendMouseButtonEvent(0, 0, 0, true, game, 0)
            task.wait(0.01)
            vim:SendMouseButtonEvent(0, 0, 0, false, game, 0)
        end)
        return true
    end
    
    return false
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================
function Hooks:Initialize(dependencies)
    if self.Initialized then return true end
    
    Utils = dependencies.Utils
    Settings = dependencies.Settings
    EventBus = dependencies.EventBus
    
    self:DetectCapabilities()
    
    self.Initialized = true
    
    return true
end

-- ============================================================================
-- CLEANUP
-- ============================================================================
function Hooks:Cleanup()
    -- Desconecta hooks automáticos
    for name, connection in pairs(self.ActiveHooks) do
        if connection and connection.Disconnect then
            pcall(function() connection:Disconnect() end)
        end
    end
    self.ActiveHooks = {}
    
    -- Remove hooks de remotes
    for remote, _ in pairs(self.RemoteHooks) do
        self:UnhookRemote(remote)
    end
    
    -- Limpa handlers de namecall
    NamecallHandlers = {}
end

-- ============================================================================
-- DEBUG
-- ============================================================================
function Hooks:Debug()
    print("\n═══════════ HOOKS DEBUG ═══════════")
    print("Initialized: " .. tostring(self.Initialized))
    print("NamecallHooked: " .. tostring(self.NamecallHooked))
    
    print("\n─── Capabilities ───")
    for name, value in pairs(Capabilities) do
        print("  " .. name .. ": " .. tostring(value))
    end
    
    print("\n─── Active Hooks ───")
    for name, _ in pairs(self.ActiveHooks) do
        print("  " .. name)
    end
    
    print("\n─── Remote Hooks ───")
    local count = 0
    for remote, _ in pairs(self.RemoteHooks) do
        count = count + 1
        if count <= 10 then
            print("  " .. remote.Name)
        end
    end
    if count > 10 then
        print("  ... and " .. (count - 10) .. " more")
    end
    
    print("═══════════════════════════════════════\n")
end

return Hooks