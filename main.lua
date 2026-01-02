-- ============================================================================
-- FORGEHUB ULTIMATE v23.1 - MAIN LOADER (CORRIGIDO)
-- ============================================================================

if _G.ForgeHubLoaded then
    game:GetService("StarterGui"):SetCore("SendNotification", {
        Title = "ForgeHub",
        Text = "Script já em execução!",
        Duration = 3,
    })
    return
end
_G.ForgeHubLoaded = true

-- ============================================================================
-- SERVICES
-- ============================================================================
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = workspace
local CoreGui = game:GetService("CoreGui")
local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

-- ============================================================================
-- UTILITIES
-- ============================================================================
local function SafeCall(func, name)
    local success, result = pcall(func)
    if not success then
        warn("[ForgeHub] Erro em " .. (name or "unknown") .. ": " .. tostring(result))
    end
    return success, result
end

local function Notify(title, content, image)
    pcall(function()
        if _G.Rayfield then
            _G.Rayfield:Notify({
                Title = title,
                Content = content,
                Duration = 3,
                Image = image or 4483362458,
            })
        else
            game:GetService("StarterGui"):SetCore("SendNotification", {
                Title = title,
                Text = content,
                Duration = 3,
            })
        end
    end)
end

local function NormalizeKey(keyString)
    if not keyString then return "" end
    return string.upper(string.gsub(tostring(keyString), " ", ""))
end

local function isInputMatch(inputObject, settingKey)
    if not settingKey or not inputObject then return false end
    
    local inputName = "UNKNOWN"
    if inputObject.UserInputType == Enum.UserInputType.Keyboard then
        inputName = inputObject.KeyCode.Name
    elseif inputObject.UserInputType == Enum.UserInputType.MouseButton1 then 
        inputName = "MouseButton1"
    elseif inputObject.UserInputType == Enum.UserInputType.MouseButton2 then 
        inputName = "MouseButton2"
    elseif inputObject.UserInputType == Enum.UserInputType.MouseButton3 then 
        inputName = "MouseButton3"
    end
    
    return string.upper(inputName) == NormalizeKey(settingKey)
end

-- ============================================================================
-- PLAYER CACHE
-- ============================================================================
local CachedPlayers = {}
local CachedPlayersCount = 0

local function UpdatePlayerCache()
    CachedPlayers = Players:GetPlayers()
    CachedPlayersCount = #CachedPlayers
end

Players.PlayerAdded:Connect(UpdatePlayerCache)
Players.PlayerRemoving:Connect(UpdatePlayerCache)
UpdatePlayerCache()

-- ============================================================================
-- RAYCAST PARAMS
-- ============================================================================
local _sharedRayParams = RaycastParams.new()
_sharedRayParams.FilterType = Enum.RaycastFilterType.Exclude
_sharedRayParams.FilterDescendantsInstances = {LocalPlayer.Character, Camera}

LocalPlayer.CharacterAdded:Connect(function(char)
    _sharedRayParams.FilterDescendantsInstances = {char, Camera}
end)

-- ============================================================================
-- GLOBAL SETTINGS
-- ============================================================================
local Settings = {
    -- Aimbot Core
    AimbotActive = false,
    AimbotUseKey = "MouseButton2",
    AimbotToggleKey = "Q",
    AimPart = "Head",
    AimMethod = "Camera",
    SmoothingFactor = 5,
    MaxDistance = 800,
    IgnoreTeamAimbot = true,
    VisibleCheck = true,
    MaxLockTime = 1.5,
    
    -- Target Mode
    TargetMode = "FOV",
    AimOutsideFOV = false,
    AutoResetOnKill = true,
    
    -- Rage Modes
    RageMode = false,
    UltraRageMode = false,
    GodRageMode = false,
    
    -- Silent Aim
    SilentAim = false,
    SilentFOV = 500,
    SilentHitChance = 100,
    SilentHeadshotChance = 100,
    
    -- Magic Bullet
    MagicBullet = false,
    MagicBulletMethod = "Teleport",
    MagicBulletAutoHit = true,
    MagicBulletFOV = 200,
    
    -- Trigger Bot
    TriggerBot = false,
    TriggerFOV = 100,
    TriggerDelay = 0.05,
    TriggerBurst = false,
    TriggerBurstCount = 3,
    TriggerHeadOnly = false,
    
    -- Auto Fire
    AutoFire = false,
    AutoSwitch = false,
    TargetSwitchDelay = 0.1,
    
    -- Prediction
    UsePrediction = true,
    PredictionMultiplier = 0.135,

    -- FOV Visual
    UseAimbotFOV = true,
    ShowFOV = true,
    FOV = 180,
    AimbotFOV = 180,
    FOVColor = Color3.fromRGB(255, 255, 255),
    ShowTargetIndicator = true,
    ShowSilentFOV = false,
    ShowTriggerFOV = false,

    -- ESP
    ESPEnabled = true,
    IgnoreTeamESP = true,
    ShowBox = true,
    ShowName = true,
    ShowHealthBar = true,
    ShowDistance = true,
    ShowHighlight = true,
    ESPMaxDistance = 1000,
    
    ESP = {
        Enabled = true,
        IgnoreTeam = true,
        ShowBox = true,
        ShowName = true,
        ShowDistance = true,
        ShowHealthBar = true,
        ShowHighlight = true,
        MaxDistance = 1000,
        ShowSkeleton = false,
        ShowLocalSkeleton = false,
        SkeletonMaxDistance = 300,
        HighlightMaxDistance = 500,
    },
    
    Drawing = {
        Skeleton = true,
        LocalSkeleton = false,
        SkeletonMaxDistance = 250,
    },

    -- Colors
    BoxColor = Color3.fromRGB(255, 170, 60),
    SkeletonColor = Color3.fromRGB(255, 255, 255),
    LocalSkeletonColor = Color3.fromRGB(0, 255, 255),
    HighlightFillColor = Color3.fromRGB(255, 0, 0),
    HighlightOutlineColor = Color3.fromRGB(255, 255, 255),
    HighlightTransparency = 0.5,

    -- Adaptive
    LockImprovementThreshold = 0.8,
    UseAdaptiveSmoothing = true,
    UseDeadzone = true,
    DeadzoneRadius = 0.5,
    
    -- Extra
    IgnoreWalls = false,
    MultiPartAim = false,
    ShakeReduction = 0,
}

local State = {
    DrawingESP = {},
    MouseHold = false,
    Connections = {},
}

-- ============================================================================
-- CHECK DRAWING API
-- ============================================================================
local DrawingOK = pcall(function() return Drawing ~= nil end)

-- ============================================================================
-- GLOBAL CORE EXPORT
-- ============================================================================
_G.ForgeHubCore = {
    -- Services
    Players = Players,
    RunService = RunService,
    UserInputService = UserInputService,
    Workspace = Workspace,
    CoreGui = CoreGui,
    LocalPlayer = LocalPlayer,
    Camera = Camera,
    
    -- Utilities
    Notify = Notify,
    SafeCall = SafeCall,
    NormalizeKey = NormalizeKey,
    isInputMatch = isInputMatch,
    
    -- Data
    Settings = Settings,
    State = State,
    CachedPlayers = CachedPlayers,
    UpdatePlayerCache = UpdatePlayerCache,
    
    -- Raycast
    _sharedRayParams = _sharedRayParams,
    
    -- Drawing
    DrawingOK = DrawingOK,
}

local Core = _G.ForgeHubCore

-- ============================================================================
-- MODULE LOADER
-- ============================================================================
local LoadedModules = {}

local function LoadModule(url, moduleName)
    local success, result = pcall(function()
        return loadstring(game:HttpGet(url))()
    end)
    
    if success then
        LoadedModules[moduleName] = result
        Notify("ForgeHub", "✅ " .. moduleName .. " carregado")
        return result
    else
        Notify("ForgeHub", "❌ Erro: " .. moduleName)
        warn("[ForgeHub] Erro ao carregar " .. moduleName .. ": " .. tostring(result))
        return nil
    end
end

-- ============================================================================
-- LOAD MODULES
-- ============================================================================
Notify("ForgeHub v23.1", "Iniciando carregamento...")

local BASE_URL = "https://raw.githubusercontent.com/Spectro3n/ForgeHub/main/"

-- Módulos Core
local Performance = LoadModule(BASE_URL .. "core/performance.lua", "Performance")
if not Performance then return end
Core.PerformanceManager = Performance.PerformanceManager
Core.DrawingPool = Performance.DrawingPool

local Semantic = LoadModule(BASE_URL .. "semantic/semantic.lua", "Semantic")
if not Semantic then return end
Core.SemanticEngine = Semantic

local ESP = LoadModule(BASE_URL .. "esp/esp.lua", "ESP")
if not ESP then return end
Core.ESP = ESP

-- ============================================================================
-- AIMBOT - CARREGAMENTO MODULAR
-- ============================================================================
Notify("ForgeHub", "🎯 Carregando Aimbot v4.3...")

-- Carregar submódulos do Aimbot
local AimbotUtils = LoadModule(BASE_URL .. "aimbot/utils.lua", "Aimbot/Utils")
local AimbotSettingsModule = LoadModule(BASE_URL .. "aimbot/settings.lua", "Aimbot/Settings")
local AimbotEventBus = LoadModule(BASE_URL .. "aimbot/eventbus.lua", "Aimbot/EventBus")
local AimbotHooks = LoadModule(BASE_URL .. "aimbot/Hooks.lua", "Aimbot/Hooks")
local AimbotCore = LoadModule(BASE_URL .. "aimbot/Aimbot.lua", "Aimbot/Core")
local AimbotTrigger = LoadModule(BASE_URL .. "aimbot/Trigger.lua", "Aimbot/Trigger")
local AimbotSilent = LoadModule(BASE_URL .. "aimbot/Silent.lua", "Aimbot/Silent")
local AimbotMagicBullet = LoadModule(BASE_URL .. "aimbot/MagicBullet.lua", "Aimbot/MagicBullet")

-- Verificar carregamento
if not AimbotUtils then warn("[ForgeHub] AimbotUtils não carregado") end
if not AimbotEventBus then warn("[ForgeHub] AimbotEventBus não carregado") end
if not AimbotHooks then warn("[ForgeHub] AimbotHooks não carregado") end
if not AimbotCore then warn("[ForgeHub] AimbotCore não carregado") end

-- ============================================================================
-- INICIALIZAÇÃO DO AIMBOT
-- ============================================================================
local AimbotAPI = nil

if AimbotCore and AimbotUtils and AimbotEventBus and AimbotHooks then
    -- Sincronizar settings
    local AimbotSettings = Settings
    if AimbotSettingsModule and AimbotSettingsModule.Settings then
        -- Merge settings
        for key, value in pairs(AimbotSettingsModule.Settings) do
            if Settings[key] == nil then
                Settings[key] = value
            end
        end
        AimbotSettings = Settings
    end
    
    -- Criar SharedDeps
    local SharedDeps = {
        Utils = AimbotUtils,
        Settings = AimbotSettings,
        EventBus = AimbotEventBus,
        Hooks = AimbotHooks,
        LocalPlayer = LocalPlayer,
        UserInputService = UserInputService,
        Players = Players,
    }
    
    -- Inicializar Hooks
    if AimbotHooks.Initialize then
        AimbotHooks:Initialize({EventBus = AimbotEventBus})
    end
    
    -- Obter referências do Aimbot
    local Aimbot = AimbotCore.Aimbot or AimbotCore
    local TargetLock = AimbotCore.TargetLock
    
    -- Inicializar Aimbot Core
    if Aimbot.Initialize then
        Aimbot:Initialize(SharedDeps)
    end
    
    -- Adicionar Aimbot às dependências
    SharedDeps.Aimbot = Aimbot
    
    -- Inicializar outros módulos
    if AimbotTrigger and AimbotTrigger.Initialize then
        AimbotTrigger:Initialize(SharedDeps)
    end
    
    if AimbotSilent and AimbotSilent.Initialize then
        AimbotSilent:Initialize(SharedDeps)
    end
    
    if AimbotMagicBullet and AimbotMagicBullet.Initialize then
        AimbotMagicBullet:Initialize(SharedDeps)
    end
    
    -- ========================================================================
    -- AUTO FIRE SYSTEM
    -- ========================================================================
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
        
        if Aimbot.GetCurrentTarget and not Aimbot:GetCurrentTarget() then return end
        
        if AimbotHooks.SimulateClick and AimbotHooks:SimulateClick() then
            self.LastFire = now
            if AimbotEventBus.Emit then
                AimbotEventBus:Emit("autofire:fired")
            end
        end
    end
    
    -- ========================================================================
    -- MAIN STATE
    -- ========================================================================
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
        if Aimbot.ForceReset then Aimbot:ForceReset() end
        if AimbotTrigger and AimbotTrigger.Disable then AimbotTrigger:Disable() end
        if AimbotSilent and AimbotSilent.Disable then AimbotSilent:Disable() end
        if AimbotMagicBullet and AimbotMagicBullet.Disable then AimbotMagicBullet:Disable() end
        if AimbotUtils.ClearAllCaches then AimbotUtils.ClearAllCaches() end
    end
    
    function AimbotState:OnError()
        self.ErrorCount = self.ErrorCount + 1
        if self.ErrorCount >= self.MaxErrors then
            warn("[Aimbot] Muitos erros, resetando...")
            self:Reset()
            self.ErrorCount = 0
        end
    end
    
    -- ========================================================================
    -- MAIN UPDATE LOOP
    -- ========================================================================
    local function MainUpdate()
        local success = pcall(function()
            local mouseHold = State.MouseHold
            
            -- Update aimbot
            if Aimbot.Update then
                Aimbot:Update(mouseHold)
            end
            
            -- Update trigger
            if Settings.TriggerBot and AimbotTrigger then
                if AimbotTrigger.Update then
                    AimbotTrigger:Update()
                end
                
                if AimbotTrigger.IsFiring and AimbotTrigger:IsFiring() and not AimbotTrigger.IsBursting then
                    if Settings.TriggerBurst then
                        if AimbotTrigger.StartBurst then
                            AimbotTrigger:StartBurst(function()
                                if AimbotHooks.SimulateClick then
                                    AimbotHooks:SimulateClick()
                                end
                            end)
                        end
                    else
                        if AimbotHooks.SimulateClick then
                            AimbotHooks:SimulateClick()
                        end
                        if AimbotEventBus.Emit then
                            AimbotEventBus:Emit("trigger:fire")
                        end
                    end
                end
            end
            
            -- Auto fire
            if Settings.AutoFire and Aimbot.Active then
                AutoFire:TryFire()
            end
        end)
        
        if not success then
            AimbotState:OnError()
        end
    end
    
    -- ========================================================================
    -- LOOP MANAGEMENT
    -- ========================================================================
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
    
    -- ========================================================================
    -- API PÚBLICA
    -- ========================================================================
    AimbotAPI = {
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
            print("[✓] MouseMoveRel: " .. (AimbotHooks.HasCapability and AimbotHooks:HasCapability("HasMouseMoveRel") and "OK" or "N/A"))
            print("[✓] Hooks: " .. (AimbotHooks.HasCapability and AimbotHooks:HasCapability("HasHookMetamethod") and "OK" or "N/A"))
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
            Settings.RageMode = enabled
            if AimbotSettingsModule and AimbotSettingsModule.API then
                AimbotSettingsModule.API:SetRageMode(enabled)
            end
            StopLoop()
            StartLoop()
            Notify("Aimbot", "Rage Mode " .. (enabled and "ATIVADO 🔥" or "DESATIVADO"))
        end,
        
        SetUltraRageMode = function(enabled)
            Settings.UltraRageMode = enabled
            if enabled then Settings.RageMode = true end
            if AimbotSettingsModule and AimbotSettingsModule.API then
                AimbotSettingsModule.API:SetUltraRageMode(enabled)
            end
            StopLoop()
            StartLoop()
            Notify("Aimbot", "ULTRA RAGE " .. (enabled and "ATIVADO ⚡🔥⚡" or "DESATIVADO"))
        end,
        
        SetGodRageMode = function(enabled)
            Settings.GodRageMode = enabled
            if enabled then
                Settings.RageMode = true
                Settings.UltraRageMode = true
            end
            if AimbotSettingsModule and AimbotSettingsModule.API then
                AimbotSettingsModule.API:SetGodRageMode(enabled)
            end
            StopLoop()
            StartLoop()
            Notify("Aimbot", "👑 GOD RAGE MODE 👑 " .. (enabled and "ATIVADO" or "DESATIVADO"))
        end,
        
        -- Features
        SetSilentAim = function(enabled)
            Settings.SilentAim = enabled
            if AimbotSilent then
                if enabled then
                    if AimbotSilent.Enable then AimbotSilent:Enable() end
                else
                    if AimbotSilent.Disable then AimbotSilent:Disable() end
                end
            end
            Notify("Silent Aim", enabled and "ATIVADO 🎯" or "DESATIVADO")
        end,
        
        SetMagicBullet = function(enabled)
            Settings.MagicBullet = enabled
            if AimbotMagicBullet then
                if enabled then
                    if AimbotMagicBullet.Enable then AimbotMagicBullet:Enable() end
                else
                    if AimbotMagicBullet.Disable then AimbotMagicBullet:Disable() end
                end
            end
            Notify("Magic Bullet", enabled and "ATIVADO ✨🔫" or "DESATIVADO")
        end,
        
        SetTriggerBot = function(enabled)
            Settings.TriggerBot = enabled
            if AimbotTrigger then
                if enabled then
                    if AimbotTrigger.Enable then AimbotTrigger:Enable() end
                else
                    if AimbotTrigger.Disable then AimbotTrigger:Disable() end
                end
            end
            Notify("Trigger Bot", enabled and "ATIVADO ⚡" or "DESATIVADO")
        end,
        
        -- Target Settings
        SetTargetMode = function(mode)
            Settings.TargetMode = mode
            Notify("Target Mode", mode == "Closest" and "📏 MAIS PRÓXIMO" or "🎯 FOV")
        end,
        
        SetAimOutsideFOV = function(enabled)
            Settings.AimOutsideFOV = enabled
            Notify("Aim Outside FOV", enabled and "ATIVADO ✅" or "DESATIVADO")
        end,
        
        -- FOV Settings
        SetSilentFOV = function(fov)
            Settings.SilentFOV = fov
            if AimbotSilent and AimbotSilent.SetFOV then
                AimbotSilent:SetFOV(fov)
            end
        end,
        
        SetTriggerFOV = function(fov)
            Settings.TriggerFOV = fov
        end,
        
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
            local target = Aimbot.GetCurrentTarget and Aimbot:GetCurrentTarget() or nil
            print("  Current: " .. (target and target.Name or "None"))
            print("  Kills: " .. (TargetLock and TargetLock.KillCount or 0))
            print("═══════════════════════════════════════════\n")
        end,
        
        -- Internal access
        Main = Aimbot,
        TargetLock = TargetLock,
        AimController = Aimbot,
        SilentAim = AimbotSilent,
        MagicBullet = AimbotMagicBullet,
        TriggerBot = AimbotTrigger,
        AutoFire = AutoFire,
        Settings = Settings,
        SettingsAPI = AimbotSettingsModule and AimbotSettingsModule.API,
        EventBus = AimbotEventBus,
        Hooks = AimbotHooks,
        Utils = AimbotUtils,
        
        -- Legacy
        Update = MainUpdate,
        GetClosestPlayer = function()
            return Aimbot.FindBestTarget and Aimbot:FindBestTarget() or nil
        end,
        CameraBypass = {
            GetLockedTarget = function()
                return TargetLock and TargetLock.GetTarget and TargetLock:GetTarget() or nil
            end,
            ClearLock = function()
                if TargetLock and TargetLock.Reset then
                    TargetLock:Reset()
                end
            end,
        },
    }
    
    -- Exportar para Core
    Core.Aimbot = AimbotAPI
    
    print("[ForgeHub] Aimbot v4.3 carregado com sucesso!")
else
    warn("[ForgeHub] Falha ao inicializar Aimbot - módulos não carregados")
    
    -- API vazia para evitar erros
    AimbotAPI = {
        Initialize = function() end,
        Toggle = function() end,
        SetRageMode = function() end,
        SetUltraRageMode = function() end,
        SetGodRageMode = function() end,
        SetSilentAim = function() end,
        SetMagicBullet = function() end,
        SetTriggerBot = function() end,
        SetTargetMode = function() end,
        SetAimOutsideFOV = function() end,
        SetSilentFOV = function() end,
        SetTriggerFOV = function() end,
        SetAimbotFOV = function() end,
        ForceReset = function() end,
        Debug = function() print("Aimbot não carregado") end,
        CameraBypass = {
            GetLockedTarget = function() return nil end,
            ClearLock = function() end,
        },
    }
    
    Core.Aimbot = AimbotAPI
end

-- ============================================================================
-- LOAD UI
-- ============================================================================
local UI = LoadModule(BASE_URL .. "ui/ui.lua", "UI")
if not UI then return end
Core.UI = UI

-- ============================================================================
-- INITIALIZE MODULES
-- ============================================================================
task.spawn(function()
    wait(0.5)
    
    -- Inicializar Semantic Engine
    if Semantic and Semantic.Initialize then
        Semantic:Initialize()
    end
    
    -- Inicializar ESP
    if ESP and ESP.Initialize then
        ESP:Initialize()
    end
    
    -- Inicializar Aimbot
    if AimbotAPI and AimbotAPI.Initialize then
        AimbotAPI.Initialize()
    end
    
    -- Inicializar UI
    if UI and UI.Initialize then
        UI:Initialize()
    end
    
    wait(0.5)
    Notify("ForgeHub v23.1", "✅ Todos os módulos carregados!")
end)

-- ============================================================================
-- MAIN LOOPS
-- ============================================================================

-- ESP Update Loop
task.spawn(function()
    while true do
        local interval = 0.05
        if Performance and Performance.PerformanceManager then
            interval = Performance.PerformanceManager.espInterval or 0.05
        end
        task.wait(interval)
        
        pcall(function()
            if Settings.ESPEnabled or Settings.ESP.Enabled then
                for _, player in ipairs(CachedPlayers) do
                    if player ~= LocalPlayer then
                        if ESP and ESP.UpdatePlayer then
                            ESP:UpdatePlayer(player)
                        end
                    end
                end
            end
        end)
    end
end)

-- Performance Loop
task.spawn(function()
    while wait(0.1) do
        pcall(function()
            if Performance then
                if Performance.PerformanceManager and Performance.PerformanceManager.Update then
                    Performance.PerformanceManager:Update()
                end
                if Performance.Profiler and Performance.Profiler.Update then
                    Performance.Profiler:Update()
                end
            end
        end)
    end
end)

-- Semantic Periodic Updates
task.spawn(function()
    while wait(5) do
        pcall(function()
            if Semantic then
                if Semantic.ScanForContainers then
                    Semantic:ScanForContainers()
                end
                if Semantic.AutoDetectTeamSystem then
                    Semantic:AutoDetectTeamSystem()
                end
            end
        end)
    end
end)

-- ============================================================================
-- PLAYER EVENTS
-- ============================================================================
Players.PlayerAdded:Connect(function(player)
    UpdatePlayerCache()
    
    task.delay(1, function()
        UpdatePlayerCache()
        
        if Semantic and Semantic.TrackPlayer then
            Semantic:TrackPlayer(player)
        end
        
        if ESP and ESP.CreatePlayerESP then
            ESP:CreatePlayerESP(player)
        end
        
        if AimbotUtils and AimbotUtils.BuildPartCacheFor then
            AimbotUtils.BuildPartCacheFor(player)
        end
    end)
    
    player.CharacterAdded:Connect(function(character)
        task.wait(0.2)
        UpdatePlayerCache()
        
        if AimbotUtils then
            if AimbotUtils.InvalidatePlayerData then
                AimbotUtils.InvalidatePlayerData(player)
            end
            task.wait(0.1)
            if AimbotUtils.BuildPartCacheFor then
                AimbotUtils.BuildPartCacheFor(player)
            end
        end
        
        if ESP then
            if ESP.RemovePlayerESP then
                ESP:RemovePlayerESP(player)
            end
            task.wait(0.1)
            if ESP.CreatePlayerESP then
                ESP:CreatePlayerESP(player)
            end
        end
    end)
end)

Players.PlayerRemoving:Connect(function(player)
    UpdatePlayerCache()
    
    if AimbotUtils and AimbotUtils.InvalidatePlayerData then
        AimbotUtils.InvalidatePlayerData(player)
    end
    
    if Semantic and Semantic.UntrackPlayer then
        Semantic:UntrackPlayer(player)
    end
    
    if ESP and ESP.RemovePlayerESP then
        ESP:RemovePlayerESP(player)
    end
end)

-- ============================================================================
-- CLEANUP
-- ============================================================================
local function Cleanup()
    for _, connection in ipairs(State.Connections) do
        pcall(function() connection:Disconnect() end)
    end
    
    if ESP and ESP.CleanupAll then
        ESP:CleanupAll()
    end
    
    if AimbotAPI and AimbotAPI.ForceReset then
        AimbotAPI.ForceReset()
    end
    
    if Performance and Performance.DrawingPool and Performance.DrawingPool.Clear then
        Performance.DrawingPool:Clear()
    end
    
    _G.ForgeHubLoaded = false
    _G.ForgeHubCore = nil
    
    Notify("ForgeHub", "Sistema descarregado")
end

_G.ForgeHubCleanup = Cleanup

return {
    Performance = Performance,
    Semantic = Semantic,
    ESP = ESP,
    Aimbot = AimbotAPI,
    UI = UI,
    Cleanup = Cleanup,
}