"""Publicación de eventos de sensores recientes para el mod BG3.

Descarga los ingest-events del jugador y escribe recent_events.json con los
eventos de las últimas 24 h, proyectados a lo mínimo que Effects.lua necesita
para mapear event_type -> status in-game. El mod deduplica por id, así que
reescribir el archivo completo en cada poll es seguro.
"""

import json
import logging
from datetime import datetime, timedelta
from pathlib import Path

from config import SE_RECENT_EVENTS_PATH
from session.atomic import write_atomic
from session.inventory import write_notify

logger = logging.getLogger(__name__)

# Ventana de "actividad reciente": eventos más viejos no otorgan buff.
RECENT_WINDOW_HOURS = 24

# Máximo id notificado al mod en esta ejecución (evita despertar al mod
# con write_notify cuando el poll no trae nada nuevo).
_last_notified_id: int = 0


def _parse_occurred_at(value: object) -> datetime | None:
    try:
        # Formato de la API: "2026-07-28T04:03:02" (naive, hora del servidor)
        return datetime.fromisoformat(str(value).replace("Z", ""))
    except Exception:
        return None


def _event_type(raw: dict) -> str:
    """Deriva el event_type de un raw_payload.

    EggSys manda event_type directo. LSG-Routes (sensor de rutas) no: hay
    que derivarlo de mode + route_id. route_id == "free_roam" (caminata sin
    ruta asignada) es su propio event_type genérico, sin distinguir modo.
    """
    et = raw.get("event_type")
    if et:
        return str(et)

    mode = raw.get("mode")
    route_id = raw.get("route_id")
    if not mode or not route_id:
        return ""
    if route_id == "free_roam":
        return "route.freeroam"
    return f"route.completed.{mode}"


def build_recent_events(events: list[dict]) -> list[dict]:
    """Filtra y proyecta los ingest-events crudos para el mod.

    Se conservan solo eventos con status OK dentro de la ventana reciente,
    reducidos a {id, event_type, milestone, parsed_value, occurred_at}.
    """
    cutoff = datetime.now() - timedelta(hours=RECENT_WINDOW_HOURS)
    recent: list[dict] = []

    for ev in events:
        if not isinstance(ev, dict) or ev.get("status") != "OK":
            continue
        occurred = _parse_occurred_at(ev.get("occurred_at"))
        if occurred is None or occurred < cutoff:
            continue

        raw = ev.get("raw_payload") or {}
        payload = raw.get("payload") or {}
        recent.append({
            "id":           int(ev.get("id_sensor_ingest_event") or 0),
            "event_type":   _event_type(raw),
            "milestone":    payload.get("milestone"),
            "parsed_value": ev.get("parsed_value"),
            "occurred_at":  str(ev.get("occurred_at") or ""),
        })

    recent.sort(key=lambda e: e["id"])
    return recent


async def fetch_and_write_events(api_client) -> list[dict]:
    """Descarga los ingest-events y escribe recent_events.json.

    Notifica al mod (lsg_notify.json) solo cuando aparece un evento con id
    mayor al último notificado; el archivo se reescribe siempre para que los
    eventos fuera de ventana desaparezcan.

    Returns:
        Lista de eventos recientes escritos.
    """
    global _last_notified_id

    events = await api_client.get_ingest_events()
    recent = build_recent_events(events)

    write_atomic(
        Path(SE_RECENT_EVENTS_PATH),
        json.dumps({"events": recent}, ensure_ascii=False, indent=2),
    )

    max_id = max((e["id"] for e in recent), default=0)
    if max_id > _last_notified_id:
        _last_notified_id = max_id
        write_notify(catalog_updated=False)

    return recent
