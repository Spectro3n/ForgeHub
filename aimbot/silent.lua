-- ============================================================================
-- FORGEHUB - SILENT AIM MODULE v4.3
-- Silent aim via hooks de raycast
-- ============================================================================

local Silent = {
    Enabled = false,
    Initialized = false,
    LastTarget = nil,
    LastAimPos = nil,
    HooksInstalled = false,
}

-- ============================================================================
-- DEPENDENCIES (serão injetadas)
-- ============================================================================
local Utils = nil
local Settings = nil
local EventBus = nil
local Hooks = nil
local TargetingModule = nil
local LocalPlayer = nil
local UserInputService = nil

-- ============================================================================
-- TARGET POSITION
-- ============================================================================
function Silent:GetTargetPosition()
    if not TargetingModule then return nil end
    
    local target = TargetingModule:GetLockedTarget()
    if not target then
        target = TargetingModule:FindBestTargetForSilent()
    end
    
    if not target then return nil end
    
    -- Verifica se alvo está vivo
    local data = Utils.GetPlayerData(target)
    if not data or not data.isValid then return nil end
    if data.humanoid and data.humanoid.Health <= 0 then return nil end
    
    self.LastTarget = target
    
    -- Pega melhor parte
    local aimPart = TargetingModule:GetBestAimPart(target)
    if not aimPart or not aimPart.Parent then return nil end
    
    -- Chance de headshot
    if Settings.SilentHeadshotChance < 100 then
        if not Utils.RandomChance(Settings.SilentHeadshotChance) then
            local partCache = Utils.GetPartCache(target)
            local torso = partCache and (partCache.UpperTorso or partCache.Torso)
            if torso and torso.Parent then
                aimPart = torso
            end
        end
    end
    
    local pos = TargetingModule:PredictPosition(target, aimPart)
    
    if not pos or not Utils.IsValidAimPosition(pos, Settings) then
        return nil
    end
    
    self.LastAimPos = pos
    return pos
end

function Silent:IsInFOV(position)
    if Settings.GodRageMode then return true end
    
    local Camera = Utils.GetCamera()
    local screenPos, onScreen = Camera:WorldToViewportPoint(position)
    
    if not onScreen then 
        return Settings.UltraRageMode or Settings.AimOutsideFOV 
    end
    
    local mousePos = UserInputService:GetMouseLocation()
    local dist = (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude
    
    local silentFOV = Settings.SilentFOV or 500
    if Settings.UltraRageMode then
        silentFOV = silentFOV * 3
    elseif Settings.RageMode then
        silentFOV = silentFOV * 2
    end
    
    return dist <= silentFOV
end

function Silent:ShouldHit()
    if Settings.SilentHitChance >= 100 then return true end
    return Utils.RandomChance(Settings.SilentHitChance)
end

-- ============================================================================
-- HOOK HANDLERS
-- ============================================================================
local function HandleRaycast(self, method, ...)
    if not Silent.Enabled or not Settings.SilentAim then
        return false
    end
    
    if not Silent:ShouldHit() then
        return false
    end
    
    local targetPos = Silent:GetTargetPosition()
    if not targetPos then return false end
    
    if not Silent:IsInFOV(targetPos) then return false end
    
    local args = {...}
    
    if method == "Raycast" then
        local origin = args[1]
        if origin then
            args[2] = (targetPos - origin).Unit * 5000
            
            if EventBus then
                EventBus:Emit("silent:hit", Silent.LastTarget, targetPos)
            end
            
            return true, args
        end
    elseif method == "FindPartOnRay" or method == "FindPartOnRayWithIgnoreList" or method == "FindPartOnRayWithWhitelist" then
        local ray = args[1]
        if typeof(ray) == "Ray" then
            args[1] = Ray.new(ray.Origin, (targetPos - ray.Origin).Unit * 5000)
            
            if EventBus then
                EventBus:Emit("silent:hit", Silent.LastTarget, targetPos)
            end
            
            return true, args
        end
    end
    
    return false
end

local function HandleWeaponRemote(self, ...)
    if not Silent.Enabled or not Settings.SilentAim then
        return false
    end
    
    local targetPos = Silent:GetTargetPosition()
    if not targetPos then return false end
    
    if not Silent:ShouldHit() then return false end
    
    local args = {...}
    local modified = false
    
    for i, arg in ipairs(args) do
        if typeof(arg) == "Vector3" then
            args[i] = targetPos
            modified = true
        elseif typeof(arg) == "CFrame" then
            args[i] = CFrame.new(targetPos)
            modified = true
        elseif type(arg) == "table" then
            if arg.Position then 
                arg.Position = targetPos 
                modified = true
            end
            if arg.EndPosition then 
                arg.EndPosition = targetPos 
                modified = true
            end
            if arg.HitPosition then 
                arg.HitPosition = targetPos 
                modified = true
            end
            if arg.Target then 
                arg.Target = targetPos 
                modified = true
            end
        end
    end
    
    if modified and EventBus then
        EventBus:Emit("silent:hit", Silent.LastTarget, targetPos)
    end
    
    return modified, args
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================
function Silent:InstallHooks()
    if self.HooksInstalled then return true end
    if not Hooks then return false end
    
    -- Registra handlers de namecall
    Hooks:RegisterNamecallHandler("Raycast", HandleRaycast)
    Hooks:RegisterNamecallHandler("FindPartOnRay", HandleRaycast)
    Hooks:RegisterNamecallHandler("FindPartOnRayWithIgnoreList", HandleRaycast)
    Hooks:RegisterNamecallHandler("FindPartOnRayWithWhitelist", HandleRaycast)
    
    -- Hook de namecall precisa estar ativo
    Hooks:HookNamecall()
    
    -- Auto hook remotes de armas
    Hooks:AutoHookWeaponRemotes(HandleWeaponRemote)
    
    self.HooksInstalled = true
    
    if EventBus then
        EventBus:Emit("hook:installed", "silent_aim")
    end
    
    return true
end

function Silent:Initialize(dependencies)
    if self.Initialized then return true end
    
    Utils = dependencies.Utils
    Settings = dependencies.Settings
    EventBus = dependencies.EventBus
    Hooks = dependencies.Hooks
    TargetingModule = dependencies.TargetingModule
    LocalPlayer = dependencies.LocalPlayer
    UserInputService = dependencies.UserInputService
    
    self.Initialized = true
    
    return true
end

-- ============================================================================
-- ENABLE/DISABLE
-- ============================================================================
function Silent:Enable()
    self.Enabled = true
    self:InstallHooks()
end

function Silent:Disable()
    self.Enabled = false
end

-- ============================================================================
-- GETTERS
-- ============================================================================
function Silent:GetLastTarget()
    return self.LastTarget
end

function Silent:GetLastAimPos()
    return self.LastAimPos
end

-- ============================================================================
-- DEBUG
-- ============================================================================
function Silent:Debug()
    print("\n═══════════ SILENT AIM DEBUG ═══════════")
    print("Enabled: " .. tostring(self.Enabled))
    print("Initialized: " .. tostring(self.Initialized))
    print("HooksInstalled: " .. tostring(self.HooksInstalled))
    print("LastTarget: " .. (self.LastTarget and self.LastTarget.Name or "None"))
    print("LastAimPos: " .. tostring(self.LastAimPos))
    print("═══════════════════════════════════════════\n")
end

return Silent