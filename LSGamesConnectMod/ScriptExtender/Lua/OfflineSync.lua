--- Módulo de sincronización de puntos offline para BG3 (LSGames).
--
-- Gestiona una cola local de eventos de puntos generados sin conexión
-- permanente al servidor. Permite CREDIT (ganancias) y DEBIT (canjes).
--
-- Flujo:
--   1. addEvent(...) agrega el evento a offline_queue.json.
--   2. requestSync() escribe pending_offline_sync.json firmado (señal al middleware).
--   3. El middleware verifica la firma y llama POST /offline/sync en la API LSG.
--   4. El middleware escribe los resultados en offline_sync_result.json.
--   5. processResults() actualiza la cola y retorna {total, synced, ...}.

local SHA256        = Ext.Require("SHA256.lua")
local SessionReader = Ext.Require("SessionReader.lua")

local OfflineSync = {}

local QUEUE_PATH   = "LSGMod/offline_queue.json"
local PENDING_PATH = "LSGMod/pending_offline_sync.json"
local RESULT_PATH  = "LSGMod/offline_sync_result.json"
local SESSION_PATH = "LSGMod/session.json"

-- Contador de secuencia: solo orden local dentro del estado Lua (se reinicia
-- en cada carga de partida); no participa en la unicidad del client_ref
local _seq = 0

-- ---------------------------------------------------------------------------
-- Generación de client_ref
-- ---------------------------------------------------------------------------

-- client_ref = UUID v4 del sistema (UuidCreate vía BG3SE ≥ v32): único entre
-- sesiones, reinicios del equipo, instalaciones y jugadores. Los eventos ya
-- encolados conservan su ref original al reintentarse.
local function _new_ref()
    _seq = _seq + 1
    return Ext.Utils.GenerateGuid()
end

-- ---------------------------------------------------------------------------
-- Persistencia de la cola
-- ---------------------------------------------------------------------------

local function _load_queue()
    local raw = Ext.IO.LoadFile(QUEUE_PATH, "user")
    if not raw or raw == "" then return {} end
    local ok, data = pcall(Ext.Json.Parse, raw)
    return (ok and type(data) == "table") and data or {}
end

local function _save_queue(queue)
    pcall(Ext.IO.SaveFile, QUEUE_PATH, Ext.Json.Stringify(queue))
end

-- ---------------------------------------------------------------------------
-- Datos de sesión
-- ---------------------------------------------------------------------------

local function _session_info()
    local raw = Ext.IO.LoadFile(SESSION_PATH, "user")
    if not raw then return nil, nil end
    local ok, s = pcall(Ext.Json.Parse, raw)
    if not ok or type(s) ~= "table" then return nil, nil end
    local pid = math.tointeger(tonumber(s.userId or s.playerId or ""))
    local gid = s.gameId and math.tointeger(s.gameId) or nil
    return pid, gid
end

-- ---------------------------------------------------------------------------
-- API pública
-- ---------------------------------------------------------------------------

--- Agrega un evento de puntos a la cola offline.
--
-- @param direction   "CREDIT" o "DEBIT"
-- @param dim_id      integer  ID de la dimensión de puntos (id_point_dimension)
-- @param amount      integer  puntos a acreditar/debitar (siempre positivo)
-- @param trigger     string   disparador del evento ("quest_completed", "shop_redeem", …)
-- @param mechanic_id integer|nil  ID mmvg de la mecánica si es un canje (DEBIT)
-- @return string|nil, string|nil  client_ref generado, o nil + mensaje de error
function OfflineSync.addEvent(direction, dim_id, amount, trigger, mechanic_id)
    if direction ~= "CREDIT" and direction ~= "DEBIT" then
        return nil, "direction debe ser CREDIT o DEBIT"
    end

    dim_id = math.tointeger(dim_id) or 0
    amount = math.max(1, math.tointeger(amount) or 1)

    if dim_id <= 0 then
        return nil, "dim_id inválido (debe ser entero > 0)"
    end

    local ref   = _new_ref()
    local queue = _load_queue()

    local ev_payload = { trigger = tostring(trigger or "game_event") }
    if mechanic_id then
        ev_payload.mechanic_id = math.tointeger(mechanic_id) or mechanic_id
    end

    queue[#queue + 1] = {
        client_ref         = ref,
        seq                = _seq,
        mono_time          = Ext.Utils.MonotonicTime(),
        point_dimension_id = dim_id,
        direction          = direction,
        amount             = amount,
        source_type        = "OFFLINE_GAME",
        payload            = ev_payload,
        status             = "PENDING",
    }

    _save_queue(queue)
    Ext.Utils.Print(string.format(
        "[OfflineSync] +evento  %s  dim=%d  %d pts  [%s]  ref=%s",
        direction, dim_id, amount, trigger, ref))
    return ref
end

--- Solicita sincronización al middleware escribiendo pending_offline_sync.json.
--
-- El archivo es {body, sig}: body es la solicitud serializada y sig su
-- HMAC-SHA256 con el secreto compartido. Se firma el texto tal cual se escribe,
-- así el middleware no depende de reproducir la serialización de Lua.
--
-- El middleware detecta este archivo cada 3 s, verifica la firma, llama POST /offline/sync
-- y escribe los resultados en offline_sync_result.json.
-- Si el middleware no está activo, los eventos permanecen en cola
-- hasta que se llame requestSync() de nuevo cuando haya conexión.
--
-- @return boolean, string  true + mensaje si se escribió, false + error si no
function OfflineSync.requestSync()
    local queue   = _load_queue()
    local pending = {}
    for _, ev in ipairs(queue) do
        if ev.status == "PENDING" then
            pending[#pending + 1] = ev
        end
    end

    if #pending == 0 then
        return false, "No hay eventos PENDING en la cola"
    end

    local player_id, game_id = _session_info()
    if not player_id then
        return false, "Sin sesión activa — inicia sesión en LifeSyncGames primero"
    end

    local sync_req = {
        player_id = player_id,
        game_id   = game_id,
        events    = pending,
    }

    local body = Ext.Json.Stringify(sync_req)
    local ok, err = pcall(Ext.IO.SaveFile, PENDING_PATH, Ext.Json.Stringify({
        body = body,
        sig  = SHA256.hmac(SessionReader.secret(), body),
    }))
    if not ok then
        return false, "Error al escribir pending_offline_sync.json: " .. tostring(err)
    end

    return true, string.format(
        "Sincronización solicitada: %d evento(s) enviados al middleware", #pending)
end

--- Procesa los resultados devueltos por el middleware en offline_sync_result.json.
--
-- Actualiza la cola local:
--   SYNCED: se elimina (procesado correctamente)
--   DUPLICATE: se elimina (ya existía, idempotente)
--   REJECTED: se conserva con status="REJECTED" para revisión
--   Sin estado en el lote: permanece PENDING
--
-- Limpia offline_sync_result.json tras procesarlo para evitar re-lectura.
--
-- @return table|nil  Tabla de resumen {total, synced, rejected, duplicate, results}
--                    o nil si no hay resultados nuevos
function OfflineSync.processResults()
    local raw = Ext.IO.LoadFile(RESULT_PATH, "user")
    if not raw or raw == "" then return nil end

    local ok, result = pcall(Ext.Json.Parse, raw)
    if not ok or type(result) ~= "table" then return nil end

    -- Construir mapa client_ref -> status del lote recibido
    local status_map = {}
    if type(result.results) == "table" then
        for _, r in ipairs(result.results) do
            if r.client_ref then
                status_map[r.client_ref] = r.status or "SYNCED"
            end
        end
    end

    -- Actualizar cola conservando solo los no-exitosos
    local queue     = _load_queue()
    local new_queue = {}
    for _, ev in ipairs(queue) do
        local s = status_map[ev.client_ref]
        if s == "SYNCED" or s == "DUPLICATE" then
            -- Descartado: ya procesado por el servidor
        elseif s == "REJECTED" then
            ev.status = "REJECTED"
            new_queue[#new_queue + 1] = ev
        else
            -- No estaba en este lote: mantener como PENDING
            new_queue[#new_queue + 1] = ev
        end
    end
    _save_queue(new_queue)

    -- Limpiar archivo de resultados para no reprocesarlo
    pcall(Ext.IO.SaveFile, RESULT_PATH, "")

    return result
end

--- Retorna el número de eventos en estado PENDING en la cola.
function OfflineSync.pendingCount()
    local queue = _load_queue()
    local n = 0
    for _, ev in ipairs(queue) do
        if ev.status == "PENDING" then n = n + 1 end
    end
    return n
end

--- Retorna la lista completa de eventos en la cola (todos los estados).
function OfflineSync.listQueue()
    return _load_queue()
end

return OfflineSync
