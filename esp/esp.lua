-- ============================================================================
-- FORGEHUB - ESP MODULE v2.1 (COMPATIBLE WITH MAIN.LUA)
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
local Settings = Core.Settings  -- USA DIRETAMENTE O SETTINGS DO MAIN.LUA
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
-- DRAWING CREATION
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
            obj:Remove()
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
    
    -- Para distâncias curtas, usa GetBoundingBox (mais preciso)
    if character and distance < 350 then
        local success
        success, cf, size = pcall(function()
            return character:GetBoundingBox()
        end)
        if not success then
            cf, size = nil, nil
        end
    end
    
    -- Fallback: estima baseado no HumanoidRootPart
    if not cf or not size then
        cf = anchor.CFrame
        size = Vector3.new(4, 5.5, 2)
        -- Move para cima para cobrir o personagem
        cf = cf + Vector3.new(0, 0.5, 0)
    end
    
    -- Calcula os 8 cantos do bounding box
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
    
    -- Projeta para tela
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
            if line then line.Visible = false end
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
    
    -- Esconde linhas não usadas
    for i = lineIdx, #lines do
        if lines[i] then
            lines[i].Visible = false
        end
    end
end

-- ============================================================================
-- TEAM CHECK (Simplificado)
-- ============================================================================
local function AreSameTeam(player1, player2)
    if not player1 or not player2 then return false end
    
    -- Verifica via SemanticEngine se disponível
    local SemanticEngine = Core.SemanticEngine
    if SemanticEngine and SemanticEngine.AreSameTeam then
        return SemanticEngine:AreSameTeam(player1, player2)
    end
    
    -- Fallback: Team padrão do Roblox
    if player1.Team and player2.Team then
        return player1.Team == player2.Team
    end
    
    return false
end

-- ============================================================================
-- ESP STORAGE
-- ============================================================================
local ESPData = {} -- player -> data

-- ============================================================================
-- CREATE ESP FOR PLAYER
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
        
        -- Skeleton Lines (máximo 16 para R15)
        Skeleton = {},
        
        -- Highlight (Instance)
        Highlight = nil,
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
        hl.Parent = CoreGui
        data.Highlight = hl
    end)
    
    ESPData[player] = data
    return data
end

-- ============================================================================
-- REMOVE ESP FOR PLAYER
-- ============================================================================
local function RemoveESP(player)
    local data = ESPData[player]
    if not data then return end
    
    -- Destroy drawings
    DestroyDrawing(data.Box)
    DestroyDrawing(data.BoxOutline)
    DestroyDrawing(data.Name)
    DestroyDrawing(data.Distance)
    DestroyDrawing(data.HealthBg)
    DestroyDrawing(data.HealthBar)
    
    for _, line in ipairs(data.Skeleton or {}) do
        DestroyDrawing(line)
    end
    
    -- Destroy highlight
    if data.Highlight then
        pcall(function()
            data.Highlight:Destroy()
        end)
    end
    
    ESPData[player] = nil
end

-- ============================================================================
-- HIDE ALL ESP ELEMENTS
-- ============================================================================
local function HideESP(data)
    if not data then return end
    
    if data.Box then data.Box.Visible = false end
    if data.BoxOutline then data.BoxOutline.Visible = false end
    if data.Name then data.Name.Visible = false end
    if data.Distance then data.Distance.Visible = false end
    if data.HealthBg then data.HealthBg.Visible = false end
    if data.HealthBar then data.HealthBar.Visible = false end
    
    for _, line in ipairs(data.Skeleton or {}) do
        if line then line.Visible = false end
    end
    
    if data.Highlight then
        data.Highlight.Enabled = false
    end
end

-- ============================================================================
-- UPDATE ESP FOR PLAYER
-- ============================================================================
local function UpdateESP(player, data)
    -- ===== VERIFICAÇÃO GLOBAL: ESP HABILITADO? =====
    -- IMPORTANTE: Usa Settings.ESPEnabled do main.lua
    if not Settings.ESPEnabled then
        HideESP(data)
        return
    end
    
    -- ===== OBTER CHARACTER E VALIDAR =====
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
    
    -- ===== VERIFICAR SE ESTÁ MORTO =====
    if humanoid and humanoid.Health <= 0 then
        HideESP(data)
        return
    end
    
    -- ===== CALCULAR DISTÂNCIA =====
    local camPos = Camera.CFrame.Position
    local targetPos = anchor.Position
    local distance = (targetPos - camPos).Magnitude
    
    -- ===== VERIFICAR DISTÂNCIA MÁXIMA =====
    -- Usa Settings.ESPMaxDistance do main.lua
    if distance > (Settings.ESPMaxDistance or 1000) then
        HideESP(data)
        return
    end
    
    -- ===== VERIFICAR TEAM =====
    -- Usa Settings.IgnoreTeamESP do main.lua
    if Settings.IgnoreTeamESP and AreSameTeam(LocalPlayer, player) then
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
    -- RENDERIZAR ELEMENTOS (USA SETTINGS DO MAIN.LUA)
    -- =========================================================================
    
    -- ===== BOX =====
    -- Usa Settings.ShowBox do main.lua
    if Settings.ShowBox then
        if data.Box then
            data.Box.Size = Vector2.new(w, h)
            data.Box.Position = Vector2.new(x, y)
            data.Box.Color = Settings.BoxColor or Color3.fromRGB(255, 170, 60)
            data.Box.Visible = true
        end
        
        if data.BoxOutline then
            data.BoxOutline.Size = Vector2.new(w + 2, h + 2)
            data.BoxOutline.Position = Vector2.new(x - 1, y - 1)
            data.BoxOutline.Visible = true
        end
    else
        -- IMPORTANTE: Esconde quando desativado!
        if data.Box then data.Box.Visible = false end
        if data.BoxOutline then data.BoxOutline.Visible = false end
    end
    
    -- ===== NAME =====
    -- Usa Settings.ShowName do main.lua
    if Settings.ShowName then
        if data.Name then
            data.Name.Text = player.Name
            data.Name.Position = Vector2.new(x + w/2, y - 16)
            data.Name.Color = Color3.new(1, 1, 1)
            data.Name.Visible = true
        end
    else
        if data.Name then data.Name.Visible = false end
    end
    
    -- ===== DISTANCE =====
    -- Usa Settings.ShowDistance do main.lua
    if Settings.ShowDistance then
        if data.Distance then
            data.Distance.Text = string.format("[%dm]", math.floor(distance))
            data.Distance.Position = Vector2.new(x + w/2, y + h + 2)
            data.Distance.Color = Color3.fromRGB(200, 200, 200)
            data.Distance.Visible = true
        end
    else
        if data.Distance then data.Distance.Visible = false end
    end
    
    -- ===== HEALTH BAR =====
    -- Usa Settings.ShowHealthBar do main.lua
    if Settings.ShowHealthBar and humanoid then
        local healthPct = math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1)
        
        local barWidth = 4
        local barX = x - barWidth - 4
        local barY = y
        local barHeight = h
        
        -- Background
        if data.HealthBg then
            data.HealthBg.Size = Vector2.new(barWidth, barHeight)
            data.HealthBg.Position = Vector2.new(barX, barY)
            data.HealthBg.Visible = true
        end
        
        -- Health fill (de baixo para cima)
        if data.HealthBar then
            local fillHeight = barHeight * healthPct
            data.HealthBar.Size = Vector2.new(barWidth - 2, fillHeight)
            data.HealthBar.Position = Vector2.new(barX + 1, barY + barHeight - fillHeight)
            
            -- Cor: Verde -> Amarelo -> Vermelho
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
        end
    else
        if data.HealthBg then data.HealthBg.Visible = false end
        if data.HealthBar then data.HealthBar.Visible = false end
    end
    
    -- ===== SKELETON =====
    -- Usa Settings.Drawing.Skeleton do main.lua
    local showSkeleton = Settings.Drawing and Settings.Drawing.Skeleton
    local skeletonMaxDist = Settings.Drawing and Settings.Drawing.SkeletonMaxDistance or 250
    
    if showSkeleton and distance <= skeletonMaxDist then
        local skeletonColor = Settings.SkeletonColor or Color3.new(1, 1, 1)
        RenderSkeletonLines(character, data.Skeleton, skeletonColor)
    else
        for _, line in ipairs(data.Skeleton or {}) do
            if line then line.Visible = false end
        end
    end
    
    -- ===== HIGHLIGHT =====
    -- Usa Settings.ShowHighlight do main.lua
    if Settings.ShowHighlight and data.Highlight then
        -- Limita highlight a 500m
        if distance <= 500 then
            if data.Highlight.Adornee ~= character then
                data.Highlight.Adornee = character
            end
            
            data.Highlight.FillColor = Settings.HighlightFillColor or Color3.fromRGB(255, 0, 0)
            data.Highlight.OutlineColor = Settings.HighlightOutlineColor or Color3.fromRGB(255, 255, 255)
            data.Highlight.FillTransparency = Settings.HighlightTransparency or 0.5
            data.Highlight.OutlineTransparency = 0
            data.Highlight.Enabled = true
        else
            data.Highlight.Enabled = false
        end
    else
        if data.Highlight then
            data.Highlight.Enabled = false
        end
    end
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
    -- Usa Settings.Drawing.LocalSkeleton do main.lua
    local showLocal = Settings.Drawing and Settings.Drawing.LocalSkeleton
    
    if not showLocal then
        for _, line in ipairs(LocalSkeletonData.Lines) do
            if line then line.Visible = false end
        end
        return
    end
    
    local character = LocalPlayer and LocalPlayer.Character
    if not character then
        for _, line in ipairs(LocalSkeletonData.Lines) do
            if line then line.Visible = false end
        end
        return
    end
    
    local color = Settings.LocalSkeletonColor or Color3.fromRGB(0, 255, 255)
    RenderSkeletonLines(character, LocalSkeletonData.Lines, color)
end

-- ============================================================================
-- ESP MODULE API
-- ============================================================================
local ESP = {}

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

function ESP:CleanupAll()
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

function ESP:Initialize()
    if not DrawingAvailable then
        warn("[ESP] Drawing library não disponível - ESP desabilitado")
        return false
    end
    
    -- Inicializa local skeleton
    InitLocalSkeleton()
    
    -- Cria ESP para jogadores existentes
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            CreateESP(player)
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
    
    -- Eventos de jogadores
    Players.PlayerAdded:Connect(function(player)
        task.wait(1)
        CreateESP(player)
    end)
    
    Players.PlayerRemoving:Connect(function(player)
        RemoveESP(player)
    end)
    
    print("[ESP] Inicializado com sucesso!")
    print("[ESP] Drawing disponível: " .. tostring(DrawingAvailable))
    print("[ESP] Configurações atuais:")
    print("  - ESPEnabled: " .. tostring(Settings.ESPEnabled))
    print("  - ShowBox: " .. tostring(Settings.ShowBox))
    print("  - ShowName: " .. tostring(Settings.ShowName))
    print("  - ShowDistance: " .. tostring(Settings.ShowDistance))
    print("  - ShowHealthBar: " .. tostring(Settings.ShowHealthBar))
    print("  - ShowHighlight: " .. tostring(Settings.ShowHighlight))
    print("  - Skeleton: " .. tostring(Settings.Drawing and Settings.Drawing.Skeleton))
    
    return true
end

function ESP:Debug()
    print("\n========== ESP DEBUG ==========")
    print("Drawing Library: " .. (DrawingAvailable and "OK" or "FALHOU"))
    
    print("\n--- Settings (do main.lua) ---")
    print("  ESPEnabled: " .. tostring(Settings.ESPEnabled))
    print("  ShowBox: " .. tostring(Settings.ShowBox))
    print("  ShowName: " .. tostring(Settings.ShowName))
    print("  ShowDistance: " .. tostring(Settings.ShowDistance))
    print("  ShowHealthBar: " .. tostring(Settings.ShowHealthBar))
    print("  ShowHighlight: " .. tostring(Settings.ShowHighlight))
    print("  IgnoreTeamESP: " .. tostring(Settings.IgnoreTeamESP))
    print("  ESPMaxDistance: " .. tostring(Settings.ESPMaxDistance))
    
    if Settings.Drawing then
        print("  Drawing.Skeleton: " .. tostring(Settings.Drawing.Skeleton))
        print("  Drawing.LocalSkeleton: " .. tostring(Settings.Drawing.LocalSkeleton))
        print("  Drawing.SkeletonMaxDistance: " .. tostring(Settings.Drawing.SkeletonMaxDistance))
    end
    
    print("\n--- ESP Storage ---")
    local count = 0
    for player, data in pairs(ESPData) do
        count = count + 1
        print(string.format("  %s:", player.Name))
        print("    Box: " .. (data.Box and "OK" or "FALHOU"))
        print("    Name: " .. (data.Name and "OK" or "FALHOU"))
        print("    Distance: " .. (data.Distance and "OK" or "FALHOU"))
        print("    HealthBar: " .. (data.HealthBar and "OK" or "FALHOU"))
        print("    Skeleton: " .. tostring(#data.Skeleton) .. " linhas")
        print("    Highlight: " .. (data.Highlight and "OK" or "FALHOU"))
    end
    print("Total jogadores rastreados: " .. count)
    
    print("\n--- Teste de Criação ---")
    local testLine = CreateDrawing("Line", {})
    print("  Line: " .. (testLine and "OK" or "FALHOU"))
    if testLine then DestroyDrawing(testLine) end
    
    local testText = CreateDrawing("Text", {})
    print("  Text: " .. (testText and "OK" or "FALHOU"))
    if testText then DestroyDrawing(testText) end
    
    local testSquare = CreateDrawing("Square", {})
    print("  Square: " .. (testSquare and "OK" or "FALHOU"))
    if testSquare then DestroyDrawing(testSquare) end
    
    print("================================\n")
end

-- ============================================================================
-- EXPORT
-- ============================================================================

-- Registra no Core
Core.ESP = ESP

-- Compatibilidade com State.DrawingESP
State.DrawingESP = ESPData

return ESP