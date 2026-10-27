--- Lógica de canje de la Tienda de puntos LifeSyncGames (lado cliente).
--
-- Valida saldo local, encola la compra en la cola offline (vía Shop.offline_buy,
-- que la agrega a la cola y escribe pending_offline_sync.json) y pide al servidor entregar
-- el objeto o aplicar el status BG3 correspondiente.

local Shop   = Ext.Require("Shop.lua")
local State  = Ext.Require("Client/Store/State.lua")
local Locale = Ext.Require("Locale.lua")

local Purchase = {}

local NET_GIVE_ITEM   = "LSGames_GiveItem"
local NET_GIVE_STATUS = "LSGames_GiveStatus"

--- Hook que EffectsTab registra para enterarse de estados canjeados.
-- Recibe la entrada del catálogo canjeada.
Purchase.onEffectApplied = nil

--- Canjea un ítem del catálogo.
--
-- @param item     tabla del catálogo {itemId, dimensionName, cost, bg3Status?, ...}
-- @param qty      integer  cantidad (los Estados siempre van con 1)
-- @param callback function(ok, msg)
function Purchase.buy(item, qty, callback)
    qty = math.max(1, math.tointeger(qty) or 1)
    local dim   = tostring(item.dimensionName or "?")
    local cost  = math.tointeger(item.cost) or 0
    local total = cost * qty
    local have  = math.tointeger(State.balance[dim]) or 0

    if total <= 0 then
        callback(false, string.format(Locale.t("shop_err_cost"), tostring(item.itemId or "?")))
        return
    end
    if have < total then
        callback(false, string.format(Locale.t("store_insufficient"), Locale.dim(dim)))
        return
    end

    Shop.offline_buy(item, qty, function(ok, msg)
        if not ok then
            callback(false, msg)
            return
        end

        State.debit(dim, total)

        if item.bg3TemplateId then
            pcall(Ext.ClientNet.PostMessageToServer, NET_GIVE_ITEM,
                Ext.Json.Stringify({ templateId = item.bg3TemplateId, amount = qty }))
        end
        if item.bg3Status then
            pcall(Ext.ClientNet.PostMessageToServer, NET_GIVE_STATUS,
                Ext.Json.Stringify({ status = item.bg3Status, durationTurns = item.durationTurns }))
            if Purchase.onEffectApplied then
                pcall(Purchase.onEffectApplied, item)
            end
        end

        callback(true, msg)
    end)
end

return Purchase
