--- Reloj de pared aproximado para BG3SE (que no expone os.time).
--
-- Ancla el unix time que el middleware escribe en lsg_notify.json
-- (server_time, con fallback al campo ts) al reloj monotónico del juego y
-- extrapola desde ahí. Si el middleware escribe de nuevo, se re-ancla y
-- corrige la deriva.
--
-- El error posible es siempre "hacia atrás" (el tiempo entre la escritura del
-- archivo y nuestra primera lectura no se puede medir), así que las
-- validaciones de expiración basadas en este reloj son lenientes, nunca
-- rechazan de más.

local Clock = {}

local NOTIFY_PATH = "LSGMod/lsg_notify.json"

local _anchor_wall = nil  -- segundos unix del último server_time visto
local _anchor_mono = nil  -- ms monotónicos en el momento de verlo
local _last_seen   = nil  -- último valor anclado (para detectar cambios)

--- Unix time aproximado en segundos, o nil si aún no hay referencia
-- del middleware (nunca escribió lsg_notify.json).
function Clock.now()
    local mono = Ext.Utils.MonotonicTime()

    local raw = Ext.IO.LoadFile(NOTIFY_PATH, "user")
    if raw and raw ~= "" then
        local ok, data = pcall(Ext.Json.Parse, raw)
        if ok and type(data) == "table" then
            local t = tonumber(data.server_time or data.ts)
            if t and t ~= _last_seen then
                _last_seen   = t
                _anchor_wall = math.floor(t)
                _anchor_mono = mono
            end
        end
    end

    if not _anchor_wall then return nil end
    return _anchor_wall + math.floor((mono - _anchor_mono) / 1000)
end

return Clock
