--- Estado en memoria de la Tienda de puntos LifeSyncGames (lado cliente).
--
-- Centraliza las lecturas de los archivos JSON del directorio de intercambio
-- (LSGMod/) reutilizando los módulos existentes: SessionReader (balance con
-- verificación HMAC) y Shop (catálogo). Todas las lecturas van en pcall;
-- ante archivo ausente/corrupto se degrada a estado vacío sin crashear.

local SessionReader = Ext.Require("SessionReader.lua")
local Shop          = Ext.Require("Shop.lua")
local Locale        = Ext.Require("Locale.lua")

local State = {}

local TRANSACTIONS_PATH = "LSGMod/transactions.json"

-- ---------------------------------------------------------------------------
-- Datos públicos
-- ---------------------------------------------------------------------------

State.balance      = {}   -- dimensionName -> puntos
State.catalog      = nil  -- lista de entradas de catalog.json (nil = no cargado)
State.transactions = {}   -- lista de movimientos (descendente, del middleware)
State.session_ok   = false
State.error        = nil  -- mensaje de error de sincronización (o nil)

-- Colores por divisa (mismos que la app de escritorio): Social verde,
-- Físico rojo, Afectivo morado, Mental azul, Lingüístico amarillo.
State.DIM_COLORS = {
    social      = { 0.30, 0.80, 0.35, 1.0 },
    fisico      = { 0.90, 0.25, 0.25, 1.0 },
    afectivo    = { 0.65, 0.40, 0.90, 1.0 },
    mental      = { 0.25, 0.55, 1.00, 1.0 },
    linguistico = { 0.95, 0.76, 0.20, 1.0 },
}

--- Color de una dimensión (fallback dorado para dimensiones futuras).
function State.color(dim)
    return State.DIM_COLORS[tostring(dim)] or { 0.9, 0.8, 0.3, 1.0 }
end

-- ---------------------------------------------------------------------------
-- Recarga de archivos
-- ---------------------------------------------------------------------------

local function _load_transactions()
    local raw = Ext.IO.LoadFile(TRANSACTIONS_PATH, "user")
    if not raw or raw == "" then return {} end
    local ok, data = pcall(Ext.Json.Parse, raw)
    return (ok and type(data) == "table") and data or {}
end

--- Relee balance, catálogo y transacciones desde el directorio de intercambio.
function State.reload()
    local ok, r = pcall(SessionReader.load)
    if ok and r.ok and r.session and type(r.session.balance) == "table" then
        State.balance    = r.session.balance
        State.session_ok = true
        State.error      = nil
    else
        State.balance    = {}
        State.session_ok = false
        State.error      = Locale.t("store_sync_error")
    end

    Shop.catalog(function(cat_ok, data)
        State.catalog = cat_ok and data or nil
    end)

    local tx_ok, txs = pcall(_load_transactions)
    State.transactions = tx_ok and txs or {}
end

-- ---------------------------------------------------------------------------
-- Partición del catálogo
-- ---------------------------------------------------------------------------

local function _is_status(item)
    return item.bg3Status ~= nil and item.bg3TemplateId == nil
end

--- Entradas del catálogo que son Objetos (todo lo que no es un estado puro).
function State.objects()
    local out = {}
    for _, item in ipairs(State.catalog or {}) do
        if not _is_status(item) then out[#out + 1] = item end
    end
    return out
end

--- Entradas del catálogo que son Estados (aplican un status BG3, sin objeto).
function State.statuses()
    local out = {}
    for _, item in ipairs(State.catalog or {}) do
        if _is_status(item) then out[#out + 1] = item end
    end
    return out
end

-- ---------------------------------------------------------------------------
-- Balance
-- ---------------------------------------------------------------------------

--- Descuento optimista local tras encolar una compra (el saldo real llega
-- cuando el middleware sincroniza y reescribe session.json).
function State.debit(dim, pts)
    local cur = math.tointeger(State.balance[dim]) or 0
    State.balance[dim] = math.max(0, cur - pts)
end

-- ---------------------------------------------------------------------------
-- Formateo de fechas
-- ---------------------------------------------------------------------------

--- Convierte un timestamp Unix a "YYYY-MM-DD HH:MM" (sin os.date, no
-- disponible en BG3SE). Mismo algoritmo civil-from-days de Notifier.lua.
function State.fmt_time(ts)
    ts = math.tointeger(ts) or math.floor(tonumber(ts) or 0)
    local H = math.floor((ts % 86400) / 3600)
    local M = math.floor((ts % 3600) / 60)
    local z = math.floor(ts / 86400) + 719468
    local era = math.floor((z >= 0 and z or z - 146096) / 146097)
    local doe = z - era * 146097
    local yoe = math.floor((doe - math.floor(doe/1460) + math.floor(doe/36524) - math.floor(doe/146096)) / 365)
    local y   = yoe + era * 400
    local doy = doe - (365*yoe + math.floor(yoe/4) - math.floor(yoe/100))
    local mp  = math.floor((5*doy + 2) / 153)
    local d   = doy - math.floor((153*mp + 2) / 5) + 1
    local mo  = mp + (mp < 10 and 3 or -9)
    if mo <= 2 then y = y + 1 end
    return string.format("%04d-%02d-%02d %02d:%02d", y, mo, d, H, M)
end

return State
