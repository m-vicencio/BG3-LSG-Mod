# lsgames-app: LifeSyncGames desktop middleware

[Español](README.md) | English

Desktop application (customtkinter) that sits between the LifeSync-Games API and
the BG3 mod. It authenticates the player, writes the files the mod reads, and
processes the requests the mod leaves in the `LSGMod/` folder.

## What it does

1. On launch, tries to log in with the access token stored in the OS credential
   store (keyring). If it is missing or expired, shows the login form.
2. After login, fetches the profile and the five dimension balances
   (social, fisico, afectivo, mental, linguistico) and writes a signed
   `session.json` plus `catalog.json`.
3. Polls the `LSGMod/` folder every 3 s for:
   - `pending_purchase.json`: verifies the HMAC signature and redeems the mechanic
     through `POST /videogames/{id}/players/{pid}/redeem`.
   - `pending_offline_sync.json`: verifies the HMAC signature, sends the mod's
     offline queue to `POST /offline/sync` and writes `offline_sync_result.json`.
   - `lsg_game_start.json`: opens a game session in the API and closes it when
     `bg3.exe` stops running.
   - `lsg_refresh_request.json`: refreshes profile and catalog.
4. Every 60 s, downloads the player's sensor events and writes
   `recent_events.json` for the mod's recent-activity buffs.
5. Records every redeem and credit in `transactions.json` (last 100 entries).

The window shows the player's name, email, balance per dimension and session
expiry. The UI is available in Spanish and English.

## Requirements

- Python 3.10+
- Windows (keyring uses Windows Credential Manager; process detection uses `tasklist`)

## Setup and run

```bash
cd lsgames-app
pip install -r requirements.txt
python main.py
```

## Environment variables

- `LIFESYNC_AUTH_URL`: LSG-Auth base URL.
  Default: `https://lsg.diinf.usach.cl/lsg-auth`.
- `LIFESYNC_CORE_URL`: LSG-Core-API base URL.
  Default: `https://lsg.diinf.usach.cl/lsg-core-api`.
- `LIFESYNC_BG3_GAME_ID`: BG3 game id registered in LSG. Default: `23`.
- `LIFESYNC_SHARED_SECRET`: HMAC key, must match the mod.
  Default: `change-me-in-production`.
- `LIFESYNC_LOCALE`: default UI language, `es` or `en`. Default: `es`.

## Project structure

```
lsgames-app/
  main.py                 Entry point
  config.py               API URLs, secret, LSGMod/ paths, session TTL
  i18n.py                 Translations (locales/es.json, locales/en.json)
  build.spec              PyInstaller config
  auth/
    login.py              POST /login, POST /token/refresh, GET /whoami
    token_store.py        Token, email and language in keyring
  api/
    client.py             LSG-Core-API client (balance, mechanics, redeem, sessions, offline sync)
    models.py             Dimension and UserProfile dataclasses
  session/
    atomic.py             Atomic writes to LSGMod/
    signer.py             HMAC-SHA256 sign / verify (canonical payload or raw text)
    writer.py             Signed session.json
    catalog.py            catalog.json (falls back to test potions if the API has no mechanics)
    purchase.py           Reads and verifies pending_purchase.json
    offline_sync.py       Reads and verifies pending_offline_sync.json, writes the result
    ingest_events.py      recent_events.json
    transactions.py       transactions.json
    inventory.py          lsg_notify.json
    game_session.py       Signals from the mod (game start, refresh)
  ui/
    window.py             Main window
```

## Session file

```json
{
  "userId": "42",
  "balance": { "social": 150, "fisico": 100, "afectivo": 0, "mental": 200, "linguistico": 30 },
  "expires": 1761600000,
  "sig": "hmac-sha256-hex-digest",
  "playerName": "Player Name",
  "dimensions": [ { "id": 1, "name": "social", "balance": 150 } ]
}
```

- `sig` covers `{userId, balance, expires}` serialized as compact JSON with sorted
  keys. `playerName` and `dimensions` are informational and outside the signature.
- The session lasts 120 minutes, the same as the API's JWT. It is rewritten on
  every refresh, redeem and offline sync.

## Building a standalone executable

```bash
pip install pyinstaller
pyinstaller build.spec
```

Output: `dist/LifeSyncGames.exe`.
