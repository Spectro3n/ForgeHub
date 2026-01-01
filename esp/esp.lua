-- ============================================================================
-- FORGEHUB - ESP MODULE (FIXED & IMPROVED)
-- ============================================================================

local Core = _G.ForgeHubCore
if not Core then
    error("ForgeHubCore não encontrado! Carregue main.lua primeiro.")
end

local SafeCall = Core.SafeCall
local Camera = Core.Camera
local Settings = Core.Settings
local State = Core.State
local DrawingPool = Core.DrawingPool
local SemanticEngine = Core.SemanticEngine
local Profiler = Core.Profiler
local PerformanceManager = Core.PerformanceManager

-- ============================================================================
-- SETTINGS DEFAULTS (Garante que todas as configurações existam)
-- ============================================================================
local function EnsureSettings()
    Settings.ESP = Settings.ESP or {}
    
    -- Toggles
    if Settings.ESP.Enabled == nil then Settings.ESP.Enabled = true end
    if Settings.ESP.ShowBox == nil then Settings.ESP.ShowBox = true end
    if Settings.ESP.ShowName == nil then Settings.ESP.ShowName = true end
    if Settings.ESP.ShowDistance == nil then Settings.ESP.ShowDistance = true end
    if Settings.ESP.ShowHealthBar == nil then Settings.ESP.ShowHealthBar = true end
    if Settings.ESP.ShowSkeleton == nil then Settings.ESP.ShowSkeleton = true end
    if Settings.ESP.ShowHighlight == nil then Settings.ESP.ShowHighlight = true end
    if Settings.ESP.ShowLocalSkeleton == nil then Settings.ESP.ShowLocalSkeleton = false end
    if Settings.ESP.IgnoreTeam == nil then Settings.ESP.IgnoreTeam = true end
    
    -- Distances
    if Settings.ESP.MaxDistance == nil then Settings.ESP.MaxDistance = 1000 end
    if Settings.ESP.SkeletonMaxDistance == nil then Settings.ESP.SkeletonMaxDistance = 300 end
    if Settings.ESP.HighlightMaxDistance == nil then Settings.ESP.HighlightMaxDistance = 500 end
    
    -- Colors
    if Settings.ESP.BoxColor == nil then Settings.ESP.BoxColor = Color3.fromRGB(255, 0, 0) end
    if Settings.ESP.NameColor == nil then Settings.ESP.NameColor = Color3.fromRGB(255, 255, 255) end
    if Settings.ESP.DistanceColor == nil then Settings.ESP.DistanceColor = Color3.fromRGB(200, 200, 200) end
    if Settings.ESP.SkeletonColor == nil then Settings.ESP.SkeletonColor = Color3.fromRGB(255, 255, 255) end
    if Settings.ESP.LocalSkeletonColor == nil then Settings.ESP.LocalSkeletonColor = Color3.fromRGB(0, 255, 255) end
    if Settings.ESP.HighlightFillColor == nil then Settings.ESP.HighlightFillColor = Color3.fromRGB(255, 0, 0) end
    if Settings.ESP.HighlightOutlineColor == nil then Settings.ESP.HighlightOutlineColor = Color3.fromRGB(255, 255, 255) end
    if Settings.ESP.HighlightFillTransparency == nil then Settings.ESP.HighlightFillTransparency = 0.75 end
    if Settings.ESP.HighlightOutlineTransparency == nil then Settings.ESP.HighlightOutlineTransparency = 0 end
end

EnsureSettings()

-- ============================================================================
-- BOX CACHE (Improved)
-- ============================================================================
local BoxCache = {}
local BOX_CACHE_CLEANUP_INTERVAL = 5
local BOX_CACHE_MAX_AGE = 10

local function CalculateBoundingBox(anchor, model, distance)
    if not anchor or not anchor:IsDescendantOf(workspace) then
        return false, 0, 0, 0, 0
    end
    
    local cf, size
    local useSimple = distance > 400
    
    -- Tenta usar GetBoundingBox para precisão (apenas em distâncias curtas)
    if model and not useSimple then
        local success
        success, cf, size = pcall(function()
            return model:GetBoundingBox()
        end)
        
        if not success or not cf or not size then
            cf = nil
            size = nil
        end
    end
    
    -- Fallback: usa o anchor com tamanho estimado
    if not cf or not size then
        cf = anchor.CFrame
        -- Estima tamanho baseado no anchor (geralmente HumanoidRootPart)
        local anchorSize = anchor.Size
        size = Vector3.new(
            math.max(anchorSize.X, 4) * 1.2,
            math.max(anchorSize.Y, 5) * 1.1,
            math.max(anchorSize.Z, 2) * 1.2
        )
        
        -- Ajusta altura para cobrir personagem inteiro
        size = Vector3.new(size.X, size.Y * 2.5, size.Z)
        -- Move o centro para cima (personagem está acima do root)
        cf = cf + Vector3.new(0, size.Y * 0.15, 0)
    end
    
    -- Calcula os 8 cantos do bounding box
    local corners
    if useSimple then
        -- Versão simplificada: apenas 4 cantos principais
        corners = {
            (cf * CFrame.new(size.X/2, size.Y/2, 0)).Position,
            (cf * CFrame.new(-size.X/2, size.Y/2, 0)).Position,
            (cf * CFrame.new(size.X/2, -size.Y/2, 0)).Position,
            (cf * CFrame.new(-size.X/2, -size.Y/2, 0)).Position,
        }
    else
        -- Versão completa: todos os 8 cantos
        corners = {
            (cf * CFrame.new(size.X/2, size.Y/2, size.Z/2)).Position,
            (cf * CFrame.new(-size.X/2, size.Y/2, size.Z/2)).Position,
            (cf * CFrame.new(size.X/2, -size.Y/2, size.Z/2)).Position,
            (cf * CFrame.new(-size.X/2, -size.Y/2, size.Z/2)).Position,
            (cf * CFrame.new(size.X/2, size.Y/2, -size.Z/2)).Position,
            (cf * CFrame.new(-size.X/2, size.Y/2, -size.Z/2)).Position,
            (cf * CFrame.new(size.X/2, -size.Y/2, -size.Z/2)).Position,
            (cf * CFrame.new(-size.X/2, -size.Y/2, -size.Z/2)).Position,
        }
    end
    
    -- Projeta para viewport
    local minX, minY = math.huge, math.huge
    local maxX, maxY = -math.huge, -math.huge
    local anyVisible = false
    
    for _, cornerPos in ipairs(corners) do
        local screenPos, onScreen = Camera:WorldToViewportPoint(cornerPos)
        
        if onScreen then
            anyVisible = true
            minX = math.min(minX, screenPos.X)
            minY = math.min(minY, screenPos.Y)
            maxX = math.max(maxX, screenPos.X)
            maxY = math.max(maxY, screenPos.Y)
        elseif screenPos.Z > 0 then
            -- Está atrás da câmera mas próximo - ainda considera
            anyVisible = true
            minX = math.min(minX, screenPos.X)
            minY = math.min(minY, screenPos.Y)
            maxX = math.max(maxX, screenPos.X)
            maxY = math.max(maxY, screenPos.Y)
        end
    end
    
    if anyVisible and minX < maxX and minY < maxY then
        local width = maxX - minX
        local height = maxY - minY
        
        -- Limita tamanho mínimo e máximo
        width = math.clamp(width, 10, 1000)
        height = math.clamp(height, 15, 1000)
        
        return true, minX, minY, width, height
    end
    
    return false, 0, 0, 0, 0
end

local function GetBoxFromCache(anchor, model, distance)
    if not anchor then return false, 0, 0, 0, 0 end
    
    local now = tick()
    local cacheKey = model or anchor
    local cached = BoxCache[cacheKey]
    
    -- Tempo de cache baseado na distância
    local cacheTime
    if distance > 600 then
        cacheTime = 0.4
    elseif distance > 300 then
        cacheTime = 0.2
    else
        cacheTime = 0.08
    end
    
    -- Verifica cache válido
    if cached and (now - cached.time) < cacheTime then
        -- Verifica se ainda está na tela
        local testScreen, testVisible = Camera:WorldToViewportPoint(anchor.Position)
        if testVisible or testScreen.Z > 0 then
            return cached.visible, cached.x, cached.y, cached.w, cached.h
        end
    end
    
    -- Calcula novo bounding box
    local visible, x, y, w, h = CalculateBoundingBox(anchor, model, distance)
    
    -- Atualiza cache
    BoxCache[cacheKey] = {
        visible = visible,
        x = x,
        y = y,
        w = w,
        h = h,
        time = now
    }
    
    return visible, x, y, w, h
end

-- Limpeza periódica do cache
task.spawn(function()
    while true do
        wait(BOX_CACHE_CLEANUP_INTERVAL)
        SafeCall(function()
            local now = tick()
            local toRemove = {}
            
            for key, cached in pairs(BoxCache) do
                if (now - cached.time) > BOX_CACHE_MAX_AGE then
                    table.insert(toRemove, key)
                end
            end
            
            for _, key in ipairs(toRemove) do
                BoxCache[key] = nil
            end
        end, "BoxCacheCleanup")
    end
end)

-- ============================================================================
-- SKELETON SYSTEM (Fixed)
-- ============================================================================
local SkeletonSystem = {
    LocalPlayerSkeleton = {
        Enabled = false,
        Lines = {},
        LastUpdate = 0,
    },
    ConnectionCache = {},
    CacheTimeout = 3,
}

-- Definições de skeleton por tipo de rig
local SKELETON_R15 = {
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
    {"RightLowerLeg", "RightFoot"}
}

local SKELETON_R6 = {
    {"Head", "Torso"},
    {"Torso", "Left Arm"},
    {"Torso", "Right Arm"},
    {"Torso", "Left Leg"},
    {"Torso", "Right Leg"}
}

-- Versão simplificada para longas distâncias
local SKELETON_R15_SIMPLE = {
    {"Head", "UpperTorso"},
    {"UpperTorso", "LowerTorso"},
    {"UpperTorso", "LeftUpperArm"},
    {"UpperTorso", "RightUpperArm"},
    {"LowerTorso", "LeftUpperLeg"},
    {"LowerTorso", "RightUpperLeg"},
}

local SKELETON_R6_SIMPLE = {
    {"Head", "Torso"},
    {"Torso", "Left Arm"},
    {"Torso", "Right Arm"},
}

function SkeletonSystem:DetectRigType(model)
    if not model then return "Unknown" end
    
    if model:FindFirstChild("UpperTorso") and model:FindFirstChild("LowerTorso") then
        return "R15"
    elseif model:FindFirstChild("Torso") and model:FindFirstChild("Left Arm") then
        return "R6"
    end
    
    return "Unknown"
end

function SkeletonSystem:GetConnections(model, simplified)
    if not model then return {} end
    
    local now = tick()
    local cacheKey = tostring(model) .. (simplified and "_simple" or "_full")
    local cached = self.ConnectionCache[cacheKey]
    
    if cached and (now - cached.time) < self.CacheTimeout then
        -- Verifica se as partes ainda existem
        if cached.valid then
            return cached.connections
        end
    end
    
    local rigType = self:DetectRigType(model)
    local skeleton
    
    if rigType == "R15" then
        skeleton = simplified and SKELETON_R15_SIMPLE or SKELETON_R15
    elseif rigType == "R6" then
        skeleton = simplified and SKELETON_R6_SIMPLE or SKELETON_R6
    else
        -- Tenta detectar automaticamente via Motor6D
        return self:DetectConnectionsAuto(model, simplified)
    end
    
    local connections = {}
    local valid = true
    
    for _, bonePair in ipairs(skeleton) do
        local part1 = model:FindFirstChild(bonePair[1], true)
        local part2 = model:FindFirstChild(bonePair[2], true)
        
        if part1 and part2 and part1:IsA("BasePart") and part2:IsA("BasePart") then
            table.insert(connections, {part1, part2})
        else
            valid = false
        end
    end
    
    self.ConnectionCache[cacheKey] = {
        connections = connections,
        time = now,
        valid = valid
    }
    
    return connections
end

function SkeletonSystem:DetectConnectionsAuto(model, simplified)
    if not model then return {} end
    
    local connections = {}
    local parts = {}
    
    -- Encontra todas as conexões via Motor6D/Weld
    for _, v in ipairs(model:GetDescendants()) do
        if v:IsA("Motor6D") then
            local p0, p1 = v.Part0, v.Part1
            if p0 and p1 and p0:IsA("BasePart") and p1:IsA("BasePart") then
                if p0:IsDescendantOf(model) and p1:IsDescendantOf(model) then
                    table.insert(connections, {p0, p1})
                    parts[p0] = true
                    parts[p1] = true
                end
            end
        end
    end
    
    -- Se simplificado, limita a 8 conexões
    if simplified and #connections > 8 then
        local simplified_conns = {}
        for i = 1, 8 do
            simplified_conns[i] = connections[i]
        end
        return simplified_conns
    end
    
    return connections
end

function SkeletonSystem:RenderSkeleton(model, lines, color, simplified)
    if not model or not lines or #lines == 0 then
        return
    end
    
    local connections = self:GetConnections(model, simplified)
    local lineIndex = 1
    
    for _, bone in ipairs(connections) do
        if lineIndex > #lines then break end
        
        local part1, part2 = bone[1], bone[2]
        local line = lines[lineIndex]
        
        if not line then
            lineIndex = lineIndex + 1
            continue
        end
        
        if part1 and part2 and 
           part1:IsDescendantOf(workspace) and 
           part2:IsDescendantOf(workspace) then
            
            local success, result = pcall(function()
                local pos1, vis1 = Camera:WorldToViewportPoint(part1.Position)
                local pos2, vis2 = Camera:WorldToViewportPoint(part2.Position)
                return {pos1 = pos1, vis1 = vis1, pos2 = pos2, vis2 = vis2}
            end)
            
            if success and result.vis1 and result.vis2 then
                line.From = Vector2.new(result.pos1.X, result.pos1.Y)
                line.To = Vector2.new(result.pos2.X, result.pos2.Y)
                line.Color = color
                line.Thickness = 1.5
                line.Visible = true
                lineIndex = lineIndex + 1
            else
                line.Visible = false
                lineIndex = lineIndex + 1
            end
        else
            line.Visible = false
            lineIndex = lineIndex + 1
        end
    end
    
    -- Esconde linhas não usadas
    for i = lineIndex, #lines do
        if lines[i] then
            lines[i].Visible = false
        end
    end
end

function SkeletonSystem:InitLocalPlayerSkeleton()
    -- Limpa linhas antigas
    for _, line in ipairs(self.LocalPlayerSkeleton.Lines) do
        if line then
            pcall(function() line:Remove() end)
        end
    end
    self.LocalPlayerSkeleton.Lines = {}
    
    -- Cria novas linhas
    for i = 1, 20 do
        local line = DrawingPool:Acquire("Line")
        if line then
            line.Thickness = 2
            line.Visible = false
            line.Color = Settings.ESP.LocalSkeletonColor
            line.ZIndex = 5
            table.insert(self.LocalPlayerSkeleton.Lines, line)
        end
    end
end

function SkeletonSystem:UpdateLocalPlayerSkeleton()
    local now = tick()
    
    -- Rate limit
    if (now - self.LocalPlayerSkeleton.LastUpdate) < 0.033 then
        return
    end
    self.LocalPlayerSkeleton.LastUpdate = now
    
    -- Verifica se está habilitado
    if not Settings.ESP.ShowLocalSkeleton then
        for _, line in ipairs(self.LocalPlayerSkeleton.Lines) do
            if line then line.Visible = false end
        end
        return
    end
    
    local character = Core.LocalPlayer and Core.LocalPlayer.Character
    if not character then
        for _, line in ipairs(self.LocalPlayerSkeleton.Lines) do
            if line then line.Visible = false end
        end
        return
    end
    
    self:RenderSkeleton(
        character,
        self.LocalPlayerSkeleton.Lines,
        Settings.ESP.LocalSkeletonColor,
        false
    )
end

function SkeletonSystem:ClearCache()
    self.ConnectionCache = {}
end

-- ============================================================================
-- ESP MANAGER
-- ============================================================================
local ESP = {}

-- Cria um objeto de drawing com propriedades
local function CreateDrawing(drawingType, properties)
    local obj = DrawingPool:Acquire(drawingType)
    if not obj then
        warn("[ESP] Failed to acquire drawing: " .. drawingType)
        return nil
    end
    
    for prop, value in pairs(properties or {}) do
        local success = pcall(function()
            obj[prop] = value
        end)
        if not success then
            warn("[ESP] Failed to set property: " .. prop)
        end
    end
    
    return obj
end

function ESP:CreatePlayerESP(player)
    if not Core.DrawingOK then
        warn("[ESP] Drawing not available")
        return
    end
    
    if State.DrawingESP[player] then
        return -- Já existe
    end
    
    local storage = {
        -- Box
        Box = CreateDrawing("Square", {
            Thickness = 1,
            Filled = false,
            Visible = false,
            ZIndex = 3,
            Color = Settings.ESP.BoxColor,
            Transparency = 1
        }),
        BoxOutline = CreateDrawing("Square", {
            Thickness = 3,
            Filled = false,
            Visible = false,
            ZIndex = 2,
            Color = Color3.new(0, 0, 0),
            Transparency = 1
        }),
        
        -- Name
        Name = CreateDrawing("Text", {
            Size = 14,
            Center = true,
            Outline = true,
            Font = 2,
            Visible = false,
            ZIndex = 4,
            Color = Settings.ESP.NameColor
        }),
        
        -- Distance
        Distance = CreateDrawing("Text", {
            Size = 12,
            Center = true,
            Outline = true,
            Font = 2,
            Visible = false,
            ZIndex = 4,
            Color = Settings.ESP.DistanceColor
        }),
        
        -- Health Bar
        HealthBarBg = CreateDrawing("Square", {
            Filled = true,
            Visible = false,
            ZIndex = 2,
            Color = Color3.new(0, 0, 0),
            Transparency = 0.5
        }),
        HealthBar = CreateDrawing("Square", {
            Filled = true,
            Visible = false,
            ZIndex = 3,
            Color = Color3.new(0, 1, 0)
        }),
        
        -- Skeleton
        SkeletonLines = {},
        
        -- Highlight
        Highlight = nil,
        
        -- Cache interno
        _lastUpdate = 0,
        _lastSkeletonUpdate = 0,
        _lastBoxUpdate = 0,
        _cachedBox = {visible = false, x = 0, y = 0, w = 0, h = 0},
    }
    
    -- Cria linhas do skeleton
    for i = 1, 20 do
        local line = CreateDrawing("Line", {
            Thickness = 1.5,
            Visible = false,
            Color = Settings.ESP.SkeletonColor,
            ZIndex = 3
        })
        if line then
            table.insert(storage.SkeletonLines, line)
        end
    end
    
    -- Cria Highlight
    local success, highlight = pcall(function()
        local h = Instance.new("Highlight")
        h.Name = "ForgeESP_" .. player.Name
        h.FillColor = Settings.ESP.HighlightFillColor
        h.OutlineColor = Settings.ESP.HighlightOutlineColor
        h.FillTransparency = Settings.ESP.HighlightFillTransparency
        h.OutlineTransparency = Settings.ESP.HighlightOutlineTransparency
        h.Enabled = false
        h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        h.Parent = Core.CoreGui
        return h
    end)
    
    if success and highlight then
        storage.Highlight = highlight
    end
    
    State.DrawingESP[player] = storage
end

function ESP:RemovePlayerESP(player)
    local storage = State.DrawingESP[player]
    if not storage then return end
    
    -- Remove drawings
    local drawingTypes = {
        Box = "Square",
        BoxOutline = "Square",
        Name = "Text",
        Distance = "Text",
        HealthBar = "Square",
        HealthBarBg = "Square",
    }
    
    for key, drawingType in pairs(drawingTypes) do
        if storage[key] then
            pcall(function()
                storage[key].Visible = false
            end)
            DrawingPool:Release(drawingType, storage[key])
        end
    end
    
    -- Remove skeleton lines
    for _, line in ipairs(storage.SkeletonLines or {}) do
        if line then
            pcall(function() line.Visible = false end)
            DrawingPool:Release("Line", line)
        end
    end
    
    -- Remove highlight
    if storage.Highlight then
        pcall(function()
            storage.Highlight.Enabled = false
            storage.Highlight:Destroy()
        end)
    end
    
    State.DrawingESP[player] = nil
    
    -- Limpa cache do SemanticEngine
    if SemanticEngine and SemanticEngine.ClearPlayerCache then
        SemanticEngine:ClearPlayerCache(player)
    end
end

local function HideAllESP(storage)
    if not storage then return end
    
    pcall(function()
        if storage.Box then storage.Box.Visible = false end
        if storage.BoxOutline then storage.BoxOutline.Visible = false end
        if storage.Name then storage.Name.Visible = false end
        if storage.Distance then storage.Distance.Visible = false end
        if storage.HealthBar then storage.HealthBar.Visible = false end
        if storage.HealthBarBg then storage.HealthBarBg.Visible = false end
        
        if storage.Highlight then
            storage.Highlight.Enabled = false
            storage.Highlight.Adornee = nil
        end
        
        for _, line in ipairs(storage.SkeletonLines or {}) do
            if line then line.Visible = false end
        end
    end)
    
    storage._cachedBox = {visible = false, x = 0, y = 0, w = 0, h = 0}
end

function ESP:UpdatePlayerESP(player, storage)
    if not player or player == Core.LocalPlayer then
        HideAllESP(storage)
        return
    end
    
    -- Profiler tracking
    if Profiler and Profiler.RecordESPUpdate then
        Profiler:RecordESPUpdate()
    end
    
    -- Obtém dados do jogador via SemanticEngine
    local data
    if SemanticEngine and SemanticEngine.GetCachedPlayerData then
        data = SemanticEngine:GetCachedPlayerData(player)
    else
        -- Fallback se SemanticEngine não existir
        local char = player.Character
        data = {
            isValid = char ~= nil,
            model = char,
            anchor = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso") or char:FindFirstChild("Head")),
            humanoid = char and char:FindFirstChildOfClass("Humanoid")
        }
    end
    
    -- Valida dados
    if not data.isValid or not data.anchor then
        HideAllESP(storage)
        return
    end
    
    -- Verifica se anchor existe no workspace
    if not data.anchor:IsDescendantOf(workspace) then
        HideAllESP(storage)
        return
    end
    
    -- Calcula distância
    local camPos = Camera.CFrame.Position
    local targetPos = data.anchor.Position
    local distance = (targetPos - camPos).Magnitude
    
    -- Verifica distância máxima
    if distance > Settings.ESP.MaxDistance then
        HideAllESP(storage)
        return
    end
    
    -- Verifica time
    if Settings.ESP.IgnoreTeam then
        local sameTeam = false
        if SemanticEngine and SemanticEngine.AreSameTeam then
            sameTeam = SemanticEngine:AreSameTeam(Core.LocalPlayer, player)
        else
            -- Fallback
            sameTeam = Core.LocalPlayer.Team and player.Team and Core.LocalPlayer.Team == player.Team
        end
        
        if sameTeam then
            HideAllESP(storage)
            return
        end
    end
    
    -- Verifica se está morto
    if data.humanoid and data.humanoid.Health <= 0 then
        HideAllESP(storage)
        return
    end
    
    -- Panic mode - apenas box
    if PerformanceManager and PerformanceManager.panicLevel and PerformanceManager.panicLevel >= 2 then
        local visible, x, y, w, h = GetBoxFromCache(data.anchor, data.model, distance)
        
        if visible and w > 5 and h > 5 then
            if storage.Box and Settings.ESP.ShowBox then
                storage.Box.Size = Vector2.new(w, h)
                storage.Box.Position = Vector2.new(x, y)
                storage.Box.Color = Settings.ESP.BoxColor
                storage.Box.Visible = true
            end
        else
            if storage.Box then storage.Box.Visible = false end
        end
        
        -- Esconde todo o resto
        if storage.BoxOutline then storage.BoxOutline.Visible = false end
        if storage.Name then storage.Name.Visible = false end
        if storage.Distance then storage.Distance.Visible = false end
        if storage.HealthBar then storage.HealthBar.Visible = false end
        if storage.HealthBarBg then storage.HealthBarBg.Visible = false end
        if storage.Highlight then storage.Highlight.Enabled = false end
        for _, line in ipairs(storage.SkeletonLines or {}) do
            if line then line.Visible = false end
        end
        return
    end
    
    -- Calcula bounding box
    local now = tick()
    local visible, x, y, w, h
    
    local boxUpdateInterval = distance > 400 and 0.2 or 0.05
    
    if (now - storage._lastBoxUpdate) > boxUpdateInterval then
        visible, x, y, w, h = GetBoxFromCache(data.anchor, data.model, distance)
        storage._cachedBox = {visible = visible, x = x, y = y, w = w, h = h}
        storage._lastBoxUpdate = now
    else
        local cached = storage._cachedBox
        visible = cached.visible
        x, y, w, h = cached.x, cached.y, cached.w, cached.h
    end
    
    if not visible or w < 5 or h < 5 then
        HideAllESP(storage)
        return
    end
    
    -- ==================== BOX ====================
    if Settings.ESP.ShowBox then
        if storage.Box then
            storage.Box.Size = Vector2.new(w, h)
            storage.Box.Position = Vector2.new(x, y)
            storage.Box.Color = Settings.ESP.BoxColor
            storage.Box.Visible = true
        end
        
        if storage.BoxOutline then
            storage.BoxOutline.Size = Vector2.new(w + 2, h + 2)
            storage.BoxOutline.Position = Vector2.new(x - 1, y - 1)
            storage.BoxOutline.Visible = true
        end
    else
        if storage.Box then storage.Box.Visible = false end
        if storage.BoxOutline then storage.BoxOutline.Visible = false end
    end
    
    -- ==================== NAME ====================
    if Settings.ESP.ShowName and storage.Name then
        storage.Name.Text = player.Name
        storage.Name.Position = Vector2.new(x + w/2, y - 18)
        storage.Name.Color = Settings.ESP.NameColor
        storage.Name.Visible = true
    elseif storage.Name then
        storage.Name.Visible = false
    end
    
    -- ==================== DISTANCE ====================
    if Settings.ESP.ShowDistance and storage.Distance then
        storage.Distance.Text = string.format("[%dm]", math.floor(distance))
        storage.Distance.Position = Vector2.new(x + w/2, y + h + 3)
        storage.Distance.Color = Settings.ESP.DistanceColor
        storage.Distance.Visible = true
    elseif storage.Distance then
        storage.Distance.Visible = false
    end
    
    -- ==================== HEALTH BAR ====================
    if Settings.ESP.ShowHealthBar and data.humanoid and storage.HealthBar then
        local maxHealth = data.humanoid.MaxHealth
        local health = data.humanoid.Health
        local healthPercent = math.clamp(health / maxHealth, 0, 1)
        
        local barWidth = 4
        local barHeight = h
        local barX = x - barWidth - 3
        local barY = y
        
        -- Background
        if storage.HealthBarBg then
            storage.HealthBarBg.Size = Vector2.new(barWidth, barHeight)
            storage.HealthBarBg.Position = Vector2.new(barX, barY)
            storage.HealthBarBg.Visible = true
        end
        
        -- Health bar (cresce de baixo para cima)
        local healthHeight = barHeight * healthPercent
        storage.HealthBar.Size = Vector2.new(barWidth - 2, healthHeight)
        storage.HealthBar.Position = Vector2.new(barX + 1, barY + (barHeight - healthHeight))
        
        -- Cor baseada na vida (verde -> amarelo -> vermelho)
        if healthPercent > 0.5 then
            storage.HealthBar.Color = Color3.new(
                (1 - healthPercent) * 2,
                1,
                0
            )
        else
            storage.HealthBar.Color = Color3.new(
                1,
                healthPercent * 2,
                0
            )
        end
        storage.HealthBar.Visible = true
    else
        if storage.HealthBar then storage.HealthBar.Visible = false end
        if storage.HealthBarBg then storage.HealthBarBg.Visible = false end
    end
    
    -- ==================== SKELETON ====================
    if Settings.ESP.ShowSkeleton and distance <= Settings.ESP.SkeletonMaxDistance then
        local skeletonInterval = distance > 150 and 0.1 or 0.05
        
        if (now - storage._lastSkeletonUpdate) > skeletonInterval then
            local simplified = distance > 100
            SkeletonSystem:RenderSkeleton(
                data.model,
                storage.SkeletonLines,
                Settings.ESP.SkeletonColor,
                simplified
            )
            storage._lastSkeletonUpdate = now
        end
    else
        for _, line in ipairs(storage.SkeletonLines or {}) do
            if line then line.Visible = false end
        end
    end
    
    -- ==================== HIGHLIGHT ====================
    if Settings.ESP.ShowHighlight and storage.Highlight and distance <= Settings.ESP.HighlightMaxDistance then
        if storage.Highlight.Adornee ~= data.model then
            storage.Highlight.Adornee = data.model
        end
        
        storage.Highlight.FillColor = Settings.ESP.HighlightFillColor
        storage.Highlight.OutlineColor = Settings.ESP.HighlightOutlineColor
        storage.Highlight.FillTransparency = Settings.ESP.HighlightFillTransparency
        storage.Highlight.Enabled = true
    elseif storage.Highlight then
        storage.Highlight.Enabled = false
    end
end

function ESP:UpdatePlayer(player)
    if not Settings.ESP.Enabled then
        if State.DrawingESP[player] then
            HideAllESP(State.DrawingESP[player])
        end
        return
    end
    
    if not State.DrawingESP[player] then
        self:CreatePlayerESP(player)
    end
    
    if State.DrawingESP[player] then
        self:UpdatePlayerESP(player, State.DrawingESP[player])
    end
end

function ESP:CleanupAll()
    for player, _ in pairs(State.DrawingESP) do
        self:RemovePlayerESP(player)
    end
    
    SkeletonSystem:ClearCache()
    BoxCache = {}
end

function ESP:UpdateSettings(newSettings)
    if not newSettings then return end
    
    for key, value in pairs(newSettings) do
        Settings.ESP[key] = value
    end
end

function ESP:Toggle(enabled)
    Settings.ESP.Enabled = enabled
    
    if not enabled then
        for _, storage in pairs(State.DrawingESP) do
            HideAllESP(storage)
        end
    end
end

function ESP:Initialize()
    EnsureSettings()
    SkeletonSystem:InitLocalPlayerSkeleton()
    
    -- Loop de atualização do skeleton local
    task.spawn(function()
        while true do
            wait(0.033) -- ~30 FPS
            SafeCall(function()
                SkeletonSystem:UpdateLocalPlayerSkeleton()
            end, "LocalSkeletonUpdate")
        end
    end)
    
    print("[ESP] Initialized successfully")
end

-- ============================================================================
-- DEBUG FUNCTION
-- ============================================================================
function ESP:Debug()
    print("=== ESP Debug ===")
    print("Settings.ESP:", Settings.ESP)
    print("Active ESP count:", #(function()
        local count = 0
        for _ in pairs(State.DrawingESP) do count = count + 1 end
        return count
    end)())
    print("BoxCache entries:", #(function()
        local count = 0
        for _ in pairs(BoxCache) do count = count + 1 end
        return count
    end)())
    print("================")
end

-- ============================================================================
-- EXPORT
-- ============================================================================
Core.ESP = ESP
Core.SkeletonSystem = SkeletonSystem

return ESP