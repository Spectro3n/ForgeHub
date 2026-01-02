-- ============================================================================
-- FORGEHUB - AIMBOT UTILS v4.3
-- Helpers e funções utilitárias
-- ============================================================================

local Utils = {}

-- ============================================================================
-- CACHE
-- ============================================================================
local CameraCache = {ref = nil, lastUpdate = 0}
local mathMax = math.max
local mathMin = math.min
local mathAbs = math.abs
local mathSqrt = math.sqrt
local mathRandom = math.random
local mathClamp = math.clamp
local mathCos = math.cos
local mathRad = math.rad

-- ============================================================================
-- CAMERA
-- ============================================================================
function Utils.GetCamera()
    local now = tick()
    if now - CameraCache.lastUpdate > 0.05 or not CameraCache.ref then
        CameraCache.ref = workspace.CurrentCamera
        CameraCache.lastUpdate = now
    end
    return CameraCache.ref
end

function Utils.InvalidateCameraCache()
    CameraCache.lastUpdate = 0
end

-- ============================================================================
-- SAFE CALL
-- ============================================================================
function Utils.SafeCall(func, name)
    local success, err = pcall(func)
    if not success then
        warn("[Aimbot] Erro em " .. (name or "unknown") .. ": " .. tostring(err))
    end
    return success, err
end

-- ============================================================================
-- MATH HELPERS
-- ============================================================================
function Utils.Clamp(value, min, max)
    return mathMax(min, mathMin(max, value))
end

function Utils.RandomChance(percent)
    return mathRandom(1, 100) <= percent
end

function Utils.DistanceSquared(pos1, pos2)
    local delta = pos1 - pos2
    return delta.X * delta.X + delta.Y * delta.Y + delta.Z * delta.Z
end

function Utils.Distance(pos1, pos2)
    return mathSqrt(Utils.DistanceSquared(pos1, pos2))
end

function Utils.Lerp(a, b, t)
    return a + (b - a) * t
end

function Utils.LerpVector3(a, b, t)
    return Vector3.new(
        Utils.Lerp(a.X, b.X, t),
        Utils.Lerp(a.Y, b.Y, t),
        Utils.Lerp(a.Z, b.Z, t)
    )
end

-- ============================================================================
-- FOV HELPERS (CORRIGIDO)
-- ============================================================================
function Utils.CalculateFOVCosThreshold(fovDegrees)
    local halfRad = mathRad(fovDegrees * 0.5)
    return mathCos(halfRad)
end

function Utils.IsInFOVAngle(camLook, dirToTarget, fovDegrees)
    local cosThreshold = Utils.CalculateFOVCosThreshold(fovDegrees)
    local dot = camLook:Dot(dirToTarget)
    return dot >= cosThreshold
end

function Utils.GetScreenDistanceSquared(screenPos, mousePos)
    local dx = screenPos.X - mousePos.X
    local dy = screenPos.Y - mousePos.Y
    return dx * dx + dy * dy
end

-- ============================================================================
-- POSITION VALIDATION (CORRIGIDO - evita mirar no chão)
-- ============================================================================
function Utils.IsValidAimPosition(position, settings)
    if not position then return false end
    if typeof(position) ~= "Vector3" then return false end
    
    -- Verifica valores NaN ou infinitos
    if position.X ~= position.X or position.Y ~= position.Y or position.Z ~= position.Z then
        return false
    end
    
    local Camera = Utils.GetCamera()
    if Camera then
        local camY = Camera.CFrame.Position.Y
        local minHeight = settings and settings.MinAimHeightBelowCamera or 50
        
        -- Se a posição está muito abaixo da câmera, provavelmente é inválida (chão)
        if position.Y < camY - minHeight then
            return false
        end
    end
    
    return true
end

-- Validação adicional com referência ao player local
function Utils.IsValidAimPositionAdvanced(position, settings, localCharacter)
    if not Utils.IsValidAimPosition(position, settings) then
        return false
    end
    
    -- Compara com a posição do HumanoidRootPart local
    if localCharacter then
        local hrp = localCharacter:FindFirstChild("HumanoidRootPart")
        if hrp then
            local localY = hrp.Position.Y
            local threshold = settings and settings.MinAimHeightBelowCamera or 50
            
            -- Se muito abaixo do player local, pode ser chão
            if position.Y < localY - threshold then
                return false
            end
        end
    end
    
    return true
end

-- ============================================================================
-- VISIBILITY CACHE
-- ============================================================================
local VisibilityCache = {
    Data = {},
    Frame = 0,
    MaxAge = 4,
    CleanupInterval = 5,
}

function VisibilityCache:NextFrame()
    self.Frame = self.Frame + 1
    
    if self.Frame % self.CleanupInterval == 0 then
        local toRemove = {}
        local maxAge = self.MaxAge
        local currentFrame = self.Frame
        
        for key, data in pairs(self.Data) do
            if currentFrame - data.frame > maxAge then
                toRemove[#toRemove + 1] = key
            end
        end
        
        for i = 1, #toRemove do
            self.Data[toRemove[i]] = nil
        end
    end
end

function VisibilityCache:Get(player)
    local data = self.Data[player]
    if data and (self.Frame - data.frame) <= self.MaxAge then
        return data.visible, data.part, true
    end
    return nil, nil, false
end

function VisibilityCache:Set(player, visible, part)
    self.Data[player] = {visible = visible, part = part, frame = self.Frame}
end

function VisibilityCache:Clear()
    self.Data = {}
    self.Frame = 0
end

function VisibilityCache:Invalidate(player)
    self.Data[player] = nil
end

Utils.VisibilityCache = VisibilityCache

-- ============================================================================
-- RAYCAST PARAMS MANAGER
-- ============================================================================
local RayParamsManager = {
    Params = nil,
    LastUpdate = 0,
    UpdateInterval = 0.5,
}

function RayParamsManager:Initialize()
    self.Params = RaycastParams.new()
    self.Params.FilterType = Enum.RaycastFilterType.Exclude
    self.Params.FilterDescendantsInstances = {}
end

function RayParamsManager:Update(localPlayer, camera)
    local now = tick()
    if now - self.LastUpdate < self.UpdateInterval then return end
    
    self.LastUpdate = now
    
    if not self.Params then
        self:Initialize()
    end
    
    local filter = {camera}
    if localPlayer and localPlayer.Character then
        table.insert(filter, localPlayer.Character)
    end
    
    self.Params.FilterDescendantsInstances = filter
end

function RayParamsManager:Get()
    if not self.Params then
        self:Initialize()
    end
    return self.Params
end

Utils.RayParamsManager = RayParamsManager

-- ============================================================================
-- PART CACHE
-- ============================================================================
local PartCache = {}
local PartCacheTime = {}

local PART_NAMES = {
    "Head", "UpperTorso", "Torso", "HumanoidRootPart", "LowerTorso",
    "LeftUpperArm", "RightUpperArm", "LeftUpperLeg", "RightUpperLeg",
    "Left Arm", "Right Arm", "Left Leg", "Right Leg", "Neck"
}

local PART_MAP = {
    Head = {"Head"},
    Torso = {"UpperTorso", "Torso"},
    Root = {"HumanoidRootPart"},
    HumanoidRootPart = {"HumanoidRootPart"},
    UpperTorso = {"UpperTorso", "Torso"},
    LowerTorso = {"LowerTorso", "Torso"},
    LeftArm = {"LeftUpperArm", "Left Arm"},
    RightArm = {"RightUpperArm", "Right Arm"},
    LeftLeg = {"LeftUpperLeg", "Left Leg"},
    RightLeg = {"RightUpperLeg", "Right Leg"},
    Neck = {"Neck", "Head"},
    Chest = {"UpperTorso", "Torso"},
}

local PartPriorityMap = {
    Head = 1,
    UpperTorso = 2,
    Torso = 2,
    HumanoidRootPart = 3,
    LowerTorso = 4,
    LeftUpperArm = 5,
    RightUpperArm = 5,
    LeftUpperLeg = 6,
    RightUpperLeg = 6,
}

function Utils.BuildPartCacheFor(player)
    local char = player.Character
    if not char then 
        PartCache[player] = nil
        return 
    end
    
    local map = {}
    for i = 1, #PART_NAMES do
        local name = PART_NAMES[i]
        local p = char:FindFirstChild(name, true)
        if p and p:IsA("BasePart") then 
            map[name] = p 
        end
    end
    
    map._humanoid = char:FindFirstChildOfClass("Humanoid")
    map._anchor = map.HumanoidRootPart or map.Torso or map.Head
    map._model = char
    
    PartCache[player] = map
    PartCacheTime[player] = tick()
end

function Utils.GetCachedPart(player, partName)
    local cache = PartCache[player]
    if cache then
        return cache[partName]
    end
    return nil
end

function Utils.GetPartCache(player)
    return PartCache[player]
end

function Utils.InvalidatePartCache(player)
    PartCache[player] = nil
    PartCacheTime[player] = nil
end

function Utils.IsPartCacheValid(player)
    local cache = PartCache[player]
    if not cache then return false end
    
    local anchor = cache._anchor
    if not anchor then return false end
    if not anchor.Parent then return false end
    if not anchor:IsDescendantOf(workspace) then return false end
    
    local humanoid = cache._humanoid
    if humanoid and humanoid.Health <= 0 then return false end
    
    return true
end

function Utils.ClearAllPartCache()
    PartCache = {}
    PartCacheTime = {}
end

Utils.PART_MAP = PART_MAP
Utils.PART_NAMES = PART_NAMES
Utils.PartPriorityMap = PartPriorityMap

-- ============================================================================
-- PLAYER DATA HELPER
-- ============================================================================
local PlayerDataCache = {}
local PLAYER_DATA_CACHE_TTL = 0.1

function Utils.GetPlayerData(player, semanticEngine)
    if not player then return nil end
    
    local now = tick()
    local cached = PlayerDataCache[player]
    
    if cached and (now - cached.time) < PLAYER_DATA_CACHE_TTL then
        if cached.data and cached.data.isValid then
            local anchor = cached.data.anchor
            if anchor and anchor.Parent and anchor:IsDescendantOf(workspace) then
                local hum = cached.data.humanoid
                if not hum or hum.Health > 0 then
                    return cached.data
                end
            end
        end
        PlayerDataCache[player] = nil
    end
    
    -- Usa PartCache primeiro
    if Utils.IsPartCacheValid(player) then
        local partCache = PartCache[player]
        local anchor = partCache._anchor
        local humanoid = partCache._humanoid
        
        local data = {
            isValid = true,
            model = partCache._model,
            anchor = anchor,
            humanoid = humanoid,
            health = humanoid and humanoid.Health or 100,
            maxHealth = humanoid and humanoid.MaxHealth or 100,
        }
        PlayerDataCache[player] = {data = data, time = now}
        return data
    end
    
    -- Fallback para SemanticEngine
    if semanticEngine and semanticEngine.GetCachedPlayerData then
        local data = semanticEngine:GetCachedPlayerData(player)
        if data and data.isValid then
            if data.anchor and data.anchor.Parent and data.anchor:IsDescendantOf(workspace) then
                if not data.humanoid or data.humanoid.Health > 0 then
                    PlayerDataCache[player] = {data = data, time = now}
                    return data
                end
            end
        end
    end
    
    -- Fallback manual
    local character = player.Character
    if not character then return nil end
    
    local anchor = character:FindFirstChild("HumanoidRootPart")
                or character:FindFirstChild("Torso")
                or character:FindFirstChild("Head")
    
    if not anchor or not anchor.Parent or not anchor:IsDescendantOf(workspace) then 
        return nil 
    end
    
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    
    if humanoid and humanoid.Health <= 0 then
        return nil
    end
    
    local data = {
        isValid = true,
        model = character,
        anchor = anchor,
        humanoid = humanoid,
        health = humanoid and humanoid.Health or 100,
        maxHealth = humanoid and humanoid.MaxHealth or 100,
    }
    
    PlayerDataCache[player] = {data = data, time = now}
    Utils.BuildPartCacheFor(player)
    
    return data
end

function Utils.InvalidatePlayerData(player)
    PlayerDataCache[player] = nil
    Utils.InvalidatePartCache(player)
    VisibilityCache:Invalidate(player)
end

function Utils.ClearPlayerDataCache()
    PlayerDataCache = {}
end

-- ============================================================================
-- TEAM CHECK
-- ============================================================================
local TeamCache = {}
local TEAM_CACHE_TTL = 1

function Utils.AreSameTeam(player1, player2, semanticEngine)
    if not player1 or not player2 then return false end
    
    local cacheKey = tostring(player1.UserId) .. "_" .. tostring(player2.UserId)
    local now = tick()
    local cached = TeamCache[cacheKey]
    
    if cached and (now - cached.time) < TEAM_CACHE_TTL then
        return cached.result
    end
    
    local result = false
    
    if semanticEngine and semanticEngine.AreSameTeam then
        local success, res = pcall(function()
            return semanticEngine:AreSameTeam(player1, player2)
        end)
        if success then 
            result = res 
        end
    else
        if player1.Team and player2.Team then
            result = player1.Team == player2.Team
        end
    end
    
    TeamCache[cacheKey] = {result = result, time = now}
    return result
end

function Utils.ClearTeamCache()
    TeamCache = {}
end

-- ============================================================================
-- WEAPON DETECTION
-- ============================================================================
local WEAPON_KEYWORDS = {
    shoot = true, fire = true, bullet = true, gun = true, 
    weapon = true, damage = true, hit = true, attack = true
}

local BULLET_KEYWORDS = {
    bullet = true, projectile = true, shot = true, missile = true, arrow = true
}

function Utils.IsWeaponRemote(name)
    local lowerName = name:lower()
    for keyword in pairs(WEAPON_KEYWORDS) do
        if lowerName:find(keyword) then
            return true
        end
    end
    return false
end

function Utils.IsBullet(name)
    local lowerName = name:lower()
    for keyword in pairs(BULLET_KEYWORDS) do
        if lowerName:find(keyword) then
            return true
        end
    end
    return false
end

-- ============================================================================
-- DEBUG
-- ============================================================================
function Utils.Debug()
    print("\n═══════════ UTILS DEBUG ═══════════")
    print("PartCache entries: " .. Utils.TableLength(PartCache))
    print("PlayerDataCache entries: " .. Utils.TableLength(PlayerDataCache))
    print("TeamCache entries: " .. Utils.TableLength(TeamCache))
    print("VisibilityCache frame: " .. VisibilityCache.Frame)
    print("════════════════════════════════════\n")
end

function Utils.TableLength(t)
    local count = 0
    for _ in pairs(t) do count = count + 1 end
    return count
end

return Utils