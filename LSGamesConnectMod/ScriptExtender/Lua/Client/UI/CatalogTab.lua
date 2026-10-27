--- Pestaña Catálogo de la Tienda de puntos (Objetos / Estados).
--
-- El toggle Objetos/Estados arranca sin selección: mientras no se elija una
-- categoría se muestra un estado vacío que lo pide. El panel "Divisas disponibles" muestra las 5 dimensiones LSG
-- con icono, nombre y saldo coloreado.

local State    = Ext.Require("Client/Store/State.lua")
local Purchase = Ext.Require("Client/Store/Purchase.lua")
local Icons    = Ext.Require("Icons.lua")
local Locale   = Ext.Require("Locale.lua")

local CatalogTab = {}

-- ---------------------------------------------------------------------------
-- Estado interno
-- ---------------------------------------------------------------------------

local _mode = nil            -- nil | "objects" | "states" (nil = estado vacío)
local _amounts = {}          -- itemId -> cantidad seleccionada
local _btn_objects, _btn_states = nil, nil
local _currency_group, _content_group = nil, nil
-- Widgets creados dinámicamente (tracking manual: la propiedad Children no es
-- fiable entre versiones de SE)
local _currency_items, _content_items = {}, {}

local COLOR_ACTIVE   = { 0.20, 0.45, 0.80, 1.0 }
local COLOR_INACTIVE = { 0.23, 0.23, 0.26, 1.0 }
local COLOR_DIM_TEXT = { 0.70, 0.70, 0.70, 1.0 }
local COLOR_ERROR    = { 0.95, 0.30, 0.30, 1.0 }
local COLOR_OK       = { 0.35, 0.85, 0.45, 1.0 }

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function _clear(items)
    for _, w in ipairs(items) do
        pcall(function() w:Destroy() end)
    end
    for i = #items, 1, -1 do items[i] = nil end
end

local function _tracker(items)
    return function(w) items[#items + 1] = w; return w end
end

local function _paint_toggle()
    if not _btn_objects then return end
    pcall(function()
        _btn_objects:SetColor("Button", _mode == "objects" and COLOR_ACTIVE or COLOR_INACTIVE)
        _btn_states:SetColor("Button",  _mode == "states"  and COLOR_ACTIVE or COLOR_INACTIVE)
    end)
end

-- ---------------------------------------------------------------------------
-- Panel de divisas
-- ---------------------------------------------------------------------------

local function _populate_currencies()
    if not _currency_group then return end
    _clear(_currency_items)
    local track = _tracker(_currency_items)

    local keys = {}
    for k in pairs(State.balance) do keys[#keys + 1] = k end
    table.sort(keys)

    if #keys == 0 then
        local msg = track(_currency_group:AddText(State.error or Locale.t("no_balance")))
        pcall(function() msg:SetColor("Text", COLOR_ERROR) end)
        return
    end

    for i, dim in ipairs(keys) do
        local img = Icons.add(_currency_group, "dim_" .. dim, { 20, 20 })
        if img then track(img); img.SameLine = (i > 1) end
        local pts = math.tointeger(State.balance[dim]) or 0
        local lbl = track(_currency_group:AddText(string.format("%s %d", Locale.dim(dim), pts)))
        lbl.SameLine = (img ~= nil) or (i > 1)
        lbl.IDContext = "cur_" .. dim
        pcall(function() lbl:SetColor("Text", State.color(dim)) end)
    end
end

-- ---------------------------------------------------------------------------
-- Filas de ítems
-- ---------------------------------------------------------------------------

--- Renderiza una fila de ítem. with_qty=true añade el selector de cantidad.
local function _add_item_row(item, with_qty, track)
    local id = tostring(item.itemId)
    _amounts[id] = _amounts[id] or 1
    local dim = tostring(item.dimensionName or "?")

    local img = Icons.add(_content_group, "dim_" .. dim, { 22, 22 })
    if img then track(img) end
    local name = track(_content_group:AddText(tostring(item.name or id)))
    name.IDContext = "name_" .. id
    if img then name.SameLine = true end
    pcall(function() name:SetColor("Text", State.color(dim)) end)

    if item.description and item.description ~= "" then
        local desc = track(_content_group:AddText(tostring(item.description)))
        desc.IDContext = "desc_" .. id
        desc.TextWrapPos = 0
        pcall(function() desc:SetColor("Text", COLOR_DIM_TEXT) end)
    end

    local cost = math.tointeger(item.cost) or 0
    local cost_lbl  -- se define abajo; el selector la actualiza

    local function _cost_text()
        return string.format(Locale.t("store_cost"), cost * _amounts[id])
    end

    if with_qty then
        local minus = track(_content_group:AddButton("<##" .. id))
        local qty   = track(_content_group:AddText(string.format(" %d ", _amounts[id])))
        local plus  = track(_content_group:AddButton(">##" .. id))
        qty.SameLine, plus.SameLine = true, true
        qty.IDContext = "qty_" .. id

        minus.OnClick = function()
            _amounts[id] = math.max(1, _amounts[id] - 1)
            qty.Label = string.format(" %d ", _amounts[id])
            if cost_lbl then cost_lbl.Label = _cost_text() end
        end
        plus.OnClick = function()
            _amounts[id] = math.min(99, _amounts[id] + 1)
            qty.Label = string.format(" %d ", _amounts[id])
            if cost_lbl then cost_lbl.Label = _cost_text() end
        end
    else
        _amounts[id] = 1
    end

    cost_lbl = track(_content_group:AddText(_cost_text()))
    cost_lbl.SameLine = with_qty
    cost_lbl.IDContext = "cost_" .. id
    local cost_icon = Icons.add(_content_group, "dim_" .. dim, { 16, 16 })
    if cost_icon then track(cost_icon); cost_icon.SameLine = true end

    local buy = track(_content_group:AddButton(Locale.t("btn_redeem") .. "##" .. id))
    buy.SameLine = true

    -- Mensaje de resultado bajo la fila (rojo si error, verde si OK)
    local msg = track(_content_group:AddText(""))
    msg.IDContext = "msg_" .. id

    buy.OnClick = function()
        Purchase.buy(item, _amounts[id], function(ok, text)
            msg.Label = tostring(text or "")
            pcall(function() msg:SetColor("Text", ok and COLOR_OK or COLOR_ERROR) end)
            if ok then
                _populate_currencies()
            end
        end)
    end

    track(_content_group:AddSeparator())
end

-- ---------------------------------------------------------------------------
-- Contenido (lista o placeholder)
-- ---------------------------------------------------------------------------

local function _populate_content()
    if not _content_group then return end
    _clear(_content_items)
    local track = _tracker(_content_items)

    -- Vista 5: sin subcategoría seleccionada o sin catálogo válido
    if _mode == nil or State.catalog == nil then
        pcall(function() track(_content_group:AddDummy(0, 60)) end)
        local icon = Icons.add(_content_group, "item_placeholder", { 32, 32 })
        if icon then track(icon) end
        local txt = track(_content_group:AddText(Locale.t("store_empty_catalog")))
        pcall(function() txt:SetColor("Text", COLOR_DIM_TEXT) end)
        return
    end

    local items = (_mode == "objects") and State.objects() or State.statuses()
    if #items == 0 then
        pcall(function() track(_content_group:AddDummy(0, 40)) end)
        local txt = track(_content_group:AddText(Locale.t("no_items")))
        pcall(function() txt:SetColor("Text", COLOR_DIM_TEXT) end)
        return
    end

    for _, item in ipairs(items) do
        _add_item_row(item, _mode == "objects", track)
    end
end

local function _set_mode(mode)
    _mode = mode
    _paint_toggle()
    _populate_content()
end

-- ---------------------------------------------------------------------------
-- API pública
-- ---------------------------------------------------------------------------

--- Construye la pestaña dentro del tab item dado (una sola vez).
function CatalogTab.build(parent)
    _btn_objects = parent:AddButton(Locale.t("store_objects"))
    _btn_states  = parent:AddButton(Locale.t("store_states"))
    _btn_states.SameLine = true
    _btn_objects.OnClick = function() _set_mode("objects") end
    _btn_states.OnClick  = function() _set_mode("states") end
    _paint_toggle()

    -- AddSeparatorText no existe en versiones antiguas de SE
    local ok = pcall(function() parent:AddSeparatorText(Locale.t("store_currencies")) end)
    if not ok then
        parent:AddSeparator()
        parent:AddText(Locale.t("store_currencies"))
    end
    _currency_group = parent:AddGroup("lsg_currencies")
    _populate_currencies()

    parent:AddSeparator()
    _content_group = parent:AddGroup("lsg_catalog_content")
    _populate_content()
end

--- Repuebla divisas y contenido con el estado actual (tras State.reload()).
function CatalogTab.refresh()
    _populate_currencies()
    _populate_content()
end

return CatalogTab
