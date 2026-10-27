# LSGamesConnectMod: mod de BG3 Script Extender

Español | [English](README-BG3LSGmod.en.md)

Mod de Baldur's Gate 3 (Lua, BG3 Script Extender) que conecta el juego con la
plataforma LifeSync-Games. Lee el `session.json` firmado que escribe
`lsgames-app`, muestra una tienda de puntos dentro del juego y aplica status de
BG3 según el progreso del jugador en la vida real.

## Funciones

- **Verificación de sesión**: valida `session.json` (campos, expiración y
  HMAC-SHA256) cada vez que se carga una partida.
- **Detección de cambios**: revisa `lsg_notify.json` cada 5 s y hace una
  verificación completa cada 5 min como respaldo.
- **Tienda de puntos**: ventana ImGui con las pestañas Catálogo, Efectos activos y
  Transacciones.
- **Botón flotante y atajo**: el botón "Tienda LSG" y `F7` abren y cierran la tienda.
- **Canjes**: las compras de la tienda van a una cola offline. El mod la envía al
  middleware firmada con HMAC-SHA256 y el middleware la sincroniza con la API.
  Los objetos y status se aplican en el juego.
- **Efectos pasivos**: status permanentes por dimensión cuando el balance alcanza
  un umbral ([EFFECTS.md](ScriptExtender/EFFECTS.md)).
- **Actividad reciente**: buffs temporales por eventos de sensores de las últimas
  24 h ([EVENT_EFFECTS.md](ScriptExtender/EVENT_EFFECTS.md)).
- **Idiomas**: español e inglés, sincronizados con `lsgames-app`.
- **Multijugador**: el servidor transmite el estado de la sesión y los efectos a
  todos los clientes.

## Estructura de archivos

```
LSGamesConnectMod/
  meta.lsx
  ScriptExtender/
    Config.json                 ModTable: "LSGamesConnect"
    EFFECTS.md                  Efectos pasivos y buffs de actividad reciente
    EVENT_EFFECTS.md            Justificación del mapeo de eventos de sensores
    Lua/
      BootstrapServer.lua       Servidor: verificación de sesión, efectos, comandos de consola
      BootstrapClient.lua       Cliente: mensajes de red, inicio de la tienda, F7, !lsgstore
      SessionReader.lua         Lee y valida session.json
      Clock.lua                 Reloj de pared aproximado (BG3SE no tiene os.time)
      Notifier.lua              Mensajes en consola y diálogos en el juego
      Shop.lua                  Catálogo, solicitudes de compra firmadas, canjes offline
      OfflineSync.lua           Cola de puntos offline (CREDIT / DEBIT), solicitudes firmadas
      Effects.lua               Tiers pasivos y buffs de actividad reciente
      Locale.lua                Textos ES / EN
      Icons.lua                 Mapa de iconos de la tienda
      SHA256.lua                SHA-256 y HMAC-SHA-256 en Lua 5.4 puro
      Client/Store/State.lua    Estado de la tienda leído de LSGMod/
      Client/Store/Purchase.lua Flujo de canje de la tienda
      Client/UI/                StoreWindow, CatalogTab, EffectsTab, TransactionsTab
```

## Validación de la sesión

```
1. ¿Existe LSGMod/session.json?                     NOT_FOUND si falta
2. ¿JSON válido con userId, balance y expires?      PARSE_ERR si no
3. ¿Sin expirar?                                    EXPIRED si ya pasó `expires`
4. ¿Coincide el HMAC-SHA256?                        BAD_SIG si fue alterado
   Todo correcto                                    OK
```

BG3SE no expone `os.time()`, así que la expiración se comprueba con `Clock.lua`,
que ancla la marca de tiempo que el middleware escribe en `lsg_notify.json` al
reloj monotónico del juego. Si el middleware todavía no escribió ese archivo, la
comprobación de expiración se omite.

## Requisitos

- Baldur's Gate 3 (PC)
- [BG3 Script Extender](https://www.nexusmods.com/baldursgate3/mods/2172)
- `lsgames-app` en ejecución y con sesión iniciada

## Instalación

1. Copiar la carpeta `LSGamesConnectMod` (o el `.pak` empaquetado) en la carpeta de mods de BG3:

```
%LOCALAPPDATA%\Larian Studios\Baldur's Gate 3\Mods\
```

2. Activar el mod en BG3 Mod Manager.
3. Opcional: activar la consola del Script Extender creando
   `ScriptExtenderSettings.json` junto a `bg3.exe`:

```json
{
  "CreateConsole": true,
  "DeveloperMode": true
}
```

## Secreto compartido

Para cambiar el secreto por defecto, crear este archivo:

```
%LOCALAPPDATA%\Larian Studios\Baldur's Gate 3\Script Extender\LSGMod\mod_config.json
```

```json
{ "shared_secret": "tu-secreto" }
```

Debe coincidir con `LIFESYNC_SHARED_SECRET` en `lsgames-app`.

## Comandos de consola

Contexto de servidor (`server` en la consola SE):

- `!lsgames`: verifica la sesión y muestra un diálogo en el juego.
- `!lsgbalance`: muestra el balance por dimensión.
- `!lsgshop`: lista el catálogo.
- `!lsgbuy <itemId> [n]`: canjea una mecánica a través del middleware (`pending_purchase.json`).
- `!lsgsync`: pide al middleware sincronizar la cola offline.
- `!lsgqueue`: muestra la cola offline.
- `!lsgearn <dim_id> <pts> [trigger]`: encola un abono de puntos.
- `!lsgredeem <dim_id> <pts> [mechanic_id]`: encola un canje manual.
- `!lsgeffects [clear]`: vuelve a evaluar (o quita) los efectos pasivos.
- `!lsgevents`: lista los eventos de sensores recientes y aplica los buffs pendientes.

Contexto de cliente (`client`):

- `!lsgstore`: abre o cierra la tienda (igual que `F7`).

IDs de dimensión: Social=1, Fisico=2, Afectivo=3, Mental=4, Linguistico=5.

## Ejemplos de salida en consola

**Conectado:**
```
[LSGames] ------------------------------------------------------------
[LSGames] CONECTADO  |  Jugador: 42  |  Afectivo: 0  |  Fisico: 100  |  Linguistico: 30  |  Mental: 200  |  Social: 150  |  Expira: 27/10/2026 18:45:00
[LSGames] ------------------------------------------------------------
```

**Sin conexión:**
```
[LSGames] ------------------------------------------------------------
[LSGames] SIN CONEXIÓN  |  NOT_FOUND  |  Archivo de sesión no encontrado: LSGMod/session.json
[LSGames] ------------------------------------------------------------
```
