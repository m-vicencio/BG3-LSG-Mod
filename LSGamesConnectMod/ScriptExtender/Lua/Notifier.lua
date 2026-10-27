--- Módulo de notificaciones para el estado del middleware LSGames.
--
-- Muestra el balance multidimensional del Gemelo Digital Simplificado en la
-- consola SE y en diálogos del juego. BootstrapClient reutiliza los
-- formateadores de fecha y balance.

local Locale  = Ext.Require("Locale.lua")
local Notifier = {}

local PREFIX = "[LSGames]"

local function _fmt_time(ts)
    ts = math.tointeger(ts) or math.floor(ts)
    local H = math.floor((ts % 86400) / 3600)
    local M = math.floor((ts % 3600) / 60)
    local S = ts % 60
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
    return string.format("%02d/%02d/%04d %02d:%02d:%02d", d, mo, y, H, M, S)
end

-- ---------------------------------------------------------------------------
-- Helpers de formateo
-- ---------------------------------------------------------------------------

--- Formatea el balance multidimensional de session.balance como string.
--
-- session.balance es un dict {nombre_dim: puntos} con los atributos LSG
-- (social, fisico, afectivo, mental, linguistico).
local function _fmt_balance(balance)
    if type(balance) ~= "table" then return "sin balance" end
    local parts = {}
    local keys  = {}
    for k in pairs(balance) do keys[#keys+1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do
        local pts = math.tointeger(balance[k]) or math.floor(balance[k])
        parts[#parts+1] = k:sub(1,1):upper() .. k:sub(2) .. ": " .. pts
    end
    return table.concat(parts, "  |  ")
end

local function _format_status_line(result)
    if result.ok then
        local s = result.session
        return string.format(
            "CONECTADO  |  Jugador: %s  |  %s  |  Expira: %s",
            s.userId,
            _fmt_balance(s.balance),
            _fmt_time(s.expires)
        )
    else
        return string.format("SIN CONEXIÓN  |  %s  |  %s",
            result.status, result.error or "error desconocido")
    end
end

local function _format_dialog(result)
    if result.ok then
        local s = result.session
        local name_line = ""
        if s.playerName then
            name_line = Locale.t("notifier_player") .. ": " .. tostring(s.playerName) .. "\n"
        end
        return string.format(
            Locale.t("notifier_ok") .. "\n\n"
            .. "%s"
            .. Locale.t("notifier_id") .. ": %s\n"
            .. "%s\n"
            .. Locale.t("notifier_expires") .. ": %s",
            name_line,
            s.userId,
            _fmt_balance(s.balance),
            _fmt_time(s.expires)
        )
    else
        local labels = {
            NOT_FOUND = Locale.t("notifier_not_found"),
            PARSE_ERR = Locale.t("notifier_parse_err"),
            EXPIRED   = Locale.t("notifier_expired"),
            BAD_SIG   = Locale.t("notifier_bad_sig"),
        }
        local titulo = labels[result.status] or Locale.t("notifier_err")
        return string.format(
            "LifeSyncGames — %s\n\n%s\n\n" .. Locale.t("notifier_open_app"),
            titulo,
            result.error or ""
        )
    end
end

-- ---------------------------------------------------------------------------
-- API pública
-- ---------------------------------------------------------------------------

function Notifier.console(result)
    Ext.Utils.Print(PREFIX .. " " .. _format_status_line(result))
end

function Notifier.ingame(result, characterGuid)
    if not characterGuid or characterGuid == "" then
        Ext.Utils.Print(PREFIX .. " [AVISO] No hay personaje host para mostrar el diálogo.")
        return
    end
    local text = _format_dialog(result)
    local ok, err = pcall(Osi.OpenMessageBox, characterGuid, text)
    if not ok then
        Ext.Utils.Print(PREFIX .. " [AVISO] No se pudo mostrar el diálogo: " .. tostring(err))
    end
end

function Notifier.separator()
    Ext.Utils.Print(PREFIX .. " " .. string.rep("-", 60))
end

Notifier.fmt_time    = _fmt_time
Notifier.fmt_balance = _fmt_balance

return Notifier
