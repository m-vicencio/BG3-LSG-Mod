"""Procesamiento de solicitudes de sincronización offline desde el mod BG3.

El mod escribe pending_offline_sync.json cuando el jugador tiene eventos
de puntos offline (ganancias o canjes) que aún no se han confirmado en el
servidor. Este módulo lee ese archivo, construye el payload para
POST /offline/sync y escribe los resultados en offline_sync_result.json.
"""

import json
import logging
from datetime import datetime, timezone
from pathlib import Path

from config import SE_OFFLINE_PENDING_PATH, SE_OFFLINE_RESULT_PATH
from session.atomic import write_atomic
from session.signer import verify_text

logger = logging.getLogger(__name__)

# Campos permitidos en cada evento al enviar a POST /offline/sync
_EVENT_API_FIELDS = {
    "client_ref", "client_generated_at",
    "point_dimension_id", "direction",
    "amount", "source_type", "payload",
}


def read_pending_offline_sync() -> dict | None:
    """Lee y elimina pending_offline_sync.json si existe y es válido.

    El archivo es {body, sig}: body es la solicitud serializada por el mod y
    sig su HMAC-SHA256. Se descarta si la firma no coincide.

    Asigna client_generated_at (ISO 8601 UTC) a los eventos que no lo tienen,
    ya que el mod sólo dispone de tiempo monotónico de juego.
    Filtra los campos del evento a los que acepta la API (/offline/sync).

    Returns:
        Diccionario {player_id, game_id, events} listo para enviar a la API,
        o None si no hay solicitud pendiente.
    """
    path = Path(SE_OFFLINE_PENDING_PATH)
    if not path.exists():
        return None

    try:
        signed = json.loads(path.read_text(encoding="utf-8"))
        body = signed["body"]
        if not isinstance(body, str):
            raise ValueError("body no es texto")
    except Exception as exc:
        logger.warning("No se pudo leer pending_offline_sync.json: %s", exc)
        _safe_delete(path)
        return None

    if not verify_text(body, signed.get("sig")):
        logger.warning("Firma inválida en pending_offline_sync.json, solicitud rechazada")
        _safe_delete(path)
        return None

    try:
        data = json.loads(body)
    except Exception as exc:
        logger.warning("pending_offline_sync.json con body ilegible: %s", exc)
        _safe_delete(path)
        return None

    if not isinstance(data, dict):
        logger.warning("pending_offline_sync.json tiene formato inválido — descartado")
        _safe_delete(path)
        return None

    events = data.get("events")
    if not isinstance(events, list) or not events:
        logger.debug("pending_offline_sync.json sin eventos — descartado")
        _safe_delete(path)
        return None

    now_iso = datetime.now(timezone.utc).isoformat()

    clean_events = []
    for ev in events:
        if not isinstance(ev, dict):
            continue
        # Asignar timestamp real si el mod no lo incluyó (usa tiempo monotónico)
        if not ev.get("client_generated_at"):
            ev["client_generated_at"] = now_iso
        # Mantener solo campos que acepta la API
        clean_ev = {k: v for k, v in ev.items() if k in _EVENT_API_FIELDS}
        if clean_ev.get("client_ref") and clean_ev.get("point_dimension_id"):
            clean_events.append(clean_ev)

    if not clean_events:
        logger.warning("pending_offline_sync.json: ningún evento válido tras limpieza")
        _safe_delete(path)
        return None

    _safe_delete(path)
    return {
        "player_id": int(data.get("player_id") or 0),
        "game_id":   int(data.get("game_id") or 0) or None,
        "events":    clean_events,
    }


def write_sync_result(result: dict) -> None:
    """Escribe offline_sync_result.json para que el mod lo procese.

    El mod lee este archivo en su próximo ciclo de Tick (~5 min) o cuando
    el usuario ejecuta !lsgsync, procesa los estados y limpia el archivo.

    Args:
        result: Respuesta de POST /offline/sync (HTTP 207).
    """
    write_atomic(Path(SE_OFFLINE_RESULT_PATH), json.dumps(result, ensure_ascii=False))
    logger.info(
        "Sync offline completado: %d/%d synced, %d rejected, %d duplicate",
        result.get("synced", 0),
        result.get("total", 0),
        result.get("rejected", 0),
        result.get("duplicate", 0),
    )


def _safe_delete(path: Path) -> None:
    try:
        path.unlink(missing_ok=True)
    except Exception:
        pass
