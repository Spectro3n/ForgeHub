-- ============================================================================
-- FORGEHUB ULTIMATE v24.2 - MAIN LOADER (FULLY FIXED)
-- ============================================================================

-- CORREÇÃO: Verificação segura de script duplicado
if _G.ForgeHubLoaded then
    if _G.Rayfield and type(_G.Rayfield.Notify) == "function" then
        pcall(function()
            _G.Rayfield:Notify({
                Title = "ForgeHub",
                Content = "Script já em execução!",
                Duration = 3,
                Image = 4483362458,
            })
        end)
    else
        warn("[ForgeHub] Script já em execução (Rayfield não disponível para notificar).")
    end
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
    if not _G.Rayfield then return end

    pcall(function()
        _G.Rayfield:Notify({
            Title = title,
            Content = content,
            Duration = 3,
            Image = image or 4483362458,
        })
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
-- CAMERA REFERENCE (CORRIGIDO: Auto-update)
-- ============================================================================
local function GetCamera()
    return Workspace.CurrentCamera or Workspace:FindFirstChildOfClass("Camera")
end

Camera = GetCamera()

Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
    Camera = GetCamera()
    if _G.ForgeHubCore then
        _G.ForgeHubCore.Camera = Camera
    end
end)

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
-- DETECTAR MouseMoveRel
-- ============================================================================
local DetectedMouseMoveRel = nil

local function DetectMouseMoveRel()
    local mmrNames = {"mousemoverel", "mouse_moverel", "MouseMoveRel", "movemouserel"}

    -- Tentar getgenv
    if getgenv then
        for _, name in ipairs(mmrNames) do
            local success, func = pcall(function() return getgenv()[name] end)
            if success and type(func) == "function" then
                DetectedMouseMoveRel = func
                print("[ForgeHub] MouseMoveRel detectado via getgenv:", name)
                return func
            end
        end
    end

    -- Tentar _G
    for _, name in ipairs(mmrNames) do
        local success, func = pcall(function() return _G[name] end)
        if success and type(func) == "function" then
            DetectedMouseMoveRel = func
            print("[ForgeHub] MouseMoveRel detectado via _G:", name)
            return func
        end
    end

    -- Tentar shared
    if shared then
        for _, name in ipairs(mmrNames) do
            local success, func = pcall(function() return shared[name] end)
            if success and type(func) == "function" then
                DetectedMouseMoveRel = func
                print("[ForgeHub] MouseMoveRel detectado via shared:", name)
                return func
            end
        end
    end

    print("[ForgeHub] MouseMoveRel NÃO detectado")
    return nil
end

DetectMouseMoveRel()

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
    AimbotToggleOnly = false,
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
    
    -- NOVO: Aim Safety
    AimSafety = false,
    MaxCameraFailures = 5,
    MaxMouseMovePerFrame = 50,
}

local State = {
    DrawingESP = {},
    MouseHold = false,
    Connections = {},
    CameraFailCount = 0,
}

-- ============================================================================
-- SETTINGS SYNC FUNCTION
-- ============================================================================
local function SyncSettings()
    Settings.IgnoreTeam = Settings.IgnoreTeamAimbot
    Settings.FOV = Settings.AimbotFOV
    
    -- Sync ESP settings
    if Settings.ESP then
        Settings.ESP.Enabled = Settings.ESPEnabled
        Settings.ESP.IgnoreTeam = Settings.IgnoreTeamESP
    end
end

-- Chamar sync inicial
SyncSettings()

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
    GetCamera = GetCamera,
    
    -- Utilities
    Notify = Notify,
    SafeCall = SafeCall,
    NormalizeKey = NormalizeKey,
    isInputMatch = isInputMatch,
    SyncSettings = SyncSettings,
    
    -- Data
    Settings = Settings,
    State = State,
    CachedPlayers = CachedPlayers,
    UpdatePlayerCache = UpdatePlayerCache,
    
    -- Raycast
    _sharedRayParams = _sharedRayParams,
    
    -- Drawing
    DrawingOK = DrawingOK,
    
    -- MouseMoveRel
    MouseMoveRel = DetectedMouseMoveRel,
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
Notify("ForgeHub v24.2", "Iniciando carregamento...")

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
Notify("ForgeHub", "🎯 Carregando Sistema de Mira...")

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

if AimbotLegitModule and AimbotUtils then
    print("[ForgeHub] Módulos de Aimbot carregados, inicializando...")
    
    -- Sincronizar settings
    if AimbotSettingsModule and type(AimbotSettingsModule) == "table" then
        for key, value in pairs(AimbotSettingsModule) do
            if type(value) ~= "function" and Settings[key] == nil then
                Settings[key] = value
            end
        end
    end
    
    SyncSettings()
    
    -- SharedDeps
    local SharedDeps = {
        Utils = AimbotUtils,
        Settings = Settings,
        LocalPlayer = LocalPlayer,
        UserInputService = UserInputService,
        Players = Players,
        Camera = Camera,
        MouseMoveRel = DetectedMouseMoveRel,
        Workspace = Workspace,
        RunService = RunService,
    }
    
    -- Obter referências
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
        local initSuccess, initError = pcall(function()
            Aimbot:Initialize(SharedDeps)
        end)
        if initSuccess then
            print("[ForgeHub] ✓ Aimbot Legit inicializado")
            
            if Aimbot._hasMMR then
                print("[ForgeHub] ✓ MouseMoveRel disponível no Aimbot")
            else
                print("[ForgeHub] ⚠ MouseMoveRel não disponível, usando Camera method")
            end
            
            if Settings.AimSafety then
                print("[ForgeHub] 🛡️ AimSafety ativo - MMR desativado por segurança")
            end
        else
            warn("[ForgeHub] ✗ Falha ao inicializar Aimbot Legit: " .. tostring(initError))
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
    -- CLICK SIMULATION
    -- ========================================================================
    local function SimulateClick()
        local success = false
        
        if mouse1press and mouse1release then
            pcall(function()
                mouse1press()
                task.wait(0.01)
                mouse1release()
                success = true
            end)
        end
        
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
        State.CameraFailCount = 0
        if Aimbot and Aimbot.ForceReset then pcall(function() Aimbot:ForceReset() end) end
        if Rage and Rage.ForceReset then pcall(function() Rage:ForceReset() end) end
        if TPBullet and TPBullet.ForceReset then pcall(function() TPBullet:ForceReset() end) end
        if AimbotTrigger and AimbotTrigger.Disable then pcall(function() AimbotTrigger:Disable() end) end
        if AimbotUtils and AimbotUtils.ClearAllCaches then pcall(function() AimbotUtils.ClearAllCaches() end) end
    end
    
    local function MainUpdate()
        if not Settings.AimbotActive then return end
        
        local success, errorMsg = pcall(function()
            local mouseHold = State.MouseHold
            
            if Settings.AimbotToggleOnly then
                mouseHold = true
            end
            
            local rageProcessed = false
            
            if Rage and Rage.IsActive and Rage:IsActive() then
                if Rage.Update then
                    rageProcessed = Rage:Update(mouseHold)
                end
            end
            
            if not rageProcessed and Aimbot and Aimbot.Update then
                Aimbot:Update(mouseHold)
            end
            
            if TPBullet and Settings.TPBullet and TPBullet.Update then
                TPBullet:Update(mouseHold)
            end
            
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
            
            if Settings.AutoFire and mouseHold then
                AutoFire:TryFire()
            end
        end)
        
        if not success then
            AimbotState.ErrorCount = AimbotState.ErrorCount + 1
            
            if AimbotState.ErrorCount <= 3 then
                warn("[Aimbot] Error #" .. AimbotState.ErrorCount .. ": " .. tostring(errorMsg))
            end
            
            if AimbotState.ErrorCount >= AimbotState.MaxErrors then
                warn("[Aimbot] Muitos erros, resetando...")
                AimbotState:Reset()
            end
        else
            if AimbotState.ErrorCount > 0 then
                AimbotState.ErrorCount = math.max(0, AimbotState.ErrorCount - 1)
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
        print("[Aimbot] Loop iniciado usando", 
              (Settings.GodRageMode or Settings.UltraRageMode or Settings.RageMode) 
              and "RenderStepped" or "Heartbeat")
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
        Initialize = function()
            StartLoop()
            
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
            print("  SISTEMA DE MIRA v24.2 FIXED")
            print("═══════════════════════════════════════════")
            print("[✓] Aimbot: " .. (Aimbot and "OK" or "N/A"))
            print("[✓] Rage: " .. (Rage and "OK" or "N/A"))
            print("[✓] TP Bullet: " .. (TPBullet and "OK" or "N/A"))
            print("[✓] Trigger: " .. (AimbotTrigger and "OK" or "N/A"))
            print("[✓] MouseMoveRel: " .. (DetectedMouseMoveRel and "Detectado" or "Não disponível"))
            print("[✓] AimSafety: " .. (Settings.AimSafety and "ON" or "OFF"))
            print("═══════════════════════════════════════════")
        end,
        
        Toggle = function(enabled)
            Settings.AimbotActive = enabled
            if not enabled then
                AimbotState:Reset()
            end
        end,
        
        SetToggleOnlyMode = function(enabled)
            Settings.AimbotToggleOnly = enabled
            Notify("Aimbot", "Toggle-Only: " .. (enabled and "ATIVADO" or "DESATIVADO"))
        end,
        
        GetToggleOnlyMode = function()
            return Settings.AimbotToggleOnly
        end,
        
        -- NOVO: Aim Safety
        SetAimSafety = function(enabled)
            Settings.AimSafety = enabled
            
            -- Revalidar MMR
            if Aimbot and Aimbot.RevalidateMMR then
                Aimbot:RevalidateMMR()
            end
            
            Notify("Aim Safety", enabled and "🛡️ ATIVADO - MMR desativado" or "❌ DESATIVADO")
        end,
        
        GetAimSafety = function()
            return Settings.AimSafety
        end,
        
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
        
        SetAutoFire = function(enabled)
            Settings.AutoFire = enabled
            Notify("Auto Fire", enabled and "ATIVADO 🔫" or "DESATIVADO")
        end,
        
        SetAutoSwitch = function(enabled)
            Settings.AutoSwitch = enabled
        end,
        
        SetPrediction = function(enabled)
            Settings.UsePrediction = enabled
        end,
        
        SetPredictionMultiplier = function(mult)
            Settings.PredictionMultiplier = mult
        end,
        
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
        
        GetHasMMR = function()
            if Aimbot and Aimbot._hasMMR then
                return true
            end
            return DetectedMouseMoveRel ~= nil
        end,
        
        GetDebugInfo = function()
            local aimbotInfo = {}
            if Aimbot and Aimbot.GetDebugInfo then
                aimbotInfo = Aimbot:GetDebugInfo()
            end
            
            return {
                AimbotActive = Settings.AimbotActive,
                ToggleOnly = Settings.AimbotToggleOnly,
                AimSafety = Settings.AimSafety,
                MouseHold = State.MouseHold,
                HasMMR = AimbotAPI.GetHasMMR(),
                RageMode = Settings.RageMode,
                UltraRageMode = Settings.UltraRageMode,
                GodRageMode = Settings.GodRageMode,
                TargetMode = Settings.TargetMode,
                CurrentTarget = AimbotAPI.GetCurrentTarget(),
                ErrorCount = AimbotState.ErrorCount,
                AimbotDetails = aimbotInfo,
            }
        end,
        
        Debug = function()
            local info = AimbotAPI.GetDebugInfo()
            print("\n═══════════════ AIMBOT DEBUG v24.2 ═══════════════")
            print("AimbotActive: " .. tostring(info.AimbotActive))
            print("ToggleOnly: " .. tostring(info.ToggleOnly))
            print("AimSafety: " .. tostring(info.AimSafety))
            print("MouseHold: " .. tostring(info.MouseHold))
            print("Connection Active: " .. tostring(AimbotState.Connection ~= nil))
            print("Error Count: " .. tostring(info.ErrorCount))
            print("\n─── TARGET SETTINGS ───")
            print("  TargetMode: " .. (info.TargetMode or "FOV"))
            print("  AimOutsideFOV: " .. tostring(Settings.AimOutsideFOV))
            print("  AimbotFOV: " .. tostring(Settings.AimbotFOV))
            print("  MaxDistance: " .. tostring(Settings.MaxDistance))
            print("\n─── RAGE STATUS ───")
            print("  RageMode: " .. tostring(info.RageMode))
            print("  UltraRageMode: " .. tostring(info.UltraRageMode))
            print("  GodRageMode: " .. tostring(info.GodRageMode))
            print("\n─── EXECUTOR ───")
            print("  HasMMR: " .. tostring(info.HasMMR))
            print("  AimMethod: " .. tostring(Settings.AimMethod))
            print("  ChosenMethod: " .. (info.AimbotDetails.aimMethod or "N/A"))
            print("\n─── MODULES ───")
            print("  Aimbot: " .. (Aimbot and "Loaded" or "Not Loaded"))
            print("  Rage: " .. (Rage and "Loaded" or "Not Loaded"))
            print("  TPBullet: " .. (TPBullet and "Loaded" or "Not Loaded"))
            print("  Trigger: " .. (AimbotTrigger and "Loaded" or "Not Loaded"))
            print("\n─── Current Target ───")
            print("  Target: " .. (info.CurrentTarget and info.CurrentTarget.Name or "None"))
            print("═══════════════════════════════════════════\n")
        end,
        
        EnableDebug = function(enabled)
            if Aimbot and Aimbot.EnableDebug then
                Aimbot:EnableDebug(enabled)
            end
            if Rage and Rage.EnableDebug then
                Rage:EnableDebug(enabled)
            end
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
    
    Core.Aimbot = AimbotAPI
    
    print("[ForgeHub] ✓ Sistema de Mira v24.2 pronto!")
    
else
    warn("[ForgeHub] ✗ Falha ao carregar módulos de Aimbot!")
    warn("[ForgeHub] AimbotLegitModule: " .. tostring(AimbotLegitModule ~= nil))
    warn("[ForgeHub] AimbotUtils: " .. tostring(AimbotUtils ~= nil))
    
    AimbotAPI = {
        Initialize = function() warn("Aimbot não carregado") end,
        Toggle = function() end,
        SetToggleOnlyMode = function() end,
        GetToggleOnlyMode = function() return false end,
        SetAimSafety = function() end,
        GetAimSafety = function() return false end,
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
        GetHasMMR = function() return false end,
        GetDebugInfo = function() return {} end,
        Debug = function() print("Aimbot não carregado") end,
        EnableDebug = function() end,
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
    
    if Semantic and Semantic.Initialize then
        SafeCall(function() Semantic:Initialize() end, "SemanticInit")
    end
    
    if ESP and ESP.Initialize then
        SafeCall(function() ESP:Initialize() end, "ESPInit")
    end
    
    if AimbotAPI and AimbotAPI.Initialize then
        SafeCall(function() AimbotAPI.Initialize() end, "AimbotInit")
    end
    
    if UI and UI.Initialize then
        SafeCall(function() UI:Initialize() end, "UIInit")
    end
    
    wait(0.5)
    Notify("ForgeHub v24.2", "✅ Todos os módulos carregados!")
end)

-- ============================================================================
-- INPUT HANDLING
-- ============================================================================
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    
    if isInputMatch(input, Settings.AimbotUseKey) then
        State.MouseHold = true
    end
    
    if isInputMatch(input, Settings.AimbotToggleKey) then
        Settings.AimbotActive = not Settings.AimbotActive
        
        local status = Settings.AimbotActive and "ATIVADO ✅" or "DESATIVADO ❌"
        
        if Settings.AimbotToggleOnly then
            status = status .. " (Toggle-Only)"
        end
        
        if Settings.AimSafety then
            status = status .. " 🛡️"
        end
        
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
    if isInputMatch(input, Settings.AimbotUseKey) then
        State.MouseHold = false
    end
end)

-- ============================================================================
-- MAIN LOOPS
-- ============================================================================

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

-- ============================================================================
-- EXPORT
-- ============================================================================
return {
    Performance = Performance,
    Semantic = Semantic,
    ESP = ESP,
    Aimbot = AimbotAPI,
    UI = UI,
    Cleanup = Cleanup,
}