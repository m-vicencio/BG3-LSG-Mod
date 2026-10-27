--- Efectos pasivos por completitud de metas (lado servidor).
--
-- Dos mecanismos:
--   1) Tiers por acumulación: por dimensión, umbrales de puntos -> status.
--      Se aplica el tier más alto alcanzado (permanente mientras se mantenga);
--      al bajar del umbral se remueve. Re-evaluado en cada lectura de balance.
--   2) Actividad reciente: eventos de sensores (LSGMod/recent_events.json,
--      escrito por lsgames-app desde GET /sensors/players/{id}/ingest-events)
--      se mapean por event_type a un buff temporal que expira solo.
--      Dedupe por id de evento, persistido en archivo.
--
-- Todos los status están verificados contra Status_BOOST.txt del juego.
-- Para ajustar metas/efectos solo edita las tablas de abajo. Doc: EFFECTS.md.
-- Justificación del mapeo evento -> status: EVENT_EFFECTS.md.

local Effects = {}

-- ---------------------------------------------------------------------------
-- Config: tiers por dimensión
-- ---------------------------------------------------------------------------
-- Claves = nombre de dimensión en minúscula (las del catálogo / session.balance):
--   social, fisico, afectivo, mental, linguistico
-- Cada tier: { min = <puntos mínimos>, status = "<STATUS>" }. Orden libre.
Effects.tiers = {
    social = {
        { min = 5,  status = "GUIDANCE" },        -- +1d4 pruebas de habilidad
        { min = 25, status = "EAGLES_SPLENDOR" }, -- ventaja en Carisma
        { min = 75, status = "BLESS" },           -- +1d4 ataque y salvaciones
    },
    fisico = {
        { min = 5,  status = "GUIDANCE" },
        { min = 25, status = "BULLS_STRENGTH" },  -- ventaja en Fuerza, carga x2
        { min = 75, status = "BEARS_ENDURANCE" }, -- ventaja en Constitución, +7 HP temp
    },
    mental = {
        { min = 25, status = "FOXS_CUNNING" },    -- ventaja en Inteligencia
        { min = 75, status = "AID" },             -- +5 HP máx
    },
    afectivo = {
        { min = 25, status = "OWLS_WISDOM" },     -- ventaja en Sabiduría
        { min = 75, status = "SHIELD_OF_FAITH" }, -- +2 CA
    },
    linguistico = {
        { min = 25, status = "CATS_GRACE" },      -- ventaja en Destreza
        { min = 75, status = "HEROISM" },         -- inmune a miedo
    },
}

-- ---------------------------------------------------------------------------
-- Config: buffs temporales por eventos de sensores
-- ---------------------------------------------------------------------------
-- event_type -> { status, duration (segundos) }. Son buffs suaves, sin
-- acciones extra, CA ni ventaja de ataque; eso queda para los tiers.
Effects.events = {
    ["streak.daily_logging"]    = { status = "GUIDANCE",    duration = 600  },
    ["budget.month_met"]        = { status = "RESISTANCE",  duration = 900  },
    ["route.completed.walking"] = { status = "LONGSTRIDER", duration = 1200 },
    ["route.completed.jogging"] = { status = "LONGSTRIDER", duration = 1800 },
    ["route.completed.hiking"]  = { status = "BLADE_WARD",  duration = 900  },
    ["route.freeroam"]          = { status = "LONGSTRIDER", duration = 600  },
}

-- savings.milestone escala con el hito (25/50/75): BLADE_WARD 300 s por cada
-- 25 % de la meta. Al 100 % (evento único por cuenta) el premio es HEROISM.
Effects.milestone = {
    status         = "BLADE_WARD",
    base_duration  = 300,
    final_status   = "HEROISM",
    final_duration = 900,
}

local EVENTS_PATH  = "LSGMod/recent_events.json"
-- Último id aplicado, persistido en archivo y no en PersistentVars: la
-- actividad es del mundo real y no debe re-otorgarse al cargar otra partida.
local APPLIED_PATH = "LSGMod/applied_events.json"

-- ---------------------------------------------------------------------------
-- Estado interno
-- ---------------------------------------------------------------------------
local _applied    = {}  -- dim -> status actualmente aplicado por tier (o nil)
local _tiers_info = {}  -- dim -> {status, min, pts} del tier aplicado (para snapshot)
local _recent_active = {}  -- lista de {status, event_type, expires} buffs de actividad reciente en curso

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function _host()
    local ok, h = pcall(Osi.GetHostCharacter)
    if ok and h and h ~= "" then return h end
    return nil
end

-- Normaliza el balance de la sesión a un dict {dimname(lower) = pts}.
local function _balance_map(session)
    local out = {}
    if type(session.balance) == "table" then
        for k, v in pairs(session.balance) do
            out[tostring(k):lower()] = math.tointeger(v) or math.floor(tonumber(v) or 0)
        end
    end
    -- Fallback/refuerzo: array dimensions [{name, balance}]
    if type(session.dimensions) == "table" then
        for _, d in ipairs(session.dimensions) do
            if d.name then
                out[tostring(d.name):lower()] = math.tointeger(d.balance) or 0
            end
        end
    end
    return out
end

-- Tier más alto cuyo min <= pts (o nil si ninguno).
local function _best_tier(dim, pts)
    local tiers = Effects.tiers[dim]
    if not tiers then return nil end
    local best = nil
    for _, t in ipairs(tiers) do
        if pts >= t.min and (best == nil or t.min >= best.min) then best = t end
    end
    return best
end

-- ---------------------------------------------------------------------------
-- API
-- ---------------------------------------------------------------------------

--- Re-evalúa todos los efectos contra el balance de la sesión dada.
function Effects.update(session)
    local host = _host()
    if not host or type(session) ~= "table" then return end
    local bal = _balance_map(session)

    -- 1) Tiers por acumulación
    for dim in pairs(Effects.tiers) do
        local pts  = bal[dim] or 0
        local tier = _best_tier(dim, pts)
        local want = tier and tier.status or nil
        local cur  = _applied[dim]
        if want ~= cur then
            if cur then Osi.RemoveStatus(host, cur) end
            if want then
                Osi.ApplyStatus(host, want, -1, 1, host)
                Ext.Utils.Print(string.format(
                    "[LSGames] Efecto pasivo %s aplicado (%s: %d pts)", want, dim, pts))
            else
                Ext.Utils.Print(string.format(
                    "[LSGames] Efecto pasivo %s removido (%s: %d pts)", cur, dim, pts))
            end
            _applied[dim] = want
        end
        -- Info fresca para el snapshot (pts cambia aunque el tier no)
        _tiers_info[dim] = want and { status = want, min = tier.min, pts = pts } or nil
    end
end

-- Status y duración para un evento, o nil si el event_type no está mapeado.
local function _event_buff(ev)
    local et = tostring(ev.event_type or "")
    if et == "savings.milestone" then
        local m   = Effects.milestone
        local pct = math.tointeger(ev.milestone) or 0
        if pct < 25 then return nil end
        if pct >= 100 then return m.final_status, m.final_duration end
        return m.status, m.base_duration * math.floor(pct / 25)
    end
    local cfg = Effects.events[et]
    if cfg then return cfg.status, cfg.duration end
    return nil
end

local function _load_last_event_id()
    local raw = Ext.IO.LoadFile(APPLIED_PATH, "user")
    if not raw or raw == "" then return 0 end
    local ok, st = pcall(Ext.Json.Parse, raw)
    return (ok and type(st) == "table" and math.tointeger(st.last_id)) or 0
end

--- Aplica buffs temporales por eventos de sensores aún no vistos.
-- Lee recent_events.json (solo eventos de las últimas 24 h; el filtro de
-- ventana lo hace el middleware, que tiene reloj real) y aplica el buff
-- mapeado a cada evento con id mayor al último ya aplicado.
function Effects.applyRecentEvents()
    local host = _host()
    if not host then return end

    local raw = Ext.IO.LoadFile(EVENTS_PATH, "user")
    if not raw or raw == "" then return end
    local ok, data = pcall(Ext.Json.Parse, raw)
    if not ok or type(data) ~= "table" or type(data.events) ~= "table" then return end

    local last   = _load_last_event_id()
    local max_id = last

    for _, ev in ipairs(data.events) do
        local id = math.tointeger(ev.id) or 0
        if id > last then
            local status, duration = _event_buff(ev)
            if status then
                Osi.ApplyStatus(host, status, duration, 1, host)
                _recent_active[#_recent_active + 1] = {
                    status     = status,
                    event_type = tostring(ev.event_type),
                    expires    = Ext.Utils.MonotonicTime() + duration * 1000,
                }
                Ext.Utils.Print(string.format(
                    "[LSGames] Actividad real: %s -> buff %s por %ds (evento #%d)",
                    tostring(ev.event_type), status, duration, id))
            end
            if id > max_id then max_id = id end
        end
    end

    if max_id > last then
        pcall(Ext.IO.SaveFile, APPLIED_PATH,
            Ext.Json.Stringify({ last_id = max_id }))
    end
end

--- Remueve todos los efectos pasivos por tier actualmente aplicados.
function Effects.clearAll()
    local host = _host()
    if not host then return end
    for dim, status in pairs(_applied) do
        if status then Osi.RemoveStatus(host, status) end
        _applied[dim] = nil
    end
    _tiers_info = {}
end

--- Snapshot de los efectos pasivos por tier actualmente aplicados.
-- Lo transmite BootstrapServer al cliente para la pestaña Efectos activos.
-- @return lista de {dim, status, min, pts} ordenada por dimensión
function Effects.snapshot()
    local out = {}
    for dim, info in pairs(_tiers_info) do
        out[#out + 1] = { dim = dim, status = info.status, min = info.min, pts = info.pts }
    end
    table.sort(out, function(a, b) return a.dim < b.dim end)
    return out
end

--- Snapshot de los buffs temporales por actividad reciente aún vigentes.
-- Descarta los ya expirados. Lo transmite BootstrapServer al cliente para
-- la pestaña Efectos activos > Actividad reciente.
-- @return lista de {status, event_type, remaining_ms}
function Effects.snapshotRecent()
    local now = Ext.Utils.MonotonicTime()
    local out = {}
    local kept = {}
    for _, e in ipairs(_recent_active) do
        if e.expires > now then
            kept[#kept + 1] = e
            out[#out + 1] = { status = e.status, event_type = e.event_type,
                               remaining_ms = e.expires - now }
        end
    end
    _recent_active = kept
    return out
end

return Effects
