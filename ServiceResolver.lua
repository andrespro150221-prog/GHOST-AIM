-- ═══════════════════════════════════════════════════════════════
--  ServiceResolver v1.0
--  Resuelve servicios de Roblox bypassing hooks de anti-cheat
--  Compatible: Delta, Arceus X, Codex, Fluxus, PC
-- ═══════════════════════════════════════════════════════════════

local ServiceResolver = {}
ServiceResolver.__index = ServiceResolver

ServiceResolver._cache = {}
ServiceResolver._hooks = {}
ServiceResolver._active = true
ServiceResolver._originals = {}

-- Servicios que anti-cheat suele monitorear
ServiceResolver._watchedServices = {
    "Players", "RunService", "UserInputService", "TweenService",
    "VirtualUser", "CoreGui", "GuiService", "HttpService",
    "MarketplaceService", "StarterGui", "Workspace", "ReplicatedFirst",
    "ReplicatedStorage", "ServerStorage", "Lighting", "SoundService",
    "Chat", "Teams", "TestService", "Selection", "Stats",
    "PhysicsService", "PathfindingService", "CollectionService",
    "AnalyticsService", "SocialService", "TextService",
}

-- ══════════════════════════════════════════
--  UTILS
-- ══════════════════════════════════════════

function ServiceResolver:_log(msg)
    -- Silencioso en producción
end

function ServiceResolver:_randStr(len)
    local out = ""
    for _ = 1, len do
        out = out .. string.char(math.random(65, 122))
    end
    return out
end

-- ══════════════════════════════════════════
--  1. RESOLVE SEGURO — Obtén servicios sin触发 hooks
-- ══════════════════════════════════════════

function ServiceResolver:Get(serviceName)
    if self._cache[serviceName] then
        return self._cache[serviceName]
    end

    local service = nil

    -- Método 1: game:GetService normal (la mayoría de ejecutores)
    local ok, result = pcall(function()
        return game:GetService(serviceName)
    end)
    if ok and result then
        service = result
    end

    -- Método 2: game:FindService (bypassa algunos hooks)
    if not service then
        ok, result = pcall(function()
            return game:FindService(serviceName)
        end)
        if ok and result then
            service = result
        end
    end

    -- Método 3: rawget del game (bypassa __namecall)
    if not service then
        ok, result = pcall(function()
            return rawget(game, serviceName)
        end)
        if ok and result then
            service = result
        end
    end

    -- Método 4: Acceso directo por children (último recurso)
    if not service then
        for _, child in ipairs(game:GetChildren()) do
            if child.ClassName == serviceName or child.Name == serviceName then
                service = child
                break
            end
        end
    end

    if service then
        self._cache[serviceName] = service
    end

    return service
end

-- ══════════════════════════════════════════
--  2. HOOK GETSERVICE — Intercepta y filtra
-- ══════════════════════════════════════════

function ServiceResolver:HookGetService(targetGui)
    pcall(function()
        local oldGetService = game.GetService
        self._originals.gameGetService = oldGetService

        game.GetService = function(self, name, ...)
            local service = oldGetService(self, name, ...)

            -- Si alguien pide CoreGui y tenemos un GUI protegido,filtrar
            if name == "CoreGui" and targetGui and service then
                local filtered = {}
                for _, child in ipairs(service:GetChildren()) do
                    if child ~= targetGui then
                        table.insert(filtered, child)
                    end
                end
                -- Retorna un proxy que filtra nuestro GUI
                local proxy = newproxy(true)
                local mt = getmetatable(proxy)
                mt.__index = function(_, key)
                    if key == "GetChildren" then
                        return function()
                            return filtered
                        end
                    elseif key == "GetDescendants" then
                        return function()
                            local desc = {}
                            for _, child in ipairs(filtered) do
                                for _, d in ipairs(child:GetDescendants()) do
                                    table.insert(desc, d)
                                end
                            end
                            return desc
                        end
                    elseif key == "FindFirstChild" then
                        return function(_, name)
                            for _, child in ipairs(filtered) do
                                if child.Name == name then return child end
                            end
                            return nil
                        end
                    elseif key == "IsA" then
                        return function(_, className)
                            return className == "ServiceProvider" or className == "Instance"
                        end
                    elseif key == "ClassName" then
                        return "CoreGui"
                    elseif key == "Name" then
                        return "CoreGui"
                    end
                    return service[key]
                end
                mt.__tostring = function() return "CoreGui" end
                return proxy
            end

            return service
        end
    end)
end

-- ══════════════════════════════════════════
--  3. HOOK NAMECALL — Bypass __namecall hooks
-- ══════════════════════════════════════════

function ServiceResolver:HookNamecall(targetGui)
    pcall(function()
        if not hookmetamethod then return end

        local oldNamecall
        oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
            local method = getnamecallmethod and getnamecallmethod() or ""
            local args = {...}

            -- Si piden CoreGui y tenemos GUI protegido
            if method == "GetService" and args[1] == "CoreGui" and targetGui then
                local service = oldNamecall(self, ...)
                return service
            end

            -- Filtra GetChildren/GetDescendants del CoreGui
            if (method == "GetChildren" or method == "GetDescendants") and targetGui then
                local isCoreGui = false
                pcall(function()
                    isCoreGui = self == game:GetService("CoreGui")
                end)
                if isCoreGui then
                    local result = oldNamecall(self, ...)
                    local filtered = {}
                    for _, v in ipairs(result) do
                        if v ~= targetGui and not v:IsDescendantOf(targetGui) then
                            table.insert(filtered, v)
                        end
                    end
                    return filtered
                end
            end

            return oldNamecall(self, ...)
        end)
    end)
end

-- ══════════════════════════════════════════
--  4. HOOK GC — Oculta objetos del garbage collector
-- ══════════════════════════════════════════

function ServiceResolver:HookGC(filterFunc)
    pcall(function()
        if not getgc then return end

        local oldGetGc = getgc
        self._originals.getgc = oldGetGc

        getgc = function(instancesOnly)
            local result = oldGetGc(instancesOnly)
            if type(result) == "table" and filterFunc then
                local filtered = {}
                for _, v in ipairs(result) do
                    if not filterFunc(v) then
                        table.insert(filtered, v)
                    end
                end
                return filtered
            end
            return result
        end
    end)
end

-- ══════════════════════════════════════════
--  5. HOOK BYTECODE — Oculta bytecode de scripts
-- ══════════════════════════════════════════

function ServiceResolver:HookBytecode(filterFunc)
    pcall(function()
        if not getscriptbytecode then return end

        local oldBytecode = getscriptbytecode
        self._originals.getscriptbytecode = oldBytecode

        getscriptbytecode = function(script)
            if filterFunc and filterFunc(script) then
                return self:_randStr(math.random(200, 600))
            end
            return oldBytecode(script)
        end
    end)
end

-- ══════════════════════════════════════════
--  6. HOOK DEBUG — Oculta source info
-- ══════════════════════════════════════════

function ServiceResolver:HookDebug(patterns)
    pcall(function()
        if not debug or not debug.getinfo then return end

        local oldGetInfo = debug.getinfo
        self._originals.debugGetInfo = oldGetInfo

        debug.getinfo = function(obj, what)
            local info = oldGetInfo(obj, what)
            if info and info.short_src then
                for _, pattern in ipairs(patterns or {}) do
                    if string.find(info.short_src, pattern) then
                        info.short_src = "="
                        info.source = "=builtin"
                        info.name = "tick"
                        break
                    end
                end
            end
            return info
        end
    end)
end

-- ══════════════════════════════════════════
--  7. HOOK STRING.DUMP — Protege contra dumpers
-- ══════════════════════════════════════════

function ServiceResolver:HookStringDump(filterFunc)
    pcall(function()
        if not hookfunction then return end

        local oldDump = string.dump
        self._originals.stringDump = oldDump

        string.dump = function(func, strip)
            if filterFunc and filterFunc(func) then
                return self:_randStr(math.random(100, 400))
            end
            return oldDump(func, strip)
        end
    end)
end

-- ══════════════════════════════════════════
--  8. INITIALIZE — Configura todo de una vez
-- ══════════════════════════════════════════

function ServiceResolver:Initialize(targetGui, config)
    config = config or {}

    if config.hookGetService ~= false then
        self:HookGetService(targetGui)
    end

    if config.hookNamecall ~= false then
        self:HookNamecall(targetGui)
    end

    if config.hookGC ~= false then
        self:HookGC(function(v)
            return (typeof(v) == "table" and v._gui == targetGui)
        end)
    end

    if config.hookBytecode ~= false then
        self:HookBytecode(function(script)
            return typeof(script) == "Instance" and script:IsDescendantOf(targetGui)
        end)
    end

    if config.hookDebug ~= false then
        self:HookDebug({"Flow", "UIService", "AimLock", "GHOST"})
    end

    if config.hookStringDump ~= false then
        self:HookStringDump(function(func)
            local ok, info = pcall(debug.getinfo, func)
            return ok and info and info.source and
                (string.find(info.source, "UIService") or string.find(info.source, "Flow"))
        end)
    end
end

-- ══════════════════════════════════════════
--  9. DESTROY — Restaura todo
-- ══════════════════════════════════════════

function ServiceResolver:Destroy()
    self._active = false

    pcall(function()
        if self._originals.gameGetService then
            game.GetService = self._originals.gameGetService
        end
    end)
    pcall(function()
        if self._originals.getgc then
            getgc = self._originals.getgc
        end
    end)
    pcall(function()
        if self._originals.getscriptbytecode then
            getscriptbytecode = self._originals.getscriptbytecode
        end
    end)
    pcall(function()
        if self._originals.debugGetInfo then
            debug.getinfo = self._originals.debugGetInfo
        end
    end)
    pcall(function()
        if self._originals.stringDump then
            string.dump = self._originals.stringDump
        end
    end)

    self._originals = {}
    self._cache = {}
end

return ServiceResolver
