# Mapeo de eventos de sensor a status in-game

Documenta por qué cada `event_type` de los sensores LSG otorga el status BG3
que otorga. Configuración en `Lua/Effects.lua` (`Effects.events` y
`Effects.milestone`); mecánica general en `EFFECTS.md`.

## Principio de balance

Los buffs por actividad reciente son **temporales y suaves**:

- **Nada de acciones extra, CA ni ventaja de ataque.** Los status de impacto
  directo en combate (HASTE, ventajas de atributo, AID, SHIELD_OF_FAITH...)
  quedan reservados a los **tiers por acumulación**, que exigen esfuerzo
  sostenido, y a la **tienda**, que cuesta puntos.
- Solo utilidad menor: dados extra fuera de combate (+1d4), movilidad,
  resistencia física. Recompensan sin trivializar encuentros.
- Duración corta (5 a 30 min de tiempo real): es una "ventana de actividad",
  no un poder permanente.
- Eventos de más de 24 h no otorgan buff (filtro del middleware): se premia la
  actividad del día, no el historial.

Dos status del mapeo también se usan en tiers: `GUIDANCE` (tier 1 de Social y
Físico) y `HEROISM` (tier 3 de Lingüístico). Si el jugador ya tiene ese tier, el
buff no le suma nada; y si pierde el tier mientras el buff está activo, el
`RemoveStatus` del tier quita también el buff.

## Tabla de asignación

| event_type | Sensor / señal | Dimensión | Status | Duración | Lógica |
|---|---|---|---|---|---|
| `streak.daily_logging` | EggSys: registró movimientos en días distintos de la semana | Mental | `GUIDANCE` (+1d4 pruebas de habilidad) | 10 min | La constancia diaria es disciplina de hábito: se traduce en "hacer mejor las tareas cotidianas", que es lo que da GUIDANCE fuera de combate. |
| `budget.month_met` | EggSys: cerró el mes dentro del presupuesto | Mental | `RESISTANCE` (+1d4 salvaciones) | 15 min | Planificar un presupuesto es prepararse para imprevistos, y RESISTANCE es resistir mejor lo inesperado. Al ser una señal mensual y difícil, dura más que la racha. |
| `savings.milestone` (25/50/75 %) | EggSys: el saldo alcanzó un umbral de la meta de ahorro | Afectivo | `BLADE_WARD` (resistencia a daño físico) | 5 min × (hito/25) | El ahorro es un colchón que amortigua golpes. La duración escala con el hito (5/10/15 min) porque cada umbral cuesta más que el anterior. |
| `savings.milestone` (100 %) | EggSys: meta de ahorro cumplida | Afectivo | `HEROISM` (inmune a miedo, HP temp/turno) | 15 min | Cumplir la meta da seguridad y confianza, y la inmunidad a miedo es su lectura mecánica. Es el buff más fuerte del mapeo porque el evento es **único por cuenta y umbral**, así que no se puede farmear. |
| `route.completed.walking` | LSG-Routes: ruta completada caminando | Físico | `LONGSTRIDER` (+3 m movimiento) | 20 min | Caminar en la vida real se traduce en moverse mejor en el juego. Mapeo temático, sin peso en combate. |
| `route.completed.jogging` | LSG-Routes: ruta completada trotando | Físico | `LONGSTRIDER` (+3 m movimiento) | 30 min | Mismo status que caminar, con más duración por la mayor intensidad del esfuerzo. |
| `route.completed.hiking` | LSG-Routes: ruta completada en senderismo | Físico | `BLADE_WARD` (resistencia a daño físico) | 15 min | El senderismo en terreno difícil curte físicamente. Resistencia en vez de ventaja de atributo (BEARS_ENDURANCE queda para el tier de Físico). |
| `route.freeroam` | LSG-Routes: movimiento sin ruta asignada (`route_id: "free_roam"`) | Físico | `LONGSTRIDER` (+3 m movimiento) | 10 min | Actividad real sin la estructura de una ruta completa. Recibe el mismo status que caminar o trotar, pero con la mitad de duración: vale menos que comprometerse con una ruta. |

Cualquier `event_type` no listado se ignora (y se marca como visto): agregar
sensores nuevos al backend no rompe el mod, y para darles efecto basta añadir
una entrada a `Effects.events`.

## Por qué estos status y no otros

Del listado verificado en `EFFECTS.md` (contra `Status_BOOST.txt`) se
descartaron para este mapeo:

- `HASTE`: da una acción extra y rompe el balance de cualquier encuentro.
- `BLESS`, `SHIELD_OF_FAITH`, `BARKSKIN`, `AID`: impacto directo en combate
  (ataque/CA/HP); BLESS y AID además ya se usan en tiers.
- Familia *Enhance Ability* (`BULLS_STRENGTH`, `OWLS_WISDOM`, ...): dan ventaja
  en un atributo y son la recompensa de los tiers de 25 pts; duplicarlos aquí
  abarataría esa meta.
- `DARKVISION`: su utilidad es tan situacional que no se percibiría como
  recompensa.

## Ajustar

Editar `Effects.events` / `Effects.milestone` en `Lua/Effects.lua`
(duraciones en segundos). Probar con `!lsgevents` en la consola SE
(contexto `server`): lista `recent_events.json` y aplica los pendientes.
El dedupe vive en `LSGMod/applied_events.json` (`last_id`); borrarlo hace
que los eventos aún dentro de la ventana de 24 h se vuelvan a aplicar.
