"""Configuración central de la aplicación LifeSyncGames."""

import os

# URLs de la API de producción
AUTH_BASE_URL: str = os.environ.get(
    "LIFESYNC_AUTH_URL", "https://lsg.diinf.usach.cl/lsg-auth"
)
CORE_BASE_URL: str = os.environ.get(
    "LIFESYNC_CORE_URL", "https://lsg.diinf.usach.cl/lsg-core-api"
)

# ID del videojuego BG3 registrado en la plataforma LSG
BG3_GAME_ID: int = int(os.environ.get("LIFESYNC_BG3_GAME_ID", "23"))

# Secreto compartido para firmas HMAC-SHA256. En producción se define con la
# variable de entorno LIFESYNC_SHARED_SECRET.
SHARED_SECRET: str = os.environ.get("LIFESYNC_SHARED_SECRET", "change-me-in-production")

# Rutas de archivos del Script Extender de BG3
SE_SESSION_PATH: str = os.path.expandvars(
    r"%LOCALAPPDATA%\Larian Studios\Baldur's Gate 3\Script Extender\LSGMod\session.json"
)
SE_CATALOG_PATH: str = os.path.expandvars(
    r"%LOCALAPPDATA%\Larian Studios\Baldur's Gate 3\Script Extender\LSGMod\catalog.json"
)
SE_PURCHASE_PATH: str = os.path.expandvars(
    r"%LOCALAPPDATA%\Larian Studios\Baldur's Gate 3\Script Extender\LSGMod\pending_purchase.json"
)
SE_GAME_START_PATH: str = os.path.expandvars(
    r"%LOCALAPPDATA%\Larian Studios\Baldur's Gate 3\Script Extender\LSGMod\lsg_game_start.json"
)
SE_NOTIFY_PATH: str = os.path.expandvars(
    r"%LOCALAPPDATA%\Larian Studios\Baldur's Gate 3\Script Extender\LSGMod\lsg_notify.json"
)
SE_OFFLINE_PENDING_PATH: str = os.path.expandvars(
    r"%LOCALAPPDATA%\Larian Studios\Baldur's Gate 3\Script Extender\LSGMod\pending_offline_sync.json"
)
SE_OFFLINE_RESULT_PATH: str = os.path.expandvars(
    r"%LOCALAPPDATA%\Larian Studios\Baldur's Gate 3\Script Extender\LSGMod\offline_sync_result.json"
)
SE_LOCALE_PATH: str = os.path.expandvars(
    r"%LOCALAPPDATA%\Larian Studios\Baldur's Gate 3\Script Extender\LSGMod\locale.json"
)
SE_TRANSACTIONS_PATH: str = os.path.expandvars(
    r"%LOCALAPPDATA%\Larian Studios\Baldur's Gate 3\Script Extender\LSGMod\transactions.json"
)
SE_RECENT_EVENTS_PATH: str = os.path.expandvars(
    r"%LOCALAPPDATA%\Larian Studios\Baldur's Gate 3\Script Extender\LSGMod\recent_events.json"
)
SE_REFRESH_REQUEST_PATH: str = os.path.expandvars(
    r"%LOCALAPPDATA%\Larian Studios\Baldur's Gate 3\Script Extender\LSGMod\lsg_refresh_request.json"
)

# Idioma por defecto de la UI ("es" o "en")
DEFAULT_LOCALE: str = os.environ.get("LIFESYNC_LOCALE", "es")

# Tiempo de vida de la sesión local en segundos; debe coincidir con el TTL del JWT
# (ver GET /token/remaining; el JWT de producción expira en 120 minutos)
SESSION_TTL_SECONDS: int = 120 * 60  # 120 minutos

# Identificadores del servicio en el almacén de credenciales del SO
KEYRING_SERVICE: str = "LifeSyncGames"
KEYRING_USERNAME: str = "access_token"
KEYRING_USERNAME_EMAIL: str = "email"
