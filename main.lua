-- ============================================================================
-- FORGEHUB ULTIMATE v23.1 - MAIN LOADER
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
-- GLOBAL SETTINGS
-- ============================================================================
local Settings = {
    -- Aimbot
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
    
    -- Predição
    UsePrediction = true,
    PredictionMultiplier = 0.135,

    -- FOV
    UseAimbotFOV = true,
    ShowFOV = true,
    FOV = 180,
    FOVColor = Color3.fromRGB(255, 255, 255),
    ShowTargetIndicator = true,

    -- ESP
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

    -- Cores
    BoxColor = Color3.fromRGB(255,170,60),
    SkeletonColor = Color3.fromRGB(255,255,255),
    LocalSkeletonColor = Color3.fromRGB(0,255,255),
    HighlightFillColor = Color3.fromRGB(255,0,0),
    HighlightOutlineColor = Color3.fromRGB(255,255,255),
    HighlightTransparency = 0.5,

    -- Lock adaptativo
    LockImprovementThreshold = 0.8,
    
    -- Adaptive
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

-- Base URL (ajuste para seu repositório)
local BASE_URL = "https://raw.githubusercontent.com/Spectro3n/ForgeHub/main/"

-- Carregar módulos na ordem correta
local Performance = LoadModule(BASE_URL .. "core/performance.lua", "Performance")
if not Performance then return end

local Semantic = LoadModule(BASE_URL .. "semantic/semantic.lua", "Semantic")
if not Semantic then return end

local ESP = LoadModule(BASE_URL .. "esp/esp.lua", "ESP")
if not ESP then return end

local Aimbot = LoadModule(BASE_URL .. "aimbot/aimbot.lua", "Aimbot")
if not Aimbot then return end

local UI = LoadModule(BASE_URL .. "ui/ui.lua", "UI")
if not UI then return end

-- ============================================================================
-- INITIALIZE MODULES
-- ============================================================================
task.spawn(function()
    wait(0.5)
    
    -- Inicializar Semantic Engine primeiro
    Semantic:Initialize()
    
    -- Inicializar ESP
    ESP:Initialize()
    
    -- Inicializar Aimbot
    Aimbot:Initialize()
    
    -- Inicializar UI
    UI:Initialize()
    
    wait(0.5)
    
    -- Notificação final
    local teamMethod = Semantic.TeamSystem.Method or "Detectando..."
    Notify("ForgeHub v23.1", string.format(
        "✅ SISTEMA PRONTO!\n\n" ..
        "🎮 Times: %s\n" ..
        "⚡ FPS: %.1f\n\n" ..
        "Pressione K para abrir menu",
        teamMethod,
        Performance.PerformanceManager.currentFPS
    ))
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

-- Aimbot Update Loop (já tem interno, mas garantir)
RunService.Heartbeat:Connect(function()
    pcall(function()
        Aimbot:Update()
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
-- CLEANUP
-- ============================================================================
local function Cleanup()
    for _, connection in ipairs(State.Connections) do
        pcall(function() connection:Disconnect() end)
    end
    
    if ESP and ESP.CleanupAll then
        ESP:CleanupAll()
    end
    
    if Performance and Performance.DrawingPool then
        Performance.DrawingPool:Clear()
    end
    
    _G.ForgeHubLoaded = false
    
    Notify("ForgeHub", "Sistema descarregado")
end

if game then
    game:BindToClose(Cleanup)
end

-- Export cleanup
_G.ForgeHubCleanup = Cleanup

return {
    Performance = Performance,
    Semantic = Semantic,
    ESP = ESP,
    Aimbot = Aimbot,
    UI = UI,
    Cleanup = Cleanup,
}