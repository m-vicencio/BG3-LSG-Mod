--- Punto de entrada del servidor para el mod LSGamesConnect.

local SessionReader = Ext.Require("SessionReader.lua")
local Notifier      = Ext.Require("Notifier.lua")
local Shop          = Ext.Require("Shop.lua")
local OfflineSync   = Ext.Require("OfflineSync.lua")
local Effects       = Ext.Require("Effects.lua")

local NET_CHANNEL      = "LSGames_MiddlewareStatus"
local NET_GIVE_ITEM    = "LSGames_GiveItem"
local NET_GIVE_STATUS  = "LSGames_GiveStatus"
local NET_PASSIVE_FX   = "LSGames_PassiveEffects"

--- Transmite a los clientes el snapshot de efectos pasivos por tier
-- (los muestra la pestaña Efectos activos > Pasivos de la tienda).
local function broadcast_passive()
    pcall(function()
        Ext.ServerNet.BroadcastMessage(NET_PASSIVE_FX,
            Ext.Json.Stringify({ effects = Effects.snapshot(), recent = Effects.snapshotRecent() }))
    end)
end

local function update_effects(session)
    Effects.update(session)
    broadcast_passive()
end

-- ---------------------------------------------------------------------------
-- Lógica central de verificación
-- ---------------------------------------------------------------------------

local function check_middleware()
    return SessionReader.load()
end

local function broadcast_status(result)
    local payload = {
        ok     = result.ok,
        status = result.status,
        error  = result.error,
    }
    if result.ok and result.session then
        payload.userId     = result.session.userId
        payload.playerName = result.session.playerName
        payload.balance    = result.session.balance
        payload.dimensions = result.session.dimensions
        payload.expires    = result.session.expires
    end

    local ok, err = pcall(function()
        Ext.ServerNet.BroadcastMessage(NET_CHANNEL, Ext.Json.Stringify(payload))
    end)
    if not ok then
        Ext.Utils.Print("[LSGames] Error al transmitir estado a clientes: " .. tostring(err))
    end
end

-- ---------------------------------------------------------------------------
-- Evento: sesión de juego cargada
-- ---------------------------------------------------------------------------

Ext.Events.SessionLoaded:Subscribe(function()
    Notifier.separator()
    Ext.Utils.Print("[LSGames] Sesión de juego cargada — verificando middleware...")
    local result = check_middleware()
    Notifier.console(result)
    broadcast_status(result)
    if result.ok and result.session then
        update_effects(result.session)
    end
    Effects.applyRecentEvents()
    broadcast_passive()
    Notifier.separator()
end)

-- ---------------------------------------------------------------------------
-- Verificación periódica con detección de cambios (cada 5 minutos)
-- ---------------------------------------------------------------------------

local INTERVAL_MS = 300000  -- verificación completa de respaldo
local NOTIFY_MS   = 5000    -- vigilancia de lsg_notify.json (archivo diminuto)
local _last_check     = 0
local _last_notify    = 0
local _last_notify_ts = nil
local _last_raw       = nil

local function check_session_change()
    -- Procesar resultados de sincronización offline si el middleware los escribió
    local sync_result = OfflineSync.processResults()
    if sync_result then
        Ext.Utils.Print(string.format(
            "[LSGames] Sync offline: %d/%d synced  |  %d rechazados  |  %d duplicados",
            sync_result.synced   or 0, sync_result.total    or 0,
            sync_result.rejected or 0, sync_result.duplicate or 0))
        -- Notificar resultados por evento
        if type(sync_result.results) == "table" then
            for _, r in ipairs(sync_result.results) do
                if r.status ~= "SYNCED" then
                    Ext.Utils.Print(string.format(
                        "[LSGames]   [%s] ref=%s", r.status or "?", r.client_ref or "?"))
                end
            end
        end
    end

    -- Los eventos de sensores pueden llegar sin cambio en session.json
    -- (el poll de ingest-events del middleware solo escribe recent_events.json).
    Effects.applyRecentEvents()
    broadcast_passive()

    local raw = Ext.IO.LoadFile("LSGMod/session.json", "user")
    if raw == _last_raw then return end
    _last_raw = raw

    local result = check_middleware()
    Notifier.console(result)
    broadcast_status(result)
    if result.ok and result.session then
        update_effects(result.session)
    end
end

Ext.Events.Tick:Subscribe(function()
    local now = Ext.Utils.MonotonicTime()

    -- Vigilancia rápida: cuando el middleware toca lsg_notify.json (sync,
    -- refresh, compra), re-evaluar sesión y efectos a los pocos segundos.
    if now - _last_notify >= NOTIFY_MS then
        _last_notify = now
        local raw = Ext.IO.LoadFile("LSGMod/lsg_notify.json", "user")
        if raw then
            local ok, data = pcall(Ext.Json.Parse, raw)
            local ts = (ok and type(data) == "table") and (data.ts or data.server_time) or nil
            if ts and ts ~= _last_notify_ts then
                _last_notify_ts = ts
                check_session_change()
                _last_check = now  -- pospone la verificación de respaldo
            end
        end
    end

    -- Respaldo cada 5 min por si el middleware no escribe lsg_notify.json
    if now - _last_check < INTERVAL_MS then return end
    _last_check = now
    check_session_change()
end)

-- ---------------------------------------------------------------------------
-- Comando !lsgames: verificación manual
-- ---------------------------------------------------------------------------

Ext.RegisterConsoleCommand("lsgames", function(_cmd)
    Notifier.separator()
    Ext.Utils.Print("[LSGames] Verificación manual solicitada...")
    local result = check_middleware()
    Notifier.console(result)
    broadcast_status(result)
    local ok, host = pcall(Osi.GetHostCharacter)
    if ok and host and host ~= "" then
        Notifier.ingame(result, host)
    else
        Ext.Utils.Print("[LSGames] [AVISO] No se encontró el personaje host.")
    end
    Notifier.separator()
end)

-- ---------------------------------------------------------------------------
-- Comando !lsgshop: catálogo de mecánicas
-- ---------------------------------------------------------------------------

Ext.RegisterConsoleCommand("lsgshop", function(_cmd)
    Ext.Utils.Print("[LSGames] Consultando catálogo de mecánicas...")
    Shop.catalog(function(ok, data)
        if not ok then
            Ext.Utils.Print("[LSGames] [ERROR] " .. tostring(data))
            return
        end
        Notifier.separator()
        Ext.Utils.Print("[LSGames] ── Catálogo de mecánicas ──")
        for _, item in ipairs(data) do
            local cost_str = string.format("%d pts (%s)",
                item.cost or 0, item.dimensionName or "?")
            Ext.Utils.Print(string.format("  %-20s  %-25s  [%s]",
                item.name or "?", cost_str, item.itemId))
        end
        Notifier.separator()
    end)
end)

-- ---------------------------------------------------------------------------
-- Comando !lsgbuy <itemId> [cantidad]: canjear una mecánica
-- ---------------------------------------------------------------------------

Ext.RegisterConsoleCommand("lsgbuy", function(_cmd, item_id, amount_str)
    if not item_id or item_id == "" then
        Ext.Utils.Print("[LSGames] Uso: !lsgbuy <itemId> [cantidad]")
        Ext.Utils.Print("[LSGames] Usa !lsgshop para ver las mecánicas disponibles.")
        return
    end

    local amount = math.max(1, math.tointeger(tonumber(amount_str) or 1) or 1)
    Ext.Utils.Print(string.format("[LSGames] Canjeando %dx mecánica %s...", amount, item_id))

    Shop.buy(item_id, amount, function(ok, msg)
        Notifier.separator()
        if not ok then
            Ext.Utils.Print("[LSGames] [ERROR] " .. tostring(msg))
            Notifier.separator()
            return
        end
        Ext.Utils.Print("[LSGames] Canje enviado. El balance se actualizará en breve.")
        Ext.Utils.Print("[LSGames] " .. tostring(msg))
        Notifier.separator()
    end)
end)

-- ---------------------------------------------------------------------------
-- Comando !lsgbalance: mostrar balance dimensional actual
-- ---------------------------------------------------------------------------

Ext.RegisterConsoleCommand("lsgbalance", function(_cmd)
    local result = check_middleware()
    Notifier.separator()
    if result.ok and result.session then
        local s = result.session
        local name = s.playerName or s.userId
        Ext.Utils.Print(string.format("[LSGames] Jugador: %s", tostring(name)))
        if type(s.balance) == "table" then
            local keys = {}
            for k in pairs(s.balance) do keys[#keys+1] = k end
            table.sort(keys)
            for _, k in ipairs(keys) do
                local pts = math.tointeger(s.balance[k]) or math.floor(s.balance[k])
                Ext.Utils.Print(string.format("[LSGames]   %-14s %d pts",
                    k:sub(1,1):upper()..k:sub(2)..":", pts))
            end
        end
    else
        Ext.Utils.Print("[LSGames] Sin sesión activa: " .. (result.error or "?"))
    end
    Notifier.separator()
end)

-- ---------------------------------------------------------------------------
-- Recepción de ítems de BG3 al canjear en la tienda
-- ---------------------------------------------------------------------------

Ext.Events.NetMessage:Subscribe(function(event)
    if event.Channel ~= NET_GIVE_ITEM then return end

    local ok, data = pcall(Ext.Json.Parse, event.Payload)
    if not ok or type(data) ~= "table" or not data.templateId then return end

    local char_ok, host = pcall(Osi.GetHostCharacter)
    if not char_ok or not host or host == "" then return end

    local amount = math.max(1, math.tointeger(data.amount or 1) or 1)
    local tpl    = tostring(data.templateId)

    local give_ok, give_err = pcall(Osi.TemplateAddTo, tpl, host, amount, 1)
    if give_ok then
        Ext.Utils.Print(string.format(
            "[LSGames] Ítem añadido al inventario: %s x%d", tpl, amount))
    else
        Ext.Utils.Print("[LSGames] [ERROR] No se pudo añadir ítem: " .. tostring(give_err))
    end
end)

-- ---------------------------------------------------------------------------
-- Recepción de status (buffs) al canjear una mecánica en la tienda
-- ---------------------------------------------------------------------------

Ext.Events.NetMessage:Subscribe(function(event)
    if event.Channel ~= NET_GIVE_STATUS then return end

    local ok, data = pcall(Ext.Json.Parse, event.Payload)
    if not ok or type(data) ~= "table" or not data.status then return end

    local char_ok, host = pcall(Osi.GetHostCharacter)
    if not char_ok or not host or host == "" then return end

    -- status puede ser un string o una lista de strings
    local statuses = type(data.status) == "table" and data.status or { data.status }
    -- duración: turnos -> segundos (1 turno ≈ 6 s). 0/nil => permanente (-1).
    local turns    = math.tointeger(data.durationTurns or 0) or 0
    local duration = turns > 0 and (turns * 6) or -1

    for _, st in ipairs(statuses) do
        local apply_ok, apply_err = pcall(Osi.ApplyStatus, host, tostring(st), duration, 1, host)
        if apply_ok then
            Ext.Utils.Print(string.format(
                "[LSGames] Status aplicado: %s (%s)", tostring(st),
                duration > 0 and (turns .. " turnos") or "permanente"))
        else
            Ext.Utils.Print("[LSGames] [ERROR] No se pudo aplicar status " ..
                tostring(st) .. ": " .. tostring(apply_err))
        end
    end
end)

-- ---------------------------------------------------------------------------
-- Comando !lsgsync: sincronizar cola offline con el servidor
-- ---------------------------------------------------------------------------

Ext.RegisterConsoleCommand("lsgsync", function(_cmd)
    Notifier.separator()
    local n = OfflineSync.pendingCount()
    if n == 0 then
        Ext.Utils.Print("[LSGames] Cola offline vacía — nada que sincronizar.")
        Notifier.separator()
        return
    end
    Ext.Utils.Print(string.format("[LSGames] Solicitando sincronización de %d evento(s)...", n))
    local ok, msg = OfflineSync.requestSync()
    if ok then
        Ext.Utils.Print("[LSGames] " .. msg)
        Ext.Utils.Print("[LSGames] El middleware procesará la solicitud en los próximos segundos.")
    else
        Ext.Utils.Print("[LSGames] [ERROR] " .. msg)
    end
    Notifier.separator()
end)

-- ---------------------------------------------------------------------------
-- Comando !lsgqueue: mostrar la cola offline actual
-- ---------------------------------------------------------------------------

Ext.RegisterConsoleCommand("lsgqueue", function(_cmd)
    Notifier.separator()
    local queue = OfflineSync.listQueue()
    if #queue == 0 then
        Ext.Utils.Print("[LSGames] Cola offline vacía.")
        Notifier.separator()
        return
    end
    Ext.Utils.Print(string.format("[LSGames] ── Cola offline: %d evento(s) ──", #queue))
    for i, ev in ipairs(queue) do
        local trigger = (ev.payload and ev.payload.trigger) or "?"
        local mech    = (ev.payload and ev.payload.mechanic_id) and
                        (" mech=" .. tostring(ev.payload.mechanic_id)) or ""
        Ext.Utils.Print(string.format(
            "[LSGames]  #%d  %-6s  dim=%-2d  %4d pts  %-20s%s  [%s]  ref=%s",
            i,
            ev.direction       or "?",
            ev.point_dimension_id or 0,
            ev.amount          or 0,
            trigger,
            mech,
            ev.status          or "?",
            (ev.client_ref     or "?"):sub(1, 24) -- mostrar primeros 24 chars
        ))
    end
    Notifier.separator()
end)

-- ---------------------------------------------------------------------------
-- Comando !lsgearn <dim_id> <amount> [trigger]: registrar ganancia de puntos
-- ---------------------------------------------------------------------------

Ext.RegisterConsoleCommand("lsgearn", function(_cmd, dim_str, amount_str, trigger)
    local dim_id = math.tointeger(tonumber(dim_str or "") or 0) or 0
    local amount = math.tointeger(tonumber(amount_str or "") or 0) or 0
    trigger      = (trigger and trigger ~= "") and trigger or "manual_earn"

    if dim_id <= 0 or amount <= 0 then
        Ext.Utils.Print("[LSGames] Uso: !lsgearn <dim_id> <amount> [trigger]")
        Ext.Utils.Print("[LSGames] Ejemplo: !lsgearn 2 50 quest_completed")
        Ext.Utils.Print("[LSGames] dim_id: ver catálogo de dimensiones (Social=1, Fisico=2, ...)")
        return
    end

    Notifier.separator()
    local ref, err = OfflineSync.addEvent("CREDIT", dim_id, amount, trigger, nil)
    if not ref then
        Ext.Utils.Print("[LSGames] [ERROR] " .. tostring(err))
        Notifier.separator()
        return
    end

    Ext.Utils.Print(string.format(
        "[LSGames] CREDIT registrado: dim=%d  +%d pts  [%s]", dim_id, amount, trigger))

    local ok, msg = OfflineSync.requestSync()
    Ext.Utils.Print("[LSGames] " .. (ok and msg or ("[COLA] " .. msg)))
    Notifier.separator()
end)

-- ---------------------------------------------------------------------------
-- Comando !lsgredeem <dim_id> <amount> [mechanic_id]: canje offline manual
-- ---------------------------------------------------------------------------

Ext.RegisterConsoleCommand("lsgredeem", function(_cmd, dim_str, amount_str, mech_str)
    local dim_id  = math.tointeger(tonumber(dim_str   or "") or 0) or 0
    local amount  = math.tointeger(tonumber(amount_str or "") or 0) or 0
    local mech_id = math.tointeger(tonumber(mech_str  or "") or 0) or nil

    if dim_id <= 0 or amount <= 0 then
        Ext.Utils.Print("[LSGames] Uso: !lsgredeem <dim_id> <amount> [mechanic_id]")
        Ext.Utils.Print("[LSGames] Ejemplo: !lsgredeem 2 100 5")
        return
    end

    Notifier.separator()
    local ref, err = OfflineSync.addEvent("DEBIT", dim_id, amount, "console_redeem", mech_id)
    if not ref then
        Ext.Utils.Print("[LSGames] [ERROR] " .. tostring(err))
        Notifier.separator()
        return
    end

    local mech_str_display = mech_id and (" mech=" .. mech_id) or ""
    Ext.Utils.Print(string.format(
        "[LSGames] DEBIT registrado: dim=%d  -%d pts%s", dim_id, amount, mech_str_display))

    local ok, msg = OfflineSync.requestSync()
    Ext.Utils.Print("[LSGames] " .. (ok and msg or ("[COLA] " .. msg)))
    Notifier.separator()
end)

-- ---------------------------------------------------------------------------
-- Comando !lsgeffects: re-evaluar efectos pasivos con el balance actual
-- ---------------------------------------------------------------------------

Ext.RegisterConsoleCommand("lsgeffects", function(_cmd, sub)
    Notifier.separator()
    if sub == "clear" then
        Effects.clearAll()
        broadcast_passive()
        Ext.Utils.Print("[LSGames] Efectos pasivos por tier removidos.")
        Notifier.separator()
        return
    end
    local result = check_middleware()
    if result.ok and result.session then
        Ext.Utils.Print("[LSGames] Re-evaluando efectos pasivos con el balance actual...")
        update_effects(result.session)
    else
        Ext.Utils.Print("[LSGames] Sin sesión activa: " .. (result.error or "?"))
    end
    Notifier.separator()
end)

-- ---------------------------------------------------------------------------
-- Comando !lsgevents: listar eventos de sensores recientes y aplicar buffs
-- ---------------------------------------------------------------------------

Ext.RegisterConsoleCommand("lsgevents", function(_cmd)
    Notifier.separator()
    local raw = Ext.IO.LoadFile("LSGMod/recent_events.json", "user")
    if not raw or raw == "" then
        Ext.Utils.Print("[LSGames] recent_events.json no encontrado — ¿está corriendo lsgames-app?")
        Notifier.separator()
        return
    end
    local ok, data = pcall(Ext.Json.Parse, raw)
    local events = ok and type(data) == "table" and data.events or nil
    if type(events) ~= "table" then
        Ext.Utils.Print("[LSGames] recent_events.json no se pudo parsear.")
        Notifier.separator()
        return
    end
    Ext.Utils.Print(string.format("[LSGames] ── Eventos de sensores recientes: %d ──", #events))
    for _, ev in ipairs(events) do
        Ext.Utils.Print(string.format("[LSGames]  #%-6d %-28s milestone=%-4s %s",
            math.tointeger(ev.id) or 0,
            tostring(ev.event_type),
            tostring(ev.milestone or "-"),
            tostring(ev.occurred_at or "?")))
    end
    Effects.applyRecentEvents()
    broadcast_passive()
    Notifier.separator()
end)

Ext.Utils.Print("[LSGames] Mod servidor cargado.")
Ext.Utils.Print("[LSGames] Comandos: !lsgames | !lsgshop | !lsgbuy <id> [n] | !lsgbalance | !lsgeffects [clear] | !lsgevents")
Ext.Utils.Print("[LSGames] Offline:  !lsgsync  | !lsgqueue | !lsgearn <dim> <pts> [trig] | !lsgredeem <dim> <pts> [mech]")
