-- ============================================================================
-- FORGEHUB - UI MODULE v4.0 (ULTRA RAGE EDITION)
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
local Aimbot = Core.Aimbot

local RunService = Core.RunService
local UserInputService = Core.UserInputService
local Camera = Core.Camera
local LocalPlayer = Core.LocalPlayer
local Players = Core.Players

-- ============================================================================
-- SETTINGS SYNC
-- ============================================================================
local function EnsureSettingsCompat()
    Settings.ESP = Settings.ESP or {}
    
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
    
    Settings.Drawing = Settings.Drawing or {}
    Settings.ESP.ShowSkeleton = Settings.ESP.ShowSkeleton or false
    Settings.ESP.ShowLocalSkeleton = Settings.ESP.ShowLocalSkeleton or false
    Settings.ESP.SkeletonMaxDistance = Settings.ESP.SkeletonMaxDistance or 300
    
    -- Rage settings defaults
    Settings.RageMode = Settings.RageMode or false
    Settings.UltraRageMode = Settings.UltraRageMode or false
    Settings.GodRageMode = Settings.GodRageMode or false
    
    -- Silent Aim defaults
    Settings.SilentAim = Settings.SilentAim or false
    Settings.SilentFOV = Settings.SilentFOV or 500
    Settings.SilentHitChance = Settings.SilentHitChance or 100
    Settings.SilentHeadshotChance = Settings.SilentHeadshotChance or 100
    
    -- Magic Bullet defaults
    Settings.MagicBullet = Settings.MagicBullet or false
    Settings.MagicBulletMethod = Settings.MagicBulletMethod or "Teleport"
    Settings.MagicBulletAutoHit = Settings.MagicBulletAutoHit or true
    
    -- Trigger Bot defaults
    Settings.TriggerBot = Settings.TriggerBot or false
    Settings.TriggerFOV = Settings.TriggerFOV or 50
    Settings.TriggerDelay = Settings.TriggerDelay or 0.05
    Settings.TriggerBurst = Settings.TriggerBurst or false
    Settings.TriggerBurstCount = Settings.TriggerBurstCount or 3
    Settings.TriggerHeadOnly = Settings.TriggerHeadOnly or false
    
    -- Aimbot FOV
    Settings.AimbotFOV = Settings.AimbotFOV or 180
end

EnsureSettingsCompat()

-- ============================================================================
-- FOV CIRCLES (Aimbot, Silent, Trigger)
-- ============================================================================
local FOVCircle = nil
local SilentFOVCircle = nil
local TriggerFOVCircle = nil
local TargetIndicator = nil

local function InitializeVisuals()
    if not Core.DrawingOK then 
        warn("[UI] Drawing library not available")
        return 
    end
    
    -- Aimbot FOV Circle
    FOVCircle = DrawingPool:Acquire("Circle")
    if FOVCircle then
        FOVCircle.Thickness = 1.5
        FOVCircle.NumSides = 64
        FOVCircle.Radius = Settings.AimbotFOV or 180
        FOVCircle.Filled = false
        FOVCircle.Visible = false
        FOVCircle.Color = Settings.FOVColor or Color3.fromRGB(255, 255, 255)
        FOVCircle.Transparency = 1
    end
    
    -- Silent Aim FOV Circle
    SilentFOVCircle = DrawingPool:Acquire("Circle")
    if SilentFOVCircle then
        SilentFOVCircle.Thickness = 1.5
        SilentFOVCircle.NumSides = 48
        SilentFOVCircle.Radius = Settings.SilentFOV or 500
        SilentFOVCircle.Filled = false
        SilentFOVCircle.Visible = false
        SilentFOVCircle.Color = Color3.fromRGB(255, 0, 255) -- Roxo para Silent
        SilentFOVCircle.Transparency = 1
    end
    
    -- Trigger Bot FOV Circle
    TriggerFOVCircle = DrawingPool:Acquire("Circle")
    if TriggerFOVCircle then
        TriggerFOVCircle.Thickness = 2
        TriggerFOVCircle.NumSides = 32
        TriggerFOVCircle.Radius = Settings.TriggerFOV or 50
        TriggerFOVCircle.Filled = false
        TriggerFOVCircle.Visible = false
        TriggerFOVCircle.Color = Color3.fromRGB(255, 255, 0) -- Amarelo para Trigger
        TriggerFOVCircle.Transparency = 1
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
    local success, mousePos = pcall(function()
        return UserInputService:GetMouseLocation()
    end)
    
    if not success or not mousePos then return end
    
    local mouseVec = Vector2.new(mousePos.X, mousePos.Y)
    
    -- Aimbot FOV Circle
    if FOVCircle then
        FOVCircle.Visible = Settings.ShowFOV or false
        FOVCircle.Radius = math.clamp(Settings.AimbotFOV or 180, 1, 5000)
        FOVCircle.Position = mouseVec
        FOVCircle.Color = Settings.FOVColor or Color3.fromRGB(255, 255, 255)
    end
    
    -- Silent FOV Circle
    if SilentFOVCircle then
        local showSilentFOV = Settings.SilentAim and (Settings.ShowSilentFOV or false)
        SilentFOVCircle.Visible = showSilentFOV
        SilentFOVCircle.Radius = math.clamp(Settings.SilentFOV or 500, 1, 5000)
        SilentFOVCircle.Position = mouseVec
    end
    
    -- Trigger FOV Circle
    if TriggerFOVCircle then
        local showTriggerFOV = Settings.TriggerBot and (Settings.ShowTriggerFOV or false)
        TriggerFOVCircle.Visible = showTriggerFOV
        TriggerFOVCircle.Radius = math.clamp(Settings.TriggerFOV or 50, 1, 1000)
        TriggerFOVCircle.Position = mouseVec
    end
    
    -- Target Indicator
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
                        local success2, result = pcall(function()
                            return Camera:WorldToViewportPoint(data.anchor.Position)
                        end)
                        
                        if success2 then
                            local screenPos, onScreen = result, select(2, Camera:WorldToViewportPoint(data.anchor.Position))
                            
                            if onScreen then
                                TargetIndicator.Position = Vector2.new(screenPos.X, screenPos.Y)
                                
                                -- Pulse effect baseado no modo
                                local pulse = math.abs(math.sin(tick() * 5))
                                
                                if Settings.GodRageMode then
                                    TargetIndicator.Color = Color3.fromRGB(255, 215 * pulse, 0) -- Gold
                                    TargetIndicator.Radius = 15
                                elseif Settings.UltraRageMode then
                                    TargetIndicator.Color = Color3.fromRGB(255, 0, 255 * pulse) -- Magenta
                                    TargetIndicator.Radius = 12
                                elseif Settings.RageMode then
                                    TargetIndicator.Color = Color3.fromRGB(255, 100 * pulse, 0) -- Orange
                                    TargetIndicator.Radius = 10
                                else
                                    TargetIndicator.Color = Color3.fromRGB(0, 255 * pulse, 0) -- Green
                                    TargetIndicator.Radius = 8
                                end
                                
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
        
        if isInputMatch and isInputMatch(input, Settings.AimbotUseKey) then 
            State.MouseHold = true 
        end
        
        if isInputMatch and isInputMatch(input, Settings.AimbotToggleKey) then 
            Settings.AimbotActive = not Settings.AimbotActive
            if Notify then
                local status = Settings.AimbotActive and "ATIVADO ✅" or "DESATIVADO ❌"
                if Settings.GodRageMode then
                    status = status .. " 👑 GOD MODE"
                elseif Settings.UltraRageMode then
                    status = status .. " ⚡ ULTRA"
                elseif Settings.RageMode then
                    status = status .. " 🔥 RAGE"
                end
                Notify("Aimbot", status)
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
-- UI
-- ============================================================================
local UI = {
    Window = nil,
    StatsLabels = {},
    UpdateConnection = nil,
}

local function HandleDropdown(val)
    if type(val) == "table" and #val > 0 then 
        return val[1] 
    end
    return val
end

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
        Name = "ForgeHub Ultimate | v4.0 ULTRA RAGE 🔥",
        LoadingTitle = "Carregando ForgeHub v4.0...",
        LoadingSubtitle = "🔥 RAGE MODE\n⚡ ULTRA RAGE\n👑 GOD MODE\n✨ MAGIC BULLET",
        Theme = "AmberGlow",
        ToggleUIKeybind = "K",
        ConfigurationSaving = { Enabled = false }
    })
    
    self.Window = Window

    local MainTab = Window:CreateTab("🎯 Legit Bot")
    local RageTab = Window:CreateTab("🔥 RAGE")
    local ESPTab = Window:CreateTab("👁️ Visuals")
    local SystemTab = Window:CreateTab("⚙️ Sistema")

    -- ========================================================================
    -- MAIN TAB - AIMBOT LEGIT
    -- ========================================================================
    MainTab:CreateSection("⌨️ Atalhos Principais")

    MainTab:CreateInput({
        Name = "Tecla Aimbot Toggle",
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

    MainTab:CreateSection("🎯 Configuração Legit")

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
        Range = {100, 3000},
        Increment = 100,
        CurrentValue = Settings.MaxDistance or 1000,
        Callback = function(v)
            Settings.MaxDistance = v
        end
    })

    MainTab:CreateSection("⭕ FOV & Visuals")

    MainTab:CreateToggle({
        Name = "⭕ Mostrar FOV Circle",
        CurrentValue = Settings.ShowFOV or false,
        Callback = function(v)
            Settings.ShowFOV = v
        end
    })

    MainTab:CreateSlider({
        Name = "📐 Tamanho FOV Aimbot",
        Range = {10, 1000},
        Increment = 10,
        CurrentValue = Settings.AimbotFOV or 180,
        Callback = function(v)
            Settings.AimbotFOV = v
            Settings.FOV = v
            if Core.Aimbot and Core.Aimbot.SetAimbotFOV then
                Core.Aimbot.SetAimbotFOV(v)
            end
        end
    })

    MainTab:CreateToggle({
        Name = "🎯 Indicador de Alvo",
        CurrentValue = Settings.ShowTargetIndicator or false,
        Callback = function(v)
            Settings.ShowTargetIndicator = v
        end
    })

    MainTab:CreateSection("🛡️ Filtros")

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

    MainTab:CreateSection("🚀 Predição")

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
    

    -- ========================================================================
    -- RAGE TAB - TODAS AS OPÇÕES RAGE
    -- ========================================================================
    RageTab:CreateSection("🔥 MODOS RAGE")

    RageTab:CreateParagraph({
        Title = "⚠️ AVISO",
        Content = "Modos RAGE são muito óbvios!\nUse com cuidado para evitar ban."
    })

    RageTab:CreateToggle({
        Name = "🔥 Rage Mode",
        CurrentValue = Settings.RageMode or false,
        Callback = function(v)
            if Core.Aimbot and Core.Aimbot.SetRageMode then
                Core.Aimbot.SetRageMode(v)
            else
                Settings.RageMode = v
            end
        end
    })

    RageTab:CreateToggle({
        Name = "⚡ ULTRA RAGE MODE",
        CurrentValue = Settings.UltraRageMode or false,
        Callback = function(v)
            if Core.Aimbot and Core.Aimbot.SetUltraRageMode then
                Core.Aimbot.SetUltraRageMode(v)
            else
                Settings.UltraRageMode = v
            end
        end
    })

    RageTab:CreateToggle({
        Name = "👑 GOD RAGE MODE (MÁXIMO)",
        CurrentValue = Settings.GodRageMode or false,
        Callback = function(v)
            if Core.Aimbot and Core.Aimbot.SetGodRageMode then
                Core.Aimbot.SetGodRageMode(v)
            else
                Settings.GodRageMode = v
                if v then
                    Settings.RageMode = true
                    Settings.UltraRageMode = true
                    Settings.IgnoreWalls = true
                    Settings.SilentAim = true
                    Settings.MagicBullet = true
                end
            end
            
            if v and Notify then
                Notify("👑 GOD MODE", "TODOS OS PODERES ATIVADOS!")
            end
        end
    })

    RageTab:CreateSection("🎯 TARGET MODE")

    RageTab:CreateDropdown({
        Name = "🎯 Modo de Seleção de Alvo",
        Options = {"FOV", "Closest"},
        CurrentOption = {Settings.TargetMode or "FOV"},
        Callback = function(Option)
            local mode = HandleDropdown(Option)
            Settings.TargetMode = mode
            if Core.Aimbot and Core.Aimbot.SetTargetMode then
                Core.Aimbot.SetTargetMode(mode)
            end
        end
    })

    RageTab:CreateParagraph({
        Title = "ℹ️ Modos de Target",
        Content = "FOV: Mira no alvo mais próximo do mouse\nClosest: Mira no alvo mais próximo (distância)"
    })

    RageTab:CreateToggle({
        Name = "🌍 Mirar Fora do FOV",
        CurrentValue = Settings.AimOutsideFOV or false,
        Callback = function(v)
            Settings.AimOutsideFOV = v
            if Core.Aimbot and Core.Aimbot.SetAimOutsideFOV then
                Core.Aimbot.SetAimOutsideFOV(v)
            end
        end
    })

    RageTab:CreateToggle({
        Name = "🔄 Auto Reset ao Matar",
        CurrentValue = Settings.AutoResetOnKill or true,
        Callback = function(v)
            Settings.AutoResetOnKill = v
        end
    })

    RageTab:CreateSection("⚡ TRIGGER BOT")

    RageTab:CreateToggle({
        Name = "⚡ Ativar Trigger Bot",
        CurrentValue = Settings.TriggerBot or false,
        Callback = function(v)
            Settings.TriggerBot = v
            if Core.Aimbot and Core.Aimbot.SetTriggerBot then
                Core.Aimbot.SetTriggerBot(v)
            end
        end
    })

    RageTab:CreateToggle({
        Name = "⭕ Mostrar Trigger FOV",
        CurrentValue = Settings.ShowTriggerFOV or false,
        Callback = function(v)
            Settings.ShowTriggerFOV = v
        end
    })

    RageTab:CreateSlider({
        Name = "📐 Trigger FOV",
        Range = {5, 500},
        Increment = 5,
        CurrentValue = Settings.TriggerFOV or 50,
        Callback = function(v)
            Settings.TriggerFOV = v
            if Core.Aimbot and Core.Aimbot.SetTriggerFOV then
                Core.Aimbot.SetTriggerFOV(v)
            end
        end
    })

    RageTab:CreateSlider({
        Name = "⏱️ Trigger Delay (seg)",
        Range = {0.01, 0.5},
        Increment = 0.01,
        CurrentValue = Settings.TriggerDelay or 0.05,
        Callback = function(v)
            Settings.TriggerDelay = v
        end
    })

    RageTab:CreateToggle({
        Name = "💨 Modo Burst",
        CurrentValue = Settings.TriggerBurst or false,
        Callback = function(v)
            Settings.TriggerBurst = v
        end
    })

    RageTab:CreateSlider({
        Name = "🔫 Tiros por Burst",
        Range = {2, 10},
        Increment = 1,
        CurrentValue = Settings.TriggerBurstCount or 3,
        Callback = function(v)
            Settings.TriggerBurstCount = v
        end
    })

    RageTab:CreateToggle({
        Name = "🎯 Apenas Cabeça",
        CurrentValue = Settings.TriggerHeadOnly or false,
        Callback = function(v)
            Settings.TriggerHeadOnly = v
        end
    })

    RageTab:CreateSection("🔫 AUTO FIRE & SWITCH")

    RageTab:CreateToggle({
        Name = "🔫 Auto Fire",
        CurrentValue = Settings.AutoFire or false,
        Callback = function(v)
            Settings.AutoFire = v
        end
    })

    RageTab:CreateToggle({
        Name = "🔄 Auto Switch Target",
        CurrentValue = Settings.AutoSwitch or false,
        Callback = function(v)
            Settings.AutoSwitch = v
        end
    })

    RageTab:CreateSlider({
        Name = "⏱️ Switch Delay",
        Range = {0.01, 1},
        Increment = 0.01,
        CurrentValue = Settings.TargetSwitchDelay or 0.1,
        Callback = function(v)
            Settings.TargetSwitchDelay = v
        end
    })

    RageTab:CreateSection("🎯 CONFIGURAÇÕES EXTRA")

    RageTab:CreateToggle({
        Name = "🎯 Multi-Part Aim",
        CurrentValue = Settings.MultiPartAim or false,
        Callback = function(v)
            Settings.MultiPartAim = v
        end
    })

    RageTab:CreateSlider({
        Name = "📉 Shake Reduction",
        Range = {0, 10},
        Increment = 1,
        CurrentValue = Settings.ShakeReduction or 0,
        Callback = function(v)
            Settings.ShakeReduction = v
        end
    })

    RageTab:CreateSection("🔧 CONTROLES")

    RageTab:CreateButton({
        Name = "🔄 Reset Aimbot",
        Callback = function()
            if Core.Aimbot and Core.Aimbot.ForceReset then
                Core.Aimbot.ForceReset()
                Notify("Aimbot", "Reset completo!")
            end
        end,
    })
    
    RageTab:CreateToggle({
        Name = "🚀 Ativar TP Bullet",
        CurrentValue = Settings.TPBullet or false,
        Callback = function(v)
            Settings.TPBullet = v
            if Core.Aimbot and Core.Aimbot.SetTPBullet then
                Core.Aimbot.SetTPBullet(v)
            end
        end
    })

    RageTab:CreateDropdown({
        Name = "📍 Posição do TP",
        Options = {"Behind", "Above", "Side", "Front", "Custom"},
        CurrentOption = {Settings.TPBulletPosition or "Behind"},
        Callback = function(Option)
            local selected = HandleDropdown(Option)
            Settings.TPBulletPosition = selected
            if Core.Aimbot and Core.Aimbot.SetTPBulletPosition then
                Core.Aimbot.SetTPBulletPosition(selected)
            end
        end
    })

    RageTab:CreateSlider({
        Name = "📏 Distância do Alvo",
        Range = {1, 30},
        Increment = 1,
        CurrentValue = Settings.TPBulletDistance or 5,
        Callback = function(v)
            Settings.TPBulletDistance = v
            if Core.Aimbot and Core.Aimbot.SetTPBulletDistance then
                Core.Aimbot.SetTPBulletDistance(v)
            end
        end
    })

    RageTab:CreateSlider({
        Name = "📐 Altura",
        Range = {-10, 15},
        Increment = 1,
        CurrentValue = Settings.TPBulletHeight or 0,
        Callback = function(v)
            Settings.TPBulletHeight = v
            if Core.Aimbot and Core.Aimbot.SetTPBulletHeight then
                Core.Aimbot.SetTPBulletHeight(v)
            end
        end
    })

    RageTab:CreateSection("⚙️ Configurações")

    RageTab:CreateToggle({
        Name = "↩️ Retornar Após Tiro",
        CurrentValue = Settings.TPBulletReturn or true,
        Callback = function(v)
            Settings.TPBulletReturn = v
            if Core.Aimbot and Core.Aimbot.SetTPBulletReturn then
                Core.Aimbot.SetTPBulletReturn(v)
            end
        end
    })

    RageTab:CreateSlider({
        Name = "⏱️ Delay de Retorno",
        Range = {0, 0.5},
        Increment = 0.05,
        CurrentValue = Settings.TPBulletReturnDelay or 0.1,
        Callback = function(v)
            Settings.TPBulletReturnDelay = v
        end
    })

    RageTab:CreateButton({
        Name = "↩️ Forçar Retorno",
        Callback = function()
            if Core.Aimbot and Core.Aimbot.ForceTPReturn then
                Core.Aimbot.ForceTPReturn()
                Notify("TP Bullet", "Retornado à posição original")
            end
        end
    })

    RageTab:CreateSection("⚠️ Segurança")

    RageTab:CreateToggle({
        Name = "🛡️ Verificação de Segurança",
        CurrentValue = true,
        Callback = function(v)
            Settings.TPBulletSafety = v
        end
    })

    RageTab:CreateSlider({
     Name = "📏 Distância Máxima de TP",
        Range = {50, 1000},
        Increment = 50,
        CurrentValue = 500,
        Callback = function(v)
            Settings.TPBulletMaxDistance = v
        end
    })

    RageTab:CreateButton({
        Name = "💀 ATIVAR TUDO (FULL RAGE)",
        Callback = function()
            -- Ativa tudo
            Settings.RageMode = true
            Settings.UltraRageMode = true
            Settings.GodRageMode = true
            Settings.SilentAim = true
            Settings.MagicBullet = true
            Settings.TriggerBot = true
            Settings.AutoFire = true
            Settings.AutoSwitch = true
            Settings.IgnoreWalls = true
            Settings.MultiPartAim = true
            
            if Core.Aimbot then
                if Core.Aimbot.SetGodRageMode then
                    Core.Aimbot.SetGodRageMode(true)
                end
                if Core.Aimbot.SetSilentAim then
                    Core.Aimbot.SetSilentAim(true)
                end
                if Core.Aimbot.SetMagicBullet then
                    Core.Aimbot.SetMagicBullet(true)
                end
                if Core.Aimbot.SetTriggerBot then
                    Core.Aimbot.SetTriggerBot(true)
                end
            end
            
            Notify("💀 FULL RAGE", "TUDO ATIVADO! BOA SORTE!")
        end,
    })

    RageTab:CreateButton({
        Name = "🛑 DESATIVAR TUDO",
        Callback = function()
            Settings.RageMode = false
            Settings.UltraRageMode = false
            Settings.GodRageMode = false
            Settings.SilentAim = false
            Settings.MagicBullet = false
            Settings.TriggerBot = false
            Settings.AutoFire = false
            Settings.AutoSwitch = false
            Settings.IgnoreWalls = false
            
            if Core.Aimbot then
                if Core.Aimbot.SetGodRageMode then
                    Core.Aimbot.SetGodRageMode(false)
                end
                if Core.Aimbot.SetSilentAim then
                    Core.Aimbot.SetSilentAim(false)
                end
                if Core.Aimbot.SetMagicBullet then
                    Core.Aimbot.SetMagicBullet(false)
                end
                if Core.Aimbot.SetTriggerBot then
                    Core.Aimbot.SetTriggerBot(false)
                end
            end
            
            Notify("🛑 RAGE OFF", "Todos os modos rage desativados")
        end,
    })

    -- ========================================================================
    -- ESP TAB
    -- ========================================================================
    ESPTab:CreateSection("👁️ ESP Core")

    ESPTab:CreateToggle({
        Name = "👁️ Ativar ESP",
        CurrentValue = Settings.ESP.Enabled,
        Callback = function(v)
            Settings.ESP.Enabled = v
            Settings.ESPEnabled = v
            
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
            Settings.IgnoreTeamESP = v
        end
    })

    ESPTab:CreateSlider({
        Name = "📏 Distância Máxima ESP",
        Range = {100, 5000},
        Increment = 100,
        CurrentValue = Settings.ESP.MaxDistance,
        Callback = function(v)
            Settings.ESP.MaxDistance = v
            Settings.ESPMaxDistance = v
        end
    })

    ESPTab:CreateSection("📦 Elementos Visuais")

    ESPTab:CreateToggle({
        Name = "📦 Caixa (Box)",
        CurrentValue = Settings.ESP.ShowBox,
        Callback = function(v)
            Settings.ESP.ShowBox = v
            Settings.ShowBox = v
        end
    })

    ESPTab:CreateToggle({
        Name = "📛 Nomes",
        CurrentValue = Settings.ESP.ShowName,
        Callback = function(v)
            Settings.ESP.ShowName = v
            Settings.ShowName = v
        end
    })

    ESPTab:CreateToggle({
        Name = "📍 Distância",
        CurrentValue = Settings.ESP.ShowDistance,
        Callback = function(v)
            Settings.ESP.ShowDistance = v
            Settings.ShowDistance = v
        end
    })

    ESPTab:CreateToggle({
        Name = "💚 Barra de Vida",
        CurrentValue = Settings.ESP.ShowHealthBar,
        Callback = function(v)
            Settings.ESP.ShowHealthBar = v
            Settings.ShowHealthBar = v
        end
    })

    ESPTab:CreateToggle({
        Name = "✨ Highlight (Chams)",
        CurrentValue = Settings.ESP.ShowHighlight,
        Callback = function(v)
            Settings.ESP.ShowHighlight = v
            Settings.ShowHighlight = v
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

    ESPTab:CreateSection("🦴 Skeleton")

    ESPTab:CreateToggle({
        Name = "🦴 Skeleton (Esqueleto)",
        CurrentValue = Settings.ESP.ShowSkeleton,
        Callback = function(v)
            Settings.ESP.ShowSkeleton = v
            Settings.Drawing = Settings.Drawing or {}
            Settings.Drawing.Skeleton = v
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
            Settings.Drawing.SkeletonMaxDistance = v
        end
    })

    ESPTab:CreateSection("🎯 Local Player")

    ESPTab:CreateToggle({
        Name = "🦴 Skeleton Local",
        CurrentValue = Settings.ESP.ShowLocalSkeleton,
        Callback = function(v)
            Settings.ESP.ShowLocalSkeleton = v
            Settings.Drawing = Settings.Drawing or {}
            Settings.Drawing.LocalSkeleton = v
        end
    })

    -- ========================================================================
    -- SYSTEM TAB
    -- ========================================================================
    SystemTab:CreateSection("📊 Estatísticas")

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

    local espParagraph = SystemTab:CreateParagraph({
        Title = "👁️ ESP Status",
        Content = "Carregando..."
    })
    self.StatsLabels.ESPParagraph = espParagraph

    -- Rage Status
    local rageParagraph = SystemTab:CreateParagraph({
        Title = "🔥 Rage Status",
        Content = "Carregando..."
    })
    self.StatsLabels.RageParagraph = rageParagraph

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
        Title = "ForgeHub v4.0 ULTRA RAGE",
        Content = "🔥 Rage Mode\n⚡ Ultra Rage Mode\n👑 God Rage Mode\n👻 Silent Aim com FOV\n✨ Magic Bullet\n⚡ Trigger Bot com FOV"
    })

    self:StartStatsUpdateLoop()

    return Window
end

function UI:UpdateStats()
    if not self.StatsLabels then return end
    
    SafeCall(function()
        if self.StatsLabels.TeamParagraph and self.StatsLabels.TeamParagraph.Set then
            self.StatsLabels.TeamParagraph:Set({
                Title = "🎮 Sistema de Times",
                Content = "Método: " .. GetTeamMethod()
            })
        end
        
        if self.StatsLabels.PerfParagraph and self.StatsLabels.PerfParagraph.Set then
            local fps, panic = GetPerformanceStats()
            self.StatsLabels.PerfParagraph:Set({
                Title = "⚡ Performance",
                Content = string.format("FPS: %.1f | Panic Level: %d", fps, panic)
            })
        end
        
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
        
        -- Rage Status
        if self.StatsLabels.RageParagraph and self.StatsLabels.RageParagraph.Set then
            local rageStatus = Settings.RageMode and "🔥" or "❌"
            local ultraStatus = Settings.UltraRageMode and "⚡" or "❌"
            local godStatus = Settings.GodRageMode and "👑" or "❌"
            local silentStatus = Settings.SilentAim and "✅" or "❌"
            local magicStatus = Settings.MagicBullet and "✅" or "❌"
            local triggerStatus = Settings.TriggerBot and "✅" or "❌"
            
            self.StatsLabels.RageParagraph:Set({
                Title = "🔥 Rage Status",
                Content = string.format(
                    "Rage: %s | Ultra: %s | God: %s\nSilent: %s | Magic: %s | Trigger: %s",
                    rageStatus, ultraStatus, godStatus,
                    silentStatus, magicStatus, triggerStatus
                )
            })
        end
    end, "StatsUpdate")
end

function UI:StartStatsUpdateLoop()
    if self.UpdateConnection then
        self.UpdateConnection:Disconnect()
    end
    
    task.spawn(function()
        while true do
            wait(2)
            self:UpdateStats()
        end
    end)
end

function UI:Initialize()
    EnsureSettingsCompat()
    InitializeVisuals()
    SetupInputHandling()
    
    RunService.RenderStepped:Connect(function()
        SafeCall(function()
            UpdateVisuals()
        end, "VisualsUpdate")
    end)
    
    task.delay(1, function()
        SafeCall(function()
            self:CreateInterface()
            print("[UI] Interface v4.0 ULTRA RAGE criada!")
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