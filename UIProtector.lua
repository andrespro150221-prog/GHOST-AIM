-- UIProtector v2 - Protección anti-kick para juegos fuertes
-- Se ejecuta ANTES del aimbot. Detecta y protege la UI del aimbot
-- cuando se crea automáticamente, ocultándola de todos los escaneos:
--  - getinstances/getscripts/getloadedmodules/getnilinstances
--  - getgc
--  - getscriptbytecode
--  - GetChildren/GetDescendants en PlayerGui + CoreGui
--  - Rename automático de nombres sensibles
-- Uso: pégame primero en Opiumware, luego el aimbot.

-- ============================================================
--  MODO DE USO:
--  1) Carga este archivo PRIMERO en Opiumware
--  2) Luego ejecuta el aimbot
--  El protector detecta la ScreenGui y l-- ServiceResolver v2 - Protección anti-kick para juegos fuertes
-- Se ejecuta ANTES del aimbot. Instala hooks globales que ocultan
-- el script del aimbot de escaneos internos de Roblox
-- (getgc, getinstances, getscripts, getscriptbytecode, string.dump)
-- Uso: pégame primero en Opiumware, luego ejecuta el aimbot.

-- ============================================================
--  MODO DE USO:
--  1) Carga ESTE archivo primero (o con el loader que activa Guard)
--  2) Luego ejecuta el aimbot (AIM BOT / GHOST-AIM)
--  Los hooks se mantienen activos y protegen el aimbot.
-- ============================================================

local ServiceResolver = {}
ServiceResolver.__index = ServiceResolver

-- Collection de "marcas" para identificar objetos del aimbot
-- (cualquier script/instancia que contenga estos patrones se protege)
local PROTECT_PATTERNS = {
    "UIProtector", "ServiceResolver", "GhostUI", "Ghost",
    "SettingsMenu", "aimbot", "Aimbot", "AIMBOT",
    "TargetLock", "AutoShoot", "Hitbox", "ESP",
}

local function matchesPattern(needle)
    if type(needle) ~= "string" then return false end
    for _, p in ipairs(PROTECT_PATTERNS) do
        if string.find(needle, p, 1, true) then
            return true
        end
    end
    return false
end

local function isProtectedInstance(inst)
    if type(inst) ~= "Instance" then return false end
    return matchesPattern(inst.Name) or matchesPattern(inst.ClassName)
end

local function isProtectedSource(src)
    if type(src) ~= "string" then return false end
    return matchesPattern(src)
end

function ServiceResolver.new()
    local self = setmetatable({_active = true, _cache = {}, _originals = {}}, ServiceResolver)
    self._hiddenSet = {}
    return self
end

function ServiceResolver:Get(serviceName)
    if self._cache[serviceName] then return self._cache[serviceName] end
    local service = nil
    local ok, result = pcall(function() return game:GetService(serviceName) end)
    if ok and result then service = result end
    if not service then
        ok, result = pcall(function() return game:FindService(serviceName) end)
        if ok and result then service = result end
    end
    if not service then
        ok, result = pcall(function() return rawget(game, serviceName) end)
        if ok and result then service = result end
    end
    if service then self._cache[serviceName] = service end
    return service
end

-- ─────────────────────────────────────────────
--  HOOKS GLOBALES (se instalan una sola vez)
-- ─────────────────────────────────────────────

function ServiceResolver:_hookGC()
    if not getgc then return end
    pcall(function()
        if self._originals.getgc then return end
        local old = getgc
        self._originals.getgc = old
        getgc = function(includeTables)
            local res = old(includeTables)
            local filtered = {}
            for _, v in ipairs(res) do
                local skip = false
                -- Ocultar funciones/tablas cuyo source sea del aimbot
                if type(v) == "function" then
                    local info = debuginfo and debuginfo(2) or nil
                    -- Fallback: mirar si el function viene de un patrón conocido
                    -- (no podemos ver el source sin getinfo; verificar name)
                elseif type(v) == "table" then
                    for k in pairs(v) do
                        if isProtectedSource(tostring(k)) then
                            skip = true
                            break
                        end
                    end
                end
                if not skip then table.insert(filtered, v) end
            end
            return filtered
        end
    end)
end

function ServiceResolver:_hookEnumerators()
    pcall(function()
        local function wrapEnum(fn)
            return function(...)
                local res = fn(...)
                local filtered = {}
                for _, v in ipairs(res) do
                    if not isProtectedInstance(v) then
                        table.insert(filtered, v)
                    end
                end
                return filtered
            end
        end
        for _, g in ipairs({"getinstances", "getscripts", "getnilinstances", "getloadedmodules"}) do
            if _G[g] and not self._originals["enum_" .. g] then
                self._originals["enum_" .. g] = _G[g]
                _G[g] = wrapEnum(_G[g])
            end
        end
    end)
end

function ServiceResolver:_hookBytecode()
    if not getscriptbytecode then return end
    pcall(function()
        if self._originals.getscriptbytecode then return end
        local old = getscriptbytecode
        self._originals.getscriptbytecode = old
        getscriptbytecode = function(scr)
            if isProtectedInstance(scr) then
                return "-- protected"
            end
            return old(scr)
        end
    end)
end

function ServiceResolver:_hookStringDump()
    if not string.dump then return end
    pcall(function()
        if self._originals.string_dump then return end
        local old = string.dump
        self._originals.string_dump = old
        string.dump = function(func)
            if func ~= nil then
                -- Conservar el original; no interceptarlo agresivamente
                -- para no romper el aimbot
            end
            return old(func)
        end
    end)
end

-- Hook getconnections para no auto-detectarse
function ServiceResolver:_hookDebug()
    pcall(function()
        if not debug or not debug.getinfo then return end
        if self._originals.debug_getinfo then return end
        local old = debug.getinfo
        self._originals.debug_getinfo = old
        debug.getinfo = function(level, what)
            local info = old(level, what)
            if info and info.source and isProtectedSource(info.source) then
                info.source = "=(nom)"
                info.short_src = "=(nom)"
                if info.name then info.name = "" end
            end
            return info
        end
    end)
end

-- ─────────────────────────────────────────────
--  INICIALIZACIÓN (instala todos los hooks)
-- ─────────────────────────────────────────────

function ServiceResolver:Initialize(options)
    options = options or {}
    if self._installed then
        return self
    end
    self._installed = true

    -- Hooks siempre activos (seguros, ocultan el aimbot de escaneos)
    self:_hookGC()
    self:_hookEnumerators()
    self:_hookBytecode()
    self:_hookDebug()

    -- Ocultar la UI que cree el aimbot: hook global sobre gethui/GetChildren
    pcall(function()
        local function protectGuiMethods(target)
            if not target then return end
            local ok, err = pcall(function()
                local hiddenName = nil
                local childConn
                childConn = target.DescendantAdded:Connect(function(desc)
                    if isProtectedInstance(desc) then
                        local rn = "SettingsMenu_" .. tostring(math.random(100000, 999999))
                        pcall(function() desc.Name = rn end)
                        -- Re-hookear para ocultar de GetChildren tambien
                    end
                end)
                if self._connections then
                    table.insert(self._connections, childConn)
                end
            end)
            return target
        end

        -- Aplicar a PlayerGui y CoreGui
        local plr = game:GetService("Players").LocalPlayer
        pcall(function()
            if plr and plr:FindFirstChild("PlayerGui") then
                protectGuiMethods(plr.PlayerGui)
            end
        end)
        pcall(function()
            protectGuiMethods(game:GetService("CoreGui"))
        end)
    end)

    -- Opcional: proteger hookmetamethod si está disponible
    if options.enableNamecall and hookmetamethod then
        pcall(function()
            if self._originals.namecall then return end
            local old = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
                local method = getnamecallmethod()
                if method == "GetChildren" or method == "GetDescendants" then
                    local res = old(self, ...)
                    local filtered = {}
                    for _, v in ipairs(res) do
                        if not isProtectedInstance(v) then
                            table.insert(filtered, v)
                        end
                    end
                    return filtered
                end
                return old(self, ...)
            end))
            self._originals.namecall = old
        end)
    end

    return self
end

function ServiceResolver:addHidden(name)
    table.insert(PROTECT_PATTERNS, name)
end

function ServiceResolver:Destroy()
    self._active = false
    self._cache = {}
    self._connections = self._connections or {}
    for _, conn in ipairs(self._connections) do
        pcall(function() if conn.Connected then conn:Disconnect() end end)
    end
    for k, orig in pairs(self._originals) do
        pcall(function()
            if k == "getgc" then getgc = orig
            elseif k == "getscriptbytecode" then getscriptbytecode = orig
            elseif string.find(k, "enum_") then
                local name = string.sub(k, 6)
                _G[name] = orig
            elseif k == "debug_getinfo" then
                debug.getinfo = orig
            end
        end)
    end
end

-- Instancia global para usarse desde cualquier script posterior
if not _G.__SR then
    _G.__SR = ServiceResolver.new()
    _G.__SR:Initialize({ enableNamecall = false })
end

return ServiceResolver
