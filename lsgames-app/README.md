# lsgames-app: middleware de escritorio de LifeSyncGames

Español | [English](README.en.md)

Aplicación de escritorio (customtkinter) que se ubica entre la API de
LifeSync-Games y el mod de BG3. Autentica al jugador, escribe los archivos que lee
el mod y procesa las solicitudes que el mod deja en la carpeta `LSGMod/`.

## Qué hace

1. Al iniciar, intenta entrar con el access token guardado en el almacén de
   credenciales del sistema (keyring). Si no existe o expiró, muestra el
   formulario de login.
2. Tras el login, descarga el perfil y el balance de las cinco dimensiones
   (social, fisico, afectivo, mental, linguistico) y escribe `session.json`
   firmado y `catalog.json`.
3. Cada 3 s revisa la carpeta `LSGMod/` en busca de:
   - `pending_purchase.json`: verifica la firma HMAC y canjea la mecánica con
     `POST /videogames/{id}/players/{pid}/redeem`.
   - `pending_offline_sync.json`: verifica la firma HMAC, envía la cola offline
     del mod a `POST /offline/sync` y escribe `offline_sync_result.json`.
   - `lsg_game_start.json`: abre una sesión de juego en la API y la cierra cuando
     `bg3.exe` deja de ejecutarse.
   - `lsg_refresh_request.json`: vuelve a descargar perfil y catálogo.
4. Cada 60 s descarga los eventos de sensores del jugador y escribe
   `recent_events.json` para los buffs de actividad reciente del mod.
5. Registra cada canje y cada abono en `transactions.json` (últimas 100 entradas).

La ventana muestra el nombre, el email, el balance por dimensión y la expiración
de la sesión. La interfaz está en español e inglés.

## Requisitos

- Python 3.10+
- Windows (keyring usa el Administrador de credenciales de Windows y la detección
  del proceso del juego usa `tasklist`)

## Instalación y ejecución

```bash
cd lsgames-app
pip install -r requirements.txt
python main.py
```

## Variables de entorno

- `LIFESYNC_AUTH_URL`: URL base de LSG-Auth.
  Por defecto: `https://lsg.diinf.usach.cl/lsg-auth`.
- `LIFESYNC_CORE_URL`: URL base de LSG-Core-API.
  Por defecto: `https://lsg.diinf.usach.cl/lsg-core-api`.
- `LIFESYNC_BG3_GAME_ID`: id de BG3 registrado en LSG. Por defecto: `23`.
- `LIFESYNC_SHARED_SECRET`: clave HMAC; debe coincidir con la del mod.
  Por defecto: `change-me-in-production`.
- `LIFESYNC_LOCALE`: idioma inicial de la interfaz, `es` o `en`. Por defecto: `es`.

## Estructura

```
lsgames-app/
  main.py                 Punto de entrada
  config.py               URLs de la API, secreto, rutas de LSGMod/, TTL de sesión
  i18n.py                 Traducciones (locales/es.json, locales/en.json)
  build.spec              Configuración de PyInstaller
  auth/
    login.py              POST /login, POST /token/refresh, GET /whoami
    token_store.py        Token, email e idioma en keyring
  api/
    client.py             Cliente de LSG-Core-API (balance, mecánicas, canje, sesiones, sync offline)
    models.py             Dataclasses Dimension y UserProfile
  session/
    atomic.py             Escritura atómica en LSGMod/
    signer.py             Firma y verificación HMAC-SHA256 (payload canónico o texto tal cual)
    writer.py             session.json firmado
    catalog.py            catalog.json (usa pociones de prueba si la API no tiene mecánicas)
    purchase.py           Lee y verifica pending_purchase.json
    offline_sync.py       Lee y verifica pending_offline_sync.json, escribe el resultado
    ingest_events.py      recent_events.json
    transactions.py       transactions.json
    inventory.py          lsg_notify.json
    game_session.py       Señales del mod (inicio de partida, refresco)
  ui/
    window.py             Ventana principal
```

## Archivo de sesión

```json
{
  "userId": "42",
  "balance": { "social": 150, "fisico": 100, "afectivo": 0, "mental": 200, "linguistico": 30 },
  "expires": 1761600000,
  "sig": "hmac-sha256-hex-digest",
  "playerName": "Nombre del jugador",
  "dimensions": [ { "id": 1, "name": "social", "balance": 150 } ]
}
```

- `sig` cubre `{userId, balance, expires}` serializado como JSON compacto con las
  claves ordenadas. `playerName` y `dimensions` son informativos y quedan fuera de
  la firma.
- La sesión dura 120 minutos, lo mismo que el JWT de la API. Se reescribe en cada
  refresco, canje y sincronización offline.

## Ejecutable independiente

```bash
pip install pyinstaller
pyinstaller build.spec
```

Resultado: `dist/LifeSyncGames.exe`.
