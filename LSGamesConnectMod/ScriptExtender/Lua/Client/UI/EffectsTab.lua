--- Pestaña Efectos activos de la Tienda de puntos.
--
-- Tres submenús tipo toggle:
--   - Canjeados: Estados comprados en la tienda en esta sesión de juego, con
--     cuenta regresiva local (hook Purchase.onEffectApplied, tiempo monotónico).
--   - Pasivos: efectos por hitos de acumulación (tiers de Effects.lua, lado
--     servidor), recibidos por red vía el canal LSGames_PassiveEffects.
--   - Actividad reciente: buffs temporales por eventos de sensores
--     (Effects.applyRecentEvents, lado servidor), mismo canal de red
--     (campo "recent"). Cuenta regresiva local igual que Canjeados, pero
--     partiendo del remaining_ms recibido en el snapshot.
--
-- La lista de canjeados vive en memoria y se pierde al reiniciar el juego: el
-- countdown usa tiempo monotónico. Conservarla entre reinicios requeriría el
-- reloj de pared de Clock.lua.

local State    = Ext.Require("Client/Store/State.lua")
local Purchase = Ext.Require("Client/Store/Purchase.lua")
local Icons    = Ext.Require("Icons.lua")
local Locale   = Ext.Require("Locale.lua")

local EffectsTab = {}

local EFFECTS_PATH = "LSGMod/active_effects.json"

local COLOR_ACTIVE   = { 0.20, 0.45, 0.80, 1.0 }
local COLOR_INACTIVE = { 0.23, 0.23, 0.26, 1.0 }
local COLOR_DIM_TEXT = { 0.70, 0.70, 0.70, 1.0 }

-- ---------------------------------------------------------------------------
-- Estado interno
-- ---------------------------------------------------------------------------

local _mode = "redeemed"  -- "redeemed" | "passive" | "recent"

-- Canjeados: {name, description, dim, duration_s, expires (ms monotónicos)}
local _effects = {}
-- Pasivos (del servidor): {dim, status, min, pts}
local _passive = {}
-- Actividad reciente (del servidor): {status, event_type, expires (ms monotónicos locales)}
local _recent = {}

local _btn_redeemed, _btn_passive, _btn_recent = nil, nil, nil
local _group   = nil
local _widgets = {}   -- widgets creados dinámicamente (tracking manual)
local _timers  = {}   -- refs a labels "Tiempo restante" -> efecto

local function _clear()
    for _, w in ipairs(_widgets) do
        pcall(function() w:Destroy() end)
    end
    _widgets, _timers = {}, {}
end

local function _track(w) _widgets[#_widgets + 1] = w; return w end

local function _paint_toggle()
    if not _btn_redeemed then return end
    pcall(function()
        _btn_redeemed:SetColor("Button", _mode == "redeemed" and COLOR_ACTIVE or COLOR_INACTIVE)
        _btn_passive:SetColor("Button",  _mode == "passive"  and COLOR_ACTIVE or COLOR_INACTIVE)
        _btn_recent:SetColor("Button",   _mode == "recent"   and COLOR_ACTIVE or COLOR_INACTIVE)
    end)
end

local function _persist()
    local now = Ext.Utils.MonotonicTime()
    local out = {}
    for _, e in ipairs(_effects) do
        out[#out + 1] = {
            name         = e.name,
            dimension    = e.dim,
            remaining_ms = math.max(0, e.expires - now),
            duration_s   = e.duration_s,
        }
    end
    pcall(Ext.IO.SaveFile, EFFECTS_PATH, Ext.Json.Stringify(out))
end

local function _fmt_mmss(ms)
    local s = math.max(0, math.floor(ms / 1000))
    return string.format("%02d:%02d", math.floor(s / 60), s % 60)
end

local function _empty_state()
    pcall(function() _track(_group:AddDummy(0, 60)) end)
    local txt = _track(_group:AddText(Locale.t("store_no_effects")))
    pcall(function() txt:SetColor("Text", COLOR_DIM_TEXT) end)
end

--- Quita el marcado interno de las strings localizadas de BG3
-- (<LSTag Tooltip="...">texto</LSTag>, <br>, etc.), conservando el texto.
local function _strip_markup(s)
    s = s:gsub("<br>", " ")
    s = s:gsub("<[^>]*>", "")   -- elimina cualquier etiqueta, conserva el contenido
    s = s:gsub("%s+", " ")
    return (s:match("^%s*(.-)%s*$"))
end

--- Resuelve un campo localizado (DisplayName/Description) de un status del
-- juego a su texto in-game, sin marcado. Fallback: nil si no se puede resolver.
local function _status_loca(status_id, field)
    local text = nil
    pcall(function()
        local stat = Ext.Stats.Get(tostring(status_id))
        local handle = stat and stat[field]
        if handle and handle ~= "" then
            local resolved = Ext.Loca.GetTranslatedString(handle)
            if resolved and resolved ~= "" then
                resolved = _strip_markup(resolved)
                if resolved ~= "" then text = resolved end
            end
        end
    end)
    return text
end

--- Añade el ícono vanilla real del status (el mismo atlas que usa la barra
-- de estados del personaje), no un placeholder de dimensión.
-- Fallback: nil si el status no tiene Icon o no se pudo resolver.
local function _status_icon(parent, status_id, size)
    local img = nil
    pcall(function()
        local stat = Ext.Stats.Get(tostring(status_id))
        local icon = stat and stat.Icon
        if icon and icon ~= "" then
            img = parent:AddImage(icon, size or { 20, 20 })
        end
    end)
    return img
end

-- ---------------------------------------------------------------------------
-- Render: efectos canjeados
-- ---------------------------------------------------------------------------

local function _populate_redeemed()
    local now = Ext.Utils.MonotonicTime()

    if #_effects == 0 then
        _empty_state()
        return
    end

    for i, e in ipairs(_effects) do
        -- Encabezado: icono + nombre | tiempo restante a la derecha
        local tbl_ok = pcall(function()
            local tbl = _track(_group:AddTable("fx_hdr_" .. i, 2))
            local row = tbl:AddRow()
            local c1  = row:AddCell()
            local img = Icons.add(c1, "dim_" .. tostring(e.dim), { 20, 20 })
            local name = c1:AddText(tostring(e.name))
            if img then name.SameLine = true end
            pcall(function() name:SetColor("Text", State.color(e.dim)) end)
            local c2 = row:AddCell()
            local timer = c2:AddText(string.format(
                Locale.t("store_time_left"), _fmt_mmss(e.expires - now)))
            _timers[#_timers + 1] = { label = timer, effect = e }
        end)
        if not tbl_ok then
            -- Fallback sin tabla: todo en una línea
            local img = Icons.add(_group, "dim_" .. tostring(e.dim), { 20, 20 })
            if img then _track(img) end
            local name = _track(_group:AddText(tostring(e.name)))
            if img then name.SameLine = true end
            local timer = _track(_group:AddText(string.format(
                Locale.t("store_time_left"), _fmt_mmss(e.expires - now))))
            timer.SameLine = true
            _timers[#_timers + 1] = { label = timer, effect = e }
        end

        -- Cuerpo: "Efectos:" + viñetas
        local hdr = _track(_group:AddText(Locale.t("store_effects_label")))
        pcall(function() hdr:SetColor("Text", COLOR_DIM_TEXT) end)
        if e.description and e.description ~= "" then
            local d = _track(_group:AddText("  • " .. tostring(e.description)))
            d.TextWrapPos = 0
        end
        _track(_group:AddText("  • " .. string.format(
            Locale.t("store_total_duration"), math.floor(e.duration_s / 60))))
        _track(_group:AddText("  • " .. string.format(
            Locale.t("store_no_stack"), Locale.dim(e.dim))))
        _track(_group:AddSeparator())
    end
end

-- ---------------------------------------------------------------------------
-- Render: efectos pasivos por tier
-- ---------------------------------------------------------------------------

local function _populate_passive()
    if #_passive == 0 then
        _empty_state()
        return
    end

    for _, e in ipairs(_passive) do
        local dim = tostring(e.dim or "?")
        local status_id = tostring(e.status or "?")

        -- Encabezado: icono + nombre in-game del status + "Permanente"
        local img = Icons.add(_group, "dim_" .. dim, { 20, 20 })
        if img then _track(img) end
        local display = _status_loca(status_id, "DisplayName") or status_id
        local name = _track(_group:AddText(display))
        if img then name.SameLine = true end
        pcall(function() name:SetColor("Text", State.color(dim)) end)
        local perm = _track(_group:AddText("· " .. Locale.t("store_permanent")))
        perm.SameLine = true
        pcall(function() perm:SetColor("Text", COLOR_DIM_TEXT) end)

        -- Cuerpo: descripción in-game, motivo (hito de acumulación) y permanencia
        local hdr = _track(_group:AddText(Locale.t("store_effects_label")))
        pcall(function() hdr:SetColor("Text", COLOR_DIM_TEXT) end)
        local desc = _status_loca(status_id, "Description")
        if desc then
            local d = _track(_group:AddText("  • " .. desc))
            d.TextWrapPos = 0
        end
        local why = _track(_group:AddText("  • " .. string.format(
            Locale.t("store_passive_threshold"),
            math.tointeger(e.min) or 0,
            Locale.dim(dim),
            math.tointeger(e.pts) or 0)))
        why.TextWrapPos = 0
        local note = _track(_group:AddText("  • " .. Locale.t("store_passive_note")))
        note.TextWrapPos = 0
        _track(_group:AddSeparator())
    end
end

-- ---------------------------------------------------------------------------
-- Render: actividad reciente
-- ---------------------------------------------------------------------------

local function _populate_recent()
    local now = Ext.Utils.MonotonicTime()

    if #_recent == 0 then
        _empty_state()
        return
    end

    for i, e in ipairs(_recent) do
        local status_id = tostring(e.status or "?")
        local display   = _status_loca(status_id, "DisplayName") or status_id

        local tbl_ok = pcall(function()
            local tbl = _track(_group:AddTable("fx_recent_hdr_" .. i, 2))
            local row = tbl:AddRow()
            local c1  = row:AddCell()
            local img = _status_icon(c1, status_id)
            if img then _track(img) end
            local name = c1:AddText(display)
            if img then name.SameLine = true end
            local c2 = row:AddCell()
            local timer = c2:AddText(string.format(
                Locale.t("store_time_left"), _fmt_mmss(e.expires - now)))
            _timers[#_timers + 1] = { label = timer, effect = e }
        end)
        if not tbl_ok then
            local img = _status_icon(_group, status_id)
            if img then _track(img) end
            local name = _track(_group:AddText(display))
            if img then name.SameLine = true end
            local timer = _track(_group:AddText(string.format(
                Locale.t("store_time_left"), _fmt_mmss(e.expires - now))))
            timer.SameLine = true
            _timers[#_timers + 1] = { label = timer, effect = e }
        end

        local hdr = _track(_group:AddText(Locale.t("store_effects_label")))
        pcall(function() hdr:SetColor("Text", COLOR_DIM_TEXT) end)
        local desc = _status_loca(status_id, "Description")
        if desc then
            local d = _track(_group:AddText("  • " .. desc))
            d.TextWrapPos = 0
        end
        local note = _track(_group:AddText("  • " .. Locale.t("store_recent_note")))
        note.TextWrapPos = 0
        _track(_group:AddSeparator())
    end
end

-- ---------------------------------------------------------------------------
-- API pública
-- ---------------------------------------------------------------------------

--- Repuebla el contenido según el submenú activo.
function EffectsTab.populate()
    if not _group then return end
    _clear()
    if _mode == "passive" then
        _populate_passive()
    elseif _mode == "recent" then
        _populate_recent()
    else
        _populate_redeemed()
    end
end

--- Construye la pestaña (una sola vez) y registra el hook de compras.
function EffectsTab.build(parent)
    _btn_redeemed = parent:AddButton(Locale.t("store_fx_redeemed"))
    _btn_passive  = parent:AddButton(Locale.t("store_fx_passive"))
    _btn_recent   = parent:AddButton(Locale.t("store_fx_recent"))
    _btn_passive.SameLine = true
    _btn_recent.SameLine  = true
    _btn_redeemed.OnClick = function()
        _mode = "redeemed"; _paint_toggle(); EffectsTab.populate()
    end
    _btn_passive.OnClick = function()
        _mode = "passive"; _paint_toggle(); EffectsTab.populate()
    end
    _btn_recent.OnClick = function()
        _mode = "recent"; _paint_toggle(); EffectsTab.populate()
    end
    _paint_toggle()
    parent:AddSeparator()

    _group = parent:AddGroup("lsg_effects")
    Purchase.onEffectApplied = EffectsTab.addEffect
    EffectsTab.populate()
end

--- Registra un efecto canjeado a partir de una entrada del catálogo.
function EffectsTab.addEffect(item)
    local turns = math.tointeger(item.durationTurns or 0) or 0
    local dur_s = turns > 0 and turns * 6 or 0
    if dur_s <= 0 then return end  -- estados permanentes no llevan countdown

    _effects[#_effects + 1] = {
        name        = tostring(item.name or item.itemId or "?"),
        description = tostring(item.description or ""),
        dim         = tostring(item.dimensionName or "?"),
        duration_s  = dur_s,
        expires     = Ext.Utils.MonotonicTime() + dur_s * 1000,
    }
    _persist()
    EffectsTab.populate()
end

--- Actualiza la lista de efectos pasivos (snapshot recibido del servidor).
function EffectsTab.setPassive(list)
    _passive = (type(list) == "table") and list or {}
    if _mode == "passive" then
        EffectsTab.populate()
    end
end

--- Actualiza la lista de buffs por actividad reciente (snapshot del servidor).
-- El servidor manda remaining_ms; se convierte a un expires en tiempo
-- monotónico local (mismo reloj que usan los efectos canjeados).
function EffectsTab.setRecent(list)
    local now = Ext.Utils.MonotonicTime()
    local out = {}
    if type(list) == "table" then
        for _, e in ipairs(list) do
            out[#out + 1] = {
                status     = e.status,
                event_type = e.event_type,
                expires    = now + (tonumber(e.remaining_ms) or 0),
            }
        end
    end
    _recent = out
    if _mode == "recent" then
        EffectsTab.populate()
    end
end

--- Tick (~1 s desde BootstrapClient): expira canjeados/actividad reciente y
-- actualiza countdowns. La actividad reciente también la poda el servidor
-- en cada snapshot, pero se poda aquí también para que el countdown no se
-- quede pegado en 00:00 entre un broadcast y el siguiente.
function EffectsTab.tick(now)
    local changed = false
    for i = #_effects, 1, -1 do
        if _effects[i].expires <= now then
            table.remove(_effects, i)
            changed = true
        end
    end
    if changed then
        _persist()
        EffectsTab.populate()
        return
    end

    local recent_changed = false
    for i = #_recent, 1, -1 do
        if _recent[i].expires <= now then
            table.remove(_recent, i)
            recent_changed = true
        end
    end
    if recent_changed and _mode == "recent" then
        EffectsTab.populate()
        return
    end

    for _, t in ipairs(_timers) do
        pcall(function()
            t.label.Label = string.format(
                Locale.t("store_time_left"), _fmt_mmss(t.effect.expires - now))
        end)
    end
end

return EffectsTab
