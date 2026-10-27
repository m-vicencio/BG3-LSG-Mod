--- Módulo de localización para el mod LSGames.
--
-- Lee la preferencia de idioma desde LSGMod/locale.json (escrito por lsgames-app
-- cuando el usuario cambia el idioma en la UI del middleware).
-- Fallback a español si el archivo no existe o el idioma no está soportado.
--
-- Para añadir un idioma nuevo: agregar una tabla en STRINGS con el código ISO 639-1
-- y rellenar todas las claves.

local Locale = {}

local LOCALE_PATH = "LSGMod/locale.json"

-- ---------------------------------------------------------------------------
-- Catálogo de strings por idioma
-- ---------------------------------------------------------------------------

local DIMENSIONS = {
    es = {
        social      = "Social",
        fisico      = "Físico",
        afectivo    = "Afectivo",
        mental      = "Mental",
        linguistico = "Lingüístico",
    },
    en = {
        social      = "Social",
        fisico      = "Physical",
        afectivo    = "Affective",
        mental      = "Mental",
        linguistico = "Linguistic",
    },
}

local STRINGS = {
    es = {
        -- Botones y mensajes generales
        float_btn    = "Tienda LSG",
        btn_refresh  = "Actualizar",
        btn_close    = "Cerrar",
        btn_redeem   = "Canjear",
        pts_suffix   = " pts",
        no_balance   = "Sin datos — inicia sesión en LifeSyncGames",
        no_items     = "No hay ítems disponibles en el catálogo.",
        no_items_dim = "Sin ítems para esta dimensión.",
        processing   = "Procesando...",
        prefix_ok    = "[OK] ",
        prefix_err   = "[ERR] ",
        -- Mensajes de Shop.lua
        shop_err_dim     = "Dimensión inválida para %s",
        shop_err_cost    = "Costo no válido para %s",
        shop_sent        = "Canje enviado al servidor (%d pts).",
        shop_queued      = "Canje en cola (%d pts). Se sincronizará cuando el middleware esté activo.",
        shop_no_catalog  = "catalog.json no encontrado — asegúrate de que lsgames-app esté activo",
        shop_bad_catalog = "catalog.json no se pudo parsear",
        -- Tienda de puntos (StoreWindow / pestañas)
        store_title            = "Tienda de puntos LifeSyncGames",
        store_tab_catalog      = "Catálogo",
        store_tab_effects      = "Efectos activos",
        store_tab_transactions = "Transacciones",
        store_footer           = "Los puntos se sincronizan con tu actividad diaria en LifeSyncGames.",
        store_objects          = "Objetos",
        store_states           = "Estados",
        store_currencies       = "Divisas disponibles",
        store_cost             = "Costo: %d",
        store_insufficient     = "Saldo insuficiente de %s",
        store_empty_catalog    = "Selecciona una categoría para ver los contenidos.",
        store_no_effects       = "No hay efectos activos.",
        store_effects_label    = "Efectos:",
        store_time_left        = "Tiempo restante: %s",
        store_total_duration   = "Duración total: %d minutos",
        store_no_stack         = "No acumulable con otros efectos %s",
        store_fx_redeemed      = "Efectos canjeados",
        store_fx_passive       = "Efectos pasivos",
        store_fx_recent        = "Actividad reciente",
        store_permanent        = "Permanente",
        store_passive_threshold = "Otorgado por acumular %d pts en la dimensión %s (balance actual: %d)",
        store_passive_note     = "Se mantiene mientras el balance conserve el umbral.",
        store_recent_note      = "Buff temporal por actividad real reciente — expira solo.",
        store_no_transactions  = "Sin movimientos registrados.",
        store_col_date         = "Fecha",
        store_col_type         = "Tipo",
        store_col_desc         = "Descripción",
        store_col_currency     = "Divisa",
        store_col_amount       = "Monto",
        store_col_balance      = "Saldo",
        store_tx_expense       = "Gasto",
        store_tx_income        = "Ingreso",
        store_sync_error       = "No se pudo sincronizar con LifeSyncGames",
        -- Diálogo in-game (Notifier / OpenMessageBox)
        notifier_ok       = "LifeSyncGames — Middleware conectado",
        notifier_player    = "Jugador",
        notifier_id        = "ID     ",
        notifier_expires   = "Sesión válida hasta",
        notifier_open_app  = "Abre la aplicación LifeSyncGames e inicia sesión.",
        notifier_not_found = "Middleware no encontrado",
        notifier_parse_err = "Archivo de sesión corrupto",
        notifier_expired   = "Sesión expirada",
        notifier_bad_sig   = "Firma de sesión inválida",
        notifier_err       = "Error de conexión",
    },
    en = {
        -- General buttons and messages
        float_btn    = "LSG Store",
        btn_refresh  = "Refresh",
        btn_close    = "Close",
        btn_redeem   = "Redeem",
        pts_suffix   = " pts",
        no_balance   = "No data — log in to LifeSyncGames",
        no_items     = "No items available in catalog.",
        no_items_dim = "No items for this dimension.",
        processing   = "Processing...",
        prefix_ok    = "[OK] ",
        prefix_err   = "[ERR] ",
        -- Shop.lua messages
        shop_err_dim     = "Invalid dimension for %s",
        shop_err_cost    = "Invalid cost for %s",
        shop_sent        = "Redemption sent to server (%d pts).",
        shop_queued      = "Redemption queued (%d pts). Will sync when middleware is active.",
        shop_no_catalog  = "catalog.json not found — make sure lsgames-app is running",
        shop_bad_catalog = "catalog.json could not be parsed",
        -- Points store (StoreWindow / tabs)
        store_title            = "LifeSyncGames Points Store",
        store_tab_catalog      = "Catalog",
        store_tab_effects      = "Active effects",
        store_tab_transactions = "Transactions",
        store_footer           = "Points sync with your daily activity in LifeSyncGames.",
        store_objects          = "Items",
        store_states           = "Statuses",
        store_currencies       = "Available currencies",
        store_cost             = "Cost: %d",
        store_insufficient     = "Insufficient %s balance",
        store_empty_catalog    = "Select a category to see its contents.",
        store_no_effects       = "No active effects.",
        store_effects_label    = "Effects:",
        store_time_left        = "Time remaining: %s",
        store_total_duration   = "Total duration: %d minutes",
        store_no_stack         = "Does not stack with other %s effects",
        store_fx_redeemed      = "Redeemed effects",
        store_fx_passive       = "Passive effects",
        store_fx_recent        = "Recent activity",
        store_permanent        = "Permanent",
        store_passive_threshold = "Granted for accumulating %d pts in the %s dimension (current balance: %d)",
        store_passive_note     = "Persists while the balance stays above the threshold.",
        store_recent_note      = "Temporary buff from recent real-world activity — expires on its own.",
        store_no_transactions  = "No recorded transactions.",
        store_col_date         = "Date",
        store_col_type         = "Type",
        store_col_desc         = "Description",
        store_col_currency     = "Currency",
        store_col_amount       = "Amount",
        store_col_balance      = "Balance",
        store_tx_expense       = "Expense",
        store_tx_income        = "Income",
        store_sync_error       = "Could not sync with LifeSyncGames",
        -- In-game dialog (Notifier / OpenMessageBox)
        notifier_ok       = "LifeSyncGames — Middleware connected",
        notifier_player    = "Player ",
        notifier_id        = "ID     ",
        notifier_expires   = "Session valid until",
        notifier_open_app  = "Open the LifeSyncGames app and log in.",
        notifier_not_found = "Middleware not found",
        notifier_parse_err = "Corrupted session file",
        notifier_expired   = "Session expired",
        notifier_bad_sig   = "Invalid session signature",
        notifier_err       = "Connection error",
    },
}

local _lang = "es"
local _L    = STRINGS["es"]
local _D    = DIMENSIONS["es"]

-- ---------------------------------------------------------------------------
-- API pública
-- ---------------------------------------------------------------------------

--- Recarga la preferencia de idioma desde LSGMod/locale.json.
-- Llamar al abrir la tienda para recoger cambios del middleware sin reiniciar BG3.
function Locale.reload()
    local raw = Ext.IO.LoadFile(LOCALE_PATH, "user")
    if raw and raw ~= "" then
        local ok, data = pcall(Ext.Json.Parse, raw)
        if ok and type(data) == "table" and data.lang then
            local lang = tostring(data.lang)
            if STRINGS[lang] then
                _lang = lang
                _L    = STRINGS[lang]
                _D    = DIMENSIONS[lang] or DIMENSIONS["es"]
                return
            end
        end
    end
    _lang = "es"
    _L    = STRINGS["es"]
    _D    = DIMENSIONS["es"]
end

--- Traduce una clave al idioma activo. Devuelve la clave si no se encuentra.
function Locale.t(key)
    return _L[key] or key
end

--- Alterna entre los idiomas disponibles y escribe locale.json para sincronizar
-- con el middleware en la próxima sesión.
function Locale.toggle()
    local new_lang = (_lang == "es") and "en" or "es"
    if STRINGS[new_lang] then
        _lang = new_lang
        _L    = STRINGS[new_lang]
        _D    = DIMENSIONS[new_lang] or DIMENSIONS["es"]
        pcall(Ext.IO.SaveFile, LOCALE_PATH,
            Ext.Json.Stringify({ lang = new_lang }))
    end
end

--- Retorna la etiqueta del botón de cambio de idioma (muestra el idioma al que se irá).
function Locale.btn_label()
    return (_lang == "es") and "EN" or "ES"
end

--- Traduce el nombre de una dimensión desde su código de API.
-- Fallback a capitalize() para dimensiones futuras no registradas.
-- Ejemplo: Locale.dim("fisico") devuelve "Físico" / "Physical"
function Locale.dim(api_name)
    if not api_name then return "?" end
    return _D[api_name] or (api_name:sub(1,1):upper() .. api_name:sub(2))
end

--- Retorna el código del idioma activo ("es", "en", …).
function Locale.lang()
    return _lang
end

-- Cargar idioma al importar el módulo
Locale.reload()

return Locale
