--- Registro central de imágenes/iconos para la GUI ImGui de la Tienda LSG.
--
-- ImGui (BG3SE) no carga PNG sueltos del disco. AddImage(res, size) acepta:
--   - el nombre de un icono del juego (atlas de texturas), o
--   - el UUID de un recurso de textura empaquetado en el mod.
--
-- Por eso este módulo es un mapa "nombre lógico -> recurso". Para usar arte
-- propio (PNG) hay que empaquetarlo como textura del mod y poner su UUID aquí.
--
-- Cómo cambiar una imagen:
--   1. Icono del juego (no requiere empaquetar):  { icon = "NombreDelIcono" }
--   2. Textura propia empaquetada en el mod:      { texture = "UUID-de-textura" }
--
-- Si un nombre/UUID es inválido, BG3SE avisa en el log y el hueco queda en
-- blanco sin provocar un crash.

local Icons = {}

-- Tamaño por defecto de los iconos (px). Sobreescribible por llamada.
Icons.DEFAULT_SIZE = { 24, 24 }

-- ---------------------------------------------------------------------------
-- Mapa de recursos
-- ---------------------------------------------------------------------------
-- Por ahora son iconos genéricos del juego.
Icons.map = {
    -- Iconos por dimensión LSG (la clave es "dim_" .. dimensionName del catálogo)
    dim_social      = { icon = "Action_Help" },
    dim_fisico      = { icon = "Action_Dash" },
    dim_afectivo    = { icon = "Action_Hide" },
    dim_mental      = { icon = "Action_Shove" },
    dim_linguistico = { icon = "Action_Throw" },

    -- Logo propio: requiere empaquetar la textura; el UUID en cero queda en blanco
    lsg_logo        = { texture = "00000000-0000-0000-0000-000000000000" },

    -- Fallback para un ítem sin icono específico
    item_placeholder = { icon = "Item_LOOT_Gold_A" },
}

-- ---------------------------------------------------------------------------
-- API
-- ---------------------------------------------------------------------------

--- Resuelve el recurso (icon name o texture UUID) de un nombre lógico.
function Icons.resource(name)
    local e = Icons.map[name]
    if not e then return nil end
    return e.icon or e.texture
end

--- Añade una imagen a un parent ImGui. Devuelve el handle (o nil si no hay mapeo).
-- Degrada con gracia: recurso inválido => imagen en blanco, sin error.
function Icons.add(parent, name, size)
    local res = Icons.resource(name)
    if not res then return nil end
    return parent:AddImage(res, size or Icons.DEFAULT_SIZE)
end

return Icons
