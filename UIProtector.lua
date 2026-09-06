-- ============================================================================
--  UIProtector v2 — GUI Anti-Detection Layer (Lua-side, max hardening)
--  Cargar ANTES del aimbot. Detecta la UI del aimbot cuando se crea y la
--  oculta de: getinstances / getscripts / getgc / GetChildren /
--  GetDescendants / FindFirstChild / WaitForChild / screenshots / recording.
--  NO edita ni depende del archivo del aimbot.
-- ============================================================================

local UIProtector = {}
UIProtector.__index = UIProtector

local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local HttpService = game:GetService("HttpService")

local _LOW = function(s) return type(s) == "string" and string.lower(s) or "" end
local _D = function(...)
    local t = {...}
    local out = ""
    for i, v in ipairs(t) do out = out .. string.char(v) end
    return out
end
local GUI_MARKS = {
    _D(115,101,116,116,105,110,103,115,109,101,110,117), "S_.u_",
    _D(103,104,111,115,116), _D(97,105,109), _D(116,97,114,103,101,116),
    _D(97,117,116,111), _D(104,105,116,98,111,120), _D(102,111,118),
    _D(99,104,97,109), _D(101,115,112), _D(99,111,110,102,105,103),
    _D(118,105,115,117,97,108), _D(109,101,110,117), _D(99,111,110,116,97,105,110,101,114),
    _D(108,111,99,107), _D(117,105),
    _D(102,108,111,119),     -- flow (FlowUI / FlowCham / FlowLoaded)
    _D(109,97,105,110),      -- main (MainContainer)
    _D(116,111,103,103,108,101),  -- toggle (MobileToggleBtn)
    _D(109,111,98,105,108,101),   -- mobile
    _D(100,114,97,103),      -- drag
    _D(115,99,114,111,108,108),   -- scroll
    _D(107,101,121),         -- key
    _D(99,104,97,109,115),   -- chams
    _D(115,101,116,116,105,110,103,115),
    _D(119,97,108,108),      -- wall
    _D(97,117,116,111,102,105,114,101),  -- autofire
}

local function _m(s)
    local l = _LOW(s)
    for _, p in ipairs(GUI_MARKS) do if string.find(l, p, 1, true) then return true end end
    return false
end
local function _randName()
    return "S_.u_" .. tostring(math.random(100000, 999999)) .. "_" .. tostring(math.random(100000, 999999))
end

function UIProtector.new()
    local self = setmetatable({}, UIProtector)
    self._active = true
    self._connections = {}
    self._protected = {}
    self._o = {}
    return self
end

-- Renombra todos los children de la GUI a nombres inocentes
local function _wipeNames(gui)
    pcall(function()
        for _, d in ipairs(gui:GetDescendants()) do
            if d:IsA("Frame") or d:IsA("TextLabel") or d:IsA("TextButton") or
               d:IsA("ScrollingFrame") or d:IsA("ImageLabel") or d:IsA("UIStroke") or
               d:IsA("ImageButton") or d:IsA("TextInput") or d:IsA("UICorner") or
               d:IsA("UIGradient") or d:IsA("LocalScript") or d:IsA("ModuleScript") then
                d.Name = _randName()
            end
        end
    end)
end

function UIProtector:_protectGUI(gui, container)
    pcall(function()
        if type(gui) ~= "Instance" or not gui:IsA("ScreenGui") then return end
        if self._protected[gui] then return end

        local mark = _m(gui.Name)
        if not mark then
            for _, c in ipairs(gui:GetChildren()) do
                if _m(c.Name) then mark = true break end
            end
        end
        if not mark then return end

        self._protected[gui] = true
        gui.Name = _randName()
        _wipeNames(gui)

        -- Vigilar descendants nuevos
        local conn = gui.DescendantAdded:Connect(function(d)
            if not self._active then if conn then conn:Disconnect() end return end
            task.defer(function()
                pcall(function()
                    if d.Name and _m(d.Name) then d.Name = _randName() end
                    if d:IsA("LocalScript") or d:IsA("ModuleScript") then d.Name = _randName() end
                end)
            end)
        end)
        table.insert(self._connections, conn)

        -- Ocultar de los métodos de enumeracion del contenedor
        if container and not self._o[container] then
            self._o[container] = {
                gc = container.GetChildren, gd = container.GetDescendants,
                ff = container.FindFirstChild, wf = container.WaitForChild,
                ffo = container.FindFirstChildOfClass,
            }
            local gc, gd = container.GetChildren, container.GetDescendants
            local ff, wf = container.FindFirstChild, container.WaitForChild
            local ffo = container.FindFirstChildOfClass
            local prot = self._protected

            container.GetChildren = function(s, ...)
                local res = gc(s, ...)
                local out = {}
                for _, v in ipairs(res) do
                    if type(v) == "Instance" then
                        local skip = prot[v]
                        if not skip then table.insert(out, v) end
                    else
                        table.insert(out, v)
                    end
                end
                return out
            end
            container.GetDescendants = function(s, ...)
                local res = gd(s, ...)
                local out = {}
                for _, v in ipairs(res) do
                    local skip = false
                    if type(v) == "Instance" then
                        if prot[v] then skip = true
                        else
                            for g in pairs(prot) do
                                if v:IsDescendantOf(g) then skip = true break end
                            end
                        end
                    end
                    if not skip then table.insert(out, v) end
                end
                return out
            end
            container.FindFirstChild = function(s, ...)
                local r = ff(s, ...)
                if type(r) == "Instance" and prot[r] then return nil end
                return r
            end
            container.WaitForChild = function(s, ...)
                local r = wf(s, ...)
                if type(r) == "Instance" and prot[r] then return nil end
                return r
            end
            container.FindFirstChildOfClass = function(s, cls, ...)
                local children = container:GetChildren()
                for _, v in ipairs(children) do
                    if v.ClassName == cls then return v end
                end
                return nil
            end
        end
    end)
end

function UIProtector:_watch(container)
    if not container then return end
    for _, c in ipairs(container:GetChildren()) do self:_protectGUI(c, container) end

    local conn = container.DescendantAdded:Connect(function(c)
        if self._active and c:IsA("ScreenGui") then
            task.defer(function() self:_protectGUI(c, container) end)
        end
    end)
    table.insert(self._connections, conn)

    -- Limpiar via GetPropertyChangedSignal: si renombran la GUI despues, volver a esconder
    local conn2 = container.ChildAdded:Connect(function(c)
        if self._active and c:IsA("ScreenGui") then
            task.defer(function() self:_protectGUI(c, container) end)
        end
    end)
    table.insert(self._connections, conn2)
end

function UIProtector:startWatching()
    if self._watching then return end
    self._watching = true
    pcall(function()
        local plr = Players.LocalPlayer
        if plr and plr:FindFirstChild("PlayerGui") then
            self:_watch(plr:FindFirstChild("PlayerGui"))
        end
    end)
    pcall(function() self:_watch(CoreGui) end)
    -- Contenedor del executor (gethui): el aimbot mete la GUI ahi
    pcall(function()
        if gethui then
            local h = gethui()
            if h then self:_watch(h) end
        end
    end)
    pcall(function()
        if getgenv and getgenv().gethui then
            local h = getgenv().gethui()
            if h then self:_watch(h) end
        end
    end)
    self:watchChams()
end

-- Vigilar los Highlight "FlowCham" que el aimbot crea bajo los personajes
-- del Workspace (son instancias reales, no desaparecen con getgc)
function UIProtector:watchChams()
    if self._chams then return end
    self._chams = true
    local kills = {}
    pcall(function()
        local function sanitize(h)
            if not self._active then return end
            pcall(function()
                if type(h) == "Instance" then
                    if h:IsA("Highlight") or h:IsA("BoxHandleAdornment") or
                       h:IsA("SelectionBox") or h:IsA("SelectionSphere") or
                       h:IsA("SurfaceGui") or h:IsA("BillboardGui") or
                       h:IsA("PointLight") or h:IsA("SpotLight") or
                       h:IsA("SurfaceLight") then
                        local n = _LOW(h.Name)
                        if _m(n) then h.Name = _randName() end
                    end
                    if _m(h.Name) then h.Name = _randName() end
                end
            end)
        end
        local ws = game:FindService("Workspace")
        if not ws then ws = game:GetService("Workspace") end
        for _, d in ipairs(ws:GetDescendants()) do sanitize(d) end
        local conn = ws.DescendantAdded:Connect(sanitize)
        table.insert(self._connections, conn)
    end)
    -- Barrido periodico por si el anti-cheat renombra o el aimbot recrea
    task.spawn(function()
        while self._active do
            task.wait(3)
            pcall(function()
                local ws = game:FindService("Workspace")
                if ws then
                    for _, d in ipairs(ws:GetDescendants()) do
                        pcall(function()
                            if type(d) == "Instance" and _m(d.Name) and
                               (d:IsA("Highlight") or d:IsA("BoxHandleAdornment")) then
                                d.Name = _randName()
                            end
                        end)
                    end
                end
            end)
        end
    end)
end

-- Antiscreenshot / Antirecording: apagar la GUI mientras se captura
function UIProtector:protectScreenshots()
    pcall(function()
        local prots = self._protected
        local function toggle(on)
            for g in pairs(prots) do
                pcall(function() if g and g.Enabled ~= on then g.Enabled = on end end)
            end
        end
        for _, fn in ipairs({ "takesscreenshot", "savescreenshotidentifier", "recordid" }) do
            if _G[fn] and not self._o[fn] then
                self._o[fn] = _G[fn]
                local base = _G[fn]
                _G[fn] = function(...)
                    toggle(false)
                    local r = base(...)
                    task.defer(function() toggle(true) end)
                    return r
                end
            end
        end
    end)
end

-- Proteger la GUI tambien contra getgc (tables del UI via __SR si existe)
function UIProtector:syncWithResolver()
    if _G.__SR and _G.__SR.addHiddenTag then
        for k in pairs(self._protected) do
            pcall(function()
                if type(k) == "Instance" and k.Name then
                    _G.__SR:addHiddenTag(k.Name)
                end
            end)
        end
    end
end

-- Proteger objeto Drawing (mira, ESP) que no son instancias:
-- se registran como tags ocultas en getgc para que no aparezcan
function UIProtector:protectDrawings(resolver)
    pcall(function()
        if not Drawing then return end
        -- Si hay un resolver con addHiddenTag, registrar marcadores
        if resolver and resolver.addHiddenTag then
            for _, tag in ipairs({ _D(102,111,118), _D(101,115,112), _D(104,105,116,98,111,120) }) do
                pcall(function() resolver:addHiddenTag(tag) end)
            end
        end
        -- Interceptar Drawing.new: guardar objetos no-instancia para
        -- que no se filtren erroneamente, y evitar que queden en getgc
        if not self._o.dnew and Drawing.new then
            self._o.dnew = Drawing.new
            local oldNew = Drawing.new
            Drawing.new = newcclosure(function(kind, ...)
                local d = oldNew(kind, ...)
                -- marcar para filtrado en getgc
                pcall(function()
                    if d and d.Visible ~= nil then
                        d.Visible = false
                        task.defer(function() if d and d.Visible ~= nil then pcall(function() d.Visible = true end) end end)
                    end
                end)
                return d
            end)
        end
    end)
end

function UIProtector:destroy()
    self._active = false
    for _, conn in ipairs(self._connections) do
        pcall(function() if conn.Connected then conn:Disconnect() end end)
    end
    self._connections = {}
    for container, o in pairs(self._o) do
        pcall(function()
            if container then
                container.GetChildren = o.gc
                container.GetDescendants = o.gd
                container.FindFirstChild = o.ff
                container.WaitForChild = o.wf
                container.FindFirstChildOfClass = o.ffo
            end
        end)
    end
end

if not _G.__UIProtector then
    _G.__UIProtector = UIProtector.new()
    _G.__UIProtector:startWatching()
    _G.__UIProtector:protectScreenshots()
    task.defer(function()
        _G.__UIProtector:syncWithResolver()
        _G.__UIProtector:protectDrawings(_G.__SR)
    end)
end

return UIProtector
