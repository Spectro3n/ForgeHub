-- ============================================================================
-- FORGEHUB - ESP MODULE v2.2 (CORRIGIDO - LIMPEZA E HIGHLIGHT FIX)
-- ============================================================================

local Core = _G.ForgeHubCore
if not Core then
    error("ForgeHubCore não encontrado! Carregue main.lua primeiro.")
end

-- ============================================================================
-- IMPORTS DO CORE
-- ============================================================================
local Players = Core.Players
local RunService = Core.RunService
local LocalPlayer = Core.LocalPlayer
local Camera = Core.Camera
local CoreGui = Core.CoreGui
local Settings = Core.Settings
local State = Core.State
local Notify = Core.Notify

-- ============================================================================
-- VERIFICAÇÃO DE DRAWING
-- ============================================================================
local DrawingAvailable = false
local function CheckDrawing()
    local success = pcall(function()
        local test = Drawing.new("Line")
        test:Remove()
    end)
    return success
end

DrawingAvailable = CheckDrawing()

if not DrawingAvailable then
    warn("[ESP] Drawing library não disponível!")
end

-- ============================================================================
-- SAFE CALL WRAPPER
-- ============================================================================
local function SafeCall(func, name)
    local success, err = pcall(func)
    if not success then
        warn("[ESP] Erro em " .. (name or "unknown") .. ": " .. tostring(err))
    end
    return success
end

-- ============================================================================
-- DRAWING CREATION (MELHORADO)
-- ============================================================================
local function CreateDrawing(drawingType, properties)
    if not DrawingAvailable then return nil end
    
    local success, obj = pcall(function()
        return Drawing.new(drawingType)
    end)
    
    if not success or not obj then
        warn("[ESP] Falha ao criar " .. drawingType)
        return nil
    end
    
    -- Aplicar propriedades de forma segura
    for prop, value in pairs(properties or {}) do
        pcall(function()
            obj[prop] = value
        end)
    end
    
    return obj
end

local function DestroyDrawing(obj)
    if obj then
        pcall(function()
            obj.Visible = false
        end)
        pcall(function()
            obj:Remove()
        end)
    end
end

-- ★ NOVO: Força visibilidade para false de forma segura
local function ForceHideDrawing(obj)
    if obj then
        pcall(function()
            obj.Visible = false
        end)
    end
end

-- ============================================================================
-- BOUNDING BOX CALCULATOR
-- ============================================================================
local function GetBoundingBox(character, anchor, distance)
    if not anchor or not anchor:IsDescendantOf(workspace) then
        return false, 0, 0, 0, 0
    end
    
    local cf, size
    
    if character and distance < 350 then
        local success
        success, cf, size = pcall(function()
            return character:GetBoundingBox()
        end)
        if not success then
            cf, size = nil, nil
        end
    end
    
    if not cf or not size then
        cf = anchor.CFrame
        size = Vector3.new(4, 5.5, 2)
        cf = cf + Vector3.new(0, 0.5, 0)
    end
    
    local corners = {}
    local halfSize = size / 2
    
    for x = -1, 1, 2 do
        for y = -1, 1, 2 do
            for z = -1, 1, 2 do
                local corner = cf * CFrame.new(
                    halfSize.X * x,
                    halfSize.Y * y,
                    halfSize.Z * z
                )
                table.insert(corners, corner.Position)
            end
        end
    end
    
    local minX, minY = math.huge, math.huge
    local maxX, maxY = -math.huge, -math.huge
    local anyVisible = false
    
    for _, cornerPos in ipairs(corners) do
        local screenPos, onScreen = Camera:WorldToViewportPoint(cornerPos)
        
        if onScreen or screenPos.Z > 0 then
            anyVisible = true
            minX = math.min(minX, screenPos.X)
            minY = math.min(minY, screenPos.Y)
            maxX = math.max(maxX, screenPos.X)
            maxY = math.max(maxY, screenPos.Y)
        end
    end
    
    if anyVisible and maxX > minX and maxY > minY then
        local w = math.clamp(maxX - minX, 8, 600)
        local h = math.clamp(maxY - minY, 12, 600)
        return true, minX, minY, w, h
    end
    
    return false, 0, 0, 0, 0
end

-- ============================================================================
-- SKELETON BONES DEFINITION
-- ============================================================================
local R15_BONES = {
    {"Head", "UpperTorso"},
    {"UpperTorso", "LowerTorso"},
    {"UpperTorso", "LeftUpperArm"},
    {"LeftUpperArm", "LeftLowerArm"},
    {"LeftLowerArm", "LeftHand"},
    {"UpperTorso", "RightUpperArm"},
    {"RightUpperArm", "RightLowerArm"},
    {"RightLowerArm", "RightHand"},
    {"LowerTorso", "LeftUpperLeg"},
    {"LeftUpperLeg", "LeftLowerLeg"},
    {"LeftLowerLeg", "LeftFoot"},
    {"LowerTorso", "RightUpperLeg"},
    {"RightUpperLeg", "RightLowerLeg"},
    {"RightLowerLeg", "RightFoot"},
}

local R6_BONES = {
    {"Head", "Torso"},
    {"Torso", "Left Arm"},
    {"Torso", "Right Arm"},
    {"Torso", "Left Leg"},
    {"Torso", "Right Leg"},
}

local function GetRigType(character)
    if not character then return nil end
    if character:FindFirstChild("UpperTorso") then return "R15" end
    if character:FindFirstChild("Torso") then return "R6" end
    return nil
end

local function RenderSkeletonLines(character, lines, color)
    if not character or not lines or #lines == 0 then
        for _, line in ipairs(lines or {}) do
            ForceHideDrawing(line)
        end
        return
    end
    
    local rigType = GetRigType(character)
    local bones = rigType == "R15" and R15_BONES or (rigType == "R6" and R6_BONES or {})
    
    local lineIdx = 1
    
    for _, bonePair in ipairs(bones) do
        if lineIdx > #lines then break end
        
        local part1 = character:FindFirstChild(bonePair[1], true)
        local part2 = character:FindFirstChild(bonePair[2], true)
        local line = lines[lineIdx]
        
        if part1 and part2 and line and 
           part1:IsDescendantOf(workspace) and 
           part2:IsDescendantOf(workspace) then
            
            local success, p1, v1, p2, v2 = pcall(function()
                local pos1, vis1 = Camera:WorldToViewportPoint(part1.Position)
                local pos2, vis2 = Camera:WorldToViewportPoint(part2.Position)
                return pos1, vis1, pos2, vis2
            end)
            
            if success and v1 and v2 then
                line.From = Vector2.new(p1.X, p1.Y)
                line.To = Vector2.new(p2.X, p2.Y)
                line.Color = color
                line.Thickness = 1.5
                line.Visible = true
            else
                line.Visible = false
            end
        elseif line then
            line.Visible = false
        end
        
        lineIdx = lineIdx + 1
    end
    
    for i = lineIdx, #lines do
        ForceHideDrawing(lines[i])
    end
end

-- ★ NOVO: Esconde todas as linhas do skeleton
local function HideAllSkeletonLines(lines)
    if not lines then return end
    for _, line in ipairs(lines) do
        ForceHideDrawing(line)
    end
end

-- ============================================================================
-- TEAM CHECK
-- ============================================================================
local function AreSameTeam(player1, player2)
    if not player1 or not player2 then return false end
    
    local SemanticEngine = Core.SemanticEngine
    if SemanticEngine and SemanticEngine.AreSameTeam then
        local success, result = pcall(function()
            return SemanticEngine:AreSameTeam(player1, player2)
        end)
        if success then return result end
    end
    
    if player1.Team and player2.Team then
        return player1.Team == player2.Team
    end
    
    return false
end

-- ============================================================================
-- ESP STORAGE
-- ============================================================================
local ESPData = {}

-- ★ NOVO: Cache de settings para detectar mudanças
local SettingsCache = {
    ESPEnabled = nil,
    ShowBox = nil,
    ShowName = nil,
    ShowDistance = nil,
    ShowHealthBar = nil,
    ShowHighlight = nil,
    ShowSkeleton = nil,
    IgnoreTeamESP = nil,
}

local function SettingsChanged()
    local changed = false
    
    local checks = {
        {"ESPEnabled", Settings.ESPEnabled},
        {"ShowBox", Settings.ShowBox},
        {"ShowName", Settings.ShowName},
        {"ShowDistance", Settings.ShowDistance},
        {"ShowHealthBar", Settings.ShowHealthBar},
        {"ShowHighlight", Settings.ShowHighlight},
        {"ShowSkeleton", Settings.Drawing and Settings.Drawing.Skeleton},
        {"IgnoreTeamESP", Settings.IgnoreTeamESP},
    }
    
    for _, check in ipairs(checks) do
        local key, value = check[1], check[2]
        if SettingsCache[key] ~= value then
            SettingsCache[key] = value
            changed = true
        end
    end
    
    return changed
end

-- ============================================================================
-- CREATE ESP FOR PLAYER (MELHORADO)
-- ============================================================================
local function CreateESP(player)
    if ESPData[player] then return ESPData[player] end
    if player == LocalPlayer then return nil end
    if not DrawingAvailable then return nil end
    
    local data = {
        -- Box
        Box = CreateDrawing("Square", {
            Thickness = 1,
            Filled = false,
            Visible = false,
            ZIndex = 3,
        }),
        BoxOutline = CreateDrawing("Square", {
            Thickness = 3,
            Filled = false,
            Visible = false,
            ZIndex = 2,
            Color = Color3.new(0, 0, 0),
        }),
        
        -- Name
        Name = CreateDrawing("Text", {
            Size = 14,
            Center = true,
            Outline = true,
            Font = 2,
            Visible = false,
            ZIndex = 4,
            Color = Color3.new(1, 1, 1),
        }),
        
        -- Distance
        Distance = CreateDrawing("Text", {
            Size = 12,
            Center = true,
            Outline = true,
            Font = 2,
            Visible = false,
            ZIndex = 4,
            Color = Color3.fromRGB(200, 200, 200),
        }),
        
        -- Health Bar
        HealthBg = CreateDrawing("Square", {
            Filled = true,
            Visible = false,
            ZIndex = 2,
            Color = Color3.new(0, 0, 0),
        }),
        HealthBar = CreateDrawing("Square", {
            Filled = true,
            Visible = false,
            ZIndex = 3,
        }),
        
        -- Skeleton Lines
        Skeleton = {},
        
        -- Highlight
        Highlight = nil,
        
        -- ★ NOVO: Estado interno
        _lastCharacter = nil,
        _highlightNeedsUpdate = true,
    }
    
    -- Criar skeleton lines
    for i = 1, 16 do
        local line = CreateDrawing("Line", {
            Thickness = 1.5,
            Visible = false,
            ZIndex = 3,
        })
        if line then
            table.insert(data.Skeleton, line)
        end
    end
    
    -- Criar Highlight
    pcall(function()
        local hl = Instance.new("Highlight")
        hl.Name = "ForgeESP_" .. player.Name
        hl.Enabled = false
        hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        hl.FillTransparency = 0.5
        hl.OutlineTransparency = 0
        hl.Parent = CoreGui
        data.Highlight = hl
    end)
    
    ESPData[player] = data
    return data
end

-- ============================================================================
-- REMOVE ESP FOR PLAYER (MELHORADO)
-- ============================================================================
local function RemoveESP(player)
    local data = ESPData[player]
    if not data then return end
    
    -- ★ Destruir TODOS os drawings de forma garantida
    DestroyDrawing(data.Box)
    DestroyDrawing(data.BoxOutline)
    DestroyDrawing(data.Name)
    DestroyDrawing(data.Distance)
    DestroyDrawing(data.HealthBg)
    DestroyDrawing(data.HealthBar)
    
    -- Destruir skeleton
    for _, line in ipairs(data.Skeleton or {}) do
        DestroyDrawing(line)
    end
    data.Skeleton = {}
    
    -- ★ Destruir Highlight de forma garantida
    if data.Highlight then
        pcall(function()
            data.Highlight.Enabled = false
            data.Highlight.Adornee = nil
        end)
        pcall(function()
            data.Highlight:Destroy()
        end)
        data.Highlight = nil
    end
    
    ESPData[player] = nil
end

-- ============================================================================
-- ★ HIDE ALL ESP ELEMENTS (CORRIGIDO - GARANTIDO)
-- ============================================================================
local function HideESP(data)
    if not data then return end
    
    -- ★ Força TODOS os elementos para invisível
    ForceHideDrawing(data.Box)
    ForceHideDrawing(data.BoxOutline)
    ForceHideDrawing(data.Name)
    ForceHideDrawing(data.Distance)
    ForceHideDrawing(data.HealthBg)
    ForceHideDrawing(data.HealthBar)
    
    -- ★ Esconde TODAS as linhas do skeleton
    HideAllSkeletonLines(data.Skeleton)
    
    -- ★ Desativa Highlight de forma garantida
    if data.Highlight then
        pcall(function()
            data.Highlight.Enabled = false
        end)
    end
end

-- ============================================================================
-- ★ UPDATE HIGHLIGHT (NOVO - CORRIGE PLAYERS EXISTENTES)
-- ============================================================================
local function UpdateHighlight(data, player, character, distance, shouldShow)
    if not data.Highlight then return end
    
    -- ★ Se não deve mostrar, desativa e sai
    if not shouldShow then
        pcall(function()
            data.Highlight.Enabled = false
        end)
        return
    end
    
    -- ★ Limita highlight a distância máxima
    local maxDist = Settings.ESP and Settings.ESP.HighlightMaxDistance or 500
    if distance > maxDist then
        pcall(function()
            data.Highlight.Enabled = false
        end)
        return
    end
    
    -- ★ Verifica se character mudou ou precisa update
    local needsUpdate = data._highlightNeedsUpdate or 
                        data._lastCharacter ~= character or
                        data.Highlight.Adornee ~= character
    
    if needsUpdate then
        pcall(function()
            data.Highlight.Adornee = character
            data._lastCharacter = character
            data._highlightNeedsUpdate = false
        end)
    end
    
    -- ★ Atualiza cores e propriedades
    pcall(function()
        data.Highlight.FillColor = Settings.HighlightFillColor or Color3.fromRGB(255, 0, 0)
        data.Highlight.OutlineColor = Settings.HighlightOutlineColor or Color3.fromRGB(255, 255, 255)
        data.Highlight.FillTransparency = Settings.HighlightTransparency or 0.5
        data.Highlight.OutlineTransparency = 0
        data.Highlight.Enabled = true
    end)
end

-- ============================================================================
-- ★ UPDATE ESP FOR PLAYER (COMPLETAMENTE REESCRITO)
-- ============================================================================
local function UpdateESP(player, data)
    -- ===== VERIFICAÇÃO 1: ESP GLOBAL HABILITADO? =====
    local espEnabled = Settings.ESPEnabled
    if Settings.ESP and Settings.ESP.Enabled ~= nil then
        espEnabled = Settings.ESP.Enabled
    end
    
    if not espEnabled then
        HideESP(data)
        return
    end
    
    -- ===== VERIFICAÇÃO 2: CHARACTER VÁLIDO =====
    local character = player.Character
    if not character then
        HideESP(data)
        return
    end
    
    local anchor = character:FindFirstChild("HumanoidRootPart")
                or character:FindFirstChild("Torso")
                or character:FindFirstChild("Head")
    
    if not anchor or not anchor:IsDescendantOf(workspace) then
        HideESP(data)
        return
    end
    
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    
    -- ===== VERIFICAÇÃO 3: ESTÁ MORTO? =====
    if humanoid and humanoid.Health <= 0 then
        HideESP(data)
        return
    end
    
    -- ===== CALCULAR DISTÂNCIA =====
    local camPos = Camera.CFrame.Position
    local targetPos = anchor.Position
    local distance = (targetPos - camPos).Magnitude
    
    -- ===== VERIFICAÇÃO 4: DISTÂNCIA MÁXIMA =====
    local maxDistance = Settings.ESPMaxDistance or 1000
    if Settings.ESP and Settings.ESP.MaxDistance then
        maxDistance = Settings.ESP.MaxDistance
    end
    
    if distance > maxDistance then
        HideESP(data)
        return
    end
    
    -- ===== VERIFICAÇÃO 5: TEAM CHECK =====
    local ignoreTeam = Settings.IgnoreTeamESP
    if Settings.ESP and Settings.ESP.IgnoreTeam ~= nil then
        ignoreTeam = Settings.ESP.IgnoreTeam
    end
    
    if ignoreTeam and AreSameTeam(LocalPlayer, player) then
        HideESP(data)
        return
    end
    
    -- ===== CALCULAR BOUNDING BOX =====
    local visible, x, y, w, h = GetBoundingBox(character, anchor, distance)
    
    if not visible or w < 5 or h < 5 then
        HideESP(data)
        return
    end
    
    -- =========================================================================
    -- ★ RENDERIZAR ELEMENTOS (CADA UM VERIFICA SEU PRÓPRIO SETTING)
    -- =========================================================================
    
    -- ===== BOX =====
    local showBox = Settings.ShowBox
    if Settings.ESP and Settings.ESP.ShowBox ~= nil then
        showBox = Settings.ESP.ShowBox
    end
    
    if showBox and data.Box then
        data.Box.Size = Vector2.new(w, h)
        data.Box.Position = Vector2.new(x, y)
        data.Box.Color = Settings.BoxColor or Color3.fromRGB(255, 170, 60)
        data.Box.Visible = true
        
        if data.BoxOutline then
            data.BoxOutline.Size = Vector2.new(w + 2, h + 2)
            data.BoxOutline.Position = Vector2.new(x - 1, y - 1)
            data.BoxOutline.Visible = true
        end
    else
        -- ★ FORÇA esconder quando desativado
        ForceHideDrawing(data.Box)
        ForceHideDrawing(data.BoxOutline)
    end
    
    -- ===== NAME =====
    local showName = Settings.ShowName
    if Settings.ESP and Settings.ESP.ShowName ~= nil then
        showName = Settings.ESP.ShowName
    end
    
    if showName and data.Name then
        data.Name.Text = player.Name
        data.Name.Position = Vector2.new(x + w/2, y - 16)
        data.Name.Color = Color3.new(1, 1, 1)
        data.Name.Visible = true
    else
        ForceHideDrawing(data.Name)
    end
    
    -- ===== DISTANCE =====
    local showDistance = Settings.ShowDistance
    if Settings.ESP and Settings.ESP.ShowDistance ~= nil then
        showDistance = Settings.ESP.ShowDistance
    end
    
    if showDistance and data.Distance then
        data.Distance.Text = string.format("[%dm]", math.floor(distance))
        data.Distance.Position = Vector2.new(x + w/2, y + h + 2)
        data.Distance.Color = Color3.fromRGB(200, 200, 200)
        data.Distance.Visible = true
    else
        ForceHideDrawing(data.Distance)
    end
    
    -- ===== HEALTH BAR =====
    local showHealthBar = Settings.ShowHealthBar
    if Settings.ESP and Settings.ESP.ShowHealthBar ~= nil then
        showHealthBar = Settings.ESP.ShowHealthBar
    end
    
    if showHealthBar and humanoid and data.HealthBg and data.HealthBar then
        local healthPct = math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1)
        
        local barWidth = 4
        local barX = x - barWidth - 4
        local barY = y
        local barHeight = h
        
        data.HealthBg.Size = Vector2.new(barWidth, barHeight)
        data.HealthBg.Position = Vector2.new(barX, barY)
        data.HealthBg.Visible = true
        
        local fillHeight = barHeight * healthPct
        data.HealthBar.Size = Vector2.new(barWidth - 2, fillHeight)
        data.HealthBar.Position = Vector2.new(barX + 1, barY + barHeight - fillHeight)
        
        local r, g
        if healthPct > 0.5 then
            r = (1 - healthPct) * 2
            g = 1
        else
            r = 1
            g = healthPct * 2
        end
        data.HealthBar.Color = Color3.new(r, g, 0)
        data.HealthBar.Visible = true
    else
        ForceHideDrawing(data.HealthBg)
        ForceHideDrawing(data.HealthBar)
    end
    
    -- ===== SKELETON =====
    local showSkeleton = false
    local skeletonMaxDist = 250
    
    if Settings.Drawing then
        showSkeleton = Settings.Drawing.Skeleton
        skeletonMaxDist = Settings.Drawing.SkeletonMaxDistance or 250
    end
    if Settings.ESP then
        if Settings.ESP.ShowSkeleton ~= nil then
            showSkeleton = Settings.ESP.ShowSkeleton
        end
        if Settings.ESP.SkeletonMaxDistance then
            skeletonMaxDist = Settings.ESP.SkeletonMaxDistance
        end
    end
    
    if showSkeleton and distance <= skeletonMaxDist then
        local skeletonColor = Settings.SkeletonColor or Color3.new(1, 1, 1)
        RenderSkeletonLines(character, data.Skeleton, skeletonColor)
    else
        HideAllSkeletonLines(data.Skeleton)
    end
    
    -- ===== HIGHLIGHT =====
    local showHighlight = Settings.ShowHighlight
    if Settings.ESP and Settings.ESP.ShowHighlight ~= nil then
        showHighlight = Settings.ESP.ShowHighlight
    end
    
    -- ★ NOVO: Chama função dedicada para Highlight
    UpdateHighlight(data, player, character, distance, showHighlight)
end

-- ============================================================================
-- LOCAL PLAYER SKELETON
-- ============================================================================
local LocalSkeletonData = {
    Lines = {},
    Initialized = false,
}

local function InitLocalSkeleton()
    if LocalSkeletonData.Initialized then return end
    if not DrawingAvailable then return end
    
    for i = 1, 16 do
        local line = CreateDrawing("Line", {
            Thickness = 2,
            Visible = false,
            ZIndex = 5,
        })
        if line then
            table.insert(LocalSkeletonData.Lines, line)
        end
    end
    
    LocalSkeletonData.Initialized = true
end

local function UpdateLocalSkeleton()
    local showLocal = false
    
    if Settings.Drawing and Settings.Drawing.LocalSkeleton then
        showLocal = true
    end
    if Settings.ESP and Settings.ESP.ShowLocalSkeleton then
        showLocal = true
    end
    
    if not showLocal then
        HideAllSkeletonLines(LocalSkeletonData.Lines)
        return
    end
    
    local character = LocalPlayer and LocalPlayer.Character
    if not character then
        HideAllSkeletonLines(LocalSkeletonData.Lines)
        return
    end
    
    local color = Settings.LocalSkeletonColor or Color3.fromRGB(0, 255, 255)
    RenderSkeletonLines(character, LocalSkeletonData.Lines, color)
end

-- ============================================================================
-- ★ ESP MODULE API (MELHORADO)
-- ============================================================================
local ESP = {
    _lastSettingsCheck = 0,
    _settingsCheckInterval = 0.5,
}

function ESP:CreatePlayerESP(player)
    return CreateESP(player)
end

function ESP:RemovePlayerESP(player)
    RemoveESP(player)
end

function ESP:UpdatePlayer(player)
    if player == LocalPlayer then return end
    
    local data = ESPData[player]
    if not data then
        data = CreateESP(player)
    end
    
    if data then
        SafeCall(function()
            UpdateESP(player, data)
        end, "UpdateESP_" .. player.Name)
    end
end

function ESP:UpdateAll()
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            self:UpdatePlayer(player)
        end
    end
end

-- ★ NOVO: Força refresh de todos os ESPs
function ESP:ForceRefresh()
    for player, data in pairs(ESPData) do
        if data then
            -- Marca highlight para update
            data._highlightNeedsUpdate = true
            
            -- Força recriação do Highlight se necessário
            if data.Highlight then
                pcall(function()
                    data.Highlight.Adornee = nil
                end)
            end
        end
    end
    
    -- Atualiza todos
    self:UpdateAll()
end

-- ★ NOVO: Esconde TODOS os ESPs imediatamente
function ESP:HideAll()
    for player, data in pairs(ESPData) do
        HideESP(data)
    end
    HideAllSkeletonLines(LocalSkeletonData.Lines)
end

function ESP:CleanupAll()
    -- Esconde tudo primeiro
    self:HideAll()
    
    -- Remove todos os players
    for player, _ in pairs(ESPData) do
        RemoveESP(player)
    end
    
    -- Limpa local skeleton
    for _, line in ipairs(LocalSkeletonData.Lines) do
        DestroyDrawing(line)
    end
    LocalSkeletonData.Lines = {}
    LocalSkeletonData.Initialized = false
end

-- ★ NOVO: Recria ESP para um player (fix para players existentes)
function ESP:RecreatePlayerESP(player)
    if player == LocalPlayer then return end
    
    -- Remove antigo
    RemoveESP(player)
    
    -- Cria novo
    local data = CreateESP(player)
    
    -- Força update do highlight
    if data then
        data._highlightNeedsUpdate = true
    end
    
    return data
end

-- ★ NOVO: Recria todos os ESPs
function ESP:RecreateAll()
    local players = Players:GetPlayers()
    
    for _, player in ipairs(players) do
        if player ~= LocalPlayer then
            self:RecreatePlayerESP(player)
        end
    end
end

function ESP:Initialize()
    if not DrawingAvailable then
        warn("[ESP] Drawing library não disponível - ESP desabilitado")
        return false
    end
    
    -- Inicializa local skeleton
    InitLocalSkeleton()
    
    -- ★ NOVO: Cria ESP para jogadores existentes COM highlight fix
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            local data = CreateESP(player)
            if data then
                data._highlightNeedsUpdate = true
            end
        end
    end
    
    -- Loop de atualização do local skeleton
    task.spawn(function()
        while true do
            task.wait(0.05)
            SafeCall(function()
                UpdateLocalSkeleton()
            end, "LocalSkeleton")
        end
    end)
    
    -- ★ NOVO: Loop de verificação de settings
    task.spawn(function()
        while true do
            task.wait(0.3)
            
            if SettingsChanged() then
                -- Se ESP foi desativado, esconde tudo imediatamente
                local espEnabled = Settings.ESPEnabled
                if Settings.ESP and Settings.ESP.Enabled ~= nil then
                    espEnabled = Settings.ESP.Enabled
                end
                
                if not espEnabled then
                    self:HideAll()
                else
                    -- Force refresh para aplicar novas settings
                    self:ForceRefresh()
                end
            end
        end
    end)
    
    -- Eventos de jogadores
    Players.PlayerAdded:Connect(function(player)
        task.wait(1)
        local data = CreateESP(player)
        if data then
            data._highlightNeedsUpdate = true
        end
    end)
    
    Players.PlayerRemoving:Connect(function(player)
        RemoveESP(player)
    end)
    
    -- ★ NOVO: Observa CharacterAdded para fix do Highlight
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            player.CharacterAdded:Connect(function(character)
                task.wait(0.2)
                local data = ESPData[player]
                if data then
                    data._highlightNeedsUpdate = true
                    data._lastCharacter = nil
                    
                    -- Reseta Adornee
                    if data.Highlight then
                        pcall(function()
                            data.Highlight.Adornee = character
                        end)
                    end
                end
            end)
        end
    end
    
    print("[ESP] Inicializado com sucesso!")
    print("[ESP] Drawing disponível: " .. tostring(DrawingAvailable))
    
    return true
end

function ESP:Debug()
    print("\n========== ESP DEBUG v2.2 ==========")
    print("Drawing Library: " .. (DrawingAvailable and "OK" or "FALHOU"))
    
    print("\n--- Settings Atuais ---")
    print("  ESPEnabled: " .. tostring(Settings.ESPEnabled))
    print("  ShowBox: " .. tostring(Settings.ShowBox))
    print("  ShowName: " .. tostring(Settings.ShowName))
    print("  ShowDistance: " .. tostring(Settings.ShowDistance))
    print("  ShowHealthBar: " .. tostring(Settings.ShowHealthBar))
    print("  ShowHighlight: " .. tostring(Settings.ShowHighlight))
    
    if Settings.ESP then
        print("  ESP.Enabled: " .. tostring(Settings.ESP.Enabled))
        print("  ESP.ShowSkeleton: " .. tostring(Settings.ESP.ShowSkeleton))
    end
    
    print("\n--- ESP Storage ---")
    local count = 0
    for player, data in pairs(ESPData) do
        count = count + 1
        local hlStatus = "N/A"
        if data.Highlight then
            local adornee = data.Highlight.Adornee
            local enabled = data.Highlight.Enabled
            hlStatus = string.format("Enabled=%s, Adornee=%s", 
                tostring(enabled), 
                adornee and adornee.Name or "nil")
        end
        
        print(string.format("  %s:", player.Name))
        print("    Box.Visible: " .. tostring(data.Box and data.Box.Visible))
        print("    Name.Visible: " .. tostring(data.Name and data.Name.Visible))
        print("    Highlight: " .. hlStatus)
        print("    _highlightNeedsUpdate: " .. tostring(data._highlightNeedsUpdate))
    end
    print("Total jogadores: " .. count)
    
    print("=====================================\n")
end

-- ============================================================================
-- EXPORT
-- ============================================================================

Core.ESP = ESP
State.DrawingESP = ESPData

return ESP