--- Pestaña Transacciones de la Tienda de puntos.
--
-- Tabla de 6 columnas (Fecha, Tipo, Descripción, Divisa, Monto, Saldo) dentro
-- de un child window con scroll. Los datos vienen de LSGMod/transactions.json,
-- escrito por el middleware en orden cronológico descendente.

local State  = Ext.Require("Client/Store/State.lua")
local Icons  = Ext.Require("Icons.lua")
local Locale = Ext.Require("Locale.lua")

local TransactionsTab = {}

local COLOR_HEADER   = { 0.75, 0.75, 0.75, 1.0 }
local COLOR_DIM_TEXT = { 0.70, 0.70, 0.70, 1.0 }
local COLOR_EXPENSE  = { 0.95, 0.30, 0.30, 1.0 }
local COLOR_INCOME   = { 0.35, 0.85, 0.45, 1.0 }

local _scroll  = nil   -- child window con scroll
local _widgets = {}    -- widgets creados dinámicamente (tracking manual)

local function _clear()
    for _, w in ipairs(_widgets) do
        pcall(function() w:Destroy() end)
    end
    _widgets = {}
end

local function _track(w) _widgets[#_widgets + 1] = w; return w end

local HEADERS = {
    "store_col_date", "store_col_type", "store_col_desc",
    "store_col_currency", "store_col_amount", "store_col_balance",
}

--- Repuebla la tabla con State.transactions.
function TransactionsTab.populate()
    if not _scroll then return end
    _clear()

    if #State.transactions == 0 then
        pcall(function() _track(_scroll:AddDummy(0, 40)) end)
        local txt = _track(_scroll:AddText(Locale.t("store_no_transactions")))
        pcall(function() txt:SetColor("Text", COLOR_DIM_TEXT) end)
        return
    end

    local ok = pcall(function()
        local tbl = _track(_scroll:AddTable("lsg_tx", 6))

        -- Fila de encabezados (texto gris; no depende de la API de headers)
        local hrow = tbl:AddRow()
        for _, key in ipairs(HEADERS) do
            local cell = hrow:AddCell()
            local lbl = cell:AddText(Locale.t(key))
            pcall(function() lbl:SetColor("Text", COLOR_HEADER) end)
        end

        for i, tx in ipairs(State.transactions) do
            local row = tbl:AddRow()

            row:AddCell():AddText(State.fmt_time(tx.ts or 0))

            local is_expense = (tx.type == "gasto")
            row:AddCell():AddText(Locale.t(is_expense and "store_tx_expense" or "store_tx_income"))

            local desc = row:AddCell():AddText(tostring(tx.description or ""))
            desc.IDContext = "txd_" .. i

            local ccur = row:AddCell()
            local dim  = tostring(tx.dimensionName or "?")
            local img  = Icons.add(ccur, "dim_" .. dim, { 16, 16 })
            local dlbl = ccur:AddText(Locale.dim(dim))
            if img then dlbl.SameLine = true end
            pcall(function() dlbl:SetColor("Text", State.color(dim)) end)

            local amount = math.tointeger(tx.amount) or 0
            local alab = row:AddCell():AddText(string.format("%+d", amount))
            alab.IDContext = "txa_" .. i
            pcall(function()
                alab:SetColor("Text", is_expense and COLOR_EXPENSE or COLOR_INCOME)
            end)

            row:AddCell():AddText(tostring(math.tointeger(tx.balance) or 0))
        end
    end)

    if not ok then
        -- Fallback sin AddTable: una línea de texto por transacción
        for _, tx in ipairs(State.transactions) do
            local is_expense = (tx.type == "gasto")
            local line = _track(_scroll:AddText(string.format(
                "%s  %-7s  %-30s  %-12s  %+d  (%d)",
                State.fmt_time(tx.ts or 0),
                Locale.t(is_expense and "store_tx_expense" or "store_tx_income"),
                tostring(tx.description or ""),
                Locale.dim(tostring(tx.dimensionName or "?")),
                math.tointeger(tx.amount) or 0,
                math.tointeger(tx.balance) or 0)))
            pcall(function()
                line:SetColor("Text", is_expense and COLOR_EXPENSE or COLOR_INCOME)
            end)
        end
    end
end

--- Construye la pestaña dentro del tab item dado (una sola vez).
function TransactionsTab.build(parent)
    pcall(function() _scroll = parent:AddChildWindow("lsg_tx_scroll") end)
    if _scroll then
        pcall(function() _scroll.Size = { 0, 440 } end)  -- alto fijo; ancho = disponible
    else
        _scroll = parent:AddGroup("lsg_tx_scroll")
    end
    TransactionsTab.populate()
end

return TransactionsTab
