"""Módulo de internacionalización (i18n) para la aplicación LifeSyncGames.

Uso:
    from i18n import t, set_locale, current_locale, available_locales

    t("btn_login")                              # "Iniciar sesión"
    t("status_sync_ok", synced=3, total=5)      # "Sync offline: 3/5 sincronizados"

Para añadir un idioma nuevo:
    1. Crear lsgames-app/locales/<codigo>.json con todas las claves del es.json.
    2. El botón de idioma en la UI lo detectará automáticamente.
"""

import json
from pathlib import Path

_LOCALES_DIR = Path(__file__).parent / "locales"
_locale: str = "es"
_strings: dict = {}


def set_locale(lang: str) -> bool:
    """Carga el idioma indicado desde locales/{lang}.json.

    Returns:
        True si el idioma existe y se cargó; False si no se encontró el archivo.
    """
    global _locale, _strings
    path = _LOCALES_DIR / f"{lang}.json"
    if not path.exists():
        return False
    _strings = json.loads(path.read_text(encoding="utf-8"))
    _locale = lang
    return True


def t(key: str, **kwargs) -> str:
    """Traduce una clave al idioma activo con interpolación opcional.

    Si la clave no existe en el archivo de idioma, devuelve la propia clave
    como fallback para facilitar la detección de strings sin traducir.

    Ejemplos:
        t("btn_login")
        t("status_sync_ok", synced=3, total=5)
    """
    text = _strings.get(key, key)
    if kwargs:
        try:
            text = text.format(**kwargs)
        except (KeyError, ValueError):
            pass
    return text


def t_dim(api_name: str) -> str:
    """Traduce el nombre de una dimensión LSG desde su código de API.

    Ejemplos:
        t_dim("fisico")      # "Físico" (es) / "Physical" (en)
        t_dim("linguistico") # "Lingüístico" / "Linguistic"

    Fallback a capitalize() si la clave no existe, para dimensiones futuras.
    """
    return _strings.get(f"dim_{api_name}", api_name.capitalize())


def current_locale() -> str:
    """Retorna el código del idioma activo (ej: 'es', 'en')."""
    return _locale


def available_locales() -> list[str]:
    """Lista los idiomas disponibles detectando archivos en locales/."""
    return sorted(p.stem for p in _LOCALES_DIR.glob("*.json"))


# Cargar idioma por defecto al importar el módulo
set_locale("es")
