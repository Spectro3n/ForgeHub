-- ============================================================================
-- FORGEHUB - UI MODULE (FIXED)
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
-- SETTINGS SYNC (Garante compatibilidade com ESP module)
-- ============================================================================
local function EnsureSettingsCompat()
    -- Cria Settings.ESP se não existir
    Settings.ESP = Settings.ESP or {}
    
    -- Sincroniza settings antigos com novos
    local mappings = {
        {"ESPEnabled", "Enabled", true},
        {"ShowBox", "ShowBox", true},
        {"ShowName", "ShowName", true},
        {"ShowDistance", "ShowDistance", true},
        {"ShowHealthBar", "ShowHealthBar", true},
        {"ShowHighlight", "ShowHighlight", true},
        {"IgnoreTeamESP", "IgnoreTeam", true},
        {"ESPMaxDistance", "MaxDistance", 1000},
    }
    
    for _, map in ipairs(mappings) do
        local oldKey, newKey, default = map[1], map[2], map[3]
        if Settings[oldKey] ~= nil then
            Settings.ESP[newKey] = Settings[oldKey]
        elseif Settings.ESP[newKey] == nil then
            Settings.ESP[newKey] = default
        end
    end
    
    -- Drawing settings
    Settings.Drawing = Settings.Drawing or {}
    if Settings.Drawing.Skeleton ~= nil then
        Settings.ESP.ShowSkeleton = Settings.Drawing.Skeleton
    end
    if Settings.Drawing.LocalSkeleton ~= nil then
        Settings.ESP.ShowLocalSkeleton = Settings.Drawing.LocalSkeleton
    end
    if Settings.Drawing.SkeletonMaxDistance ~= nil then
        Settings.ESP.SkeletonMaxDistance = Settings.Drawing.SkeletonMaxDistance
    end
    
    -- Defaults
    Settings.ESP.ShowSkeleton = Settings.ESP.ShowSkeleton or false
    Settings.ESP.ShowLocalSkeleton = Settings.ESP.ShowLocalSkeleton or false
    Settings.ESP.SkeletonMaxDistance = Settings.ESP.SkeletonMaxDistance or 300
end

EnsureSettingsCompat()

-- ============================================================================
-- FOV CIRCLE & TARGET INDICATOR
-- ============================================================================
local FOVCircle = nil
local TargetIndicator = nil

local function InitializeVisuals()
    if not Core.DrawingOK then 
        warn("[UI] Drawing library not available")
        return 
    end
    
    -- FOV Circle
    FOVCircle = DrawingPool:Acquire("Circle")
    if FOVCircle then
        FOVCircle.Thickness = 1.5
        FOVCircle.NumSides = 64
        FOVCircle.Radius = Settings.FOV or 100
        FOVCircle.Filled = false
        FOVCircle.Visible = false
        FOVCircle.Color = Settings.FOVColor or Color3.fromRGB(255, 255, 255)
        FOVCircle.Transparency = 1
    end
    
    -- Target Indicator
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
    -- FOV Circle Update
    if FOVCircle then
        FOVCircle.Visible = Settings.ShowFOV or false
        FOVCircle.Radius = math.clamp(Settings.FOV or 100, 1, 5000)
        
        local success, mousePos = pcall(function()
            return UserInputService:GetMouseLocation()
        end)
        
        if success and mousePos then
            FOVCircle.Position = Vector2.new(mousePos.X, mousePos.Y)
        end
        
        FOVCircle.Color = Settings.FOVColor or Color3.fromRGB(255, 255, 255)
    end
    
    -- Target Indicator Update
    if TargetIndicator then
        local shouldShow = false
        
        if Settings.ShowTargetIndicator and Settings.AimbotActive and State.MouseHold then
            local Aimbot = Core.Aimbot
            
            if Aimbot and Aimbot.CameraBypass then
                local lockedTarget = Aimbot.CameraBypass:GetLockedTarget()
                
                if lockedTarget then
                    local data = nil
                    
                    if SemanticEngine and SemanticEngine.GetCachedPlayerData then
                        data = SemanticEngine:GetCachedPlayerData(lockedTarget)
                    end
                    
                    if data and data.isValid and data.anchor then
                        local success, result = pcall(function()
                            return Camera:WorldToViewportPoint(data.anchor.Position)
                        end)
                        
                        if success then
                            local screenPos, onScreen = result, select(2, Camera:WorldToViewportPoint(data.anchor.Position))
                            
                            if onScreen then
                                TargetIndicator.Position = Vector2.new(screenPos.X, screenPos.Y)
                                
                                -- Pulse effect
                                local pulse = math.abs(math.sin(tick() * 5))
                                TargetIndicator.Color = Color3.fromRGB(0, 255 * pulse, 0)
                                shouldShow = true
                            end
                        end
                    end
                end
            end
        end
        
        TargetIndicator.Visible = shouldShow
    end
end

-- ============================================================================
-- INPUT HANDLING
-- ============================================================================
local function SetupInputHandling()
    UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end
        
        -- Aimbot Use Key (Hold)
        if isInputMatch and isInputMatch(input, Settings.AimbotUseKey) then 
            State.MouseHold = true 
        end
        
        -- Aimbot Toggle Key
        if isInputMatch and isInputMatch(input, Settings.AimbotToggleKey) then 
            Settings.AimbotActive = not Settings.AimbotActive
            if Notify then
                Notify("Aimbot", Settings.AimbotActive and "ATIVADO ✅" or "DESATIVADO ❌")
            end
        end
    end)

    UserInputService.InputEnded:Connect(function(input, gameProcessed)
        if gameProcessed then return end
        
        if isInputMatch and isInputMatch(input, Settings.AimbotUseKey) then 
            State.MouseHold = false 
        end
    end)
end

-- ============================================================================
-- RAYFIELD UI
-- ============================================================================
local UI = {
    Window = nil,
    StatsLabels = {},
    UpdateConnection = nil,
}

-- Helper para dropdown
local function HandleDropdown(val)
    if type(val) == "table" and #val > 0 then 
        return val[1] 
    end
    return val
end

-- Obtém estatísticas de forma segura
local function GetTeamMethod()
    if SemanticEngine and SemanticEngine.TeamSystem and SemanticEngine.TeamSystem.Method then
        return SemanticEngine.TeamSystem.Method
    end
    return "Não detectado"
end

local function GetPerformanceStats()
    local fps = 60
    local panic = 0
    
    if PerformanceManager then
        fps = PerformanceManager.currentFPS or 60
        panic = PerformanceManager.panicLevel or 0
    end
    
    return fps, panic
end

local function GetSemanticStats()
    local entities = 0
    local containers = 0
    local damage = 0
    
    if SemanticEngine and SemanticEngine.Stats then
        entities = SemanticEngine.Stats.EntitiesLearned or 0
        containers = SemanticEngine.Stats.ContainersFound or 0
        damage = SemanticEngine.Stats.DamageEventsDetected or 0
    end
    
    return entities, containers, damage
end

function UI:CreateInterface()
    local success, Rayfield = pcall(function()
        return loadstring(game:HttpGet('https://sirius.menu/rayfield'))()
    end)
    
    if not success or not Rayfield then
        warn("[UI] Failed to load Rayfield library")
        return nil
    end

    local Window = Rayfield:CreateWindow({
        Name = "ForgeHub Ultimate | v23.1 MODULAR ✅",
        LoadingTitle = "Carregando Engine v23.1...",
        LoadingSubtitle = "✅ Arquitetura modular\n✅ Sistema otimizado\n✅ Performance aprimorada",
        Theme = "AmberGlow",
        ToggleUIKeybind = "K",
        ConfigurationSaving = { Enabled = false }
    })
    
    self.Window = Window

    local MainTab = Window:CreateTab("🎯 Legit Bot")
    local ESPTab = Window:CreateTab("👁️ Visuals")
    local SystemTab = Window:CreateTab("⚙️ Sistema")

    -- ========================================================================
    -- MAIN TAB - AIMBOT
    -- ========================================================================
    MainTab:CreateSection("Atalhos Principais")

    MainTab:CreateInput({
        Name = "⌨️ Tecla Aimbot Toggle",
        PlaceholderText = "Q",
        RemoveTextAfterFocusLost = false,
        Callback = function(Text)
            if NormalizeKey then
                Settings.AimbotToggleKey = NormalizeKey(Text)
            else
                Settings.AimbotToggleKey = Text:upper()
            end
        end
    })

    MainTab:CreateDropdown({
        Name = "🖱️ Botão de Mira (Segurar)",
        Options = {"MouseButton1", "MouseButton2", "MouseButton3"},
        CurrentOption = {"MouseButton2"},
        Callback = function(Option)
            local selected = HandleDropdown(Option)
            if NormalizeKey then
                Settings.AimbotUseKey = NormalizeKey(selected)
            else
                Settings.AimbotUseKey = selected
            end
        end,
    })

    MainTab:CreateSection("Configuração de Mira")

    MainTab:CreateToggle({
        Name = "🎯 Ativar Aimbot",
        CurrentValue = Settings.AimbotActive or false,
        Callback = function(v)
            Settings.AimbotActive = v
        end
    })

    MainTab:CreateDropdown({
        Name = "🎮 Método de Aim",
        Options = {"Camera", "MouseMoveRel"},
        CurrentOption = {Settings.AimMethod or "Camera"},
        Callback = function(Option)
            Settings.AimMethod = HandleDropdown(Option)
        end
    })

    MainTab:CreateDropdown({
        Name = "👀 Parte do Corpo",
        Options = {"Head", "Torso", "Root"},
        CurrentOption = {Settings.AimPart or "Head"},
        Callback = function(Option)
            Settings.AimPart = HandleDropdown(Option)
        end
    })

    MainTab:CreateSlider({
        Name = "🔧 Suavização (Legit)",
        Range = {0, 20},
        Increment = 1,
        CurrentValue = Settings.SmoothingFactor or 5,
        Callback = function(v)
            Settings.SmoothingFactor = v
        end
    })

    MainTab:CreateSlider({
        Name = "📏 Distância Máxima",
        Range = {100, 2000},
        Increment = 100,
        CurrentValue = Settings.MaxDistance or 1000,
        Callback = function(v)
            Settings.MaxDistance = v
        end
    })

    MainTab:CreateSection("FOV & Visuals")

    MainTab:CreateToggle({
        Name = "⭕ Mostrar FOV (Circle)",
        CurrentValue = Settings.ShowFOV or false,
        Callback = function(v)
            Settings.ShowFOV = v
        end
    })

    MainTab:CreateSlider({
        Name = "📐 Tamanho FOV",
        Range = {10, 1000},
        Increment = 10,
        CurrentValue = Settings.FOV or 100,
        Callback = function(v)
            Settings.FOV = v
        end
    })

    MainTab:CreateToggle({
        Name = "🎯 Indicador de Alvo",
        CurrentValue = Settings.ShowTargetIndicator or false,
        Callback = function(v)
            Settings.ShowTargetIndicator = v
        end
    })

    MainTab:CreateToggle({
        Name = "🛡️ Ignorar Meu Time",
        CurrentValue = Settings.IgnoreTeamAimbot or true,
        Callback = function(v)
            Settings.IgnoreTeamAimbot = v
        end
    })

    MainTab:CreateToggle({
        Name = "👁 Check Visibilidade",
        CurrentValue = Settings.VisibleCheck or false,
        Callback = function(v)
            Settings.VisibleCheck = v
        end
    })

    MainTab:CreateSection("Predição")

    MainTab:CreateToggle({
        Name = "🎯 Usar Predição",
        CurrentValue = Settings.UsePrediction or false,
        Callback = function(v)
            Settings.UsePrediction = v
        end
    })

    MainTab:CreateSlider({
        Name = "⚡ Multiplicador de Predição",
        Range = {0.05, 0.5},
        Increment = 0.01,
        CurrentValue = Settings.PredictionMultiplier or 0.1,
        Callback = function(v)
            Settings.PredictionMultiplier = v
        end
    })

    MainTab:CreateSection("🔥 RAGE MODE")

    MainTab:CreateToggle({  
        Name = "🔥 Rage Mode",
        CurrentValue = Settings.RageMode,
        Callback = function(v)
            if Core.Aimbot and Core.Aimbot.SetRageMode then
                Core.Aimbot.SetRageMode(v)
            else
                Settings.RageMode = v
            end
        end
    })

    MainTab:CreateToggle({  
        Name = "⚡ ULTRA RAGE MODE",
        CurrentValue = Settings.UltraRageMode,
        Callback = function(v)
            if Core.Aimbot and Core.Aimbot.SetUltraRageMode then
                Core.Aimbot.SetUltraRageMode(v)
            else
                Settings.UltraRageMode = v
            end
        end
    })

    MainTab:CreateToggle({  
            Name = "👻 Silent Aim",
            CurrentValue = Settings.SilentAim or false,
            Callback = function(v)
            Settings.SilentAim = v
        end
    })

    MainTab:CreateToggle({  
        Name = "🔫 Auto Fire",
        CurrentValue = Settings.AutoFire or false,
        Callback = function(v)
        Settings.AutoFire = v
    end
    })

    MainTab:CreateToggle({  
    Name = "🔄 Auto Switch Target",
    CurrentValue = Settings.AutoSwitch or false,
    Callback = function(v)
        Settings.AutoSwitch = v
    end
    })

    MainTab:CreateSlider({  
    Name = "⏱️ Switch Delay",
    Range = {0.05, 1},
    Increment = 0.05,
    CurrentValue = Settings.TargetSwitchDelay or 0.3,
    Callback = function(v)
        Settings.TargetSwitchDelay = v
    end
    })

    MainTab:CreateToggle({  
        Name = "🧱 Ignorar Paredes",
        CurrentValue = Settings.IgnoreWalls or false,
        Callback = function(v)
            Settings.IgnoreWalls = v
        end
    })

    MainTab:CreateToggle({
        Name = "🎯 Multi-Part Aim",
        CurrentValue = Settings.MultiPartAim or false,
        Callback = function(v)
            Settings.MultiPartAim = v
        end
    })

    MainTab:CreateSlider({
        Name = "📉 Shake Reduction",
        Range = {0, 10},
        Increment = 1,
        CurrentValue = Settings.ShakeReduction or 0,
        Callback = function(v)
            Settings.ShakeReduction = v
        end
    })

    MainTab:CreateButton({
        Name = "🔄 Reset Aimbot",
        Callback = function()
            if Core.Aimbot and Core.Aimbot.ForceReset then
                Core.Aimbot.ForceReset()
                Notify("Aimbot", "Reset completo!")
            end
        end,
    })

    MainTab:CreateButton({
        Name = "🐛 Debug Aimbot",
        Callback = function()
            if Core.Aimbot and Core.Aimbot.Debug then
                Core.Aimbot.Debug()
                Notify("Debug", "Verifique o console (F9)")
            end
        end,
    })

    -- ========================================================================
    -- ESP TAB
    -- ========================================================================
    ESPTab:CreateSection("ESP Core")

    ESPTab:CreateToggle({
        Name = "👁️ Ativar ESP",
        CurrentValue = Settings.ESP.Enabled,
        Callback = function(v)
            Settings.ESP.Enabled = v
            Settings.ESPEnabled = v -- Compat
            
            if Core.ESP and Core.ESP.Toggle then
                Core.ESP:Toggle(v)
            end
        end
    })

    ESPTab:CreateToggle({
        Name = "🤝 Ignorar Meu Time",
        CurrentValue = Settings.ESP.IgnoreTeam,
        Callback = function(v)
            Settings.ESP.IgnoreTeam = v
            Settings.IgnoreTeamESP = v -- Compat
        end
    })

    ESPTab:CreateSlider({
        Name = "📏 Distância Máxima ESP",
        Range = {100, 5000},
        Increment = 100,
        CurrentValue = Settings.ESP.MaxDistance,
        Callback = function(v)
            Settings.ESP.MaxDistance = v
            Settings.ESPMaxDistance = v -- Compat
        end
    })

    ESPTab:CreateSection("Elementos Visuais")

    ESPTab:CreateToggle({
        Name = "📦 Caixa (Box)",
        CurrentValue = Settings.ESP.ShowBox,
        Callback = function(v)
            Settings.ESP.ShowBox = v
            Settings.ShowBox = v -- Compat
        end
    })

    ESPTab:CreateToggle({
        Name = "📛 Nomes",
        CurrentValue = Settings.ESP.ShowName,
        Callback = function(v)
            Settings.ESP.ShowName = v
            Settings.ShowName = v -- Compat
        end
    })

    ESPTab:CreateToggle({
        Name = "📍 Distância",
        CurrentValue = Settings.ESP.ShowDistance,
        Callback = function(v)
            Settings.ESP.ShowDistance = v
            Settings.ShowDistance = v -- Compat
        end
    })

    ESPTab:CreateToggle({
        Name = "💚 Barra de Vida",
        CurrentValue = Settings.ESP.ShowHealthBar,
        Callback = function(v)
            Settings.ESP.ShowHealthBar = v
            Settings.ShowHealthBar = v -- Compat
        end
    })

    ESPTab:CreateToggle({
        Name = "✨ Highlight (Chams)",
        CurrentValue = Settings.ESP.ShowHighlight,
        Callback = function(v)
            Settings.ESP.ShowHighlight = v
            Settings.ShowHighlight = v -- Compat
        end
    })

    ESPTab:CreateSlider({
        Name = "📏 Distância Máx Highlight",
        Range = {100, 1000},
        Increment = 50,
        CurrentValue = Settings.ESP.HighlightMaxDistance or 500,
        Callback = function(v)
            Settings.ESP.HighlightMaxDistance = v
        end
    })

    ESPTab:CreateSection("Skeleton")

    ESPTab:CreateToggle({
        Name = "🦴 Skeleton (Esqueleto)",
        CurrentValue = Settings.ESP.ShowSkeleton,
        Callback = function(v)
            Settings.ESP.ShowSkeleton = v
            Settings.Drawing = Settings.Drawing or {}
            Settings.Drawing.Skeleton = v -- Compat
        end
    })

    ESPTab:CreateSlider({
        Name = "📏 Distância Máx Skeleton",
        Range = {50, 500},
        Increment = 25,
        CurrentValue = Settings.ESP.SkeletonMaxDistance,
        Callback = function(v)
            Settings.ESP.SkeletonMaxDistance = v
            Settings.Drawing = Settings.Drawing or {}
            Settings.Drawing.SkeletonMaxDistance = v -- Compat
        end
    })

    ESPTab:CreateSection("🎯 Local Player")

    ESPTab:CreateToggle({
        Name = "🦴 Skeleton Local",
        CurrentValue = Settings.ESP.ShowLocalSkeleton,
        Callback = function(v)
            Settings.ESP.ShowLocalSkeleton = v
            Settings.Drawing = Settings.Drawing or {}
            Settings.Drawing.LocalSkeleton = v -- Compat
        end
    })

    -- ========================================================================
    -- SYSTEM TAB (FIXED!)
    -- ========================================================================
    SystemTab:CreateSection("📊 Estatísticas")

    -- IMPORTANTE: Rayfield CreateParagraph NÃO aceita função como Content!
    -- Precisamos criar com strings estáticas e atualizar via :Set()
    
    local teamParagraph = SystemTab:CreateParagraph({
        Title = "🎮 Sistema de Times",
        Content = "Método: " .. GetTeamMethod()
    })
    self.StatsLabels.TeamParagraph = teamParagraph

    local fps, panic = GetPerformanceStats()
    local perfParagraph = SystemTab:CreateParagraph({
        Title = "⚡ Performance",
        Content = string.format("FPS: %.1f | Panic Level: %d", fps, panic)
    })
    self.StatsLabels.PerfParagraph = perfParagraph

    local entities, containers, damage = GetSemanticStats()
    local semanticParagraph = SystemTab:CreateParagraph({
        Title = "🧠 Semantic Engine",
        Content = string.format(
            "Entidades: %d\nContainers: %d\nDano Detectado: %d",
            entities, containers, damage
        )
    })
    self.StatsLabels.SemanticParagraph = semanticParagraph

    -- ESP Stats
    local espParagraph = SystemTab:CreateParagraph({
        Title = "👁️ ESP Status",
        Content = "Carregando..."
    })
    self.StatsLabels.ESPParagraph = espParagraph

    SystemTab:CreateSection("🔧 Controles")

    SystemTab:CreateButton({
        Name = "🔄 Redetectar Times",
        Callback = function()
            if SemanticEngine and SemanticEngine.DetectTeamSystemWithVoting then
                SemanticEngine:DetectTeamSystemWithVoting()
                if Notify then
                    Notify("Sistema", "Times redetectados: " .. GetTeamMethod())
                end
                self:UpdateStats()
            else
                if Notify then
                    Notify("Erro", "SemanticEngine não disponível")
                end
            end
        end,
    })

    SystemTab:CreateButton({
        Name = "🗑️ Limpar Cache ESP",
        Callback = function()
            if Core.ESP and Core.ESP.CleanupAll then
                Core.ESP:CleanupAll()
                if Notify then
                    Notify("Sistema", "Cache ESP limpo!")
                end
            else
                if Notify then
                    Notify("Erro", "ESP module não disponível")
                end
            end
        end,
    })

    SystemTab:CreateButton({
        Name = "🔄 Recriar ESP para Jogadores",
        Callback = function()
            if Core.ESP then
                for _, player in ipairs(Players:GetPlayers()) do
                    if player ~= LocalPlayer then
                        if Core.ESP.RemovePlayerESP then
                            Core.ESP:RemovePlayerESP(player)
                        end
                        if Core.ESP.CreatePlayerESP then
                            Core.ESP:CreatePlayerESP(player)
                        end
                    end
                end
                if Notify then
                    Notify("Sistema", "ESP recriado para todos os jogadores!")
                end
            end
        end,
    })

    SystemTab:CreateButton({
        Name = "🐛 Debug ESP",
        Callback = function()
            if Core.ESP and Core.ESP.Debug then
                Core.ESP:Debug()
                if Notify then
                    Notify("Debug", "Verifique o console (F9)")
                end
            end
        end,
    })

    SystemTab:CreateSection("ℹ️ Informações")

    SystemTab:CreateParagraph({
        Title = "ForgeHub v23.1 MODULAR",
        Content = "✅ Arquitetura modular\n✅ Performance otimizada\n✅ Sistema adaptativo\n✅ ESP corrigido"
    })

    -- Inicia loop de atualização de stats
    self:StartStatsUpdateLoop()

    return Window
end

-- Atualiza as estatísticas na UI
function UI:UpdateStats()
    if not self.StatsLabels then return end
    
    SafeCall(function()
        -- Team Method
        if self.StatsLabels.TeamParagraph and self.StatsLabels.TeamParagraph.Set then
            self.StatsLabels.TeamParagraph:Set({
                Title = "🎮 Sistema de Times",
                Content = "Método: " .. GetTeamMethod()
            })
        end
        
        -- Performance
        if self.StatsLabels.PerfParagraph and self.StatsLabels.PerfParagraph.Set then
            local fps, panic = GetPerformanceStats()
            self.StatsLabels.PerfParagraph:Set({
                Title = "⚡ Performance",
                Content = string.format("FPS: %.1f | Panic Level: %d", fps, panic)
            })
        end
        
        -- Semantic Engine
        if self.StatsLabels.SemanticParagraph and self.StatsLabels.SemanticParagraph.Set then
            local entities, containers, damage = GetSemanticStats()
            self.StatsLabels.SemanticParagraph:Set({
                Title = "🧠 Semantic Engine",
                Content = string.format(
                    "Entidades: %d\nContainers: %d\nDano Detectado: %d",
                    entities, containers, damage
                )
            })
        end
        
        -- ESP Status
        if self.StatsLabels.ESPParagraph and self.StatsLabels.ESPParagraph.Set then
            local espCount = 0
            if State.DrawingESP then
                for _ in pairs(State.DrawingESP) do
                    espCount = espCount + 1
                end
            end
            
            local espEnabled = Settings.ESP.Enabled and "✅" or "❌"
            local boxEnabled = Settings.ESP.ShowBox and "✅" or "❌"
            local skelEnabled = Settings.ESP.ShowSkeleton and "✅" or "❌"
            local hlEnabled = Settings.ESP.ShowHighlight and "✅" or "❌"
            
            self.StatsLabels.ESPParagraph:Set({
                Title = "👁️ ESP Status",
                Content = string.format(
                    "ESP: %s | Players: %d\nBox: %s | Skeleton: %s | Highlight: %s",
                    espEnabled, espCount,
                    boxEnabled, skelEnabled, hlEnabled
                )
            })
        end
    end, "StatsUpdate")
end

-- Loop de atualização de estatísticas
function UI:StartStatsUpdateLoop()
    if self.UpdateConnection then
        self.UpdateConnection:Disconnect()
    end
    
    -- Atualiza a cada 2 segundos
    task.spawn(function()
        while true do
            wait(2)
            self:UpdateStats()
        end
    end)
end

function UI:Initialize()
    -- Garante compatibilidade de settings
    EnsureSettingsCompat()
    
    -- Initialize visuals (FOV circle, target indicator)
    InitializeVisuals()
    
    -- Setup input handling
    SetupInputHandling()
    
    -- Start visual update loop
    RunService.RenderStepped:Connect(function()
        SafeCall(function()
            UpdateVisuals()
        end, "VisualsUpdate")
    end)
    
    -- Create UI with delay para garantir que outros módulos carregaram
    task.delay(1, function()
        SafeCall(function()
            self:CreateInterface()
            print("[UI] Interface criada com sucesso!")
        end, "UICreation")
    end)
end

-- ============================================================================
-- PLAYER EVENTS
-- ============================================================================
Players.PlayerAdded:Connect(function(player)
    SafeCall(function()
        if Core.UpdatePlayerCache then
            Core.UpdatePlayerCache()
        end
        
        if SemanticEngine and SemanticEngine.TeamSystem then
            SemanticEngine.TeamSystem.LastCheck = 0
        end
        
        -- Auto-create ESP for new player
        task.delay(1, function()
            if Core.ESP and Core.ESP.CreatePlayerESP then
                Core.ESP:CreatePlayerESP(player)
            end
        end)
    end, "PlayerAdded")
end)

Players.PlayerRemoving:Connect(function(player)
    SafeCall(function()
        if Core.ESP and Core.ESP.RemovePlayerESP then
            Core.ESP:RemovePlayerESP(player)
        end
        
        if Core.UpdatePlayerCache then
            Core.UpdatePlayerCache()
        end
    end, "PlayerRemoving")
end)

-- ============================================================================
-- EXPORT
-- ============================================================================
Core.UI = UI

return UI