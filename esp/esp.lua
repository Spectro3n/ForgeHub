-- ============================================================================
-- FORGEHUB - ESP MODULE (IMPROVED)
-- ============================================================================

-- IMPORTANT: This is an improved drop-in replacement for esp.lua.
-- Save as esp.lua (or replace the module at esp/esp.lua) and reload the loader (main.lua).

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
-- BOX CACHE (robust caching + safer world->screen checks)
-- ============================================================================
local BoxCache = {}

local function _isOnScreen(position)
    if not position then return false end
    local ok, screen = pcall(function()
        return Camera:WorldToViewportPoint(position)
    end)
    if not ok or not screen then return false end
    -- screen is Vector3 from Camera:WorldToViewportPoint -> Z>0 means in front
    return screen.Z > 0, screen
end

local function GetBoxFromAnchor(anchor, model, distance)
    if not anchor or not anchor:IsDescendantOf(workspace) then
        return false, 0, 0, 0, 0
    end

    local now = tick()
    local cacheKey = model or anchor
    local cached = BoxCache[cacheKey]

    local cacheTime = 0.1
    if distance > 800 then
        cacheTime = 0.5
    elseif distance > 400 then
        cacheTime = 0.25
    end

    if cached and (now - cached.time < cacheTime) then
        -- validate cached visibility quickly
        local onScreen, screen = _isOnScreen(anchor.Position)
        if not onScreen then
            BoxCache[cacheKey] = nil
            return false, 0, 0, 0, 0
        end
        return cached.visible, cached.x, cached.y, cached.w, cached.h
    end

    -- Helper to build box from a list of world positions
    local function computeFromPoints(points)
        local minX, minY = math.huge, math.huge
        local maxX, maxY = -math.huge, -math.huge
        local visible = false
        for _, p in ipairs(points) do
            local ok, screen = pcall(function() return Camera:WorldToViewportPoint(p) end)
            if ok and screen and screen.Z > 0 then
                visible = true
                minX = math.min(minX, screen.X)
                minY = math.min(minY, screen.Y)
                maxX = math.max(maxX, screen.X)
                maxY = math.max(maxY, screen.Y)
            end
        end
        if not visible then return false end
        local result = {
            visible = true,
            x = minX,
            y = minY,
            w = math.max(1, maxX - minX),
            h = math.max(1, maxY - minY),
            time = now
        }
        BoxCache[cacheKey] = result
        return true, result.x, result.y, result.w, result.h
    end

    -- Far distance: approximate using anchor size
    if distance > 600 then
        local ok, size, cf = pcall(function()
            local s = anchor.Size
            local c = anchor.CFrame
            return s, c
        end)
        if not ok then return false, 0, 0, 0, 0 end

        local HEIGHT = math.max(1, anchor.Size.Y * 2.5)
        local WIDTH = math.max(1, math.max(anchor.Size.X, anchor.Size.Z) * 1.5)
        local cf = anchor.CFrame
        local sizeVec = Vector3.new(WIDTH, HEIGHT, WIDTH)
        local corners = {
            cf * CFrame.new( sizeVec.X/2,  sizeVec.Y/2,  sizeVec.Z/2),
            cf * CFrame.new(-sizeVec.X/2,  sizeVec.Y/2,  sizeVec.Z/2),
            cf * CFrame.new( sizeVec.X/2, -sizeVec.Y/2,  sizeVec.Z/2),
            cf * CFrame.new(-sizeVec.X/2, -sizeVec.Y/2,  sizeVec.Z/2),
            cf * CFrame.new( sizeVec.X/2,  sizeVec.Y/2, -sizeVec.Z/2),
            cf * CFrame.new(-sizeVec.X/2,  sizeVec.Y/2, -sizeVec.Z/2),
            cf * CFrame.new( sizeVec.X/2, -sizeVec.Y/2, -sizeVec.Z/2),
            cf * CFrame.new(-sizeVec.X/2, -sizeVec.Y/2, -sizeVec.Z/2),
        }

        return computeFromPoints(corners)
    end

    -- Close distance: try model bounding box first
    if model and distance <= 600 then
        local success, cf, size = pcall(function()
            return model:GetBoundingBox()
        end)
        if success and cf and size then
            local corners = {
                cf * CFrame.new( size.X/2,  size.Y/2,  size.Z/2),
                cf * CFrame.new(-size.X/2,  size.Y/2,  size.Z/2),
                cf * CFrame.new( size.X/2, -size.Y/2,  size.Z/2),
                cf * CFrame.new(-size.X/2, -size.Y/2,  size.Z/2),
                cf * CFrame.new( size.X/2,  size.Y/2, -size.Z/2),
                cf * CFrame.new(-size.X/2,  size.Y/2, -size.Z/2),
                cf * CFrame.new( size.X/2, -size.Y/2, -size.Z/2),
                cf * CFrame.new(-size.X/2, -size.Y/2, -size.Z/2),
            }
            return computeFromPoints(corners)
        end
    end

    -- Fallback: single anchor point
    local ok, screen = pcall(function() return Camera:WorldToViewportPoint(anchor.Position) end)
    if ok and screen and screen.Z > 0 then
        local x, y = screen.X - 8, screen.Y - 12
        local w, h = 16, 24
        local result = { visible = true, x = x, y = y, w = w, h = h, time = now }
        BoxCache[cacheKey] = result
        return true, x, y, w, h
    end

    BoxCache[cacheKey] = nil
    return false, 0, 0, 0, 0
end

-- Periodic cleanup
task.spawn(function()
    while wait(5) do
        SafeCall(function()
            for key, cached in pairs(BoxCache) do
                if tick() - (cached.time or 0) > 10 then
                    BoxCache[key] = nil
                end
            end
        end, "BoxCacheCleanup")
    end
end)

-- ============================================================================
-- SKELETON SYSTEM (improved detection + safety checks)
-- ============================================================================
local SkeletonSystem = {
    LocalPlayerSkeleton = {
        Enabled = false,
        Lines = {},
        Color = Settings.LocalSkeletonColor or Color3.fromRGB(0,255,255),
        LastUpdate = 0,
    },
    GraphCache = {},
}

function SkeletonSystem:BuildGraph(model)
    if not model then return {}, nil end
    if self.GraphCache[model] and tick() - (self.GraphCache[model].time or 0) < 5 then
        return self.GraphCache[model].graph, self.GraphCache[model].torso
    end

    local graph = {}
    for _, v in ipairs(model:GetDescendants()) do
        if v:IsA("Motor6D") or v:IsA("Weld") or v:IsA("WeldConstraint") then
            local a, b = v.Part0, v.Part1
            if a and b and a:IsA("BasePart") and b:IsA("BasePart") then
                graph[a] = graph[a] or {}
                graph[b] = graph[b] or {}
                table.insert(graph[a], b)
                table.insert(graph[b], a)
            end
        end
    end

    local torso, bestScore = nil, -1
    for part, neighbors in pairs(graph) do
        if part and part:IsA("BasePart") then
            local degree = #neighbors
            local volume = math.max(0.0001, part.Size.X * part.Size.Y * part.Size.Z)
            local score = degree * 1.5 + volume * 0.0001
            if score > bestScore then
                bestScore = score
                torso = part
            end
        end
    end

    self.GraphCache[model] = { graph = graph, torso = torso, time = tick() }
    return graph, torso
end

function SkeletonSystem:GetConnectionsFromGraph(model)
    local graph, torso = self:BuildGraph(model)
    if not torso or not next(graph) then
        return self:DetectSkeletonConnectionsFallback(model)
    end

    local connections = {}
    local visited = {}
    local function bfs(start)
        local queue = {start}
        visited[start] = true
        while #queue > 0 do
            local current = table.remove(queue, 1)
            if graph[current] then
                for _, neighbor in ipairs(graph[current]) do
                    if not visited[neighbor] then
                        table.insert(connections, {current, neighbor})
                        visited[neighbor] = true
                        table.insert(queue, neighbor)
                    end
                end
            end
        end
    end
    bfs(torso)
    return connections
end

function SkeletonSystem:DetectSkeletonConnectionsFallback(model)
    if not model then return {} end
    local rigType = "Unknown"
    if model:FindFirstChild("UpperTorso") and model:FindFirstChild("LowerTorso") then
        rigType = "R15"
    elseif model:FindFirstChild("Torso") and model:FindFirstChild("Left Arm") then
        rigType = "R6"
    end

    local connections = {}
    if rigType == "R15" then
        local bones = {
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
        for _, bone in ipairs(bones) do
            local part1 = model:FindFirstChild(bone[1])
            local part2 = model:FindFirstChild(bone[2])
            if part1 and part2 then table.insert(connections, {part1, part2}) end
        end
    elseif rigType == "R6" then
        local bones = {
            {"Head", "Torso"},
            {"Torso", "Left Arm"},
            {"Torso", "Right Arm"},
            {"Torso", "Left Leg"},
            {"Torso", "Right Leg"}
        }
        for _, bone in ipairs(bones) do
            local part1 = model:FindFirstChild(bone[1])
            local part2 = model:FindFirstChild(bone[2])
            if part1 and part2 then table.insert(connections, {part1, part2}) end
        end
    end
    return connections
end

function SkeletonSystem:RenderSkeleton(model, lines, color, simplify)
    if not model or not lines then return end
    local connections = self:GetConnectionsFromGraph(model)

    if simplify then
        local simplified = {}
        for _, bone in ipairs(connections) do
            if #simplified >= 8 then break end
            table.insert(simplified, bone)
        end
        connections = simplified
    end

    local lineIndex = 1
    for _, bone in ipairs(connections) do
        if lineIndex > #lines then break end
        local part1 = bone[1]
        local part2 = bone[2]
        local line = lines[lineIndex]
        if part1 and part2 and line and part1:IsDescendantOf(workspace) and part2:IsDescendantOf(workspace) then
            local ok1, screen1 = pcall(function() return Camera:WorldToViewportPoint(part1.Position or part1.CFrame.Position) end)
            local ok2, screen2 = pcall(function() return Camera:WorldToViewportPoint(part2.Position or part2.CFrame.Position) end)
            if ok1 and ok2 and screen1.Z > 0 and screen2.Z > 0 then
                line.From = Vector2.new(screen1.X, screen1.Y)
                line.To = Vector2.new(screen2.X, screen2.Y)
                line.Color = color or Settings.SkeletonColor
                line.Thickness = 2
                line.Visible = true
                line.ZIndex = 2
                lineIndex = lineIndex + 1
            else
                line.Visible = false
            end
        elseif line then
            line.Visible = false
        end
    end

    for i = lineIndex, #lines do
        if lines[i] then lines[i].Visible = false end
    end
end

function SkeletonSystem:InitLocalPlayerSkeleton()
    for i = 1, 30 do
        local line = DrawingPool:Acquire("Line")
        if line then
            line.Thickness = 2
            line.Visible = false
            line.Color = self.LocalPlayerSkeleton.Color
            line.ZIndex = 2
            table.insert(self.LocalPlayerSkeleton.Lines, line)
        end
    end
end

function SkeletonSystem:UpdateLocalPlayerSkeleton()
    local now = tick()
    if now - self.LocalPlayerSkeleton.LastUpdate < 0.06 then return end
    self.LocalPlayerSkeleton.LastUpdate = now
    if not Settings.Drawing.LocalSkeleton then
        for _, line in ipairs(self.LocalPlayerSkeleton.Lines) do if line then line.Visible = false end end
        return
    end
    local LocalPlayer = Core.LocalPlayer
    if not LocalPlayer or not LocalPlayer.Character then return end
    self:RenderSkeleton(LocalPlayer.Character, self.LocalPlayerSkeleton.Lines, Settings.LocalSkeletonColor or self.LocalPlayerSkeleton.Color, false)
end

-- ============================================================================
-- ESP CREATION & MANAGEMENT (robust, safer, fixed highlight adornee handling)
-- ============================================================================
local function CreateDrawing(type, properties)
    local obj = DrawingPool:Acquire(type)
    if obj then
        for prop, value in pairs(properties or {}) do
            pcall(function() obj[prop] = value end)
        end
    end
    return obj
end

local ESP = {}

function ESP:CreatePlayerESP(player)
    if not Core.DrawingOK or State.DrawingESP[player] then return end

    local storage = {
        Box = CreateDrawing("Square", {Thickness = 2, Filled = false, Visible = false, ZIndex = 2, Color = Settings.BoxColor}),
        BoxOutline = CreateDrawing("Square", {Thickness = 4, Filled = false, Visible = false, ZIndex = 1, Color = Color3.new(0,0,0)}),
        Name = CreateDrawing("Text", {Size = 13, Center = true, Outline = true, Font = 2, Visible = false, ZIndex = 3, Color = Color3.new(1,1,1)}),
        Distance = CreateDrawing("Text", {Size = 12, Center = true, Outline = true, Font = 2, Visible = false, ZIndex = 3, Color = Color3.new(1,1,1)}),
        HealthBar = CreateDrawing("Square", {Filled = true, Visible = false, ZIndex = 2}),
        HealthOutline = CreateDrawing("Square", {Filled = true, Visible = false, ZIndex = 1, Color = Color3.new(0,0,0)}),
        SkeletonLines = {},
        Highlight = nil,
        _lastBoxUpdate = 0,
        _lastSkeletonUpdate = 0,
        _cachedBox = {x = 0, y = 0, w = 0, h = 0, visible = false},
    }

    -- Create highlight but keep it disabled unless needed
    local highlight
    pcall(function()
        highlight = Instance.new("Highlight")
        highlight.Name = "ForgeESP_" .. player.Name
        highlight.FillColor = Settings.HighlightFillColor or Color3.fromRGB(255,0,0)
        highlight.OutlineColor = Settings.HighlightOutlineColor or Color3.fromRGB(255,255,255)
        highlight.FillTransparency = Settings.HighlightTransparency or 0.5
        highlight.OutlineTransparency = 0
        highlight.Enabled = false
        -- Parent to CoreGui is safer for UI-related instances
        highlight.Parent = Core.CoreGui or game:GetService("CoreGui")
    end)
    storage.Highlight = highlight

    for i = 1, 30 do
        local line = CreateDrawing("Line", {Thickness = 2, Visible = false, Color = Settings.SkeletonColor, ZIndex = 2})
        if line then table.insert(storage.SkeletonLines, line) end
    end

    State.DrawingESP[player] = storage
end

function ESP:RemovePlayerESP(player)
    if not State.DrawingESP[player] then return end
    local storage = State.DrawingESP[player]

    for key, obj in pairs(storage) do
        if key:sub(1,1) ~= "_" and key ~= "SkeletonLines" and key ~= "Highlight" then
            if obj then
                local objType = nil
                if key:find("Box") then objType = "Square"
                elseif key:find("Name") or key:find("Distance") then objType = "Text"
                elseif key:find("Health") then objType = "Square" end
                if objType then DrawingPool:Release(objType, obj) end
            end
        end
    end

    for _, line in pairs(storage.SkeletonLines) do DrawingPool:Release("Line", line) end

    if storage.Highlight then
        pcall(function() storage.Highlight:Destroy() end)
    end

    State.DrawingESP[player] = nil
    SemanticEngine:ClearPlayerCache(player)
end

local function HideESP(storage)
    if not storage then return end
    if storage.Box then storage.Box.Visible = false storage.Box.Transparency = 0 end
    if storage.BoxOutline then storage.BoxOutline.Visible = false storage.BoxOutline.Transparency = 0 end
    if storage.Name then storage.Name.Visible = false end
    if storage.Distance then storage.Distance.Visible = false end
    if storage.HealthBar then storage.HealthBar.Visible = false end
    if storage.HealthOutline then storage.HealthOutline.Visible = false end
    if storage.Highlight and storage.Highlight.Enabled then storage.Highlight.Enabled = false end
    for _, line in pairs(storage.SkeletonLines) do if line then line.Visible = false end end
    storage._cachedBox = {x=0,y=0,w=0,h=0,visible=false}
end

function ESP:UpdatePlayerESP(player, storage)
    if not player or player == Core.LocalPlayer then return end
    Profiler:RecordESPUpdate()

    local data = SemanticEngine:GetCachedPlayerData(player)
    if not data or not data.isValid or not data.anchor then HideESP(storage) return end

    local camPos = Camera.CFrame.Position
    local toTarget = (data.anchor.Position - camPos)
    local distance = toTarget.Magnitude

    if distance > Settings.ESPMaxDistance then HideESP(storage) return end

    if Settings.IgnoreTeamESP then
        local sameTeam = SemanticEngine:AreSameTeam(Core.LocalPlayer, player)
        if sameTeam then HideESP(storage) return end
    end

    if data.humanoid and data.humanoid.Health and data.humanoid.Health <= 0 then HideESP(storage) return end

    -- Panic mode: extremely light rendering
    if PerformanceManager.panicLevel >= 2 then
        local visible, x, y, w, h = GetBoxFromAnchor(data.anchor, data.model, distance)
        if visible and w > 0 and h > 0 and Settings.ShowBox and storage.Box then
            storage.Box.Size = Vector2.new(w, h)
            storage.Box.Position = Vector2.new(x, y)
            storage.Box.Color = Settings.BoxColor
            storage.Box.Visible = true
        else
            HideESP(storage)
        end
        if storage.BoxOutline then storage.BoxOutline.Visible = false end
        if storage.Name then storage.Name.Visible = false end
        if storage.Distance then storage.Distance.Visible = false end
        if storage.HealthBar then storage.HealthBar.Visible = false end
        if storage.HealthOutline then storage.HealthOutline.Visible = false end
        if storage.Highlight then storage.Highlight.Enabled = false end
        for _, line in pairs(storage.SkeletonLines) do if line then line.Visible = false end end
        return
    end

    local now = tick()
    local visible, x, y, w, h
    local updateInterval = distance > 500 and 0.25 or 0.1
    if now - storage._lastBoxUpdate > updateInterval then
        visible, x, y, w, h = GetBoxFromAnchor(data.anchor, data.model, distance)
        storage._cachedBox = {x=x,y=y,w=w,h=h,visible=visible}
        storage._lastBoxUpdate = now
    else
        local cached = storage._cachedBox
        visible, x, y, w, h = cached.visible, cached.x, cached.y, cached.w, cached.h
    end

    if not visible or w <= 0 or h <= 0 then HideESP(storage) return end

    -- BOX
    if storage.Box and Settings.ShowBox then
        storage.Box.Size = Vector2.new(w, h)
        storage.Box.Position = Vector2.new(x, y)
        storage.Box.Color = Settings.BoxColor
        storage.Box.Visible = true
        if storage.BoxOutline then
            storage.BoxOutline.Size = Vector2.new(w, h)
            storage.BoxOutline.Position = Vector2.new(x, y)
            storage.BoxOutline.Visible = true
        end
    else
        if storage.Box then storage.Box.Visible = false end
        if storage.BoxOutline then storage.BoxOutline.Visible = false end
    end

    -- NAME
    if storage.Name and Settings.ShowName then
        storage.Name.Text = player.Name
        storage.Name.Position = Vector2.new(x + w/2, y - 16)
        storage.Name.Color = Settings.BoxColor or storage.Name.Color
        storage.Name.Visible = true
    else
        if storage.Name then storage.Name.Visible = false end
    end

    -- DISTANCE
    if storage.Distance and Settings.ShowDistance then
        storage.Distance.Text = math.floor(distance) .. "m"
        storage.Distance.Position = Vector2.new(x + w/2, y + h + 2)
        storage.Distance.Visible = true
    else
        if storage.Distance then storage.Distance.Visible = false end
    end

    -- HEALTH BAR
    if storage.HealthBar and Settings.ShowHealthBar and data.humanoid then
        local maxH = data.humanoid.MaxHealth or 100
        local healthPercent = math.clamp((data.humanoid.Health or 0) / maxH, 0, 1)
        local barHeight = math.clamp(h * healthPercent, 1, h)

        storage.HealthOutline.Size = Vector2.new(4, h + 2)
        storage.HealthOutline.Position = Vector2.new(x - 6, y - 1)
        storage.HealthOutline.Visible = true

        storage.HealthBar.Size = Vector2.new(2, barHeight)
        storage.HealthBar.Position = Vector2.new(x - 5, y + (h - barHeight))
        storage.HealthBar.Color = Color3.new(1 - healthPercent, healthPercent, 0)
        storage.HealthBar.Visible = true
    else
        if storage.HealthBar then storage.HealthBar.Visible = false end
        if storage.HealthOutline then storage.HealthOutline.Visible = false end
    end

    -- SKELETON
    local skeletonMaxDist = Settings.Drawing.SkeletonMaxDistance or 250
    if Settings.Drawing.Skeleton and distance <= skeletonMaxDist then
        local skeletonInterval = distance > 200 and 0.15 or 0.1
        if now - storage._lastSkeletonUpdate > skeletonInterval then
            local simplify = distance > 150
            SkeletonSystem:RenderSkeleton(data.model, storage.SkeletonLines, Settings.SkeletonColor, simplify)
            storage._lastSkeletonUpdate = now
        end
    else
        for _, line in pairs(storage.SkeletonLines) do if line then line.Visible = false end end
    end

    -- HIGHLIGHT (safe adornee assignment)
    if storage.Highlight and Settings.ShowHighlight and distance < 500 then
        local adornTarget = nil
        -- Prefer model.PrimaryPart if available
        if data.model and data.model.PrimaryPart and data.model.PrimaryPart:IsA("BasePart") then
            adornTarget = data.model.PrimaryPart
        elseif data.model and data.model:IsA("Model") then
            adornTarget = data.model
        else
            adornTarget = data.anchor
        end

        if storage.Highlight.Adornee ~= adornTarget then
            pcall(function() storage.Highlight.Adornee = adornTarget end)
        end
        if not storage.Highlight.Enabled then storage.Highlight.Enabled = true end
    elseif storage.Highlight and storage.Highlight.Enabled then
        storage.Highlight.Enabled = false
    end
end

function ESP:UpdatePlayer(player)
    if not State.DrawingESP[player] then self:CreatePlayerESP(player) end
    if State.DrawingESP[player] then self:UpdatePlayerESP(player, State.DrawingESP[player]) end
end

function ESP:CleanupAll()
    for player, _ in pairs(State.DrawingESP) do self:RemovePlayerESP(player) end
end

function ESP:Initialize()
    SkeletonSystem:InitLocalPlayerSkeleton()
    task.spawn(function()
        while wait(0.06) do
            SafeCall(function() SkeletonSystem:UpdateLocalPlayerSkeleton() end, "LocalSkeletonUpdate")
        end
    end)
end

-- Export
Core.ESP = ESP
Core.SkeletonSystem = SkeletonSystem

return ESP
