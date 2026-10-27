"""Construcción y escritura del catálogo de mecánicas para el mod BG3."""

import json
from pathlib import Path

from config import SE_CATALOG_PATH
from session.atomic import write_atomic

# Pociones de prueba, una por atributo LSG.
# Se usan cuando la API no devuelve mecánicas reales (mmvgId=-1 = sin llamada API).
# El middleware los reconoce por mmvgId=-1 y confirma localmente sin llamar a /redeem.
_TEST_CATALOG: list[dict] = [
    {
        "itemId": "test_social",
        "mmvgId": -1,
        "name": "Poción Social (prueba)",
        "description": "Ítem de prueba - dimensión Social",
        "dimensionId": 1,
        "dimensionName": "social",
        "cost": 1,
        "type": "test",
    },
    {
        "itemId": "test_fisico",
        "mmvgId": -1,
        "name": "Poción Física (prueba)",
        "description": "Ítem de prueba - dimensión Físico",
        "dimensionId": 2,
        "dimensionName": "fisico",
        "cost": 1,
        "type": "test",
    },
    {
        "itemId": "test_afectivo",
        "mmvgId": -1,
        "name": "Poción Afectiva (prueba)",
        "description": "Ítem de prueba - dimensión Afectivo",
        "dimensionId": 3,
        "dimensionName": "afectivo",
        "cost": 1,
        "type": "test",
    },
    {
        "itemId": "test_mental",
        "mmvgId": -1,
        "name": "Poción Mental (prueba)",
        "description": "Ítem de prueba - dimensión Mental",
        "dimensionId": 4,
        "dimensionName": "mental",
        "cost": 1,
        "type": "test",
    },
    {
        "itemId": "test_linguistico",
        "mmvgId": -1,
        "name": "Poción Lingüística (prueba)",
        "description": "Ítem de prueba - dimensión Lingüístico",
        "dimensionId": 5,
        "dimensionName": "linguistico",
        "cost": 1,
        "type": "test",
    },
    # Pociones vanilla de BG3: canjear añade el objeto al inventario del jugador.
    # bg3TemplateId: GUID del RootTemplate en los PAKs del juego.
    # Verificar con: for id,t in pairs(Ext.Template.GetAllRootTemplates()) do
    #                    if t.Stats == "OBJ_Potion_Healing" then print(id) end end
    {
        "itemId": "potion_healing",
        "mmvgId": -1,
        "name": "Poción de Curación",
        "description": "Restaura 2d4+2 PV. Objeto vanilla de BG3.",
        "dimensionId": 1,
        "dimensionName": "social",
        "cost": 5,
        "type": "consumable",
        "bg3TemplateId": "d47006e9-8a51-453d-b200-9e0d42e9bbab",
    },
    {
        "itemId": "potion_healing_greater",
        "mmvgId": -1,
        "name": "Poción de Curación Superior",
        "description": "Restaura 4d4+4 PV. Objeto vanilla de BG3.",
        "dimensionId": 1,
        "dimensionName": "social",
        "cost": 15,
        "type": "consumable",
        "bg3TemplateId": "e3b95c96-dc26-40fe-bfc0-baa05e1abd20",
    },
    {
        "itemId": "potion_speed",
        "mmvgId": -1,
        "name": "Poción de Velocidad",
        "description": "Otorga Haste durante 3 turnos. Objeto vanilla de BG3.",
        "dimensionId": 1,
        "dimensionName": "social",
        "cost": 20,
        "type": "consumable",
        "bg3TemplateId": "ad9f3f24-d755-48b6-aa7b-c34da068209f",
    },
]


def build_catalog_entry(mechanic: dict) -> dict | None:
    """Transforma una mecánica de la API en una entrada del catálogo del mod."""
    mmvg_id = (
        mechanic.get("id")
        or mechanic.get("id_modifiable_mechanic_videogame")
        or mechanic.get("mmvg_id")
    )
    if mmvg_id is None:
        return None

    options = mechanic.get("options") or {}
    if isinstance(options, str):
        try:
            options = json.loads(options)
        except Exception:
            options = {}
    if not isinstance(options, dict):
        options = {}

    # Solo pasan al mod las mecánicas con el formato visible estándar
    # (options con name, cost y point_dimension_id, como el "Elixir de Fuerza
    # de Gigante de las Colinas"). Las que no lo siguen (nombre nulo en la
    # API) se omiten hasta que se actualicen en el servidor.
    if not (options.get("name") or options.get("display_name")):
        return None
    if not (options.get("cost") or options.get("point_cost")):
        return None
    if not (options.get("point_dimension_id") or options.get("dimension_id")):
        return None

    # La API no devuelve mechanic_name en GET /videogames/{id}/mechanics (llega null);
    # el único campo que viaja íntegro es options. Por eso el nombre/desc/tipo se buscan
    # primero en options (donde el seed los embebe) y luego en los campos de la API.
    name = (
        options.get("name")
        or options.get("display_name")
        or mechanic.get("mechanic_name")
        or mechanic.get("name")
        or (mechanic.get("mechanic") or {}).get("name")
        or (mechanic.get("modifiable_mechanic") or {}).get("name")
        or f"Mecánica {mmvg_id}"
    )
    description = (
        options.get("description")
        or mechanic.get("mechanic_description")
        or mechanic.get("description")
        or (mechanic.get("mechanic") or {}).get("description")
        or ""
    )

    cost = int(
        options.get("cost") or options.get("point_cost")
        or mechanic.get("cost") or mechanic.get("point_cost")
        or 1
    )
    dimension_id = int(
        options.get("point_dimension_id") or options.get("dimension_id")
        or mechanic.get("point_dimension_id") or mechanic.get("dimension_id")
        or 0
    )
    dimension_name = str(
        options.get("point_dimension_name") or options.get("dimension_name")
        or mechanic.get("dimension_name")
        or (f"dim_{dimension_id}" if dimension_id else "desconocida")
    )
    mechanic_type = (
        options.get("type")
        or mechanic.get("mechanic_type")
        or mechanic.get("type")
        or (mechanic.get("mechanic") or {}).get("type")
        or "reward"
    )

    entry = {
        "itemId":        str(mmvg_id),
        "mmvgId":        int(mmvg_id),
        "name":          str(name),
        "description":   str(description),
        "dimensionId":   dimension_id,
        "dimensionName": dimension_name,
        "cost":          cost,
        "type":          str(mechanic_type),
    }

    # Efecto en juego (opcional). El mod aplica un status BG3 y/o entrega un objeto
    # al canjear. Estos campos viajan dentro de options (único campo que la API
    # devuelve íntegro).
    bg3_status = options.get("bg3_status")
    if bg3_status:
        entry["bg3Status"] = bg3_status  # string o lista de status
    duration = options.get("duration_turns")
    if duration is not None:
        entry["durationTurns"] = int(duration)
    template_id = options.get("bg3TemplateId") or options.get("bg3_template_id")
    if template_id:
        entry["bg3TemplateId"] = str(template_id)

    return entry


async def fetch_and_write_catalog(api_client) -> list[dict]:
    """Descarga las mecánicas del videojuego y escribe catalog.json.

    Si la API no devuelve mecánicas (juego sin registrar o sin mecánicas
    configuradas), usa el catálogo de prueba con una poción por atributo.

    Returns:
        Lista de entradas del catálogo escritas.
    """
    try:
        mechanics = await api_client.get_mechanics()
        catalog = [build_catalog_entry(m) for m in mechanics]
        catalog = [e for e in catalog if e]
    except Exception:
        catalog = []

    # Fallback a pociones de prueba si no hay mecánicas reales
    if not catalog:
        catalog = _TEST_CATALOG

    write_atomic(Path(SE_CATALOG_PATH), json.dumps(catalog, ensure_ascii=False, indent=2))
    return catalog
