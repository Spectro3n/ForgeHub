-- ============================================================================
-- FORGEHUB - MAGIC BULLET MODULE v4.3
-- Redirecionamento extremo de projéteis
-- ============================================================================

local MagicBullet = {
    Enabled = false,
    Initialized = false,
    LastFire = 0,
    TrackedProjectiles = {},
    HeartbeatConnection = nil,
}

-- ============================================================================
-- DEPENDENCIES (serão injetadas)
-- ============================================================================
local Utils = nil
local Settings = nil
local EventBus = nil
local Hooks = nil
local TargetingModule = nil
local RunService = nil

-- ============================================================================
-- PROJECTILE TRACKING
-- ============================================================================
function MagicBullet:TrackProjectile(projectile)
    self.TrackedProjectiles[projectile] = tick()
end

function MagicBullet:UntrackProjectile(projectile)
    self.TrackedProjectiles[projectile] = nil
end

function MagicBullet:ProcessProjectiles()
    if not self.Enabled or not Settings.MagicBullet then return end
    
    if not TargetingModule then return end
    
    local target = TargetingModule:GetLockedTarget()
    if not target then return end
    
    -- Verifica se alvo está vivo
    local data = Utils.GetPlayerData(target)
    if not data or not data.isValid then return end
    if data.humanoid and data.humanoid.Health <= 0 then return end
    
    local aimPart = TargetingModule:GetBestAimPart(target)
    if not aimPart or not aimPart.Parent then return end
    
    local targetPos = TargetingModule:PredictPosition(target, aimPart)
    if not targetPos or not Utils.IsValidAimPosition(targetPos, Settings) then return end
    
    local toRemove = {}
    
    for proj, _ in pairs(self.TrackedProjectiles) do
        if not proj or not proj.Parent then
            toRemove[#toRemove + 1] = proj
        else
            local success = pcall(function()
                local direction = (targetPos - proj.Position).Unit
                
                if Settings.MagicBulletMethod == "Teleport" then
                    proj.CFrame = CFrame.new(targetPos)
                    
                elseif Settings.MagicBulletMethod == "Curve" then
                    proj.AssemblyLinearVelocity = direction * Settings.MagicBulletSpeed
                    
                elseif Settings.MagicBulletMethod == "Phase" then
                    proj.CanCollide = false
                    proj.AssemblyLinearVelocity = direction * Settings.MagicBulletSpeed
                end
                
                if EventBus then
                    EventBus:Emit("magic:redirect", proj, target)
                end
            end)
            
            if not success then
                toRemove[#toRemove + 1] = proj
            end
        end
    end
    
    for i = 1, #toRemove do
        self.TrackedProjectiles[toRemove[i]] = nil
    end
end

-- ============================================================================
-- REMOTE HANDLER
-- ============================================================================
local function HandleWeaponRemote(self, ...)
    if not MagicBullet.Enabled or not Settings.MagicBullet then
        return false
    end
    
    if not TargetingModule then return false end
    
    local target = TargetingModule:GetLockedTarget()
    if not target then return false end
    
    local aimPart = TargetingModule:GetBestAimPart(target)
    if not aimPart or not aimPart.Parent then return false end
    
    local targetPos = TargetingModule:PredictPosition(target, aimPart)
    if not targetPos or not Utils.IsValidAimPosition(targetPos, Settings) then 
        return false 
    end
    
    local args = {...}
    local modified = false
    
    for i, arg in ipairs(args) do
        if typeof(arg) == "Vector3" then
            args[i] = targetPos
            modified = true
        elseif typeof(arg) == "CFrame" then
            args[i] = CFrame.lookAt(arg.Position, targetPos)
            modified = true
        elseif typeof(arg) == "Ray" then
            args[i] = Ray.new(arg.Origin, (targetPos - arg.Origin).Unit * 5000)
            modified = true
        elseif type(arg) == "table" then
            if arg.Position then 
                arg.Position = targetPos 
                modified = true
            end
            if arg.EndPos then 
                arg.EndPos = targetPos 
                modified = true
            end
            if arg.HitPos then 
                arg.HitPos = targetPos 
                modified = true
            end
            if arg.Origin and arg.Direction then
                arg.Direction = (targetPos - arg.Origin).Unit * 5000
                modified = true
            end
        end
    end
    
    return modified, args
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================
function MagicBullet:StartTracking()
    if self.HeartbeatConnection then return end
    
    self.HeartbeatConnection = RunService.Heartbeat:Connect(function()
        self:ProcessProjectiles()
    end)
    
    -- Detecta novos projéteis
    workspace.DescendantAdded:Connect(function(desc)
        if not desc:IsA("BasePart") then return end
        if not Utils.IsBullet(desc.Name) then return end
        
        self:TrackProjectile(desc)
    end)
end

function MagicBullet:StopTracking()
    if self.HeartbeatConnection then
        self.HeartbeatConnection:Disconnect()
        self.HeartbeatConnection = nil
    end
    
    self.TrackedProjectiles = {}
end

function MagicBullet:InstallHooks()
    if not Hooks then return false end
    
    -- Hook remotes de armas
    Hooks:AutoHookWeaponRemotes(HandleWeaponRemote)
    
    if EventBus then
        EventBus:Emit("hook:installed", "magic_bullet")
    end
    
    return true
end

function MagicBullet:Initialize(dependencies)
    if self.Initialized then return true end
    
    Utils = dependencies.Utils
    Settings = dependencies.Settings
    EventBus = dependencies.EventBus
    Hooks = dependencies.Hooks
    TargetingModule = dependencies.TargetingModule
    RunService = dependencies.RunService
    
    self.Initialized = true
    
    return true
end

-- ============================================================================
-- ENABLE/DISABLE
-- ============================================================================
function MagicBullet:Enable()
    self.Enabled = true
    Settings.MagicBullet = true
    
    self:StartTracking()
    self:InstallHooks()
end

function MagicBullet:Disable()
    self.Enabled = false
    Settings.MagicBullet = false
    
    self:StopTracking()
end

-- ============================================================================
-- DEBUG
-- ============================================================================
function MagicBullet:Debug()
    print("\n═══════════ MAGIC BULLET DEBUG ═══════════")
    print("Enabled: " .. tostring(self.Enabled))
    print("Initialized: " .. tostring(self.Initialized))
    print("HeartbeatActive: " .. tostring(self.HeartbeatConnection ~= nil))
    
    local count = 0
    for _ in pairs(self.TrackedProjectiles) do count = count + 1 end
    print("TrackedProjectiles: " .. count)
    
    print("Method: " .. (Settings.MagicBulletMethod or "Teleport"))
    print("Speed: " .. (Settings.MagicBulletSpeed or 9999))
    print("═══════════════════════════════════════════\n")
end

return MagicBullet