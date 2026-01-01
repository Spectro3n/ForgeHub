-- ============================================================================
-- FORGEHUB - UI MODULE
-- ============================================================================

local Core = _G.ForgeHubCore
if not Core then
    error("ForgeHubCore não encontrado! Carregue main.lua primeiro.")
end

local SafeCall = Core.SafeCall
local Notify = Core.Notify
local NormalizeKey = Core.NormalizeKey
local isInputMatch = Core.isInputMatch

local Settings = Core.Settings
local State = Core.State
local DrawingPool = Core.DrawingPool
local SemanticEngine = Core.SemanticEngine
local PerformanceManager = Core.PerformanceManager

local RunService = Core.RunService
local UserInputService = Core.UserInputService
local Camera = Core.Camera
local LocalPlayer = Core.LocalPlayer
local Players = Core.Players

-- ============================================================================
-- FOV CIRCLE & TARGET INDICATOR
-- ============================================================================
local FOVCircle = nil
local TargetIndicator = nil

local function InitializeVisuals()
    if not Core.DrawingOK then return end
    
    FOVCircle = DrawingPool:Acquire("Circle")
    if FOVCircle then
        FOVCircle.Thickness = 1.5
        FOVCircle.NumSides = 64
        FOVCircle.Radius = Settings.FOV
        FOVCircle.Filled = false
        FOVCircle.Visible = false
        FOVCircle.Color = Settings.FOVColor
        FOVCircle.Transparency = 1
    end
    
    TargetIndicator = DrawingPool:Acquire("Circle")
    if TargetIndicator then
        TargetIndicator.Thickness = 3
        TargetIndicator.NumSides = 32
        TargetIndicator.Radius = 10
        TargetIndicator.Filled = false
        TargetIndicator.Visible = false
        TargetIndicator.Color = Color3.fromRGB(0, 255, 0)
        TargetIndicator.Transparency = 1
    end
end

local function UpdateVisuals()
    if not FOVCircle then return end
    
    FOVCircle.Visible = Settings.ShowFOV
    FOVCircle.Radius = math.clamp(Settings.FOV or 0, 1, 5000)
    local mousePos = UserInputService:GetMouseLocation()
    FOVCircle.Position = Vector2.new(mousePos.X, mousePos.Y)
    FOVCircle.Color = Settings.FOVColor
    
    if TargetIndicator and Settings.ShowTargetIndicator then
        local Aimbot = Core.Aimbot
        if not Aimbot then return end
        
        local lockedTarget = Aimbot.CameraBypass:GetLockedTarget()
        
        if lockedTarget and Settings.AimbotActive and State.MouseHold then
            local data = SemanticEngine:GetCachedPlayerData(lockedTarget)
            if data and data.isValid and data.anchor then
                local screenPos, onScreen = Camera:WorldToViewportPoint(data.anchor.Position)
                if onScreen then
                    TargetIndicator.Position = Vector2.new(screenPos.X, screenPos.Y)
                    TargetIndicator.Visible = true
                    
                    local pulse = math.abs(math.sin(tick() * 5))
                    TargetIndicator.Color = Color3.fromRGB(0, 255 * pulse, 0)
                else
                    TargetIndicator.Visible = false
                end
            else
                TargetIndicator.Visible = false
            end
        else
            TargetIndicator.Visible = false
        end
    elseif TargetIndicator then
        TargetIndicator.Visible = false
    end
end

-- ============================================================================
-- INPUT HANDLING
-- ============================================================================
local function SetupInputHandling()
    UserInputService.InputBegan:Connect(function(input, gp)
        if gp then return end
        
        if isInputMatch(input, Settings.AimbotUseKey) then 
            State.MouseHold = true 
        end
        
        if isInputMatch(input, Settings.AimbotToggleKey) then 
            Settings.AimbotActive = not Settings.AimbotActive
            Notify("Aimbot", Settings.AimbotActive and "ATIVADO ✅" or "DESATIVADO ❌")
        end
    end)

    UserInputService.InputEnded:Connect(function(input, gp)
        if gp then return end
        
        if isInputMatch(input, Settings.AimbotUseKey) then 
            State.MouseHold = false 
        end
    end)
end

-- ============================================================================
-- RAYFIELD UI
-- ============================================================================
local UI = {}

function UI:CreateInterface()
    local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

    local Window = Rayfield:CreateWindow({
        Name = "ForgeHub Ultimate | v23.1 MODULAR ✅",
        LoadingTitle = "Carregando Engine v23.1...",
        LoadingSubtitle = "✅ Arquitetura modular\n✅ Sistema otimizado\n✅ Performance aprimorada",
        Theme = "AmberGlow",
        ToggleUIKeybind = "k",
        ConfigurationSaving = { Enabled = false }
    })

    local MainTab = Window:CreateTab("🎯 Legit Bot")
    local ESPTab = Window:CreateTab("👁️ Visuals")
    local SystemTab = Window:CreateTab("⚙️ Sistema")

    local function HandleDropdown(val)
        if type(val) == "table" and #val > 0 then 
            return val[1] 
        end
        return val
    end

    -- ========================================================================
    -- MAIN TAB
    -- ========================================================================
    MainTab:CreateSection("Atalhos Principais")

    MainTab:CreateInput({
        Name = "⌨️ Tecla Aimbot Toggle",
        PlaceholderText = "Q",
        RemoveTextAfterFocusLost = false,
        Callback = function(Text)
            Settings.AimbotToggleKey = NormalizeKey(Text)
        end
    })

    MainTab:CreateDropdown({
        Name = "🖱️ Botão de Mira (Segurar)",
        Options = {"MouseButton1","MouseButton2","MouseButton3"},
        CurrentOption = "MouseButton2",
        Callback = function(Option)
            Settings.AimbotUseKey = NormalizeKey(HandleDropdown(Option))
        end,
    })

    MainTab:CreateSection("Configuração de Mira")

    MainTab:CreateToggle({
        Name = "🎯 Ativar Aimbot",
        CurrentValue = Settings.AimbotActive,
        Callback = function(v)
            Settings.AimbotActive = v
        end
    })

    MainTab:CreateDropdown({
        Name = "🎮 Método de Aim",
        Options = {"Camera", "MouseMoveRel"},
        CurrentOption = "Camera",
        Callback = function(Option)
            Settings.AimMethod = HandleDropdown(Option)
        end
    })

    MainTab:CreateDropdown({
        Name = "👀 Parte do Corpo",
        Options = {"Head", "Torso", "Root"},
        CurrentOption = "Head",
        Callback = function(Option)
            Settings.AimPart = HandleDropdown(Option)
        end
    })

    MainTab:CreateSlider({
        Name = "🔧 Suavização (Legit)",
        Range = {0, 20},
        Increment = 1,
        CurrentValue = Settings.SmoothingFactor,
        Callback = function(v)
            Settings.SmoothingFactor = v
        end
    })

    MainTab:CreateSlider({
        Name = "📏 Distância Máxima",
        Range = {100, 2000},
        Increment = 100,
        CurrentValue = Settings.MaxDistance,
        Callback = function(v)
            Settings.MaxDistance = v
        end
    })

    MainTab:CreateSection("FOV & Visuals")

    MainTab:CreateToggle({
        Name = "⭕ Mostrar FOV (Circle)",
        CurrentValue = Settings.ShowFOV,
        Callback = function(v)
            Settings.ShowFOV = v
        end
    })

    MainTab:CreateSlider({
        Name = "📐 Tamanho FOV",
        Range = {10, 1000},
        Increment = 10,
        CurrentValue = Settings.FOV,
        Callback = function(v)
            Settings.FOV = v
        end
    })

    MainTab:CreateToggle({
        Name = "🛡️ Ignorar Meu Time",
        CurrentValue = Settings.IgnoreTeamAimbot,
        Callback = function(v)
            Settings.IgnoreTeamAimbot = v
        end
    })

    MainTab:CreateToggle({
        Name = "👁 Check Visibilidade",
        CurrentValue = Settings.VisibleCheck,
        Callback = function(v)
            Settings.VisibleCheck = v
        end
    })

    MainTab:CreateSection("Predição")

    MainTab:CreateToggle({
        Name = "🎯 Usar Predição",
        CurrentValue = Settings.UsePrediction,
        Callback = function(v)
            Settings.UsePrediction = v
        end
    })

    MainTab:CreateSlider({
        Name = "⚡ Multiplicador de Predição",
        Range = {0.05, 0.5},
        Increment = 0.01,
        CurrentValue = Settings.PredictionMultiplier,
        Callback = function(v)
            Settings.PredictionMultiplier = v
        end
    })

    -- ========================================================================
    -- ESP TAB
    -- ========================================================================
    ESPTab:CreateSection("ESP Core")

    ESPTab:CreateToggle({
        Name = "👁️ Ativar ESP",
        CurrentValue = Settings.ESPEnabled,
        Callback = function(v)
            Settings.ESPEnabled = v
        end
    })

    ESPTab:CreateToggle({
        Name = "🤝 Ignorar Meu Time",
        CurrentValue = Settings.IgnoreTeamESP,
        Callback = function(v)
            Settings.IgnoreTeamESP = v
        end
    })

    ESPTab:CreateSlider({
        Name = "📏 Distância Máxima ESP",
        Range = {100, 5000},
        Increment = 100,
        CurrentValue = Settings.ESPMaxDistance,
        Callback = function(v)
            Settings.ESPMaxDistance = v
        end
    })

    ESPTab:CreateSection("Elementos Visuais")

    ESPTab:CreateToggle({
        Name = "📦 Caixa (Box)",
        CurrentValue = Settings.ShowBox,
        Callback = function(v)
            Settings.ShowBox = v
        end
    })

    ESPTab:CreateToggle({
        Name = "🦴 Skeleton (Esqueleto)",
        CurrentValue = Settings.Drawing.Skeleton,
        Callback = function(v)
            Settings.Drawing.Skeleton = v
        end
    })

    ESPTab:CreateSlider({
        Name = "📏 Distância Máx Skeleton",
        Range = {50, 500},
        Increment = 50,
        CurrentValue = Settings.Drawing.SkeletonMaxDistance,
        Callback = function(v)
            Settings.Drawing.SkeletonMaxDistance = v
        end
    })

    ESPTab:CreateToggle({
        Name = "📛 Nomes",
        CurrentValue = Settings.ShowName,
        Callback = function(v)
            Settings.ShowName = v
        end
    })

    ESPTab:CreateToggle({
        Name = "💚 Barra de Vida",
        CurrentValue = Settings.ShowHealthBar,
        Callback = function(v)
            Settings.ShowHealthBar = v
        end
    })

    ESPTab:CreateToggle({
        Name = "📍 Distância",
        CurrentValue = Settings.ShowDistance,
        Callback = function(v)
            Settings.ShowDistance = v
        end
    })

    ESPTab:CreateToggle({
        Name = "✨ Highlight (Chams)",
        CurrentValue = Settings.ShowHighlight,
        Callback = function(v)
            Settings.ShowHighlight = v
        end
    })

    ESPTab:CreateSection("🎯 Local Player")

    ESPTab:CreateToggle({
        Name = "🦴 Skeleton Local",
        CurrentValue = Settings.Drawing.LocalSkeleton,
        Callback = function(v)
            Settings.Drawing.LocalSkeleton = v
        end
    })

    -- ========================================================================
    -- SYSTEM TAB
    -- ========================================================================
    SystemTab:CreateSection("📊 Estatísticas")

    SystemTab:CreateParagraph({
        Title = "Sistema de Times",
        Content = function()
            local method = SemanticEngine.TeamSystem.Method or "Detectando..."
            return "Método: " .. method
        end
    })

    SystemTab:CreateParagraph({
        Title = "Performance",
        Content = function()
            local fps = string.format("%.1f", PerformanceManager.currentFPS)
            local panic = PerformanceManager.panicLevel
            return string.format("FPS: %s\nNível Panic: %d", fps, panic)
        end
    })

    SystemTab:CreateParagraph({
        Title = "Semantic Engine",
        Content = function()
            local stats = SemanticEngine.Stats
            return string.format(
                "Entidades: %d\nContainers: %d\nDano Detectado: %d",
                stats.EntitiesLearned,
                stats.ContainersFound,
                stats.DamageEventsDetected
            )
        end
    })

    SystemTab:CreateSection("🔧 Controles")

    SystemTab:CreateButton({
        Name = "🔄 Redetectar Times",
        Callback = function()
            SemanticEngine:DetectTeamSystemWithVoting()
            Notify("Sistema", "Times redetectados!")
        end,
    })

    SystemTab:CreateButton({
        Name = "🗑️ Limpar Cache ESP",
        Callback = function()
            if Core.ESP then
                Core.ESP:CleanupAll()
                Notify("Sistema", "Cache ESP limpo!")
            end
        end,
    })

    SystemTab:CreateSection("ℹ️ Informações")

    SystemTab:CreateParagraph({
        Title = "ForgeHub v23.1",
        Content = "✅ Arquitetura modular\n✅ Performance otimizada\n✅ Sistema adaptativo"
    })

    return Window
end

function UI:Initialize()
    -- Initialize visuals
    InitializeVisuals()
    
    -- Setup input handling
    SetupInputHandling()
    
    -- Start visual update loop
    RunService.RenderStepped:Connect(function()
        SafeCall(function()
            UpdateVisuals()
        end, "VisualsUpdate")
    end)
    
    -- Create UI with delay
    task.delay(0.5, function()
        SafeCall(function()
            self:CreateInterface()
        end, "UICreation")
    end)
end

-- ============================================================================
-- PLAYER EVENTS
-- ============================================================================
Players.PlayerAdded:Connect(function(player)
    Core.UpdatePlayerCache()
    SemanticEngine.TeamSystem.LastCheck = 0
end)

Players.PlayerRemoving:Connect(function(player)
    if Core.ESP then
        Core.ESP:RemovePlayerESP(player)
    end
    Core.UpdatePlayerCache()
end)

-- ============================================================================
-- EXPORT
-- ============================================================================
return UI