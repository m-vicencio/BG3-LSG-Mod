# LifeSyncGames: Baldur's Gate 3 integration (v1.0)

[Español](README.md) | English

Connects the LifeSync-Games platform (InTeractiOn Lab, USACH) with Baldur's Gate 3.
Points that players earn from real-world activity can be spent in an in-game store,
unlock passive effects, and grant temporary buffs for recent activity.

## System overview

```
+--------------------+    HTTPS + JWT    +-------------------------------+
|  lsgames-app       | <---------------> |  LSG-Auth / LSG-Core-API      |
|  (Python desktop)  |                   |  lsg.diinf.usach.cl           |
+---------+----------+                   +-------------------------------+
          |
          |  JSON files in
          |  %LOCALAPPDATA%\Larian Studios\Baldur's Gate 3\Script Extender\LSGMod\
          v
+--------------------+
|  LSGamesConnectMod |  BG3 Script Extender mod (Lua)
|  (in-game)         |  store window, passive effects, offline queue
+--------------------+
```

The game never talks to the network. `lsgames-app` talks to the API and both sides
exchange JSON files through the `LSGMod/` folder.

Written by the app:

- `session.json`: player, dimension balances and expiry, HMAC-signed.
- `catalog.json`: redeemable mechanics.
- `transactions.json`: last 100 point movements.
- `recent_events.json`: sensor events from the last 24 h.
- `lsg_notify.json`: change timestamp, also used as the mod's wall clock.
- `offline_sync_result.json`: result of `POST /offline/sync`.
- `locale.json`: UI language (the mod writes it too).

Written by the mod:

- `pending_purchase.json`: signed redeem request (`!lsgbuy`).
- `pending_offline_sync.json`: signed offline queue ready to sync.
- `lsg_game_start.json`: a save was loaded (opens a game session in the API).
- `lsg_refresh_request.json`: the store's "Refresh" button was pressed.

## Components

- [`lsgames-app/`](lsgames-app/README.en.md) (Python): desktop middleware for login,
  profile, catalog, redeems and offline sync.
- [`LSGamesConnectMod/`](LSGamesConnectMod/README-BG3LSGmod.en.md) (Lua, BG3SE):
  in-game mod with session check, store, effects and console commands.
- `tests/` (Python): local tests, API integration tests and a benchmark.
- `MANUAL-lsg-auth.md`, `MANUAL-lsg-core.md`: user manuals for the LSG APIs (Spanish).

## Quick start

1. Start `lsgames-app` and log in with your LifeSync-Games account.
2. Install the mod and launch BG3 with the Script Extender.
3. Load a save. Open the store with `F7`, the floating button, or `!lsgstore`.
