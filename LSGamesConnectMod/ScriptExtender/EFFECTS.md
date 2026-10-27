# Efectos pasivos por completitud de metas

Aplica **status** de BG3 al personaje host según el balance dimensional de LSG.
Implementado en `Lua/Effects.lua` y cableado en `BootstrapServer.lua`.

## Dos mecanismos

### 1. Tiers por acumulación (permanentes)
Por dimensión se definen umbrales de puntos que otorgan un status. Se aplica el
**tier más alto alcanzado**; mientras el balance se mantenga sobre el umbral, el
status persiste (`duration = -1`). Si el balance baja del umbral, se remueve o
baja de tier.

### 2. Actividad reciente (temporal, por eventos de sensores)
`lsgames-app` consulta `GET /sensors/players/{id}/ingest-events` cada 60 s y
escribe en `LSGMod/recent_events.json` los eventos **OK de las últimas 24 h**
(id, event_type, milestone, parsed_value, occurred_at). El sensor LSG-Routes no
manda `event_type` en su `raw_payload`; `ingest_events.py` lo deriva de `mode` y
`route_id` (`route.completed.<mode>`, o `route.freeroam` si
`route_id == "free_roam"`).

El mod mapea cada `event_type` a un buff con duración limitada que **expira
solo** (no hay `RemoveStatus`). Cada evento se aplica **una sola vez**: el último
id aplicado se guarda en `LSGMod/applied_events.json`. Se usa un archivo y no el
savegame porque la actividad es del mundo real y no debe volver a otorgarse al
cargar otra partida. Un `event_type` sin entrada en la tabla se ignora y se marca
como visto.

**Justificación de cada asignación y reglas de balance: `EVENT_EFFECTS.md`.**

## Cuándo se evalúa

`Effects.update(session)` y `Effects.applyRecentEvents()` corren en:
- `SessionLoaded` (al cargar partida),
- la vigilancia de `lsg_notify.json` (~5 s): cuando el middleware sincroniza
  (compra, refresh, sync offline, eventos de sensores nuevos), y
- el poll de respaldo cada 5 min (por si el middleware no escribe notify).

`applyRecentEvents` corre incluso si `session.json` no cambió: los eventos de
sensores llegan por su propio archivo.

## Configuración (en `Lua/Effects.lua`)

```lua
Effects.tiers = {
    social = {
        { min = 5,  status = "GUIDANCE" },
        { min = 25, status = "EAGLES_SPLENDOR" },
        { min = 75, status = "BLESS" },
    },
    -- fisico, mental, afectivo, linguistico ...
}

Effects.events = {
    ["streak.daily_logging"]    = { status = "GUIDANCE",    duration = 600  },
    ["budget.month_met"]        = { status = "RESISTANCE",  duration = 900  },
    ["route.completed.walking"] = { status = "LONGSTRIDER", duration = 1200 },
    ["route.completed.jogging"] = { status = "LONGSTRIDER", duration = 1800 },
    ["route.completed.hiking"]  = { status = "BLADE_WARD",  duration = 900  },
    ["route.freeroam"]          = { status = "LONGSTRIDER", duration = 600  },
}

Effects.milestone = {  -- savings.milestone: escala con el hito (25/50/75/100 %)
    status         = "BLADE_WARD",
    base_duration  = 300,   -- segundos por cada 25 % de la meta
    final_status   = "HEROISM",
    final_duration = 900,   -- premio al 100 % (evento único por cuenta)
}
```

- **Claves de dimensión**: minúsculas, igual que en `session.balance` y el catálogo:
  `social, fisico, afectivo, mental, linguistico`.
- **Umbrales (`min`)**: en puntos. Orden libre; se elige el mayor `min` alcanzado.
- **`status`**: nombre exacto de un status del juego (ver lista abajo).
- **`duration`**: en segundos.

## Mapeo por defecto de los tiers

| Dimensión | 1er tier | 2º tier (atributo) | 3er tier |
|---|---|---|---|
| social | 5: GUIDANCE | 25: EAGLES_SPLENDOR (ventaja Carisma) | 75: BLESS |
| fisico | 5: GUIDANCE | 25: BULLS_STRENGTH (ventaja Fuerza) | 75: BEARS_ENDURANCE |
| mental | (ninguno) | 25: FOXS_CUNNING (ventaja Inteligencia) | 75: AID (+5 HP máx) |
| afectivo | (ninguno) | 25: OWLS_WISDOM (ventaja Sabiduría) | 75: SHIELD_OF_FAITH (+2 CA) |
| linguistico | (ninguno) | 25: CATS_GRACE (ventaja Destreza) | 75: HEROISM (inmune a miedo) |

La tabla de actividad reciente y su justificación están en `EVENT_EFFECTS.md`.

## Status verificados (Status_BOOST.txt del juego)

Familia *Enhance Ability* (ventaja en pruebas de un atributo):
`BULLS_STRENGTH` (FUE), `BEARS_ENDURANCE` (CON), `CATS_GRACE` (DES),
`FOXS_CUNNING` (INT), `OWLS_WISDOM` (SAB), `EAGLES_SPLENDOR` (CAR).

Buffs generales:
`GUIDANCE` (+1d4 habilidad), `RESISTANCE` (+1d4 salv.), `BLESS` (+1d4 ataque/salv.),
`SHIELD_OF_FAITH` (+2 CA), `BARKSKIN` (CA mín 16), `AID` (+5 HP máx),
`HEROISM` (inmune a miedo), `LONGSTRIDER` (+3 m mov.), `HASTE` (+mov, +2 CA, +1 acción),
`BLADE_WARD` (resist. daño físico), `DARKVISION`.

El status de "Eagle's Splendor" es `EAGLES_SPLENDOR`, con S. `EAGLE_SPLENDOR` no
existe y `ApplyStatus` falla sin avisar.

Para ver los 852 statuses en vivo (consola SE, contexto `server`):
```lua
for _, n in ipairs(Ext.Stats.GetStats("StatusData")) do print(n) end
```

## Visibilidad en la tienda

`BootstrapServer` transmite a los clientes, por el canal de red
`LSGames_PassiveEffects`, un snapshot con los tiers aplicados (`{dim, status,
min, pts}`) y los buffs de actividad reciente vigentes. La ventana **Tienda de
puntos > Efectos activos** tiene tres submenús:

- **Canjeados**: Estados comprados en la tienda, con cuenta regresiva.
- **Pasivos**: los tiers por acumulación, marcados "Permanente" con su
  dimensión, umbral y balance actual.
- **Actividad reciente**: los buffs por eventos de sensores, con cuenta regresiva.

## Probar

Consola SE (contexto `server`):

```
!lsgearn 1 30 test        -- suma 30 pts a la dimensión Social (dispara tiers)
!lsgeffects               -- re-evalúa efectos con el balance actual
!lsgeffects clear         -- remueve los efectos por tier
!lsgevents                -- lista recent_events.json y aplica buffs pendientes
!lsgbalance               -- ver balance dimensional
```

Para probar los buffs por evento sin backend, escribir a mano
`LSGMod/recent_events.json`:

```json
{ "events": [ { "id": 9001, "event_type": "route.completed.walking",
                "milestone": null, "occurred_at": "2026-08-06T18:00:00" } ] }
```

y ejecutar `!lsgevents`. Repetirlo no vuelve a aplicar el evento (dedupe por id
en `applied_events.json`; para repetir la prueba hay que borrar ese archivo o
subir el id).

IDs de dimensión para `!lsgearn`: Social=1, Fisico=2, Afectivo=3, Mental=4, Linguistico=5.

## Notas para producción (pendientes de calibrar)

Los valores por defecto están pensados para **probar** que el sistema funciona, no
para el balance final. Antes de publicar conviene revisar:

- **Los umbrales 5 / 25 / 75 son arbitrarios e iguales para todas las dimensiones.**
  Hay que calibrarlos con los rangos reales de puntos que otorga LSG.
  Probablemente cada dimensión necesite umbrales distintos según cuántos puntos se
  ganan típicamente.
- **Duraciones de los buffs por evento (5 a 30 min).** Calibrar con sesiones de
  juego reales; ver `EVENT_EFFECTS.md` para el criterio de cada una.
- **Acumulación de buffs fuertes.** Varios tiers tope a la vez (AID + ventajas)
  pueden desbalancear el combate. Se podría limitar a 1 o 2 efectos activos o
  reservar los tiers altos para metas difíciles.

## Cómo aplicar un status manualmente (referencia)

```lua
Osi.ApplyStatus(charUuid, "EAGLES_SPLENDOR", -1, 1, charUuid)  -- -1 = permanente
Osi.ApplyStatus(charUuid, "HASTE", 60, 1, charUuid)            -- 60 s, expira solo
Osi.RemoveStatus(charUuid, "EAGLES_SPLENDOR")
```
Firma: `ApplyStatus(target, status, durationSegundos, force, source)`.
