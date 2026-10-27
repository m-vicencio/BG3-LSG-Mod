--- Lectura y validación del archivo de sesión generado por el middleware LSGames.
--
-- Lee ``Script Extender/LSGMod/session.json`` desde el directorio de usuario
-- de BG3 (``%LOCALAPPDATA%\Larian Studios\Baldur's Gate 3\``), valida la
-- expiración y verifica la firma HMAC-SHA-256.
--
-- Uso:
--   local SessionReader = Ext.Require("SessionReader.lua")
--   local result = SessionReader.load()
--   if result.ok then ... end

local SHA256 = Ext.Require("SHA256.lua")
local Clock  = Ext.Require("Clock.lua")

local SessionReader = {}

-- Ruta del archivo de sesión relativa al directorio de usuario de BG3.
-- Coincide con ``SE_SESSION_PATH`` en ``lsgames-app/config.py``.
local SESSION_PATH = "LSGMod/session.json"

-- Ruta del archivo de configuración del mod (contiene el secreto compartido).
-- Debe crearse manualmente con: {"shared_secret": "tu_secreto"}
local MOD_CONFIG_PATH = "LSGMod/mod_config.json"

-- Secreto por defecto: debe coincidir con SHARED_SECRET en lsgames-app/config.py.
-- Sobreescribir usando el archivo de configuración del mod indicado arriba.
local DEFAULT_SECRET = "change-me-in-production"

-- ---------------------------------------------------------------------------
-- Utilidades internas
-- ---------------------------------------------------------------------------

--- Carga el secreto compartido desde el archivo de configuración del mod.
--
-- Si el archivo no existe o no se puede parsear, devuelve el valor por defecto.
--
-- @return string  Secreto compartido a usar para verificar la firma.
local function _load_secret()
    local raw = Ext.IO.LoadFile(MOD_CONFIG_PATH, "user")
    if not raw then
        return DEFAULT_SECRET
    end

    local ok, cfg = pcall(Ext.Json.Parse, raw)
    if ok and cfg and cfg.shared_secret then
        return tostring(cfg.shared_secret)
    end

    return DEFAULT_SECRET
end

--- Serializa un valor Lua a JSON canónico con claves ordenadas alfabéticamente.
--
-- Replica ``json.dumps(payload, sort_keys=True, separators=(",", ":"))`` de Python.
-- Solo soporta los tipos presentes en el payload de sesión: string, number, table.
--
-- @param value any  Valor a serializar.
-- @return string    Representación JSON canónica.
local function _canonical_json(value)
    local t = type(value)

    if t == "number" then
        -- Todos los números del payload son enteros; eliminar decimales si los hubiera
        local as_int = math.tointeger(value)
        return tostring(as_int ~= nil and as_int or math.floor(value))

    elseif t == "string" then
        -- Escapado mínimo necesario para los valores del payload
        local escaped = value
            :gsub("\\", "\\\\")
            :gsub('"',  '\\"')
            :gsub("\n", "\\n")
            :gsub("\r", "\\r")
            :gsub("\t", "\\t")
        return '"' .. escaped .. '"'

    elseif t == "table" then
        -- Ordenar claves alfabéticamente para firma determinista
        local keys = {}
        for k in pairs(value) do
            keys[#keys + 1] = k
        end
        table.sort(keys)

        local parts = {}
        for _, k in ipairs(keys) do
            parts[#parts + 1] = '"' .. k .. '":' .. _canonical_json(value[k])
        end
        return "{" .. table.concat(parts, ",") .. "}"

    elseif t == "boolean" then
        return value and "true" or "false"
    end

    return "null"
end

--- Construye el payload de verificación eliminando el campo ``"sig"``.
--
-- El payload firmado contiene userId, balance (dict de dimensiones) y expires.
-- Las claves de balance son las de session.json (p. ej. {social=150, fisico=100}).
--
-- @param session table  Sesión parseada completa (incluye "sig").
-- @return table         Copia del payload sin los campos fuera del HMAC.
local function _payload_without_sig(session)
    return {
        userId  = session.userId,
        balance = session.balance,  -- tabla con las dimensiones reales
        expires = session.expires,
    }
end

-- ---------------------------------------------------------------------------
-- API pública
-- ---------------------------------------------------------------------------

--- Estado de conexión enumerado para facilitar comparaciones en BootstrapServer.
SessionReader.Status = {
    NOT_FOUND  = "NOT_FOUND",   -- El archivo de sesión no existe
    PARSE_ERR  = "PARSE_ERR",   -- El JSON no se pudo parsear
    EXPIRED    = "EXPIRED",     -- La sesión está vencida
    BAD_SIG    = "BAD_SIG",     -- La firma HMAC no coincide
    OK         = "OK",          -- Sesión válida y activa
}

--- Lee, parsea y valida el archivo session.json del middleware.
--
-- Pasos de validación (en orden):
--   1. Existencia del archivo.
--   2. Estructura mínima (campos obligatorios presentes).
--   3. Expiración del timestamp ``expires``.
--   4. Verificación de firma HMAC-SHA-256.
--
-- @return table  Resultado con los campos:
--   - ``ok``      (boolean) true si la sesión es válida y activa.
--   - ``status``  (string)  Código de ``SessionReader.Status``.
--   - ``session`` (table|nil) Datos de la sesión si fue leída correctamente.
--   - ``error``   (string|nil) Mensaje de error legible si ``ok`` es false.
function SessionReader.load()
    -- 1. Leer el archivo desde el directorio de usuario de BG3
    local raw = Ext.IO.LoadFile(SESSION_PATH, "user")
    if not raw or raw == "" then
        return {
            ok     = false,
            status = SessionReader.Status.NOT_FOUND,
            error  = "Archivo de sesión no encontrado: " .. SESSION_PATH,
        }
    end

    -- 2. Parsear JSON
    local ok, session = pcall(Ext.Json.Parse, raw)
    if not ok or type(session) ~= "table" then
        return {
            ok     = false,
            status = SessionReader.Status.PARSE_ERR,
            error  = "No se pudo parsear session.json: " .. tostring(session),
        }
    end

    -- Verificar campos obligatorios
    if not session.userId or not session.expires or
       type(session.balance) ~= "table" or not next(session.balance) then
        return {
            ok      = false,
            status  = SessionReader.Status.PARSE_ERR,
            session = session,
            error   = "session.json no contiene los campos obligatorios (userId, balance con dimensiones, expires)",
        }
    end

    -- 3. Verificar expiración (best-effort: usa el reloj de pared anclado por
    --    Clock desde lsg_notify.json; si aún no hay referencia, se omite)
    local expires = math.tointeger(session.expires) or math.floor(session.expires)
    local now = Clock.now()
    if now and now > expires then
        return {
            ok      = false,
            status  = SessionReader.Status.EXPIRED,
            session = session,
            error   = "La sesión expiró — abre LifeSyncGames para renovarla",
        }
    end

    -- 4. Verificar firma HMAC-SHA-256
    local secret  = _load_secret()
    local payload = _payload_without_sig(session)
    local canonical  = _canonical_json(payload)
    local expected   = SHA256.hmac(secret, canonical)
    local actual_sig = tostring(session.sig or "")

    if expected ~= actual_sig then
        return {
            ok      = false,
            status  = SessionReader.Status.BAD_SIG,
            session = session,
            error   = "Firma HMAC inválida — el secreto compartido no coincide o el archivo fue alterado",
        }
    end

    -- Sesión válida
    return {
        ok      = true,
        status  = SessionReader.Status.OK,
        session = session,
    }
end

--- Secreto compartido actual (mod_config.json o el valor por defecto).
-- Lo usan Shop y OfflineSync para firmar sus solicitudes al middleware.
SessionReader.secret = _load_secret

return SessionReader
