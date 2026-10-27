--- Punto de entrada del cliente para el mod LSGamesConnect.

local NET_CHANNEL    = "LSGames_MiddlewareStatus"
local NET_PASSIVE_FX = "LSGames_PassiveEffects"
local PREFIX         = "[LSGames][Cliente]"

local StoreWindow = Ext.Require("Client/UI/StoreWindow.lua")
local EffectsTab  = Ext.Require("Client/UI/EffectsTab.lua")
local Notifier    = Ext.Require("Notifier.lua")

-- ---------------------------------------------------------------------------
-- Formateo del estado recibido del servidor
-- ---------------------------------------------------------------------------

local function _format_received(data)
    if data.ok then
        local name = data.playerName or data.userId or "?"
        return string.format(
            "CONECTADO  |  Jugador: %s  |  %s  |  Expira: %s",
            tostring(name),
            Notifier.fmt_balance(data.balance),
            Notifier.fmt_time(data.expires or 0)
        )
    else
        return string.format("NO DISPONIBLE  |  %s  |  %s",
            tostring(data.status or "?"),
            tostring(data.error  or "sin detalles"))
    end
end

-- ---------------------------------------------------------------------------
-- Mensajes de red del servidor
-- ---------------------------------------------------------------------------

Ext.Events.NetMessage:Subscribe(function(event)
    if event.Channel ~= NET_CHANNEL then return end

    local ok, data = pcall(Ext.Json.Parse, event.Payload)
    if not ok or type(data) ~= "table" then
        Ext.Utils.Print(PREFIX .. " [ERROR] Payload inválido.")
        return
    end

    Ext.Utils.Print(PREFIX .. " " .. string.rep("-", 55))
    Ext.Utils.Print(PREFIX .. " " .. _format_received(data))
    Ext.Utils.Print(PREFIX .. " " .. string.rep("-", 55))
end)

-- ---------------------------------------------------------------------------
-- Efectos pasivos por tier (snapshot del servidor)
-- ---------------------------------------------------------------------------

Ext.Events.NetMessage:Subscribe(function(event)
    if event.Channel ~= NET_PASSIVE_FX then return end
    local ok, data = pcall(Ext.Json.Parse, event.Payload)
    if not ok or type(data) ~= "table" then return end
    if type(data.effects) == "table" then EffectsTab.setPassive(data.effects) end
    if type(data.recent) == "table" then EffectsTab.setRecent(data.recent) end
end)

-- ---------------------------------------------------------------------------
-- Inicializar UI al cargar la sesión
-- ---------------------------------------------------------------------------

Ext.Events.SessionLoaded:Subscribe(function()
    Ext.IO.SaveFile("LSGMod/lsg_game_start.json",
        Ext.Json.Stringify({ ts = Ext.Utils.MonotonicTime() }))
    StoreWindow.init()
end)

-- ---------------------------------------------------------------------------
-- Tick throttled: notificaciones del middleware y countdown de efectos
-- ---------------------------------------------------------------------------
--
-- El countdown de efectos corre 1 vez por segundo y lsg_notify.json se lee
-- cada 3 s, en vez de en cada tick (~30 por segundo).

local TICK_FAST_MS = 1000   -- countdown de efectos
local TICK_POLL_MS = 3000   -- lectura de lsg_notify.json
local _last_fast = 0
local _last_poll = 0
local _last_notify_ts = nil

Ext.Events.Tick:Subscribe(function()
    local now = Ext.Utils.MonotonicTime()

    if now - _last_fast >= TICK_FAST_MS then
        _last_fast = now
        StoreWindow.tick(now)
    end

    if now - _last_poll < TICK_POLL_MS then return end
    _last_poll = now

    local raw = Ext.IO.LoadFile("LSGMod/lsg_notify.json", "user")
    if not raw then return end
    local ok, data = pcall(Ext.Json.Parse, raw)
    if not ok or type(data) ~= "table" then return end
    -- Si el timestamp cambió (balance, catálogo o transacciones nuevas),
    -- forzar relectura de archivos y repoblado de la tienda.
    local ts = data.catalog_ts or data.ts
    if ts and ts ~= _last_notify_ts then
        _last_notify_ts = ts
        StoreWindow.refresh()
    end
end)

-- ---------------------------------------------------------------------------
-- Comando: !lsgstore
-- ---------------------------------------------------------------------------

Ext.RegisterConsoleCommand("lsgstore", function()
    StoreWindow.toggle()
end)

-- ---------------------------------------------------------------------------
-- Hotkey: F7
-- ---------------------------------------------------------------------------

pcall(function()
    Ext.Events.KeyInput:Subscribe(function(e)
        if e.Event == "KeyDown" and e.Key == "F7" then
            StoreWindow.toggle()
        end
    end)
end)

Ext.Utils.Print("[LSGames] Mod cliente cargado. Botón flotante activo | !lsgstore | F7")
