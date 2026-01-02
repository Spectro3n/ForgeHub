-- ============================================================================
-- FORGEHUB ULTIMATE v23.1 - MAIN LOADER (CORRIGIDO)
-- ============================================================================

-- Single instance check
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
-- GLOBAL SETTINGS (UNIFICADO COM AIMBOT)
-- ============================================================================
local Settings = {
    -- ══════════ AIMBOT CORE ══════════
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
    
    -- ══════════ AIMBOT v4.3 SETTINGS ══════════
    TargetMode = "FOV",           -- "FOV" ou "Closest"
    AimOutsideFOV = false,
    AutoResetOnKill = true,
    AimbotFOV = 180,
    
    -- Rage Modes
    RageMode = false,
    UltraRageMode = false,
    GodRageMode = false,
    
    -- Features
    SilentAim = false,
    SilentFOV = 150,
    MagicBullet = false,
    MagicBulletFOV = 200,
    TriggerBot = false,
    TriggerFOV = 100,
    TriggerDelay = 0.05,
    TriggerBurst = false,
    TriggerBurstCount = 3,
    AutoFire = false,
    
    -- ══════════ PREDICTION ══════════
    UsePrediction = true,
    PredictionMultiplier = 0.135,

    -- ══════════ FOV VISUAL ══════════
    UseAimbotFOV = true,
    ShowFOV = true,
    FOV = 180,
    FOVColor = Color3.fromRGB(255, 255, 255),
    ShowTargetIndicator = true,

    -- ══════════ ESP ══════════
    ESPEnabled = true,
    IgnoreTeamESP = true,
    ShowBox = true,
    ShowName = true,
    ShowHealthBar = true,
    ShowDistance = true,
    ShowHighlight = true,
    ESPMaxDistance = 1000,
    
    Drawing = {
        Skeleton = true,
        LocalSkeleton = false,
        SkeletonMaxDistance = 250,
    },

    -- ══════════ COLORS ══════════
    BoxColor = Color3.fromRGB(255, 170, 60),
    SkeletonColor = Color3.fromRGB(255, 255, 255),
    LocalSkeletonColor = Color3.fromRGB(0, 255, 255),
    HighlightFillColor = Color3.fromRGB(255, 0, 0),
    HighlightOutlineColor = Color3.fromRGB(255, 255, 255),
    HighlightTransparency = 0.5,

    -- ══════════ ADAPTIVE ══════════
    LockImprovementThreshold = 0.8,
    UseAdaptiveSmoothing = true,
    UseDeadzone = true,
    DeadzoneRadius = 0.5,
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
local function LoadModule(url, moduleName)
    local success, result = pcall(function()
        return loadstring(game:HttpGet(url))()
    end)
    
    if success then
        Notify("ForgeHub", "✅ " .. moduleName .. " carregado")
        return result
    else
        Notify("ForgeHub", "❌ Erro ao carregar " .. moduleName)
        warn("[ForgeHub] Erro ao carregar " .. moduleName .. ": " .. tostring(result))
        return nil
    end
end

-- ============================================================================
-- LOAD MODULES
-- ============================================================================
Notify("ForgeHub v23.1", "Iniciando carregamento...")

local BASE_URL = "https://raw.githubusercontent.com/Spectro3n/ForgeHub/main/"

-- Carregar módulos base primeiro
local Performance = LoadModule(BASE_URL .. "core/performance.lua", "Performance")
if not Performance then return end

local Semantic = LoadModule(BASE_URL .. "semantic/semantic.lua", "Semantic")
if not Semantic then return end

local ESP = LoadModule(BASE_URL .. "esp/esp.lua", "ESP")
if not ESP then return end

-- ════════════════════════════════════════════════════════════════════════════
-- CARREGAR AIMBOT v4.3 (MODULAR)
-- ════════════════════════════════════════════════════════════════════════════

-- Primeiro carregar dependências do Aimbot
local AimbotUtils = LoadModule(BASE_URL .. "aimbot/utils.lua", "Aimbot/Utils")
local AimbotSettings = LoadModule(BASE_URL .. "aimbot/settings.lua", "Aimbot/Settings")
local AimbotEventBus = LoadModule(BASE_URL .. "aimbot/eventbus.lua", "Aimbot/EventBus")
local AimbotHooks = LoadModule(BASE_URL .. "aimbot/Hooks.lua", "Aimbot/Hooks")
local AimbotCore = LoadModule(BASE_URL .. "aimbot/Aimbot.lua", "Aimbot/Core")
local AimbotTrigger = LoadModule(BASE_URL .. "aimbot/Trigger.lua", "Aimbot/Trigger")
local AimbotSilent = LoadModule(BASE_URL .. "aimbot/Silent.lua", "Aimbot/Silent")
local AimbotMagicBullet = LoadModule(BASE_URL .. "aimbot/MagicBullet.lua", "Aimbot/MagicBullet")

-- Verificar se todos carregaram
if not (AimbotUtils and AimbotSettings and AimbotEventBus and AimbotHooks and AimbotCore) then
    warn("[ForgeHub] Falha ao carregar módulos do Aimbot")
    return
end

-- Sincronizar settings
if AimbotSettings.Settings then
    for key, value in pairs(Settings) do
        if AimbotSettings.Settings[key] == nil then
            AimbotSettings.Settings[key] = value
        end
    end
    -- Usar settings do aimbot como referência compartilhada
    Core.Settings = setmetatable(Settings, {
        __index = AimbotSettings.Settings,
        __newindex = function(t, k, v)
            rawset(t, k, v)
            if AimbotSettings.Settings then
                AimbotSettings.Settings[k] = v
            end
        end
    })
end

-- Criar SharedDeps para inicialização
local SharedDeps = {
    Utils = AimbotUtils,
    Settings = AimbotSettings.Settings or Settings,
    EventBus = AimbotEventBus,
    Hooks = AimbotHooks,
    LocalPlayer = LocalPlayer,
    UserInputService = UserInputService,
    Players = Players,
}

-- Inicializar módulos do Aimbot
AimbotHooks:Initialize({EventBus = AimbotEventBus})

local Aimbot = AimbotCore.Aimbot or AimbotCore
local TargetLock = AimbotCore.TargetLock

Aimbot:Initialize(SharedDeps)
SharedDeps.Aimbot = Aimbot

if AimbotTrigger then AimbotTrigger:Initialize(SharedDeps) end
if AimbotSilent then AimbotSilent:Initialize(SharedDeps) end
if AimbotMagicBullet then AimbotMagicBullet:Initialize(SharedDeps) end

-- ════════════════════════════════════════════════════════════════════════════
-- CRIAR API UNIFICADA DO AIMBOT
-- ════════════════════════════════════════════════════════════════════════════

local AimbotAPI = {
    Main = Aimbot,
    TargetLock = TargetLock,
    Trigger = AimbotTrigger,
    Silent = AimbotSilent,
    MagicBullet = AimbotMagicBullet,
    Utils = AimbotUtils,
    Hooks = AimbotHooks,
    EventBus = AimbotEventBus,
    Settings = AimbotSettings,
    
    Initialize = function()
        print("═══════════════════════════════════════════")
        print("  AIMBOT v4.3 - INTEGRADO COM FORGEHUB")
        print("═══════════════════════════════════════════")
        print("[✓] Target Mode: " .. (Settings.TargetMode or "FOV"))
        print("[✓] Modules Loaded: OK")
        print("═══════════════════════════════════════════")
    end,
    
    Update = function()
        local mouseHold = State.MouseHold
        Aimbot:Update(mouseHold)
        
        if Settings.TriggerBot and AimbotTrigger then
            AimbotTrigger:Update()
        end
    end,
    
    Toggle = function(enabled)
        Settings.AimbotActive = enabled
        if not enabled then
            Aimbot:ForceReset()
        end
    end,
    
    SetRageMode = function(enabled)
        if AimbotSettings.API then
            AimbotSettings.API:SetRageMode(enabled)
        end
        Settings.RageMode = enabled
        Notify("Aimbot", "Rage Mode " .. (enabled and "ATIVADO 🔥" or "DESATIVADO"))
    end,
    
    SetSilentAim = function(enabled)
        Settings.SilentAim = enabled
        if AimbotSilent then
            if enabled then AimbotSilent:Enable() else AimbotSilent:Disable() end
        end
        Notify("Silent Aim", enabled and "ATIVADO 🎯" or "DESATIVADO")
    end,
    
    SetMagicBullet = function(enabled)
        Settings.MagicBullet = enabled
        if AimbotMagicBullet then
            if enabled then AimbotMagicBullet:Enable() else AimbotMagicBullet:Disable() end
        end
        Notify("Magic Bullet", enabled and "ATIVADO ✨" or "DESATIVADO")
    end,
    
    SetTriggerBot = function(enabled)
        Settings.TriggerBot = enabled
        if AimbotTrigger then
            if enabled then AimbotTrigger:Enable() else AimbotTrigger:Disable() end
        end
        Notify("Trigger Bot", enabled and "ATIVADO ⚡" or "DESATIVADO")
    end,
    
    GetCurrentTarget = function()
        return Aimbot:GetCurrentTarget()
    end,
    
    Debug = function()
        print("\n═══════════════ AIMBOT DEBUG ═══════════════")
        print("AimbotActive: " .. tostring(Settings.AimbotActive))
        print("RageMode: " .. tostring(Settings.RageMode))
        print("SilentAim: " .. tostring(Settings.SilentAim))
        print("TriggerBot: " .. tostring(Settings.TriggerBot))
        local target = Aimbot:GetCurrentTarget()
        print("Current Target: " .. (target and target.Name or "None"))
        print("═══════════════════════════════════════════\n")
    end,
}

-- Exportar para Core
Core.Aimbot = AimbotAPI

-- ════════════════════════════════════════════════════════════════════════════

local UI = LoadModule(BASE_URL .. "ui/ui.lua", "UI")
if not UI then return end

-- ============================================================================
-- INITIALIZE MODULES
-- ============================================================================
task.spawn(function()
    wait(0.5)
    
    Semantic:Initialize()
    ESP:Initialize()
    AimbotAPI.Initialize()
    UI:Initialize()
    
    wait(0.5)
end)

-- ============================================================================
-- INPUT HANDLING (Mouse Hold para Aimbot)
-- ============================================================================
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    
    if isInputMatch(input, Settings.AimbotUseKey) then
        State.MouseHold = true
    end
    
    if isInputMatch(input, Settings.AimbotToggleKey) then
        Settings.AimbotActive = not Settings.AimbotActive
        Notify("Aimbot", Settings.AimbotActive and "ATIVADO" or "DESATIVADO")
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if isInputMatch(input, Settings.AimbotUseKey) then
        State.MouseHold = false
    end
end)

-- ============================================================================
-- MAIN LOOPS
-- ============================================================================

-- ESP Update Loop
task.spawn(function()
    while task.wait(Performance.PerformanceManager.espInterval) do
        pcall(function()
            if Settings.ESPEnabled then
                for _, player in ipairs(CachedPlayers) do
                    if player ~= LocalPlayer then
                        ESP:UpdatePlayer(player)
                    end
                end
            end
        end)
    end
end)

-- Aimbot Update Loop
RunService.Heartbeat:Connect(function()
    pcall(function()
        if Settings.AimbotActive or State.MouseHold then
            AimbotAPI.Update()
        end
    end)
end)

-- Performance & Profiler Loop
task.spawn(function()
    while wait(0.1) do
        pcall(function()
            Performance.PerformanceManager:Update()
            Performance.Profiler:Update()
        end)
    end
end)

-- Semantic Periodic Updates
task.spawn(function()
    while wait(5) do
        pcall(function()
            Semantic:ScanForContainers()
            Semantic:AutoDetectTeamSystem()
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
        
        if Core.SemanticEngine and Core.SemanticEngine.TrackPlayer then
            Core.SemanticEngine:TrackPlayer(player)
        end
        
        if Core.ESP and Core.ESP.CreatePlayerESP then
            Core.ESP:CreatePlayerESP(player)
        end
        
        -- Notificar Aimbot Utils
        if AimbotUtils and AimbotUtils.BuildPartCacheFor then
            AimbotUtils.BuildPartCacheFor(player)
        end
    end)
    
    player.CharacterAdded:Connect(function(character)
        task.wait(0.2)
        UpdatePlayerCache()
        
        if AimbotUtils then
            AimbotUtils.InvalidatePlayerData(player)
            task.wait(0.1)
            AimbotUtils.BuildPartCacheFor(player)
        end
        
        if Core.ESP then
            Core.ESP:RemovePlayerESP(player)
            task.wait(0.1)
            Core.ESP:CreatePlayerESP(player)
        end
    end)
end)

Players.PlayerRemoving:Connect(function(player)
    UpdatePlayerCache()
    
    if AimbotUtils and AimbotUtils.InvalidatePlayerData then
        AimbotUtils.InvalidatePlayerData(player)
    end
    
    if Core.ESP and Core.ESP.RemovePlayerESP then
        Core.ESP:RemovePlayerESP(player)
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
    
    if Aimbot and Aimbot.ForceReset then
        Aimbot:ForceReset()
    end
    
    if Performance and Performance.DrawingPool then
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