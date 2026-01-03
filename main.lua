-- ============================================================================
-- FORGEHUB ULTIMATE v24.0 - MAIN LOADER (CLEAN MODULAR)
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
    
    -- Trigger Bot
    TriggerBot = false,
    TriggerFOV = 50,
    ShowTriggerFOV = false,
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
    
    -- TP Bullet
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
    
    if success and result then
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
Notify("ForgeHub v24.0", "Iniciando carregamento...")

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
-- AIMBOT - CARREGAMENTO MODULAR LIMPO v24.0
-- ============================================================================
Notify("ForgeHub", "🎯 Carregando Sistema de Mira...")

-- Carregar módulos do Aimbot
local AimbotUtils = LoadModule(BASE_URL .. "aimbot/utils.lua", "Aimbot/Utils")
local AimbotSettingsModule = LoadModule(BASE_URL .. "aimbot/settings.lua", "Aimbot/Settings")
local AimbotLegitModule = LoadModule(BASE_URL .. "aimbot/aimbot.lua", "Aimbot/Legit")
local AimbotRageModule = LoadModule(BASE_URL .. "aimbot/rage.lua", "Aimbot/Rage")
local TPBulletModule = LoadModule(BASE_URL .. "aimbot/tp_bullet.lua", "Aimbot/TPBullet")
local AimbotTrigger = LoadModule(BASE_URL .. "aimbot/trigger.lua", "Aimbot/Trigger")

-- ============================================================================
-- INICIALIZAÇÃO DO SISTEMA DE MIRA
-- ============================================================================
local AimbotAPI = nil
local Aimbot = nil
local Rage = nil
local TPBullet = nil
local TargetLock = nil

-- Verificar se os módulos essenciais carregaram
if AimbotLegitModule and AimbotUtils then
    print("[ForgeHub] Módulos de Aimbot carregados, inicializando...")
    
    -- Sincronizar settings do módulo
    if AimbotSettingsModule and type(AimbotSettingsModule) == "table" then
        for key, value in pairs(AimbotSettingsModule) do
            if type(value) ~= "function" and Settings[key] == nil then
                Settings[key] = value
            end
        end
    end
    
    -- Sincronizar IgnoreTeam
    Settings.IgnoreTeam = Settings.IgnoreTeamAimbot
    
    -- Criar SharedDeps (sem EventBus e Hooks)
    local SharedDeps = {
        Utils = AimbotUtils,
        Settings = Settings,
        LocalPlayer = LocalPlayer,
        UserInputService = UserInputService,
        Players = Players,
        Camera = Camera,
        Workspace = Workspace,
        RunService = RunService,
    }
    
    -- Obter referências do módulo Legit
    if AimbotLegitModule.Aimbot then
        Aimbot = AimbotLegitModule.Aimbot
    elseif type(AimbotLegitModule) == "table" and AimbotLegitModule.Initialize then
        Aimbot = AimbotLegitModule
    end
    
    if AimbotLegitModule.TargetLock then
        TargetLock = AimbotLegitModule.TargetLock
    end
    
    -- Inicializar Aimbot Legit
    if Aimbot and Aimbot.Initialize then
        local initSuccess = pcall(function()
            Aimbot:Initialize(SharedDeps)
        end)
        if initSuccess then
            print("[ForgeHub] ✓ Aimbot Legit inicializado")
        else
            warn("[ForgeHub] ✗ Falha ao inicializar Aimbot Legit")
        end
    end
    
    SharedDeps.Aimbot = Aimbot
    
    -- Inicializar Rage Module
    if AimbotRageModule then
        if AimbotRageModule.Rage then
            Rage = AimbotRageModule.Rage
        elseif type(AimbotRageModule) == "table" and AimbotRageModule.Initialize then
            Rage = AimbotRageModule
        end
        
        if Rage and Rage.Initialize then
            local initSuccess = pcall(function()
                Rage:Initialize(SharedDeps)
            end)
            if initSuccess then
                print("[ForgeHub] ✓ Rage Module inicializado")
            end
        end
        SharedDeps.Rage = Rage
    end
    
    -- Inicializar TP Bullet
    if TPBulletModule then
        if TPBulletModule.TPBullet then
            TPBullet = TPBulletModule.TPBullet
        elseif type(TPBulletModule) == "table" and TPBulletModule.Initialize then
            TPBullet = TPBulletModule
        end
        
        if TPBullet and TPBullet.Initialize then
            local initSuccess = pcall(function()
                TPBullet:Initialize(SharedDeps)
            end)
            if initSuccess then
                print("[ForgeHub] ✓ TP Bullet inicializado")
            end
        end
        SharedDeps.TPBullet = TPBullet
    end
    
    -- Inicializar Trigger
    if AimbotTrigger and AimbotTrigger.Initialize then
        local initSuccess = pcall(function()
            AimbotTrigger:Initialize(SharedDeps)
        end)
        if initSuccess then
            print("[ForgeHub] ✓ Trigger Bot inicializado")
        end
    end
    
    -- ========================================================================
    -- SIMPLE CLICK SIMULATION
    -- ========================================================================
    local function SimulateClick()
        local success = false
        
        -- Método 1: mouse1press/mouse1release
        if mouse1press and mouse1release then
            pcall(function()
                mouse1press()
                task.wait(0.01)
                mouse1release()
                success = true
            end)
        end
        
        -- Método 2: VirtualInputManager
        if not success then
            pcall(function()
                local vim = game:GetService("VirtualInputManager")
                vim:SendMouseButtonEvent(0, 0, 0, true, game, 1)
                task.wait(0.01)
                vim:SendMouseButtonEvent(0, 0, 0, false, game, 1)
                success = true
            end)
        end
        
        return success
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
        if Rage and Rage.IsActive and Rage:IsActive() then
            hasTarget = Rage:GetCurrentTarget() ~= nil
        elseif Aimbot and Aimbot.GetCurrentTarget then
            hasTarget = Aimbot:GetCurrentTarget() ~= nil
        end
        
        if not hasTarget then return end
        
        if SimulateClick() then
            self.LastFire = now
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
        if Aimbot and Aimbot.ForceReset then pcall(function() Aimbot:ForceReset() end) end
        if Rage and Rage.ForceReset then pcall(function() Rage:ForceReset() end) end
        if TPBullet and TPBullet.ForceReset then pcall(function() TPBullet:ForceReset() end) end
        if AimbotTrigger and AimbotTrigger.Disable then pcall(function() AimbotTrigger:Disable() end) end
        if AimbotUtils and AimbotUtils.ClearAllCaches then pcall(function() AimbotUtils.ClearAllCaches() end) end
    end
    
    local function MainUpdate()
        -- Verificar se aimbot está ativo
        if not Settings.AimbotActive then return end
        
        local success = pcall(function()
            local mouseHold = State.MouseHold
            local rageProcessed = false
            
            -- Se Rage está ativo, usar Rage
            if Rage and Rage.IsActive and Rage:IsActive() then
                if Rage.Update then
                    rageProcessed = Rage:Update(mouseHold)
                end
            end
            
            -- Se Rage não processou, usar Legit
            if not rageProcessed and Aimbot and Aimbot.Update then
                Aimbot:Update(mouseHold)
            end
            
            -- Update TP Bullet
            if TPBullet and Settings.TPBullet and TPBullet.Update then
                TPBullet:Update(mouseHold)
            end
            
            -- Update Trigger
            if Settings.TriggerBot and AimbotTrigger then
                if AimbotTrigger.Update then
                    AimbotTrigger:Update()
                end
                
                if AimbotTrigger.IsFiring and AimbotTrigger:IsFiring() then
                    if Settings.TriggerBurst and AimbotTrigger.StartBurst then
                        AimbotTrigger:StartBurst(SimulateClick)
                    else
                        SimulateClick()
                    end
                end
            end
            
            -- Auto Fire
            if Settings.AutoFire and mouseHold then
                AutoFire:TryFire()
            end
        end)
        
        if not success then
            AimbotState.ErrorCount = AimbotState.ErrorCount + 1
            if AimbotState.ErrorCount >= AimbotState.MaxErrors then
                warn("[Aimbot] Muitos erros, resetando...")
                AimbotState:Reset()
            end
        else
            AimbotState.ErrorCount = 0
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
        print("[Aimbot] Loop iniciado")
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
                while _G.ForgeHubLoaded do
                    task.wait(2)
                    if not AimbotState.Connection and Settings.AimbotActive then
                        warn("[Aimbot] Loop morreu, reiniciando...")
                        StartLoop()
                    end
                end
            end)
            
            print("═══════════════════════════════════════════")
            print("  SISTEMA DE MIRA v24.0 CLEAN")
            print("═══════════════════════════════════════════")
            print("[✓] Aimbot: " .. (Aimbot and "OK" or "N/A"))
            print("[✓] Rage: " .. (Rage and "OK" or "N/A"))
            print("[✓] TP Bullet: " .. (TPBullet and "OK" or "N/A"))
            print("[✓] Trigger: " .. (AimbotTrigger and "OK" or "N/A"))
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
            if Rage and Rage.SetRageMode then Rage:SetRageMode(enabled) end
            StopLoop()
            StartLoop()
            Notify("Aimbot", "Rage Mode " .. (enabled and "ATIVADO 🔥" or "DESATIVADO"))
        end,
        
        SetUltraRageMode = function(enabled)
            Settings.UltraRageMode = enabled
            if enabled then Settings.RageMode = true end
            if Rage and Rage.SetUltraRageMode then Rage:SetUltraRageMode(enabled) end
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
            if Rage and Rage.SetGodRageMode then Rage:SetGodRageMode(enabled) end
            StopLoop()
            StartLoop()
            Notify("Aimbot", "👑 GOD RAGE 👑 " .. (enabled and "ATIVADO" or "DESATIVADO"))
        end,
        
        -- TP Bullet
        SetTPBullet = function(enabled)
            Settings.TPBullet = enabled
            if TPBullet and TPBullet.Toggle then TPBullet:Toggle(enabled) end
            Notify("TP Bullet", enabled and "ATIVADO 🚀" or "DESATIVADO")
        end,
        
        SetTPBulletPosition = function(pos)
            Settings.TPBulletPosition = pos
            if TPBullet and TPBullet.SetPosition then TPBullet:SetPosition(pos) end
        end,
        
        SetTPBulletDistance = function(dist)
            Settings.TPBulletDistance = dist
            if TPBullet and TPBullet.SetDistance then TPBullet:SetDistance(dist) end
        end,
        
        SetTPBulletHeight = function(height)
            Settings.TPBulletHeight = height
            if TPBullet and TPBullet.SetHeight then TPBullet:SetHeight(height) end
        end,
        
        SetTPBulletReturn = function(enabled)
            Settings.TPBulletReturn = enabled
            if TPBullet and TPBullet.SetReturnAfterShot then TPBullet:SetReturnAfterShot(enabled) end
        end,
        
        ForceTPReturn = function()
            if TPBullet and TPBullet.ForceReturn then return TPBullet:ForceReturn() end
            return false
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
            if Rage and Rage.IsActive and Rage:IsActive() then
                if Rage.GetCurrentTarget then
                    return Rage:GetCurrentTarget()
                end
            end
            if Aimbot and Aimbot.GetCurrentTarget then
                return Aimbot:GetCurrentTarget()
            end
            return nil
        end,
        
        Debug = function()
            print("\n═══════════════ AIMBOT DEBUG v24.0 ═══════════════")
            print("AimbotActive: " .. tostring(Settings.AimbotActive))
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
            print("\n─── MODULES ───")
            print("  Aimbot: " .. (Aimbot and "Loaded" or "Not Loaded"))
            print("  Rage: " .. (Rage and "Loaded" or "Not Loaded"))
            print("  TPBullet: " .. (TPBullet and "Loaded" or "Not Loaded"))
            print("  Trigger: " .. (AimbotTrigger and "Loaded" or "Not Loaded"))
            print("\n─── Current Target ───")
            local target = AimbotAPI.GetCurrentTarget()
            print("  Target: " .. (target and target.Name or "None"))
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
        Utils = AimbotUtils,
        
        -- Legacy Compatibility
        Main = Aimbot,
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
    
    print("[ForgeHub] ✓ Sistema de Mira v24.0 pronto!")
    
else
    warn("[ForgeHub] ✗ Falha ao carregar módulos de Aimbot!")
    warn("[ForgeHub] AimbotLegitModule: " .. tostring(AimbotLegitModule ~= nil))
    warn("[ForgeHub] AimbotUtils: " .. tostring(AimbotUtils ~= nil))
    
    -- API mínima para evitar erros
    AimbotAPI = {
        Initialize = function() warn("Aimbot não carregado") end,
        Toggle = function() end,
        SetRageMode = function() end,
        SetUltraRageMode = function() end,
        SetGodRageMode = function() end,
        SetTPBullet = function() end,
        SetTriggerBot = function() end,
        SetTargetMode = function() end,
        SetAimOutsideFOV = function() end,
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
        SafeCall(function() Semantic:Initialize() end, "SemanticInit")
    end
    
    -- Inicializar ESP
    if ESP and ESP.Initialize then
        SafeCall(function() ESP:Initialize() end, "ESPInit")
    end
    
    -- Inicializar Aimbot
    if AimbotAPI and AimbotAPI.Initialize then
        SafeCall(function() AimbotAPI.Initialize() end, "AimbotInit")
    end
    
    -- Inicializar UI
    if UI and UI.Initialize then
        SafeCall(function() UI:Initialize() end, "UIInit")
    end
    
    wait(0.5)
    Notify("ForgeHub v24.0", "✅ Todos os módulos carregados!")
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
        
        local status = Settings.AimbotActive and "ATIVADO ✅" or "DESATIVADO ❌"
        if Settings.GodRageMode then
            status = status .. " 👑 GOD"
        elseif Settings.UltraRageMode then
            status = status .. " ⚡ ULTRA"
        elseif Settings.RageMode then
            status = status .. " 🔥 RAGE"
        end
        
        Notify("Aimbot", status)
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
    while _G.ForgeHubLoaded do
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
    while _G.ForgeHubLoaded do
        wait(0.1)
        pcall(function()
            if Performance then
                if Performance.PerformanceManager and Performance.PerformanceManager.Update then
                    Performance.PerformanceManager:Update()
                end
            end
        end)
    end
end)

-- Semantic Periodic Updates
task.spawn(function()
    while _G.ForgeHubLoaded do
        wait(5)
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