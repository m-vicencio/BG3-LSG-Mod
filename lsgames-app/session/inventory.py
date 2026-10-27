"""Escritura de notificaciones de sesión para el mod BG3."""

import json
import time
from pathlib import Path

from config import SE_NOTIFY_PATH
from session.atomic import write_atomic


def write_notify(catalog_updated: bool = False) -> None:
    """Escribe lsg_notify.json con el timestamp actual.

    El mod BG3 detecta el cambio de timestamp en su Tick handler y refresca
    el balance y, si catalog_updated=True, también recarga los tabs del catálogo.

    Args:
        catalog_updated: Si True, incluye catalog_ts para que el mod reconstruya
                         los tabs de dimensiones cuando cambió el catálogo.
    """
    now = time.time()
    # server_time: referencia de reloj de pared para el mod (BG3SE no expone
    # os.time); Clock.lua la ancla al tiempo monotónico del juego.
    payload: dict = {"ts": now, "server_time": int(now)}
    if catalog_updated:
        payload["catalog_ts"] = now

    write_atomic(Path(SE_NOTIFY_PATH), json.dumps(payload))
