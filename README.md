# LifeSyncGames: integración con Baldur's Gate 3 (v1.0)

Español | [English](README.en.md)

Conecta la plataforma LifeSync-Games (InTeractiOn Lab, USACH) con Baldur's Gate 3.
Los puntos que el jugador gana con su actividad en la vida real se pueden gastar en
una tienda dentro del juego, desbloquean efectos pasivos y otorgan buffs temporales
por actividad reciente.

## Visión general

```
+--------------------+    HTTPS + JWT    +-------------------------------+
|  lsgames-app       | <---------------> |  LSG-Auth / LSG-Core-API      |
|  (Python, desktop) |                   |  lsg.diinf.usach.cl           |
+---------+----------+                   +-------------------------------+
          |
          |  archivos JSON en
          |  %LOCALAPPDATA%\Larian Studios\Baldur's Gate 3\Script Extender\LSGMod\
          v
+--------------------+
|  LSGamesConnectMod |  mod de BG3 Script Extender (Lua)
|  (en el juego)     |  tienda, efectos pasivos, cola offline
+--------------------+
```

El juego nunca se conecta a la red. `lsgames-app` habla con la API y ambos lados
intercambian archivos JSON a través de la carpeta `LSGMod/`.

Los escribe la app:

- `session.json`: jugador, balance por dimensión y expiración, firmado con HMAC.
- `catalog.json`: mecánicas canjeables.
- `transactions.json`: últimos 100 movimientos de puntos.
- `recent_events.json`: eventos de sensores de las últimas 24 h.
- `lsg_notify.json`: marca de tiempo de cambios; el mod también la usa como reloj de pared.
- `offline_sync_result.json`: resultado de `POST /offline/sync`.
- `locale.json`: idioma de la interfaz (también lo escribe el mod).

Los escribe el mod:

- `pending_purchase.json`: solicitud de canje firmada (`!lsgbuy`).
- `pending_offline_sync.json`: cola offline firmada, lista para sincronizar.
- `lsg_game_start.json`: se cargó una partida (abre una sesión de juego en la API).
- `lsg_refresh_request.json`: se pulsó el botón "Actualizar" de la tienda.

## Componentes

- [`lsgames-app/`](lsgames-app/README.md) (Python): middleware de escritorio para
  login, perfil, catálogo, canjes y sincronización offline.
- [`LSGamesConnectMod/`](LSGamesConnectMod/README-BG3LSGmod.md) (Lua, BG3SE):
  mod con verificación de sesión, tienda, efectos y comandos de consola.
- `tests/` (Python): tests locales, tests de integración con la API y un benchmark.
- `MANUAL-lsg-auth.md`, `MANUAL-lsg-core.md`: manuales de usuario de las APIs LSG.

## Inicio rápido

1. Abrir `lsgames-app` e iniciar sesión con la cuenta de LifeSync-Games.
2. Instalar el mod y lanzar BG3 con el Script Extender.
3. Cargar una partida. La tienda se abre con `F7`, con el botón flotante o con `!lsgstore`.
