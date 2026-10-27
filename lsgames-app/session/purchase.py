"""Lectura y verificación de solicitudes de compra pendientes desde el mod BG3."""

import json
import logging
from collections import deque
from pathlib import Path

from config import SE_PURCHASE_PATH
from session.signer import verify_payload

logger = logging.getLogger(__name__)

# Firmas ya procesadas: rechaza la re-colocación de un archivo de compra
# capturado (replay). Solo vive en memoria, así que no cubre un replay
# después de reiniciar la app.
_seen_sigs: deque = deque(maxlen=50)


def read_pending_purchase() -> dict | None:
    """Lee, verifica y elimina pending_purchase.json si existe y es válido.

    Verifica la firma HMAC-SHA256 sobre {itemId, amount, timestamp} antes
    de devolver la solicitud. Rechaza y elimina el archivo si la firma
    no coincide.

    Returns:
        Diccionario con {itemId, amount} o None si no hay solicitud válida.
        itemId corresponde al mmvgId de la mecánica a canjear.
    """
    path = Path(SE_PURCHASE_PATH)
    if not path.exists():
        return None

    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        logger.warning("No se pudo leer pending_purchase.json: %s", exc)
        _safe_delete(path)
        return None

    sig = data.pop("sig", None)
    if sig is None:
        logger.warning("pending_purchase.json sin firma — solicitud rechazada")
        _safe_delete(path)
        return None

    payload = {
        "itemId":    data.get("itemId"),
        "amount":    data.get("amount"),
        "timestamp": data.get("timestamp"),
    }

    if not verify_payload(payload, sig):
        logger.warning("Firma inválida en pending_purchase.json — solicitud rechazada")
        _safe_delete(path)
        return None

    if sig in _seen_sigs:
        logger.warning("pending_purchase.json repetido (replay) — solicitud rechazada")
        _safe_delete(path)
        return None
    _seen_sigs.append(sig)

    _safe_delete(path)
    return {"itemId": data["itemId"], "amount": int(data["amount"])}


def _safe_delete(path: Path) -> None:
    try:
        path.unlink(missing_ok=True)
    except Exception:
        pass
