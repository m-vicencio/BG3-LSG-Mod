--- Módulo de tienda LSGames. Se comunica con el middleware solo mediante
-- archivos locales.
--
-- Lee el catálogo desde LSGMod/catalog.json (escrito por lsgames-app).
-- Las solicitudes de compra se escriben en LSGMod/pending_purchase.json
-- firmadas con HMAC-SHA256; el middleware verifica la firma antes de procesar.
--
-- offline_buy() usa la cola offline (POST /offline/sync) en vez del
-- flujo directo, permitiendo canjear sin conexión permanente al servidor.

local SHA256        = Ext.Require("SHA256.lua")
local SessionReader = Ext.Require("SessionReader.lua")
local OfflineSync   = Ext.Require("OfflineSync.lua")
local Locale        = Ext.Require("Locale.lua")
local Shop          = {}

local CATALOG_PATH   = "LSGMod/catalog.json"
local PURCHASE_PATH  = "LSGMod/pending_purchase.json"

-- ---------------------------------------------------------------------------
-- JSON canónico para firma determinista
-- ---------------------------------------------------------------------------

local function _canonical(value)
    local t = type(value)
    if t == "number" then
        local i = math.tointeger(value)
        return tostring(i ~= nil and i or math.floor(value))
    elseif t == "string" then
        return '"' .. value:gsub("\\","\\\\"):gsub('"','\\"'):gsub("\n","\\n") .. '"'
    elseif t == "boolean" then
        return value and "true" or "false"
    elseif t == "table" then
        local keys = {}
        for k in pairs(value) do keys[#keys+1] = k end
        table.sort(keys)
        local parts = {}
        for _, k in ipairs(keys) do
            parts[#parts+1] = '"' .. k .. '":' .. _canonical(value[k])
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    return "null"
end

-- ---------------------------------------------------------------------------
-- API pública
-- ---------------------------------------------------------------------------

--- Lee el catálogo de ítems desde catalog.json.
function Shop.catalog(callback)
    local raw = Ext.IO.LoadFile(CATALOG_PATH, "user")
    if not raw or raw == "" then
        callback(false, Locale.t("shop_no_catalog"))
        return
    end
    local ok, data = pcall(Ext.Json.Parse, raw)
    if not ok or type(data) ~= "table" then
        callback(false, Locale.t("shop_bad_catalog"))
        return
    end
    callback(true, data)
end

--- Escribe una solicitud de compra firmada en pending_purchase.json.
--
-- El payload {itemId, amount, timestamp} se firma con HMAC-SHA256
-- usando el mismo secreto que session.json. El middleware rechaza
-- cualquier solicitud con firma inválida.
function Shop.buy(item_id, amount, callback)
    local payload = {
        itemId    = item_id,
        amount    = math.max(1, amount),
        timestamp = Ext.Utils.MonotonicTime(),
    }

    local secret    = SessionReader.secret()
    local canonical = _canonical(payload)
    local sig       = SHA256.hmac(secret, canonical)

    local signed = {
        itemId    = payload.itemId,
        amount    = payload.amount,
        timestamp = payload.timestamp,
        sig       = sig,
    }

    local ok, err = pcall(Ext.IO.SaveFile, PURCHASE_PATH,
        Ext.Json.Stringify(signed))

    if not ok then
        callback(false, "No se pudo escribir la solicitud: " .. tostring(err))
        return
    end

    callback(true, "Compra realizada. El balance se actualizara en breve.")
end

--- Canjea una mecánica usando la cola de puntos offline (POST /offline/sync).
--
-- En lugar de pending_purchase.json (canje online inmediato), registra un
-- evento DEBIT en la cola offline y solicita sincronización al middleware.
-- Si el middleware no está activo, el evento queda en cola para la próxima
-- vez que haya conexión.
--
-- @param item         tabla del catálogo con {itemId, mmvgId, dimensionId, cost}
-- @param amount_mult  integer  veces a canjear (multiplica item.cost)
-- @param callback     function(ok, msg)
function Shop.offline_buy(item, amount_mult, callback)
    local dim_id  = math.tointeger(item.dimensionId) or 0
    local cost    = math.tointeger(item.cost) or 0
    local mmvg_id = math.tointeger(item.mmvgId) or 0
    amount_mult   = math.max(1, math.tointeger(amount_mult) or 1)

    if dim_id == 0 then
        callback(false, string.format(Locale.t("shop_err_dim"), tostring(item.itemId or "?")))
        return
    end
    if cost <= 0 then
        callback(false, string.format(Locale.t("shop_err_cost"), tostring(item.itemId or "?")))
        return
    end

    local total_pts = cost * amount_mult
    local ref, err  = OfflineSync.addEvent(
        "DEBIT", dim_id, total_pts, "shop_redeem", mmvg_id)

    if not ref then
        callback(false, Locale.t("prefix_err") .. tostring(err))
        return
    end

    -- Intentar sincronización inmediata; si falla, el evento queda en cola
    local sync_ok, _ = OfflineSync.requestSync()
    if sync_ok then
        callback(true, string.format(Locale.t("shop_sent"), total_pts))
    else
        callback(true, string.format(Locale.t("shop_queued"), total_pts))
    end
end

return Shop
