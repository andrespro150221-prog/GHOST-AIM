-- ═══════════════════════════════════════════════════════════════
--  UIProtector v1.0
--  Protección completa para ScreenGuis en Roblox
--  Anti-detección, anti-dump, anti-screenshot, anti-tamper
--  Compatible: Delta, Arceus X, Codex, Fluxus, PC
-- ═══════════════════════════════════════════════════════════════

local UIProtector = {}
UIProtector.__index = UIProtector

UIProtector._instances = {}
UIProtector._active = true
UIProtector._originals = {}

-- ══════════════════════════════════════════
--  UTILS INTERNOS
-- ══════════════════════════════════════════

function UIProtector:_randStr(len)
    local out = ""
    for _ = 1, len do
        out = out .. string.char(math.random(65, 122))
    end
    return out
end

function UIProtector:_safeCall(fn, ...)
    local ok, err = pcall(fn, ...)
    return ok, err
end

-- ══════════════════════════════════════════
--  1. NOMBRE SPOOF — Cambia el nombre del GUI a algo inocente
-- ══════════════════════════════════════════

function UIProtector:_spoofName(guiObj)
    local realName = guiObj.Name
    local fakeName = "SettingsMenu_" .. tostring(math.random(100000, 999999))

    guiObj.Name = fakeName

    -- Guarda el nombre real para restauración
    self._realName = realName
    self._fakeName = fakeName

    return fakeName
end

-- ══════════════════════════════════════════
--  2. EXPLORER SPOOF — Muestra nombre falso en Explorer
-- ══════════════════════════════════════════

function UIProtector:_spoofExplorer(guiObj)
    pcall(function()
        local fakeName = self._fakeName or "SettingsMenu"

        -- Renombra todos los hijos con nombres aleatorios
        for _, desc in ipairs(guiObj:GetDescendants()) do
            pcall(function()
                if desc:IsA("Frame") or desc:IsA("TextLabel") or
                   desc:IsA("TextButton") or desc:IsA("ScrollingFrame") or
                   desc:IsA("ImageLabel") or desc:IsA("UIStroke") then
                    desc.Name = self:_randStr(math.random(5, 12))
                end
            end)
        end

        -- Watcher para hijos nuevos
        local conn
        conn = guiObj.DescendantAdded:Connect(function(desc)
            task.defer(function()
                if not self._active then
                    if conn then conn:Disconnect() end
                    return
                end
                pcall(function()
                    if desc:IsA("Frame") or desc:IsA("TextLabel") or
                       desc:IsA("TextButton") or desc:IsA("ScrollingFrame") or
                       desc:IsA("ImageLabel") or desc:IsA("UIStroke") then
                        desc.Name = self:_randStr(math.random(5, 12))
                    end
                end)
            end)
        end)
        table.insert(self._connections, conn)
    end)
end

-- ══════════════════════════════════════════
--  3. ANTI-SCREENSHOT — Bloquea captures del GUI
-- ══════════════════════════════════════════

function UIProtector:_antiScreenshot(guiObj)
    pcall(function()
        local CoreGui = game:GetService("CoreGui")

        -- Hook de GetChildren
        local oldGetChildren = CoreGui.GetChildren
        self._originals.CoreGuiGetChildren = oldGetChildren

        CoreGui.GetChildren = function(self, ...)
            local result = oldGetChildren(self, ...)
            local filtered = {}
            for _, v in ipairs(result) do
                if v ~= guiObj then
                    table.insert(filtered, v)
                end
            end
            return filtered
        end

        -- Hook de GetDescendants
        local oldGetDescendants = CoreGui.GetDescendants
        self._originals.CoreGuiGetDescendants = oldGetDescendants

        CoreGui.GetDescendants = function(self, ...)
            local result = oldGetDescendants(self, ...)
            local filtered = {}
            for _, v in ipairs(result) do
                if v ~= guiObj and not v:IsDescendantOf(guiObj) then
                    table.insert(filtered, v)
                end
            end
            return filtered
        end
    end)
end

-- ══════════════════════════════════════════
--  4. ANTI-TAMPER — Detecta destrucción externa
-- ══════════════════════════════════════════

function UIProtector:_antiTamper(guiObj, onTamper)
    local conn = guiObj.Destroying:Connect(function()
        if self._active then
            pcall(function()
                task.defer(function()
                    if self._active then
                        self._active = false
                        if onTamper then onTamper() end
                    end
                end)
            end)
        end
    end)
    table.insert(self._connections, conn)
end

-- ══════════════════════════════════════════
--  5. DESCENDANT WATCHER — Renombra hijos nuevos
-- ══════════════════════════════════════════

function UIProtector:_descendantWatcher(guiObj, sensitiveNames)
    local conn = guiObj.DescendantAdded:Connect(function(desc)
        task.defer(function()
            if not self._active then return end

            -- Renombra nombres sensibles
            for _, name in ipairs(sensitiveNames or {}) do
                if desc.Name and string.find(desc.Name, name) then
                    desc.Name = self:_randStr(math.random(6, 14))
                end
            end

            -- Renombra scripts nuevos
            if desc:IsA("LocalScript") or desc:IsA("ModuleScript") then
                desc.Name = self:_randStr(math.random(6, 12))
            end
        end)
    end)
    table.insert(self._connections, conn)
end

-- ══════════════════════════════════════════
--  6. OBFUSCATE TEXT — Inyecta zero-width chars en textos sensibles
-- ══════════════════════════════════════════

function UIProtector:_obfuscateText(guiObj, sensitiveNames)
    pcall(function()
        for _, desc in ipairs(guiObj:GetDescendants()) do
            if desc:IsA("TextLabel") or desc:IsA("TextButton") then
                local txt = desc.Text or ""
                for _, name in ipairs(sensitiveNames or {}) do
                    if string.find(txt, name) then
                        local out = ""
                        for i = 1, #txt do
                            out = out .. string.sub(txt, i, i)
                            if i < #txt and math.random() > 0.5 then
                                out = out .. "\u{200B}"
                            end
                        end
                        desc.Text = out
                        break
                    end
                end
            end
        end
    end)
end

-- ══════════════════════════════════════════
--  7. SANITIZE NAMES — Limpia nombres sensibles
-- ══════════════════════════════════════════

function UIProtector:_sanitizeNames(guiObj, sensitiveNames)
    pcall(function()
        for _, child in ipairs(guiObj:GetChildren()) do
            for _, name in ipairs(sensitiveNames or {}) do
                if child.Name and string.find(child.Name, name) then
                    child.Name = self:_randStr(math.random(6, 14))
                end
            end
        end
    end)
end

-- ══════════════════════════════════════════
--  8. HIDE PROPERTIES — Oculta propiedades vulnerables
-- ══════════════════════════════════════════

function UIProtector:_hideProperties(guiObj)
    pcall(function()
        guiObj.ResetOnSpawn = false
        guiObj.IgnoreGuiInset = true
        guiObj.DisplayOrder = 999
    end)
end

-- ══════════════════════════════════════════
--  PUBLIC API
-- ══════════════════════════════════════════

function UIProtector.new(guiObj, config)
    local self = setmetatable({}, UIProtector)
    self._gui = guiObj
    self._active = true
    self._connections = {}
    self._config = config or {}

    config = self._config

    -- Sensible names por defecto
    self._sensitiveNames = config.sensitiveNames or {
        "FlowUI", "AimLock", "Aimbot", "ESP", "Hitbox",
        "FlowCham", "GHOST", "AutoShoot", "Flow",
    }

    -- Aplica protecciones
    self:_hideProperties(guiObj)
    self:_spoofName(guiObj)
    self:_spoofExplorer(guiObj)

    if config.antiScreenshot ~= false then
        self:_antiScreenshot(guiObj)
    end

    if config.antiTamper ~= false then
        self:_antiTamper(guiObj, config.onTamper)
    end

    self:_descendantWatcher(guiObj, self._sensitiveNames)

    return self
end

function UIProtector:finalize()
    self:_sanitizeNames(self._gui, self._sensitiveNames)
    self:_obfuscateText(self._gui, self._sensitiveNames)
end

function UIProtector:destroy()
    self._active = false

    -- Desconecta todos los listeners
    for _, conn in ipairs(self._connections) do
        pcall(function() conn:Disconnect() end)
    end
    self._connections = {}

    -- Restaura hooks
    pcall(function()
        if self._originals.CoreGuiGetChildren then
            game:GetService("CoreGui").GetChildren = self._originals.CoreGuiGetChildren
        end
    end)
    pcall(function()
        if self._originals.CoreGuiGetDescendants then
            game:GetService("CoreGui").GetDescendants = self._originals.CoreGuiGetDescendants
        end
    end)

    -- Restaura nombre real
    pcall(function()
        if self._realName then
            self._gui.Name = self._realName
        end
    end)
end

function UIProtector:isActive()
    return self._active
end

function UIProtector:getGui()
    return self._gui
end

return UIProtector
