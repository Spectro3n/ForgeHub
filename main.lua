-- ============================================================================
-- FORGEHUB ULTIMATE v23.1 - MAIN LOADER (MODULAR v4.6)
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
    -- Modos Rage
    RageMode = false,
    UltraRageMode = false,
    GodRageMode = false,
    
    -- Target Mode
    TargetMode = "FOV",
    AimOutsideFOV = false,
    AutoResetOnKill = true,
    MinAimHeightBelowCamera = 50,
    
    -- Aimbot Core
    AimbotActive = false,
    AimbotUseKey = "MouseButton2",
    AimbotToggleKey = "Q",
    AimPart = "Head",
    AimMethod = "Camera",
    SmoothingFactor = 5,
    MaxDistance = 2000,
    IgnoreTeamAimbot = true,
    IgnoreTeam = true,
    VisibleCheck = true,
    MaxLockTime = 1.5,
    UpdateRate = 0,
    ThreadedAim = true,
    
    -- FOV
    UseAimbotFOV = true,
    AimbotFOV = 180,
    FOV = 180,
    ShowFOV = true,
    FOVColor = Color3.fromRGB(255, 255, 255),
    
    -- Prediction
    UsePrediction = true,
    PredictionMultiplier = 0.15,
    
    -- Smoothing & Deadzone
    UseAdaptiveSmoothing = true,
    UseDeadzone = true,
    DeadzoneRadius = 2,
    ShakeReduction = 0,
    
    -- Multi-Part Aim
    MultiPartAim = false,
    AimParts = {"Head", "UpperTorso", "HumanoidRootPart"},
    IgnoreWalls = false,
    AntiAimDetection = false,
    
    -- Silent Aim
    SilentAim = false,
    SilentFOV = 500,
    SilentHitChance = 100,
    SilentHeadshotChance = 100,
    SilentPrediction = true,
    
    -- Magic Bullet
    MagicBullet = false,
    MagicBulletMethod = "Teleport",
    MagicBulletSpeed = 9999,
    MagicBulletIgnoreWalls = true,
    MagicBulletAutoHit = true,
    
    -- Trigger Bot
    TriggerBot = false,
    TriggerFOV = 50,
    TriggerDelay = 0.05,
    TriggerBurst = false,
    TriggerBurstCount = 3,
    TriggerHeadOnly = false,
    TriggerHitChance = 100,
    
    -- Auto Fire / Switch
    AutoFire = false,
    AutoSwitch = false,
    TargetSwitchDelay = 0.05,
    InstantKill = false,
    
    -- Lock
    LockImprovementThreshold = 0.8,
    ShowTargetIndicator = true,
    
    -- TP Bullet (NOVO)
    TPBullet = false,
    TPBulletPosition = "Behind",
    TPBulletDistance = 5,
    TPBulletHeight = 0,
    TPBulletReturn = true,
    TPBulletReturnDelay = 0.1,
    TPBulletMaxDistance = 500,
    TPBulletSafety = true,
    
    -- Rage Específicos
    RageHeadOnly = false,
    RageIgnoreWalls = true,
    RageInstantSwitch = true,

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
        ShowSkeleton = true,
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
-- AIMBOT - CARREGAMENTO MODULAR v4.6
-- ============================================================================
Notify("ForgeHub", "🎯 Carregando Sistema de Mira Modular...")

-- Carregar submódulos base
local AimbotUtils = LoadModule(BASE_URL .. "aimbot/utils.lua", "aimbot/utils")
local AimbotSettingsModule = LoadModule(BASE_URL .. "aimbot/settings.lua", "aimbot/settings")
local AimbotEventBus = LoadModule(BASE_URL .. "aimbot/eventbus.lua", "aimbot/eventbus")
local AimbotHooks = LoadModule(BASE_URL .. "aimbot/hooks.lua", "aimbot/hooks")

-- Carregar módulos principais SEPARADOS
local AimbotLegitModule = LoadModule(BASE_URL .. "aimbot/aimbot.lua", "aimbot/legit")
local AimbotRageModule = LoadModule(BASE_URL .. "aimbot/rage.lua", "aimbot/rage")
local TPBulletModule = LoadModule(BASE_URL .. "aimbot/tp_bullet.lua", "aimbot/tp_bullet")
local AimbotTrigger = LoadModule(BASE_URL .. "aimbot/trigger.lua", "aimbot/trigger")

-- ============================================================================
-- INICIALIZAÇÃO DO SISTEMA MODULAR
-- ============================================================================
local AimbotAPI = nil

if AimbotLegitModule and AimbotUtils and AimbotEventBus and AimbotHooks then
    -- Sincronizar settings
    local AimbotSettings = Settings
    if AimbotSettingsModule then
        -- Se o módulo de settings tem função de merge, usa
        if type(AimbotSettingsModule) == "table" then
            for key, value in pairs(AimbotSettingsModule) do
                if type(value) ~= "function" and Settings[key] == nil then
                    Settings[key] = value
                end
            end
        end
    end
    
    -- Sincronizar IgnoreTeam
    Settings.IgnoreTeam = Settings.IgnoreTeamAimbot
    
    -- Criar SharedDeps base
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
    
    -- Obter referências
    local Aimbot = AimbotLegitModule.Aimbot
    local TargetLock = AimbotLegitModule.TargetLock
    
    -- Inicializar Aimbot Legit
    if Aimbot and Aimbot.Initialize then
        Aimbot:Initialize(SharedDeps)
    end
    
    -- Adicionar Aimbot às deps
    SharedDeps.Aimbot = Aimbot
    
    -- Inicializar Rage Module
    local Rage = nil
    if AimbotRageModule and AimbotRageModule.Rage then
        Rage = AimbotRageModule.Rage
        if Rage.Initialize then
            Rage:Initialize(SharedDeps)
        end
        SharedDeps.Rage = Rage
    end
    
    -- Inicializar TP Bullet
    local TPBullet = nil
    if TPBulletModule and TPBulletModule.TPBullet then
        TPBullet = TPBulletModule.TPBullet
        if TPBullet.Initialize then
            TPBullet:Initialize(SharedDeps)
        end
        SharedDeps.TPBullet = TPBullet
    end
    
    -- Inicializar Trigger
    if AimbotTrigger and AimbotTrigger.Initialize then
        AimbotTrigger:Initialize(SharedDeps)
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
        
        -- Verificar se tem alvo
        local hasTarget = false
        if Rage and Rage:IsActive() then
            hasTarget = Rage:GetCurrentTarget() ~= nil
        elseif Aimbot and Aimbot.GetCurrentTarget then
            hasTarget = Aimbot:GetCurrentTarget() ~= nil
        end
        
        if not hasTarget then return end
        
        if AimbotHooks.SimulateClick and AimbotHooks:SimulateClick() then
            self.LastFire = now
            if AimbotEventBus.Emit then
                AimbotEventBus:Emit("autofire:fired")
            end
        end
    end
    
    -- ========================================================================
    -- MAIN UPDATE LOOP
    -- ========================================================================
    local AimbotState = {
        Active = false,
        Connection = nil,
        ErrorCount = 0,
        MaxErrors = 15,
    }
    
    function AimbotState:Reset()
        self.Active = false
        self.ErrorCount = 0
        if Aimbot and Aimbot.ForceReset then Aimbot:ForceReset() end
        if Rage and Rage.ForceReset then Rage:ForceReset() end
        if TPBullet and TPBullet.ForceReset then TPBullet:ForceReset() end
        if AimbotTrigger and AimbotTrigger.Disable then AimbotTrigger:Disable() end
        if AimbotUtils and AimbotUtils.ClearAllCaches then AimbotUtils.ClearAllCaches() end
    end
    
    local function MainUpdate()
        local success = pcall(function()
            local mouseHold = State.MouseHold
            
            local rageProcessed = false
            
            -- Se Rage está ativo, usar Rage
            if Rage and Rage:IsActive() then
                rageProcessed = Rage:Update(mouseHold)
            end
            
            -- Se Rage não processou, usar Legit
            if not rageProcessed and Aimbot and Aimbot.Update then
                Aimbot:Update(mouseHold)
            end
            
            -- Update TP Bullet
            if TPBullet and Settings.TPBullet then
                TPBullet:Update(mouseHold)
            end
            
            -- Update Trigger
            if Settings.TriggerBot and AimbotTrigger then
                if AimbotTrigger.Update then
                    AimbotTrigger:Update()
                end
                
                if AimbotTrigger.IsFiring and AimbotTrigger:IsFiring() then
                    if Settings.TriggerBurst and AimbotTrigger.StartBurst then
                        AimbotTrigger:StartBurst(function()
                            if AimbotHooks.SimulateClick then
                                AimbotHooks:SimulateClick()
                            end
                        end)
                    else
                        if AimbotHooks.SimulateClick then
                            AimbotHooks:SimulateClick()
                        end
                    end
                end
            end
            
            -- Auto Fire
            if Settings.AutoFire and (Aimbot.Active or (Rage and Rage._active)) then
                AutoFire:TryFire()
            end
        end)
        
        if not success then
            AimbotState.ErrorCount = AimbotState.ErrorCount + 1
            if AimbotState.ErrorCount >= AimbotState.MaxErrors then
                warn("[Aimbot] Muitos erros, resetando...")
                AimbotState:Reset()
            end
        end
    end
    
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
            print("  SISTEMA DE MIRA MODULAR v4.6")
            print("═══════════════════════════════════════════")
            print("[✓] Legit Aimbot: " .. (Aimbot and "OK" or "N/A"))
            print("[✓] Rage Module: " .. (Rage and "OK" or "N/A"))
            print("[✓] TP Bullet: " .. (TPBullet and "OK" or "N/A"))
            print("[✓] Trigger Bot: " .. (AimbotTrigger and "OK" or "N/A"))
            print("[✓] MouseMoveRel: " .. (AimbotHooks.HasCapability and AimbotHooks:HasCapability("HasMouseMoveRel") and "OK" or "N/A"))
            print("═══════════════════════════════════════════")
        end,
        
        Toggle = function(enabled)
            Settings.AimbotActive = enabled
            if not enabled then
                AimbotState:Reset()
            end
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
        
        SetAimbotFOV = function(fov)
            Settings.AimbotFOV = fov
            Settings.FOV = fov
        end,
        
        SetAimPart = function(part)
            Settings.AimPart = part
        end,
        
        SetSmoothing = function(value)
            Settings.SmoothingFactor = value
        end,
        
        SetMaxDistance = function(dist)
            Settings.MaxDistance = dist
        end,
        
        -- Rage Modes
        SetRageMode = function(enabled)
            Settings.RageMode = enabled
            if Rage then Rage:SetRageMode(enabled) end
            StopLoop()
            StartLoop()
            Notify("Aimbot", "Rage Mode " .. (enabled and "ATIVADO 🔥" or "DESATIVADO"))
        end,
        
        SetUltraRageMode = function(enabled)
            Settings.UltraRageMode = enabled
            if enabled then Settings.RageMode = true end
            if Rage then Rage:SetUltraRageMode(enabled) end
            StopLoop()
            StartLoop()
            Notify("Aimbot", "ULTRA RAGE " .. (enabled and "ATIVADO ⚡🔥" or "DESATIVADO"))
        end,
        
        SetGodRageMode = function(enabled)
            Settings.GodRageMode = enabled
            if enabled then
                Settings.RageMode = true
                Settings.UltraRageMode = true
            end
            if Rage then Rage:SetGodRageMode(enabled) end
            StopLoop()
            StartLoop()
            Notify("Aimbot", "👑 GOD RAGE 👑 " .. (enabled and "ATIVADO" or "DESATIVADO"))
        end,
        
        SetRageHeadOnly = function(enabled)
            Settings.RageHeadOnly = enabled
        end,
        
        -- TP Bullet
        SetTPBullet = function(enabled)
            Settings.TPBullet = enabled
            if TPBullet then TPBullet:Toggle(enabled) end
            Notify("TP Bullet", enabled and "ATIVADO 🚀" or "DESATIVADO")
        end,
        
        SetTPBulletPosition = function(pos)
            Settings.TPBulletPosition = pos
            if TPBullet then TPBullet:SetPosition(pos) end
        end,
        
        SetTPBulletDistance = function(dist)
            Settings.TPBulletDistance = dist
            if TPBullet then TPBullet:SetDistance(dist) end
        end,
        
        SetTPBulletHeight = function(height)
            Settings.TPBulletHeight = height
            if TPBullet then TPBullet:SetHeight(height) end
        end,
        
        SetTPBulletReturn = function(enabled)
            Settings.TPBulletReturn = enabled
            if TPBullet then TPBullet:SetReturnAfterShot(enabled) end
        end,
        
        SetTPBulletReturnDelay = function(delay)
            Settings.TPBulletReturnDelay = delay
            if TPBullet then TPBullet.ReturnDelay = delay end
        end,
        
        ForceTPReturn = function()
            if TPBullet then return TPBullet:ForceReturn() end
            return false
        end,
        
        -- Silent Aim
        SetSilentAim = function(enabled)
            Settings.SilentAim = enabled
            Notify("Silent Aim", enabled and "ATIVADO 🔇" or "DESATIVADO")
        end,
        
        SetSilentFOV = function(fov)
            Settings.SilentFOV = fov
        end,
        
        SetSilentHitChance = function(chance)
            Settings.SilentHitChance = chance
        end,
        
        -- Magic Bullet
        SetMagicBullet = function(enabled)
            Settings.MagicBullet = enabled
            Notify("Magic Bullet", enabled and "ATIVADO ✨" or "DESATIVADO")
        end,
        
        -- Trigger
        SetTriggerBot = function(enabled)
            Settings.TriggerBot = enabled
            if AimbotTrigger then
                if enabled and AimbotTrigger.Enable then 
                    AimbotTrigger:Enable() 
                elseif AimbotTrigger.Disable then 
                    AimbotTrigger:Disable() 
                end
            end
            Notify("Trigger Bot", enabled and "ATIVADO ⚡" or "DESATIVADO")
        end,
        
        SetTriggerFOV = function(fov)
            Settings.TriggerFOV = fov
        end,
        
        SetTriggerDelay = function(delay)
            Settings.TriggerDelay = delay
        end,
        
        SetTriggerBurst = function(enabled)
            Settings.TriggerBurst = enabled
        end,
        
        SetTriggerBurstCount = function(count)
            Settings.TriggerBurstCount = count
        end,
        
        -- Auto Fire
        SetAutoFire = function(enabled)
            Settings.AutoFire = enabled
            Notify("Auto Fire", enabled and "ATIVADO 🔫" or "DESATIVADO")
        end,
        
        SetAutoSwitch = function(enabled)
            Settings.AutoSwitch = enabled
        end,
        
        -- Prediction
        SetPrediction = function(enabled)
            Settings.UsePrediction = enabled
        end,
        
        SetPredictionMultiplier = function(mult)
            Settings.PredictionMultiplier = mult
        end,
        
        -- Utils
        ForceReset = function()
            print("[Aimbot] Force reset")
            AimbotState:Reset()
            StopLoop()
            task.wait(0.1)
            StartLoop()
        end,
        
        GetCurrentTarget = function()
            if Rage and Rage:IsActive() then
                return Rage:GetCurrentTarget()
            end
            if Aimbot and Aimbot.GetCurrentTarget then
                return Aimbot:GetCurrentTarget()
            end
            return nil
        end,
        
        Debug = function()
            print("\n═══════════════ AIMBOT DEBUG v4.6 ═══════════════")
            print("Connection Active: " .. tostring(AimbotState.Connection ~= nil))
            print("\n─── TARGET SETTINGS ───")
            print("  TargetMode: " .. (Settings.TargetMode or "FOV"))
            print("  AimOutsideFOV: " .. tostring(Settings.AimOutsideFOV))
            print("  AimbotFOV: " .. tostring(Settings.AimbotFOV))
            print("  MaxDistance: " .. tostring(Settings.MaxDistance))
            print("\n─── RAGE STATUS ───")
            print("  RageMode: " .. tostring(Settings.RageMode))
            print("  UltraRageMode: " .. tostring(Settings.UltraRageMode))
            print("  GodRageMode: " .. tostring(Settings.GodRageMode))
            print("\n─── TP BULLET ───")
            print("  Enabled: " .. tostring(Settings.TPBullet))
            print("  Position: " .. (Settings.TPBulletPosition or "Behind"))
            print("  Distance: " .. tostring(Settings.TPBulletDistance))
            if TPBullet then
                print("  Teleported: " .. tostring(TPBullet:IsTeleported()))
            end
            print("\n─── FEATURES ───")
            print("  SilentAim: " .. tostring(Settings.SilentAim))
            print("  MagicBullet: " .. tostring(Settings.MagicBullet))
            print("  TriggerBot: " .. tostring(Settings.TriggerBot))
            print("  AutoFire: " .. tostring(Settings.AutoFire))
            print("\n─── Current Target ───")
            local target = AimbotAPI.GetCurrentTarget()
            print("  Target: " .. (target and target.Name or "None"))
            if TargetLock then
                print("  Kills: " .. tostring(TargetLock.Kills or 0))
            end
            print("═══════════════════════════════════════════\n")
        end,
        
        -- Internal References
        Legit = Aimbot,
        Rage = Rage,
        TPBullet = TPBullet,
        TargetLock = TargetLock,
        TriggerBot = AimbotTrigger,
        AutoFire = AutoFire,
        Settings = Settings,
        EventBus = AimbotEventBus,
        Hooks = AimbotHooks,
        Utils = AimbotUtils,
        
        -- Legacy Compatibility
        Main = Aimbot,
        AimController = Aimbot,
        Update = MainUpdate,
        GetClosestPlayer = function()
            if Aimbot and Aimbot.FindBest then
                local target = Aimbot:FindBest()
                return target
            end
            return nil
        end,
        CameraBypass = {
            GetLockedTarget = function()
                return AimbotAPI.GetCurrentTarget()
            end,
            ClearLock = function()
                if TargetLock and TargetLock.Clear then
                    TargetLock:Clear()
                end
                if Rage and Rage.ForceReset then
                    Rage:ForceReset()
                end
            end,
        },
    }
    
    -- Exportar para Core
    Core.Aimbot = AimbotAPI
    
    print("[ForgeHub] Sistema de Mira Modular v4.6 carregado!")
else
    warn("[ForgeHub] Falha ao inicializar Aimbot - módulos não carregados")
    
    -- API vazia para evitar erros
    AimbotAPI = {
        Initialize = function() end,
        Toggle = function() end,
        SetRageMode = function() end,
        SetUltraRageMode = function() end,
        SetGodRageMode = function() end,
        SetTPBullet = function() end,
        SetTPBulletPosition = function() end,
        SetTPBulletDistance = function() end,
        SetTPBulletHeight = function() end,
        SetTPBulletReturn = function() end,
        ForceTPReturn = function() end,
        SetSilentAim = function() end,
        SetMagicBullet = function() end,
        SetTriggerBot = function() end,
        SetTargetMode = function() end,
        SetAimOutsideFOV = function() end,
        SetSilentFOV = function() end,
        SetTriggerFOV = function() end,
        SetAimbotFOV = function() end,
        ForceReset = function() end,
        GetCurrentTarget = function() return nil end,
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
-- INPUT HANDLING
-- ============================================================================
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    
    -- Mouse Hold
    if isInputMatch(input, Settings.AimbotUseKey) then
        State.MouseHold = true
    end
    
    -- Toggle Aimbot
    if isInputMatch(input, Settings.AimbotToggleKey) then
        Settings.AimbotActive = not Settings.AimbotActive
        Notify("Aimbot", Settings.AimbotActive and "ATIVADO ✅" or "DESATIVADO ❌")
    end
end)

UserInputService.InputEnded:Connect(function(input, gameProcessed)
    -- Mouse Release
    if isInputMatch(input, Settings.AimbotUseKey) then
        State.MouseHold = false
    end
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