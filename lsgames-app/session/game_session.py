"""Lectura de señales simples (presencia de archivo) enviadas por el mod BG3."""

import logging
from pathlib import Path

from config import SE_GAME_START_PATH, SE_REFRESH_REQUEST_PATH

logger = logging.getLogger(__name__)


def _read_and_clear(path_str: str, label: str) -> bool:
    path = Path(path_str)
    if not path.exists():
        return False
    try:
        path.unlink(missing_ok=True)
        return True
    except Exception as exc:
        logger.warning("No se pudo eliminar %s: %s", label, exc)
        return False


def read_game_start_signal() -> bool:
    """Lee y elimina lsg_game_start.json si existe.

    Returns:
        True si el archivo existía (el mod acaba de cargar sesión).
    """
    return _read_and_clear(SE_GAME_START_PATH, "lsg_game_start.json")


def read_refresh_request() -> bool:
    """Lee y elimina lsg_refresh_request.json si existe.

    El botón "Actualizar" de la tienda in-game lo escribe para pedirle a
    lsgames-app que vuelva a descargar perfil y catálogo, igual que el botón
    Actualizar del middleware.

    Returns:
        True si el archivo existía (hay una solicitud de refresco pendiente).
    """
    return _read_and_clear(SE_REFRESH_REQUEST_PATH, "lsg_refresh_request.json")
