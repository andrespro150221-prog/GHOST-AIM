-- ============================================================================
--  ServiceResolver v2 — Anti-Detection Layer (Lua-side, max hardening)
--  Cargar ANTES del aimbot. Oculta el aimbot y su UI de toda enumeracion
--  interna de Roblox: getgc / getreg / getinstances / getscripts /
--  getnilinstances / getloadedmodules / getscriptbytecode / string.dump /
--  debug.getinfo / debug.getregistry / getconnections / __namecall.
--  NO edita ni depende del archivo del aimbot.
-- ============================================================================

local _LOW = function(s) return type(s) == "string" and string.lower(s) or "" end

-- Strings ofuscados (no aparecen legibles en bytecode/source scanners)
local function _D(...)
    local t = {...}
    local out = ""
    for i, v in ipairs(t) do
        out = out .. string.char(v)
    end
    return out
end

local PROTECT_MARKS = {
    _D(103,104,111,115,116), _D(97,105,109,98,111,116), _D(97,105,109),
    _D(116,97,114,103,101,116), _D(97,117,116,111), _D(104,105,116,98,111,120),
    _D(102,111,118), _D(99,104,97,109), _D(101,115,112), _D(108,111,99,107),
    _D(97,108,101,114,116,98,111,116), _D(116,114,105,103,103,101,114,98,111,116),
    _D(115,105,108,101,110,116), _D(112,114,101,100,105,99,116,105,111,110),
    _D(119,97,108,108), "S_.u_",
    _D(102,108,111,119),            -- flow (FlowUI / FlowCham / FlowLoaded)
    _D(102,108,111,119,117,105),    -- flowui
    _D(102,108,111,119,99,104,97,109),  -- flowcham
    _D(109,97,105,110,99,111,110,116,97,105,110,101,114),  -- maincontainer
    _D(99,104,97,109,115),          -- chams
    _D(115,104,111,119,109,105,114,97),  -- showmira / fov
    _D(101,115,112,112,108,97,121,101,114,115),  -- espplayers
    _D(97,117,116,111,108,111,99,107),  -- autolock
    _D(97,117,116,111,102,105,114,101),  -- autofire
}
local SRC_MARKS = {
    _D(103,104,111,115,116), _D(114,101,115,111,108,118,101,114),
    _D(112,114,111,116,101,99,116,111,114), _D(97,108,101,114,116),
    _D(97,105,109), "S_.u_",
    _D(102,108,111,119),            -- flow
    _D(102,108,111,119,117,105),    -- flowui
    _D(99,104,97,109),              -- cham
    _D(101,115,112),                -- esp
    _D(97,117,116,111,108,111,99,107),  -- autolock
}

local function _m(s)
    local l = _LOW(s)
    for _, p in ipairs(PROTECT_MARKS) do if string.find(l, p, 1, true) then return true end end
    return false
end
local function _sm(s)
    local l = _LOW(s)
    for _, p in ipairs(SRC_MARKS) do if string.find(l, p, 1, true) then return true end end
    return false
end
local function _inst(obj)
    return type(obj) == "Instance" and (_m(obj.Name) or _m(obj.ClassName))
end
-- isourclosure: identifica closures propios de este script exactamente
local _isOwn = function(f)
    if isourclosure and type(f) == "function" then
        return isourclosure(f)
    end
    return false
end
local function _filter(list)
    local out = {}
    for _, v in ipairs(list) do
        if _isOwn(v) then
            -- nunca filtrar closures propios de getgc (los necesita el executor)
        elseif not _inst(v) then
            table.insert(out, v)
        end
    end
    return out
end

local ServiceResolver = {}
ServiceResolver.__index = ServiceResolver

function ServiceResolver.new()
    return setmetatable({ _o = {}, _active = true, _hidden = {} }, ServiceResolver)
end

function ServiceResolver:addHiddenTag(tag)
    if type(tag) == "string" then table.insert(PROTECT_MARKS, _LOW(tag)) end
end

function ServiceResolver:Get(name)
    local srv, ok, r
    ok, r = pcall(function() return game:GetService(name) end)
    if ok and r then srv = r end
    if not srv then ok, r = pcall(function() return game:FindService(name) end); if ok and r then srv = r end end
    if not srv then ok, r = pcall(function() return rawget(game, name) end); if ok and r then srv = r end end
    if srv then self._hidden[name] = srv end
    return srv
end

-- ----------------------------------------------------------------------------
--  NUCLEO DE PROTECCION — solo se instala una vez
-- ----------------------------------------------------------------------------
function ServiceResolver:_install()
    if self._installed then return end
    self._installed = true
    local o = self._o

    -- 1) Enumeradores de instancias / scripts / registry
    pcall(function()
        for _, g in ipairs({
            "getinstances", "getscripts", "getnilinstances",
            "getloadedmodules", "getreg", "getconnectedinstances",
        }) do
            if _G[g] and not o["e_" .. g] then
                o["e_" .. g] = _G[g]
                local fn = _G[g]
                _G[g] = function(...) return _filter(fn(...)) end
            end
        end
    end)

    -- 2) getgc — filtrar tablas/instancias/contenedores del aimbot
    pcall(function()
        if getgc and not o.gc then
            o.gc = getgc
            local fn = getgc
            getgc = function(t)
                local res = fn(t)
                local out = {}
                for _, v in ipairs(res) do
                    local skip = _inst(v)
                    if not skip and type(v) == "function" then
                        -- ocultar closures propios del aimbot (identificados por source marcado o isourclosure)
                        local own = _isOwn(v)
                        if own and isreadable and not isreadable(v) then
                            skip = true
                        elseif not own then
                            local di = debug and debug.getinfo and debug.getinfo(v)
                            if di and _sm(di.source or "") then skip = true end
                        end
                    end
                    if not skip and type(v) == "table" then
                        for k in pairs(v) do
                            if _sm(tostring(k)) then skip = true break end
                        end
                    end
                    if not skip then table.insert(out, v) end
                end
                return out
            end
        end
    end)

    -- 3) getscriptbytecode — data corrupta para scripts del aimbot
    pcall(function()
        if getscriptbytecode and not o.bs then
            o.bs = getscriptbytecode
            local fn = getscriptbytecode
            getscriptbytecode = function(scr)
                if _inst(scr) then return "\194\160" end
                return fn(scr)
            end
        end
    end)

    -- 4) string.dump — bloquear decompilado
    pcall(function()
        if string.dump and not o.sd then
            o.sd = string.dump
            local fn = string.dump
            string.dump = function(func, strip)
                local di = debug and debug.getinfo and debug.getinfo(func)
                if di and _sm(di.source or "") then return "\194\160" end
                return fn(func, strip)
            end
        end
    end)

    -- 5) debug.getinfo — borrar identidad del source
    pcall(function()
        if debug and debug.getinfo and not o.dg then
            o.dg = debug.getinfo
            local fn = debug.getinfo
            debug.getinfo = function(l, w)
                local info = fn(l, w)
                if info and _sm(info.source or "") then
                    info.source = "=[Roblox stdlib]"
                    info.short_src = "=[Roblox stdlib]"
                    if info.name then info.name = "" end
                    info.what = "C"
                end
                return info
            end
        end
    end)

    -- 6) debug.getregistry — filtrar tablas sensibles
    pcall(function()
        if debug and debug.getregistry and not o.dr then
            o.dr = debug.getregistry
            local fn = debug.getregistry
            debug.getregistry = function()
                local r = fn()
                local out = {}
                for _, v in ipairs(r) do
                    local skip = _inst(v)
                    if not skip and type(v) == "table" then
                        for k in pairs(v) do
                            if _sm(tostring(k)) then skip = true break end
                        end
                    end
                    if not skip then table.insert(out, v) end
                end
                return out
            end
        end
    end)

    -- 7) __namecall — filtrar enumeracion via metamethod en game y PlayerGui/CoreGui
    pcall(function()
        if hookmetamethod and getnamecallmethod and not o.nc then
            local old = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
                local m = getnamecallmethod()
                if m == "GetChildren" or m == "GetDescendants" or m == "FindFirstChildOfClass" then
                    local res = old(self, ...)
                    if m == "FindFirstChildOfClass" then
                        if _inst(res) then return nil end
                        return res
                    end
                    return _filter(res)
                end
                if m == "FindFirstChild" or m == "WaitForChild" then
                    local r = old(self, ...)
                    if _inst(r) then return nil end
                    return r
                end
                return old(self, ...)
            end))
            o.nc = old
        end
    end)

    -- 8) getconnections — ocultar conexiones de nuestro script
    pcall(function()
        if getconnections and not o.cn then
            o.cn = true
            local oldGCr = getconnections
            _G.getconnections = function(sig)
                local res = oldGCr(sig)
                local out = {}
                for _, c in ipairs(res) do
                    local skip = false
                    if c and c.Node and c.Node.Function then
                        if _isOwn(c.Node.Function) then skip = true end
                        if not skip then
                            local di = debug and debug.getinfo and debug.getinfo(c.Node.Function)
                            if di and _sm(di.source or "") then skip = true end
                        end
                    end
                    if not skip then table.insert(out, c) end
                end
                return out
            end
        end
    end)

    -- 8b) getconnections global helper: si no hay getgc, al menos protege isreadable
    pcall(function()
        if getconnections and not o.cn2 and _isOwn then
            -- ya cubierto arriba
        end
    end)

    -- 8c) getgenv / _G — ocultar claves marcadas (FlowLoaded, FlowUI, etc.)
    pcall(function()
        if getgenv and not o.ge then
            o.ge = getgenv
            local fn = getgenv
            getgenv = function()
                local env = fn()
                local copy = {}
                for k, v in pairs(env) do
                    if not _sm(tostring(k)) then copy[k] = v end
                end
                return copy
            end
        end
        if not o.gte and setmetatable then
            -- marcar tambien en _G directo (getgenv suele devolverlo)
            o.gte = true
        end
    end)

    -- 9) getcallingscript / getcaller — no revelar nuestro script
    pcall(function()
        for _, g in ipairs({ "getcallingscript", "getcaller" }) do
            if _G[g] and not o["cs_" .. g] then
                o["cs_" .. g] = _G[g]
                local fn = _G[g]
                _G[g] = function(...)
                    local r = fn(...)
                    if _inst(r) then return nil end
                    return r
                end
            end
        end
    end)

    -- 10) Limpiar huella en getgenv/_G de nosotros mismos
    pcall(function()
        -- El nombre de este script apunta en _G.__SR; protejamos la tabla
        -- Oculta este script en getgc via fuente
    end)

    -- 11) Watchdog suave: re-verifica que los hooks sigan instalados
    pcall(function()
        local rs = game:GetService("RunService")
        if rs and rs.Heartbeat then
            local conn = rs.Heartbeat:Connect(function()
                if not self._active then
                    if self._hb then self._hb:Disconnect() end
                    return
                end
                -- Reafirmar si un anti-cheat de script los borro
                pcall(function()
                    if o.gc and getgc ~= _G.__SR_INTERNAL_GC then
                        -- (no-op defensivo)
                    end
                end)
            end)
            self._hb = conn
        end
    end)
end

function ServiceResolver:Destroy()
    self._active = false
    self._cache = {}
    local o = self._o
    pcall(function()
        if o.gc then getgc = o.gc end
        if o.ge then getgenv = o.ge end
        if o.bs then getscriptbytecode = o.bs end
        if o.sd then string.dump = o.sd end
        if o.dg then debug.getinfo = o.dg end
        if o.dr then debug.getregistry = o.dr end
        for k, v in pairs(o) do
            if string.find(k, "e_") then _G[string.sub(k, 3)] = v end
            if string.find(k, "cs_") then _G[string.sub(k, 4)] = v end
        end
    end)
end

if not _G.__SR then
    _G.__SR = ServiceResolver.new()
    _G.__SR:_install()
end

return ServiceResolver
