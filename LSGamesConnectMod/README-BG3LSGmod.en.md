# LSGamesConnectMod: BG3 Script Extender mod

[Español](README-BG3LSGmod.md) | English

Baldur's Gate 3 mod (Lua, BG3 Script Extender) that connects the game to the
LifeSync-Games platform. It reads the signed `session.json` written by
`lsgames-app`, shows an in-game points store, and applies BG3 statuses based on
the player's real-world progress.

## Features

- **Session check**: validates `session.json` (fields, expiry, HMAC-SHA256) on
  every save load.
- **Change detection**: watches `lsg_notify.json` every 5 s, with a full re-check
  every 5 min as a fallback.
- **Points store**: ImGui window with Catalog, Active effects and Transactions tabs.
- **Floating button and hotkey**: the "Tienda LSG" button and `F7` toggle the store.
- **Redeems**: store purchases go to an offline queue. The mod sends it to the
  middleware signed with HMAC-SHA256, and the middleware syncs it with the API.
  Items and statuses are applied in game.
- **Passive effects**: permanent statuses per dimension when the balance reaches a
  threshold ([EFFECTS.md](ScriptExtender/EFFECTS.md)).
- **Recent activity**: temporary buffs for sensor events from the last 24 h
  ([EVENT_EFFECTS.md](ScriptExtender/EVENT_EFFECTS.md)).
- **Languages**: Spanish and English, synced with `lsgames-app`.
- **Multiplayer**: the server broadcasts session status and effects to all clients.

## File structure

```
LSGamesConnectMod/
  meta.lsx
  ScriptExtender/
    Config.json                 ModTable: "LSGamesConnect"
    EFFECTS.md                  Passive effects and recent-activity buffs
    EVENT_EFFECTS.md            Rationale for the sensor event mapping
    Lua/
      BootstrapServer.lua       Server: session checks, effects, console commands
      BootstrapClient.lua       Client: network listeners, store init, F7, !lsgstore
      SessionReader.lua         Reads and validates session.json
      Clock.lua                 Approximate wall clock (BG3SE has no os.time)
      Notifier.lua              Console and in-game dialog messages
      Shop.lua                  Catalog, signed purchase requests, offline redeems
      OfflineSync.lua           Offline point queue (CREDIT / DEBIT), signed sync requests
      Effects.lua               Passive tiers and recent-activity buffs
      Locale.lua                ES / EN strings
      Icons.lua                 Icon map for the store
      SHA256.lua                Pure Lua 5.4 SHA-256 and HMAC-SHA-256
      Client/Store/State.lua    Store state read from LSGMod/
      Client/Store/Purchase.lua Store redeem flow
      Client/UI/                StoreWindow, CatalogTab, EffectsTab, TransactionsTab
```

## Session validation

```
1. LSGMod/session.json exists?              NOT_FOUND if missing
2. Valid JSON with userId, balance, expires? PARSE_ERR if not
3. Not expired?                              EXPIRED if past `expires`
4. HMAC-SHA256 matches?                      BAD_SIG if tampered
   All pass                                  OK
```

BG3SE does not expose `os.time()`, so the expiry check uses `Clock.lua`, which
anchors the timestamp written by the middleware in `lsg_notify.json` to the
game's monotonic clock. If the middleware has not written that file yet, the
expiry check is skipped.

## Requirements

- Baldur's Gate 3 (PC)
- [BG3 Script Extender](https://www.nexusmods.com/baldursgate3/mods/2172)
- `lsgames-app` running and logged in

## Installation

1. Copy the `LSGamesConnectMod` folder (or the packed `.pak`) into the BG3 mods directory:

```
%LOCALAPPDATA%\Larian Studios\Baldur's Gate 3\Mods\
```

2. Activate the mod in BG3 Mod Manager.
3. Optional: enable the Script Extender console by creating
   `ScriptExtenderSettings.json` next to `bg3.exe`:

```json
{
  "CreateConsole": true,
  "DeveloperMode": true
}
```

## Shared secret

Create this file to override the default secret:

```
%LOCALAPPDATA%\Larian Studios\Baldur's Gate 3\Script Extender\LSGMod\mod_config.json
```

```json
{ "shared_secret": "your-secret-here" }
```

It must match `LIFESYNC_SHARED_SECRET` in `lsgames-app`.

## Console commands

Server context (`server` in the SE console):

- `!lsgames`: check the session and show an in-game dialog.
- `!lsgbalance`: show the balance per dimension.
- `!lsgshop`: list the catalog.
- `!lsgbuy <itemId> [n]`: redeem a mechanic through the middleware (`pending_purchase.json`).
- `!lsgsync`: ask the middleware to sync the offline queue.
- `!lsgqueue`: show the offline queue.
- `!lsgearn <dim_id> <pts> [trigger]`: queue a point credit.
- `!lsgredeem <dim_id> <pts> [mechanic_id]`: queue a manual redeem.
- `!lsgeffects [clear]`: re-evaluate (or remove) passive effects.
- `!lsgevents`: list recent sensor events and apply pending buffs.

Client context (`client`):

- `!lsgstore`: toggle the store window (same as `F7`).

Dimension ids: Social=1, Fisico=2, Afectivo=3, Mental=4, Linguistico=5.

## Console output examples

**Connected:**
```
[LSGames] ------------------------------------------------------------
[LSGames] CONECTADO  |  Jugador: 42  |  Afectivo: 0  |  Fisico: 100  |  Linguistico: 30  |  Mental: 200  |  Social: 150  |  Expira: 27/10/2026 18:45:00
[LSGames] ------------------------------------------------------------
```

**Not connected:**
```
[LSGames] ------------------------------------------------------------
[LSGames] SIN CONEXIÓN  |  NOT_FOUND  |  Archivo de sesión no encontrado: LSGMod/session.json
[LSGames] ------------------------------------------------------------
```
