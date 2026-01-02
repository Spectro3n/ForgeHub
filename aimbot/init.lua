-- ============================================================================
-- FORGEHUB - AIMBOT INIT v4.3
-- Bootstrap e wiring de todos os módulos
-- ============================================================================

local Core = _G.ForgeHubCore
if not Core then
    error("ForgeHubCore não encontrado! Carregue main.lua primeiro.")
end

-- ============================================================================
-- LOAD MODULES
-- ============================================================================
local Utils = require(script.Parent.utils)
local SettingsModule = require(script.Parent.settings)
local EventBus = require(script.Parent.eventbus)
local Hooks = require(script.Parent.Hooks)
local AimbotModule = require(script.Parent.Aimbot)
local Trigger = require(script.Parent.Trigger)
local Silent = require(script.Parent.Silent)
local MagicBullet = require(script.Parent.MagicBullet)

local Settings = SettingsModule.Settings
local SettingsAPI = SettingsModule.API
local Aimbot = AimbotModule.Aimbot
local TargetLock = AimbotModule.TargetLock

-- ============================================================================
-- SERVICES
-- ============================================================================
local Players = Core.Players
local RunService = Core.RunService
local UserInputService = Core.UserInputService
local LocalPlayer = Core.LocalPlayer
local Notify = Core.Notify

-- ============================================================================
-- SHARED DEPENDENCIES
-- ============================================================================
local SharedDeps = {
    Utils = Utils,
    Settings = Settings,
    EventBus = EventBus,
    Hooks = Hooks,
    LocalPlayer = LocalPlayer,
    UserInputService = UserInputService,
    Players = Players,
}

-- ============================================================================
-- INITIALIZE ALL MODULES
-- ============================================================================
Hooks:Initialize({EventBus = EventBus})
Aimbot:Initialize(SharedDeps)

-- Adiciona Aimbot às dependências para outros módulos
SharedDeps.Aimbot = Aimbot

Trigger:Initialize(SharedDeps)
Silent:Initialize(SharedDeps)
MagicBullet:Initialize(SharedDeps)

-- ============================================================================
-- AUTO FIRE SYSTEM
-- ============================================================================
local AutoFire = {
    LastFire = 0,
    FireRate = 0.05,
}

function AutoFire:TryFire()
    if not Settings.AutoFire then return end
    
    local now = tick()
    local rate = Settings.GodRageMode and 0.01 or 
                 (Settings.UltraRageMode and 0.02 or 
                 (Settings.RageMode and 0.03 or self.FireRate))
    
    if now - self.LastFire < rate then return end
    
    if not Aimbot:GetCurrentTarget() then return end
    
    if Hooks:SimulateClick() then
        self.LastFire = now
        EventBus:Emit("autofire:fired")
    end
end

-- ============================================================================
-- MAIN STATE
-- ============================================================================
local AimbotState = {
    Active = false,
    LastUpdate = 0,
    ErrorCount = 0,
    MaxErrors = 15,
    Connection = nil,
}

function AimbotState:Reset()
    self.Active = false
    self.ErrorCount = 0
    Aimbot:ForceReset()
    Trigger:Disable()
    Silent:Disable()
    MagicBullet:Disable()
    Utils.ClearAllCaches()
end

function AimbotState:OnError()
    self.ErrorCount = self.ErrorCount + 1
    if self.ErrorCount >= self.MaxErrors then
        warn("[Aimbot] Muitos erros, resetando...")
        self:Reset()
        self.ErrorCount = 0
    end
end

-- ============================================================================
-- MAIN UPDATE LOOP
-- ============================================================================
local function MainUpdate()
    local success = pcall(function()
        local mouseHold = Core.State and Core.State.MouseHold
        
        -- Update aimbot
        Aimbot:Update(mouseHold)
        
        -- Update trigger
        if Settings.TriggerBot then
            Trigger:Update()
            
            -- Se trigger decidiu atirar e não está em burst
            if Trigger:IsFiring() and not Trigger.IsBursting then
                if Settings.TriggerBurst then
                    Trigger:StartBurst(function()
                        Hooks:SimulateClick()
                    end)
                else
                    Hooks:SimulateClick()
                    EventBus:Emit("trigger:fire")
                end
            end
        end
        
        -- Auto fire
        if Settings.AutoFire and Aimbot.Active then
            AutoFire:TryFire()
        end
        
        -- Silent/Magic são passivos via hooks
    end)
    
    if not success then
        AimbotState:OnError()
    end
end

-- ============================================================================
-- LOOP MANAGEMENT
-- ============================================================================
local function StartLoop()
    if AimbotState.Connection then
        AimbotState.Connection:Disconnect()
        AimbotState.Connection = nil
    end
    
    local event
    if Settings.GodRageMode or Settings.UltraRageMode then
        event = RunService.RenderStepped
    elseif Settings.RageMode then
        event = RunService.RenderStepped
    else
        event = RunService.Heartbeat
    end
    
    AimbotState.Connection = event:Connect(MainUpdate)
end

local function StopLoop()
    if AimbotState.Connection then
        AimbotState.Connection:Disconnect()
        AimbotState.Connection = nil
    end
    AimbotState:Reset()
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================
local API = {
    -- Core
    Initialize = function()
        StartLoop()
        
        -- Watchdog
        task.spawn(function()
            while true do
                task.wait(1.5)
                if not AimbotState.Connection then
                    warn("[Aimbot] Loop morreu, reiniciando...")
                    StartLoop()
                end
            end
        end)
        
        print("═══════════════════════════════════════════")
        print("  AIMBOT v4.3 - MODULAR EDITION")
        print("═══════════════════════════════════════════")
        print("[✓] Target Mode: " .. (Settings.TargetMode or "FOV"))
        print("[✓] MouseMoveRel: " .. (Hooks:HasCapability("HasMouseMoveRel") and "OK" or "N/A"))
        print("[✓] Hooks: " .. (Hooks:HasCapability("HasHookMetamethod") and "OK" or "N/A"))
        print("═══════════════════════════════════════════")
    end,
    
    Toggle = function(enabled)
        Settings.AimbotActive = enabled
        if not enabled then
            AimbotState:Reset()
        end
    end,
    
    -- Rage Modes
    SetRageMode = function(enabled)
        SettingsAPI:SetRageMode(enabled)
        StopLoop()
        StartLoop()
        if Notify then
            Notify("Aimbot", "Rage Mode " .. (enabled and "ATIVADO 🔥" or "DESATIVADO"))
        end
    end,
    
    SetUltraRageMode = function(enabled)
        SettingsAPI:SetUltraRageMode(enabled)
        StopLoop()
        StartLoop()
        if Notify then
            Notify("Aimbot", "ULTRA RAGE " .. (enabled and "ATIVADO ⚡🔥⚡" or "DESATIVADO"))
        end
    end,
    
    SetGodRageMode = function(enabled)
        SettingsAPI:SetGodRageMode(enabled)
        StopLoop()
        StartLoop()
        if Notify then
            Notify("Aimbot", "👑 GOD RAGE MODE 👑 " .. (enabled and "ATIVADO" or "DESATIVADO"))
        end
    end,
    
    -- Features
    SetSilentAim = function(enabled)
        if enabled then
            Silent:Enable()
        else
            Silent:Disable()
        end
        if Notify then
            Notify("Silent Aim", enabled and "ATIVADO 🎯" or "DESATIVADO")
        end
    end,
    
    SetMagicBullet = function(enabled)
        if enabled then
            MagicBullet:Enable()
        else
            MagicBullet:Disable()
        end
        if Notify then
            Notify("Magic Bullet", enabled and "ATIVADO ✨🔫" or "DESATIVADO")
        end
    end,
    
    SetTriggerBot = function(enabled)
        if enabled then
            Trigger:Enable()
        else
            Trigger:Disable()
        end
        if Notify then
            Notify("Trigger Bot", enabled and "ATIVADO ⚡" or "DESATIVADO")
        end
    end,
    
    -- Target Settings
    SetTargetMode = function(mode)
        Settings.TargetMode = mode
        if Notify then
            Notify("Target Mode", mode == "Closest" and "📏 MAIS PRÓXIMO" or "🎯 FOV")
        end
    end,
    
    SetAimOutsideFOV = function(enabled)
        Settings.AimOutsideFOV = enabled
        if Notify then
            Notify("Aim Outside FOV", enabled and "ATIVADO ✅" or "DESATIVADO")
        end
    end,
    
    -- FOV Settings
    SetSilentFOV = function(fov) Silent:SetFOV(fov) end,
    SetTriggerFOV = function(fov) Settings.TriggerFOV = fov end,
    SetAimbotFOV = function(fov) 
        Settings.AimbotFOV = fov 
        Settings.FOV = fov 
    end,
    
    -- Utils
    ForceReset = function()
        print("[Aimbot] Force reset")
        AimbotState:Reset()
        StopLoop()
        task.wait(0.1)
        StartLoop()
    end,
    
    Debug = function()
        print("\n═══════════════ AIMBOT DEBUG v4.3 ═══════════════")
        print("Connection Active: " .. tostring(AimbotState.Connection ~= nil))
        print("\n─── TARGET SETTINGS ───")
        print("  TargetMode: " .. (Settings.TargetMode or "FOV"))
        print("  AimOutsideFOV: " .. tostring(Settings.AimOutsideFOV))
        print("  AutoResetOnKill: " .. tostring(Settings.AutoResetOnKill))
        print("\n─── RAGE STATUS ───")
        print("  RageMode: " .. tostring(Settings.RageMode))
        print("  UltraRageMode: " .. tostring(Settings.UltraRageMode))
        print("  GodRageMode: " .. tostring(Settings.GodRageMode))
        print("\n─── FEATURES ───")
        print("  SilentAim: " .. tostring(Settings.SilentAim))
        print("  MagicBullet: " .. tostring(Settings.MagicBullet))
        print("  TriggerBot: " .. tostring(Settings.TriggerBot))
        print("\n─── Target ───")
        local target = Aimbot:GetCurrentTarget()
        print("  Current: " .. (target and target.Name or "None"))
        print("  Kills: " .. TargetLock.KillCount)
        print("═══════════════════════════════════════════\n")
    end,
    
    -- Internal access
    Main = Aimbot,
    TargetLock = TargetLock,
    AimController = Aimbot,
    SilentAim = Silent,
    MagicBullet = MagicBullet,
    TriggerBot = Trigger,
    AutoFire = AutoFire,
    Settings = Settings,
    SettingsAPI = SettingsAPI,
    EventBus = EventBus,
    Hooks = Hooks,
    Utils = Utils,
    
    -- Legacy compatibility
    Update = MainUpdate,
    GetClosestPlayer = function() return Aimbot:FindBestTarget() end,
    CameraBypass = {
        GetLockedTarget = function() return TargetLock:GetTarget() end,
        ClearLock = function() TargetLock:Reset() end,
    },
}

-- ============================================================================
-- PLAYER EVENTS
-- ============================================================================
Players.PlayerRemoving:Connect(function(player)
    Utils.InvalidatePlayerData(player)
end)

for _, player in ipairs(Players:GetPlayers()) do
    if player ~= LocalPlayer and player.Character then
        Utils.BuildPartCacheFor(player)
    end
    
    player.CharacterAdded:Connect(function()
        task.wait(0.1)
        Utils.BuildPartCacheFor(player)
    end)
    
    player.CharacterRemoving:Connect(function()
        Utils.InvalidatePlayerData(player)
    end)
end

Players.PlayerAdded:Connect(function(player)
    player.CharacterAdded:Connect(function()
        task.wait(0.1)
        Utils.BuildPartCacheFor(player)
    end)
    player.CharacterRemoving:Connect(function()
        Utils.InvalidatePlayerData(player)
    end)
end)

-- ============================================================================
-- EXPORT TO CORE
-- ============================================================================
Core.Aimbot = API

return API