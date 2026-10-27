--- Ventana principal "Tienda de puntos LifeSyncGames" (ImGui, lado cliente).
--
-- Estructura común a todas las vistas: tab bar (Catálogo / Efectos activos /
-- Transacciones) + pie persistente con el texto de sincronización y el botón
-- de refresco. BootstrapClient.lua usa su API pública: init/refresh/toggle/tick.

local State           = Ext.Require("Client/Store/State.lua")
local CatalogTab      = Ext.Require("Client/UI/CatalogTab.lua")
local EffectsTab      = Ext.Require("Client/UI/EffectsTab.lua")
local TransactionsTab = Ext.Require("Client/UI/TransactionsTab.lua")
local Locale          = Ext.Require("Locale.lua")
local Icons           = Ext.Require("Icons.lua")

local StoreWindow = {}

local COLOR_FOOTER = { 0.65, 0.65, 0.65, 1.0 }

local _wnd       = nil
local _float_wnd = nil

-- ---------------------------------------------------------------------------
-- Construcción
-- ---------------------------------------------------------------------------

local function _build_main_window()
    _wnd = Ext.IMGUI.NewWindow(Locale.t("store_title"))
    _wnd.Visible = false
    pcall(function() _wnd.Closeable = true end)
    pcall(function() _wnd:SetSize({ 720, 640 }, "FirstUseEver") end)
    pcall(function() _wnd:SetSizeConstraints({ 560, 420 }, { 1100, 1000 }) end)

    Icons.add(_wnd, "lsg_logo", { 32, 32 })

    local bar = _wnd:AddTabBar("lsg_tabs")
    CatalogTab.build(bar:AddTabItem(Locale.t("store_tab_catalog")))
    EffectsTab.build(bar:AddTabItem(Locale.t("store_tab_effects")))
    TransactionsTab.build(bar:AddTabItem(Locale.t("store_tab_transactions")))

    -- Pie persistente (fuera del tab bar: visible en todas las pestañas)
    _wnd:AddSeparator()
    local footer = _wnd:AddText(Locale.t("store_footer"))
    footer.TextWrapPos = 0
    pcall(function() footer:SetColor("Text", COLOR_FOOTER) end)
    local refresh = _wnd:AddButton(Locale.t("btn_refresh"))
    refresh.SameLine = true
    refresh.OnClick = function()
        -- Pide a lsgames-app que vuelva a descargar perfil y catálogo, igual
        -- que su propio botón Actualizar; releer solo los archivos locales no
        -- traería datos nuevos.
        pcall(Ext.IO.SaveFile, "LSGMod/lsg_refresh_request.json", "{}")
        StoreWindow.refresh()
    end
end

local function _build_float_window()
    _float_wnd = Ext.IMGUI.NewWindow("LSGames_FloatBtn")
    _float_wnd.NoTitleBar       = true
    _float_wnd.NoResize         = true
    _float_wnd.AlwaysAutoResize = true
    _float_wnd.NoCollapse       = true
    _float_wnd.NoSavedSettings  = true
    local btn = _float_wnd:AddButton(Locale.t("float_btn"))
    btn.OnClick = function() StoreWindow.toggle() end
end

-- ---------------------------------------------------------------------------
-- API pública
-- ---------------------------------------------------------------------------

--- Crea las ventanas. Llamar en SessionLoaded (no en frame 0).
function StoreWindow.init()
    Locale.reload()
    State.reload()
    _build_float_window()
    _build_main_window()
end

--- Relee los archivos de intercambio y repuebla todas las pestañas.
function StoreWindow.refresh()
    State.reload()
    CatalogTab.refresh()
    EffectsTab.populate()
    TransactionsTab.populate()
end

function StoreWindow.open()
    StoreWindow.refresh()
    if _wnd then _wnd.Visible = true end
end

function StoreWindow.close()
    if _wnd then _wnd.Visible = false end
end

-- Se lee _wnd.Visible en vez de guardar un estado propio de abierta/cerrada:
-- la ventana también se cierra desde el motor (X, Esc) y ese estado quedaría
-- desincronizado.
function StoreWindow.toggle()
    if _wnd and _wnd.Visible then StoreWindow.close() else StoreWindow.open() end
end

--- Tick (~1 s desde BootstrapClient): countdown de efectos si la ventana está abierta.
function StoreWindow.tick(now)
    EffectsTab.tick(now)  -- expira efectos aunque la ventana esté cerrada
end

return StoreWindow
