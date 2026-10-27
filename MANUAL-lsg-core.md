# Manual de Usuario - LSG-Core-API
## API Principal LifeSync-Games

**URL del servicio:** https://lsg.diinf.usach.cl/lsg-core-api/docs  
**Versión:** 1.2.4 | **Proyecto:** LifeSync-Games - InTeractiOn Lab, USACH

---

## Antes de empezar - Autenticación obligatoria

**Todos los endpoints requieren un token JWT válido.** Sigue estos pasos antes de usar cualquier endpoint:

```
1. Ve a https://lsg.diinf.usach.cl/lsg-auth/docs
2. Ejecuta POST /login con tu email y contraseña
3. Copia el access_token de la respuesta
4. Vuelve a https://lsg.diinf.usach.cl/lsg-core-api/docs
5. Haz clic en el botón "Authorize" (esquina superior derecha)
6. Escribe: Bearer <el_token_copiado>
7. Haz clic en "Authorize" y luego "Close"
```

El token expira en **120 minutos**. Si ves un error 401, renueva el token repitiendo los pasos.

---

## Tabla de acceso por rol

| Sección | player | teacher | researcher | developer | admin |
|---------|:------:|:-------:|:----------:|:---------:|:-----:|
| Ver mis propios datos | OK | OK | OK | OK | OK |
| Ver datos de otros jugadores | X | OK | OK | OK | OK |
| Crear videojuegos y mecánicas | X | X | OK | OK | OK |
| Ajustar puntos de jugadores | X | X | OK | OK | OK |
| Administración del sistema | X | X | X | X | OK |
| Exportar datos de investigación | X | X | OK | X | OK |
| Calcular y ver IC² propio | OK | OK | OK | OK | OK |
| Ver IC² de otros | X | OK | OK | X | OK |

> **Token y roles:** Si te acaban de asignar un rol nuevo (ej: `developer`), el token actual **no lo incluirá** - los roles se graban en el JWT al momento del login. Renueva con `POST /lsg-auth/token/refresh` o haz un nuevo `POST /login` para que el rol sea efectivo.

---

## 1. Health y Meta

---

### GET /health - Verificar disponibilidad del servicio

**¿Para qué sirve?** Confirmar que la API está en línea. No requiere token.

```bash
curl -X GET 'https://lsg.diinf.usach.cl/lsg-core-api/health'
```
Respuesta: `{"status": "ok"}`

---

### GET /health/full - Estado detallado del sistema

**¿Para qué sirve?** Verificar que la base de datos, las vistas SQL y las tablas de features nuevas (IC², offline) estén disponibles. Útil para diagnóstico.

**Roles:** todos

```bash
curl -X GET 'https://lsg.diinf.usach.cl/lsg-core-api/health/full' \
  -H 'Authorization: Bearer <token>'
```

**Respuesta exitosa:**
```json
{
  "status": "ok",
  "checks": {
    "database": {"status": "ok"},
    "views": [
      {"name": "v_points_balance", "status": "ok"},
      {"name": "v_ic2_latest", "status": "ok"}
    ],
    "feature_tables": [
      {"name": "ic2_result", "status": "ok"},
      {"name": "offline_points_queue", "status": "ok"}
    ]
  }
}
```

Si algún elemento muestra `"status": "error"`, reportar al equipo técnico.

---

### GET /meta/info - Información de la API

**¿Para qué sirve?** Ver la versión actual, entorno y base de datos conectada.

```bash
curl -X GET 'https://lsg.diinf.usach.cl/lsg-core-api/meta/info' \
  -H 'Authorization: Bearer <token>'
```

---

## 2. Jugadores

---

### GET /players - Listar todos los jugadores

**¿Para qué sirve?** Obtener la lista paginada de todos los jugadores registrados, incluyendo sus roles activos.

**Roles:** teacher, researcher, admin

**Parámetros (query):**

| Parámetro | Default | Descripción |
|-----------|---------|-------------|
| `page` | 1 | Número de página |
| `page_size` | 50 | Jugadores por página (máx. 200) |

```bash
curl -X GET 'https://lsg.diinf.usach.cl/lsg-core-api/players?page=1&page_size=20' \
  -H 'Authorization: Bearer <token>'
```

**Respuesta:**
```json
{
  "items": [
    {
      "id_players": 46,
      "name": "Alejandro Aldea",
      "email": "alejandro.aldea@usach.cl",
      "age": 28,
      "created_at": "2026-04-01T10:00:00",
      "roles": ["researcher"]
    }
  ],
  "page": 1,
  "page_size": 20,
  "total": 10
}
```

---

### GET /players/{id} - Ver detalle de un jugador

**¿Para qué sirve?** Obtener toda la información de un jugador específico, incluyendo roles activos.

**Roles:** todos (player solo puede ver su propio perfil)

```bash
# Ver mi propio perfil (cualquier rol)
curl -X GET 'https://lsg.diinf.usach.cl/lsg-core-api/players/46' \
  -H 'Authorization: Bearer <token>'
```

**Respuesta:**
```json
{
  "id_players": 46,
  "name": "Alejandro Aldea",
  "email": "alejandro.aldea@usach.cl",
  "age": 28,
  "created_at": "2026-04-01T10:00:00",
  "updated_at": "2026-05-01T09:00:00",
  "roles": ["researcher", "player"]
}
```

**Error 403:** Si eres `player` e intentas ver el perfil de otro jugador.

---

### GET /players/{id}/games - Videojuegos de un jugador

**¿Para qué sirve?** Ver en qué videojuegos participa un jugador y cuántos puntos ha gastado.

**Roles:** todos (player solo sus propios datos)

```bash
curl -X GET 'https://lsg.diinf.usach.cl/lsg-core-api/players/46/games' \
  -H 'Authorization: Bearer <token>'
```

**Respuesta:**
```json
[
  {
    "id_videogame": 14,
    "videogame_name": "Cities: Skylines",
    "points_spent": 95,
    "seconds_with_lsg": 7200
  }
]
```

---

### GET /players/{id}/timeline - Timeline de eventos del jugador

**¿Para qué sirve?** Ver todos los eventos de un jugador en orden cronológico: sesiones de juego, movimientos de puntos, ingestas de sensores y canjes.

**Roles:** todos (player solo sus propios datos)

**Parámetros (query):**

| Parámetro | Descripción |
|-----------|-------------|
| `from_ts` | Filtrar desde fecha (YYYY-MM-DD HH:MM:SS) |
| `to_ts` | Filtrar hasta fecha (YYYY-MM-DD HH:MM:SS) |
| `limit` | Máximo de eventos (10-1000, default 200) |

```bash
curl -X GET 'https://lsg.diinf.usach.cl/lsg-core-api/players/46/timeline?from_ts=2026-05-01+00:00:00&limit=50' \
  -H 'Authorization: Bearer <token>'
```

---

### POST /players/{id}/attributes/init - Inicializar atributos

**¿Para qué sirve?** Crear los registros iniciales de atributos para un jugador nuevo. Debe ejecutarse una vez al incorporar a un participante.

**Roles:** admin, teacher, researcher

```bash
curl -X POST 'https://lsg.diinf.usach.cl/lsg-core-api/players/54/attributes/init' \
  -H 'Authorization: Bearer <token>'
```

**Respuesta:** `{"status": "initialized", "id_players": 54}`

---

## 3. Atributos y Puntos

---

### GET /attributes - Catálogo de atributos

**¿Para qué sirve?** Ver todos los atributos disponibles en LSG (Físico, Mental, Social, etc.).

**Roles:** todos

```bash
curl -X GET 'https://lsg.diinf.usach.cl/lsg-core-api/attributes' \
  -H 'Authorization: Bearer <token>'
```

---

### GET /attributes/{id}/subattributes - Subatributos de un atributo

**¿Para qué sirve?** Ver los subatributos específicos dentro de un atributo (ej: MVPA, pasos dentro del atributo Físico).

**Roles:** todos

```bash
curl -X GET 'https://lsg.diinf.usach.cl/lsg-core-api/attributes/1/subattributes' \
  -H 'Authorization: Bearer <token>'
```

---

### GET /attributes-map - Mapa completo atributos-subatributos

**¿Para qué sirve?** Ver el árbol completo de atributos y sus subatributos en un solo JSON. Útil para entender la estructura del perfil del jugador.

**Roles:** todos

```bash
curl -X GET 'https://lsg.diinf.usach.cl/lsg-core-api/attributes-map' \
  -H 'Authorization: Bearer <token>'
```

---

### GET /players/{id}/points/balance - Saldo de puntos por dimensión

**¿Para qué sirve?** Ver cuántos puntos tiene el jugador en cada dimensión de puntos del sistema.

**Roles:** todos (player solo sus propios datos)

```bash
curl -X GET 'https://lsg.diinf.usach.cl/lsg-core-api/players/46/points/balance' \
  -H 'Authorization: Bearer <token>'
```

**Respuesta:**
```json
[
  {"id_players": 46, "id_point_dimension": 1, "balance": 131},
  {"id_players": 46, "id_point_dimension": 2, "balance": 114},
  {"id_players": 46, "id_point_dimension": 3, "balance": 89}
]
```

---

### GET /points/ledger - Historial de movimientos de puntos

**¿Para qué sirve?** Ver el historial detallado de todos los créditos y débitos de puntos. Los jugadores solo ven sus propios movimientos; researcher y admin pueden filtrar por cualquier jugador.

**Roles:** todos (`player` filtrado automáticamente a sus propios datos)

**Parámetros (query):**

| Parámetro | Descripción |
|-----------|-------------|
| `player_id` | Filtrar por jugador (researcher/admin) |
| `videogame_id` | Filtrar por videojuego |
| `source_type` | SENSOR, REDEMPTION, ADJUST, OFFLINE_GAME |
| `from_ts` | Desde fecha (YYYY-MM-DD HH:MM:SS) |
| `to_ts` | Hasta fecha (YYYY-MM-DD HH:MM:SS) |

```bash
curl -X GET 'https://lsg.diinf.usach.cl/lsg-core-api/points/ledger?player_id=46&source_type=REDEMPTION' \
  -H 'Authorization: Bearer <token>'
```

---

### POST /players/{id}/points/adjust - Ajuste manual de puntos

**¿Para qué sirve?** Agregar o quitar puntos manualmente a un jugador (ej: corrección de datos, puntos de compensación). Queda registrado con `source_type = ADJUST`.

**Roles:** admin, researcher, developer

**Body JSON:**

| Campo | Tipo | Descripción |
|-------|------|-------------|
| `point_dimension_id` | integer | ID de la dimensión de puntos |
| `direction` | `CREDIT` o `DEBIT` | CREDIT suma, DEBIT resta |
| `amount` | integer | Cantidad de puntos (siempre positivo) |
| `reason` | string | Motivo del ajuste (opcional, recomendado) |
| `videogame_id` | integer | Videojuego asociado (opcional) |

```bash
curl -X POST 'https://lsg.diinf.usach.cl/lsg-core-api/players/46/points/adjust' \
  -H 'Authorization: Bearer <token>' \
  -H 'Content-Type: application/json' \
  -d '{
    "point_dimension_id": 1,
    "direction": "CREDIT",
    "amount": 50,
    "reason": "Corrección por error en sesión del 2026-05-01",
    "videogame_id": 14
  }'
```

**Respuesta:** `{"status": "ok", "source_ref": "ADJUST-uuid..."}`

---

## 4. Videojuegos y Sesiones

---

### GET /videogames - Catálogo de videojuegos

**Roles:** todos

```bash
curl -X GET 'https://lsg.diinf.usach.cl/lsg-core-api/videogames' \
  -H 'Authorization: Bearer <token>'
```

**Respuesta:**
```json
[
  {"id_videogame": 8, "name": "Terraria", "genre": "sandbox", "engine": "own", "type": "game"},
  {"id_videogame": 14, "name": "Cities: Skylines", "genre": "simulation", "engine": "Unity", "type": "game"}
]
```

---

### GET /videogames/{id}/mechanics - Mecánicas modificables de un juego

**¿Para qué sirve?** Ver qué mecánicas del juego pueden ser modificadas según el IC² del jugador (stamina, velocidad, drop-rate, etc.). El campo `options` contiene los parámetros de cada mecánica.

**Roles:** todos

```bash
curl -X GET 'https://lsg.diinf.usach.cl/lsg-core-api/videogames/8/mechanics' \
  -H 'Authorization: Bearer <token>'
```

**Respuesta:**
```json
[
  {
    "id_modifiable_mechanic_videogame": 2,
    "id_videogame": 8,
    "options": {"max_level": 5, "cost_per_level": 100},
    "mechanic_name": "Faster Peasants",
    "mechanic_description": "Aumenta velocidad de los campesinos",
    "mechanic_type": "nerf"
  }
]
```

---

### POST /videogames/{id}/players/{pid}/connect - Conectar jugador al videojuego

**¿Para qué sirve?** Registrar que un jugador está usando el mod LSG en un videojuego. Debe llamarse cuando el jugador inicia el juego con el mod activo.

**Roles:** todos (player solo para sí mismo)

```bash
curl -X POST 'https://lsg.diinf.usach.cl/lsg-core-api/videogames/14/players/46/connect' \
  -H 'Authorization: Bearer <token>' \
  -H 'Content-Type: application/json' \
  -d '{
    "lsg_enabled": true,
    "plugin_version": "1.2.0"
  }'
```

---

### POST /videogames/{id}/players/{pid}/sessions - Iniciar sesión de juego

**¿Para qué sirve?** Registrar el inicio de una sesión de juego. Llama a este endpoint cuando el jugador abre el juego con el mod LSG activo.

**Roles:** todos (player solo para sí mismo)

```bash
curl -X POST 'https://lsg.diinf.usach.cl/lsg-core-api/videogames/14/players/46/sessions' \
  -H 'Authorization: Bearer <token>' \
  -H 'Content-Type: application/json' \
  -d '{
    "plugin_version": "1.2.0",
    "session_metrics": {"map": "tutorial_01"}
  }'
```

**Respuesta:** `{"status": "started", "id_session": 23}`  
Guarda el `id_session` para cerrar la sesión después.

---

### PATCH /videogames/{id}/players/{pid}/sessions/{sid}/end - Cerrar sesión de juego

**¿Para qué sirve?** Registrar el cierre de una sesión. El sistema calcula automáticamente la duración (`duration_seconds`). También registra el evento en `interaction_logs` para trazabilidad.

**Roles:** todos (player solo para sí mismo)

```bash
curl -X PATCH 'https://lsg.diinf.usach.cl/lsg-core-api/videogames/14/players/46/sessions/23/end' \
  -H 'Authorization: Bearer <token>' \
  -H 'Content-Type: application/json' \
  -d '{}'
```

**Respuesta:** `{"status": "ended", "id_session": 23}`

**Nota:** Si no tienes la hora exacta de cierre, envía el body vacío `{}` y el servidor usará la hora actual.

---

### POST /videogames/{id}/players/{pid}/redeem/preview - Vista previa del canje

**¿Para qué sirve?** Verificar si el jugador tiene suficientes puntos para un canje, sin realizarlo. Ideal para mostrar al jugador qué puede canjear antes de confirmar.

**Roles:** todos (player solo para sí mismo)

**Body JSON:**

| Campo | Descripción |
|-------|-------------|
| `modifiable_mechanic_videogame_id` | ID de la mecánica a canjear (de `GET /videogames/{id}/mechanics`) |
| `point_dimension_id` | Dimensión de puntos a usar |
| `amount` | Puntos a gastar |

```bash
curl -X POST 'https://lsg.diinf.usach.cl/lsg-core-api/videogames/14/players/46/redeem/preview' \
  -H 'Authorization: Bearer <token>' \
  -H 'Content-Type: application/json' \
  -d '{
    "modifiable_mechanic_videogame_id": 5,
    "point_dimension_id": 2,
    "amount": 17
  }'
```

**Respuesta:**
```json
{
  "can_redeem": true,
  "current_balance": 131,
  "required_amount": 17,
  "resulting_balance": 114
}
```

---

### POST /videogames/{id}/players/{pid}/redeem - Realizar canje

**¿Para qué sirve?** Efectuar el canje de puntos por una mecánica del juego. Si el jugador tiene saldo suficiente, se descuentan los puntos y se activa la mecánica. Se registra en `interaction_logs` para trazabilidad.

**Roles:** todos (player solo para sí mismo)

```bash
curl -X POST 'https://lsg.diinf.usach.cl/lsg-core-api/videogames/14/players/46/redeem' \
  -H 'Authorization: Bearer <token>' \
  -H 'Content-Type: application/json' \
  -d '{
    "modifiable_mechanic_videogame_id": 5,
    "point_dimension_id": 2,
    "amount": 17,
    "metadata": {"session_id": 23}
  }'
```

**Respuesta exitosa (200):**
```json
{
  "status": "redeemed",
  "points_ledger_id": 83,
  "source_ref": "REDEMPTION-d561ed81-...",
  "current_balance": 131,
  "redeemed_amount": 17,
  "resulting_balance": 114,
  "game_id": 14,
  "player_id": 46,
  "point_dimension_id": 2,
  "modifiable_mechanic_videogame_id": 5
}
```

**Error 400 - saldo insuficiente:**
```json
{
  "code": "INSUFFICIENT_POINTS",
  "current_balance": 5,
  "required_amount": 17
}
```

---

## 5. Sensores

Los sensores son fuentes externas de datos físicos del participante (smartbands, aplicaciones de salud, etc.). El flujo para integrar un sensor por primera vez es:

```
Paso 1: GET /sensors → obtener id_online_sensor
Paso 2: POST /sensors/players/{id}/link → vincular sensor al jugador
Paso 3: GET /sensors/{id}/endpoints → obtener id_sensor_endpoint
Paso 4: POST /sensors/players/{id}/link-endpoint → activar (obtiene id_players_sensor_endpoint)
Paso 5: POST /sensors/ingest/webhook → ingestar datos usando los IDs obtenidos
```

---

### GET /sensors - Catálogo de sensores disponibles

**Roles:** todos

```bash
curl -X GET 'https://lsg.diinf.usach.cl/lsg-core-api/sensors' \
  -H 'Authorization: Bearer <token>'
```

---

### GET /sensors/{id}/endpoints - Endpoints de un sensor

**¿Para qué sirve?** Ver los endpoints de ingestión de un sensor. El `id_sensor_endpoint` obtenido aquí se necesita para el webhook.

**Roles:** todos

```bash
curl -X GET 'https://lsg.diinf.usach.cl/lsg-core-api/sensors/1/endpoints' \
  -H 'Authorization: Bearer <token>'
```

---

### GET /sensors/players/{id} - Sensores activos de un jugador

**¿Para qué sirve?** Ver qué sensores tiene configurado un jugador, con los IDs necesarios para ingestar datos.

**Roles:** todos (player solo sus propios datos)

```bash
curl -X GET 'https://lsg.diinf.usach.cl/lsg-core-api/sensors/players/46' \
  -H 'Authorization: Bearer <token>'
```

**Campos importantes en la respuesta:**
- `id_players_sensor_endpoint`: usar en `POST /sensors/ingest/webhook`
- `id_sensor_endpoint`: ID del endpoint del sensor
- `activated`: si el endpoint está activo

---

### POST /sensors/players/{id}/link - Vincular sensor a jugador

**Roles:** admin, researcher

```bash
curl -X POST 'https://lsg.diinf.usach.cl/lsg-core-api/sensors/players/46/link' \
  -H 'Authorization: Bearer <token>' \
  -H 'Content-Type: application/json' \
  -d '{"sensor_id": 1, "tokens": {"api_key": "abc123"}}'
```

---

### POST /sensors/players/{id}/link-endpoint - Activar endpoint para jugador

**¿Para qué sirve?** Activar un endpoint de sensor específico para un jugador. Genera el `id_players_sensor_endpoint` necesario para el webhook.

**Roles:** admin, researcher

> **`schedule_time`**: entero en formato HHMM (hora × 100 + minutos).  
> Ejemplos: `800` = 08:00 | `1430` = 14:30 | `null` = sin horario fijo (default).  
> Enviar `null` si no necesitas programar una hora de ingesta.

```bash
curl -X POST 'https://lsg.diinf.usach.cl/lsg-core-api/sensors/players/46/link-endpoint' \
  -H 'Authorization: Bearer <token>' \
  -H 'Content-Type: application/json' \
  -d '{
    "sensor_endpoint_id": 3,
    "activated": true,
    "schedule_time": 800
  }'
```

**Respuesta:**
```json
{
  "status": "linked",
  "id_players_sensor_endpoint": 12,
  "player_id": 46,
  "sensor_endpoint_id": 3,
  "activated": true
}
```

---

### POST /sensors/ingest/webhook - Ingestar evento de sensor

**¿Para qué sirve?** Registrar un dato capturado por un sensor (pasos, frecuencia cardíaca, calidad del sueño, etc.).

**Roles:** todos (`player` solo para su propio `player_id`)

**¿Dónde obtengo los IDs?**
- `sensor_endpoint_id`: de `GET /sensors/{id}/endpoints` → campo `id_sensor_endpoint`
- `players_sensor_endpoint_id`: de `POST /sensors/players/{id}/link-endpoint` → campo `id_players_sensor_endpoint`, o de `GET /sensors/players/{id}` → campo `id_players_sensor_endpoint`

```bash
curl -X POST 'https://lsg.diinf.usach.cl/lsg-core-api/sensors/ingest/webhook' \
  -H 'Authorization: Bearer <token>' \
  -H 'Content-Type: application/json' \
  -d '{
    "player_id": 46,
    "sensor_endpoint_id": 3,
    "players_sensor_endpoint_id": 12,
    "raw_payload": {
      "steps": 8500,
      "date": "2026-05-07"
    },
    "parsed_value": 8500.0,
    "status": "OK",
    "occurred_at": "2026-05-07T23:59:00"
  }'
```

**Respuesta:** `{"status": "ok", "id_sensor_ingest_event": 78}`

---

## 6. IC² LSG - Índice Compuesto Físico-Mental

El IC² LSG es el núcleo científico del sistema. Convierte señales reales del participante (actividad física, calidad del sueño, rendimiento cognitivo) en un índice numérico [0,1] que determina las mecánicas activas en el videojuego.

**Versión de goalposts activa:** `v1.0`

---

### GET /ic2/goalposts - Ver los parámetros de normalización vigentes

**¿Para qué sirve?** Consultar qué rangos y estrategias de normalización se aplican a cada señal. Transparencia total para los participantes.

**Roles:** todos

```bash
curl -X GET 'https://lsg.diinf.usach.cl/lsg-core-api/ic2/goalposts?version_tag=v1.0' \
  -H 'Authorization: Bearer <token>'
```

---

### POST /ic2/compute - Calcular el IC² de un jugador

**¿Para qué sirve?** Enviar las señales medidas de un participante y recibir su Índice Compuesto Físico-Mental. El resultado se almacena automáticamente y se registra en `interaction_logs`.

**Roles:** todos (`player` solo para su propio `player_id`)

**Señales que se pueden enviar (todas opcionales):**

| Señal | Unidad | Rango normal | Estrategia |
|-------|--------|--------------|-----------|
| `MVPA_min_week` | min/semana | 0-300 | Logarítmica |
| `steps_day` | pasos/día | 0-12.000 | Logarítmica |
| `resting_hr_bpm` | lpm | 40-100 | Sigmoidal |
| `sleep_quality_score` | puntuación | 0-10 | Ordinal |
| `memory_accuracy_pct` | % | 0-100 | Min-max |
| `recall_speed_ms` | ms | 200-1.800 | Min-max |
| `decision_accuracy_pct` | % | 0-100 | Min-max |
| `reaction_time_ms` | ms | 150-1.000 | Min-max |

Si una señal está ausente, su subdimensión se marca como `NA` y no participa en la agregación.

```bash
curl -X POST 'https://lsg.diinf.usach.cl/lsg-core-api/ic2/compute' \
  -H 'Authorization: Bearer <token>' \
  -H 'Content-Type: application/json' \
  -d '{
    "player_id": 46,
    "version_tag": "v1.0",
    "experiment_tag": "LSG_C1_T1_CV",
    "session_time_minutes": 45,
    "signals": {
      "MVPA_min_week": 180,
      "steps_day": 7500,
      "resting_hr_bpm": 65,
      "sleep_quality_score": 7,
      "memory_accuracy_pct": 82,
      "recall_speed_ms": 650,
      "decision_accuracy_pct": 78,
      "reaction_time_ms": 420
    }
  }'
```

**Respuesta exitosa (200):**
```json
{
  "player_id": 46,
  "version_tag": "v1.0",
  "window": {"start": "2026-05-01", "end": "2026-05-07"},
  "indices": {
    "Icf": 0.7234,
    "Isfg": 0.6891,
    "Ipma": 0.7912,
    "Itd": 0.8103,
    "IC_fis": 0.7055,
    "IC_ment": 0.8006,
    "IC_LSG": 0.7521,
    "IAR": 0.6812
  },
  "rules_triggered": ["R1", "R2", "R3"],
  "admissibility": {
    "Icf": true, "Isfg": true, "Ipma": true, "Itd": true
  },
  "id_ic2_result": 5
}
```

**Interpretación de índices:**

| Índice | Descripción |
|--------|-------------|
| `Icf` | Condición física (MVPA + pasos) |
| `Isfg` | Salud física general (FC reposo + sueño) |
| `Ipma` | Procesos de memoria y aprendizaje |
| `Itd` | Toma de decisiones |
| `IC_fis` | Índice físico compuesto = √(Icf × Isfg) |
| `IC_ment` | Índice mental compuesto = √(Ipma × Itd) |
| `IC_LSG` | Índice global = ⁴√(Icf × Isfg × Ipma × Itd) |
| `IAR` | Índice de autorregulación (incluye tiempo de sesión) |

**Reglas activadas:**

| Regla | Condición | Efecto en el juego |
|-------|-----------|-------------------|
| R1 | IC_fis ≥ 0.60 | +10% stamina, +5% velocidad de regeneración (48 hrs) |
| R2 | IC_ment ≥ 0.55 | -15% cooldown de habilidades (24 hrs) |
| R3 | IC_LSG ≥ 0.60 + R1 + R2 | +5% drop-rate + quest especial (72 hrs) |
| R4 | IC_fis < 0.40 | Misión de recuperación (pausa activa) |
| R5 | IC_ment < 0.35 | Test cognitivo sugerido al inicio |
| R6 | IC_fis ≥ 0.70 y IC_ment ≥ 0.65 | Desbloqueo región/evento especial (96 hrs) |

---

### GET /ic2/history - Historial de resultados IC²

**¿Para qué sirve?** Ver la evolución histórica del IC² de un jugador a lo largo del tiempo.

**Roles:** todos (`player` solo sus propios datos; `teacher/researcher/admin` pueden ver de cualquiera)

**Parámetros:**

| Parámetro | Descripción |
|-----------|-------------|
| `player_id` | ID del jugador (requerido) |
| `experiment_tag` | Filtrar por cohorte/período (ej: `LSG_C1_T1_CV`) |
| `from_date` | Desde fecha (YYYY-MM-DD) |
| `to_date` | Hasta fecha (YYYY-MM-DD) |
| `limit` | Máx. resultados (1-500, default 50) |

```bash
curl -X GET 'https://lsg.diinf.usach.cl/lsg-core-api/ic2/history?player_id=46&experiment_tag=LSG_C1_T1_CV' \
  -H 'Authorization: Bearer <token>'
```

---

## 7. Puntos Offline (Starbound / Baldur's Gate 3)

Para videojuegos que no tienen conexión permanente con el servidor, el sistema permite registrar eventos de puntos offline y sincronizarlos cuando hay conexión.

**¿Cómo funciona?**
1. El mod del juego genera eventos de puntos y los almacena localmente con un UUID único (`client_ref`).
2. Cuando hay conexión, envía el lote al servidor.
3. El servidor valida cada evento (ventana de 30 días, saldo suficiente, idempotencia).
4. El resultado es HTTP 207 (multi-status): cada evento puede ser SYNCED, REJECTED o DUPLICATE.

---

### POST /offline/sync - Sincronizar lote de puntos offline

**Roles:** todos (`player` solo para sí mismo)

```bash
curl -X POST 'https://lsg.diinf.usach.cl/lsg-core-api/offline/sync' \
  -H 'Authorization: Bearer <token>' \
  -H 'Content-Type: application/json' \
  -d '{
    "player_id": 46,
    "game_id": 14,
    "events": [
      {
        "client_ref": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
        "client_generated_at": "2026-05-06T22:15:00+00:00",
        "point_dimension_id": 1,
        "direction": "CREDIT",
        "amount": 45,
        "source_type": "OFFLINE_GAME",
        "payload": {"trigger": "quest_completed", "quest_id": "boss_cave"}
      }
    ]
  }'
```

**Respuesta (207):**
```json
{
  "total": 1,
  "synced": 1,
  "rejected": 0,
  "duplicate": 0,
  "results": [
    {
      "client_ref": "a1b2c3d4-...",
      "status": "SYNCED",
      "id_points_ledger": 92
    }
  ]
}
```

**Estados posibles:**

| Estado | Causa |
|--------|-------|
| `SYNCED` | Evento aceptado y guardado en el ledger |
| `REJECTED` | Fuera de ventana, saldo insuficiente, o error |
| `DUPLICATE` | `client_ref` ya existe (evento enviado antes) |

**Errores comunes:**
- `client_generated_at` anterior a 30 días → REJECTED
- `direction: DEBIT` con saldo insuficiente → REJECTED
- Mismo `client_ref` enviado dos veces → DUPLICATE (no es error, es idempotencia)

---

### GET /offline/queue - Ver cola offline de un jugador

**Roles:** todos (`player` solo sus propios datos; `researcher/admin` pueden ver cualquiera)

```bash
curl -X GET 'https://lsg.diinf.usach.cl/lsg-core-api/offline/queue?player_id=46&status=REJECTED' \
  -H 'Authorization: Bearer <token>'
```

---

## 8. Analytics (Investigación)

Estos endpoints son para researcher y admin. Proveen vistas agregadas para análisis longitudinal.

---

### GET /analytics/ic2/summary - Resumen estadístico IC² por condición

**¿Para qué sirve?** Ver la media, desviación estándar, mínimo y máximo del IC² agrupado por `experiment_tag`. Compatible con el análisis Q01.

**Roles:** admin, researcher

```bash
curl -X GET 'https://lsg.diinf.usach.cl/lsg-core-api/analytics/ic2/summary?experiment_tag=LSG_C1_T1_CV' \
  -H 'Authorization: Bearer <token>'
```

**Respuesta:**
```json
{
  "items": [
    {
      "experiment_tag": "LSG_C1_T1_CV",
      "condicion": "CV",
      "n_participantes": 8,
      "n_calculos": 24,
      "IC_fis_media": 0.6823,
      "IC_fis_sd": 0.0921,
      "IC_LSG_media": 0.7105,
      "IC_LSG_sd": 0.0834,
      "IAR_media": 0.6412,
      "IAR_sd": 0.0756,
      "primer_registro": "2026-04-15",
      "ultimo_registro": "2026-05-07"
    }
  ],
  "count": 1
}
```

---

## 9. Exportación de datos de investigación

Todos los endpoints de exportación:
- Seudonimizán la identidad con código `LSG-PXXX` (estable por participante).
- Soportan formato JSON y CSV.
- Solo accesibles para admin y researcher.

---

### GET /research/export/points - Exportar movimientos de puntos

```bash
# Exportar como CSV
curl -X GET \
  'https://lsg.diinf.usach.cl/lsg-core-api/research/export/points?experiment_tag=LSG_C1_T1_CV&format=csv' \
  -H 'Authorization: Bearer <token>' \
  --output puntos_export.csv
```

**Parámetros:**

| Parámetro | Descripción |
|-----------|-------------|
| `from_ts` / `to_ts` | Ventana temporal |
| `player_id` | Filtrar por participante |
| `videogame_id` | Filtrar por juego |
| `source_type` | SENSOR, REDEMPTION, ADJUST, OFFLINE_GAME |
| `format` | `json` o `csv` |
| `include_raw_ids` | `false` (default): elimina email/nombre. `true`: incluye datos reales |
| `limit` | Máx. filas (hasta 100.000) |

---

### GET /research/export/sessions - Exportar sesiones de juego

```bash
curl -X GET \
  'https://lsg.diinf.usach.cl/lsg-core-api/research/export/sessions?format=csv' \
  -H 'Authorization: Bearer <token>' \
  --output sesiones_export.csv
```

---

### GET /research/export/sensors - Exportar eventos de sensor

```bash
curl -X GET \
  'https://lsg.diinf.usach.cl/lsg-core-api/research/export/sensors?format=csv' \
  -H 'Authorization: Bearer <token>' \
  --output sensores_export.csv
```

---

### GET /research/export/ic2 - Exportar resultados IC²

**¿Para qué sirve?** Exportar todos los resultados IC² calculados, incluyendo señales crudas y admisibilidad. Diseñado para análisis estadístico en R o Python.

```bash
# Exportar condición CV a CSV
curl -X GET \
  'https://lsg.diinf.usach.cl/lsg-core-api/research/export/ic2?experiment_tag=LSG_C1_T1_CV&format=csv' \
  -H 'Authorization: Bearer <token>' \
  --output ic2_condicion_CV.csv

# Exportar todo el estudio en JSON
curl -X GET \
  'https://lsg.diinf.usach.cl/lsg-core-api/research/export/ic2' \
  -H 'Authorization: Bearer <token>'
```

**Parámetros:**

| Parámetro | Descripción |
|-----------|-------------|
| `experiment_tag` | Filtrar por cohorte/período/condición |
| `from_date` / `to_date` | Ventana temporal (YYYY-MM-DD) |
| `player_id` | Filtrar por participante específico |
| `version_tag` | Versión de goalposts (default: todos) |
| `format` | `json` o `csv` |
| `include_raw_ids` | `false` (default): seudonimizado |

---

## 11. Rol developer - Guía de integración de mods

El rol `developer` está diseñado para quienes integran el mod LSG en un videojuego. Tiene acceso a las operaciones necesarias para el ciclo completo de pruebas.

### Endpoints disponibles para developer

| Grupo | Endpoint | Descripción |
|-------|----------|-------------|
| Videojuegos | `POST /videogames` | Registrar el videojuego en el sistema |
| Mecánicas | `POST /videogames/{id}/mechanics/bulk` | Cargar hasta 500 mecánicas en lote |
| Mecánicas | `POST /videogames/mechanics/catalog` | Crear mecánica individual |
| Mecánicas | `POST /videogames/{id}/mechanics` | Vincular mecánica al juego |
| Sesiones | `POST /videogames/{id}/players/{pid}/sessions` | Iniciar sesión de juego |
| Sesiones | `PATCH .../sessions/{sid}/end` | Cerrar sesión |
| Canjes | `POST .../redeem/preview` | Preview de canje |
| Canjes | `POST .../redeem` | Confirmar canje |
| Puntos | `POST /players/{id}/points/adjust` | Cargar/ajustar puntos directamente |
| IC² | `POST /ic2/compute` | Calcular IC² para pruebas |
| Offline | `POST /offline/sync` | Sincronizar puntos generados offline |

### Flujo típico de integración

```
1. POST /videogames            → crear juego, guardar id_videogame
2. POST /videogames/{id}/mechanics/bulk  → cargar mecánicas del mod
3. POST /videogames/{id}/players/{pid}/connect  → vincular jugador de prueba
4. POST /videogames/{id}/players/{pid}/sessions → abrir sesión
   ... el jugador interactúa con el mod ...
   POST /players/{pid}/points/adjust     → cargar puntos del evento
   POST /videogames/{id}/players/{pid}/redeem → canjear mecánica
5. PATCH .../sessions/{sid}/end          → cerrar sesión
6. GET /players/{pid}/points/balance     → verificar saldo resultante
```

### ⚠️ Importante: token actualizado

Si el admin te acaba de asignar el rol `developer`, tu token anterior **no incluye ese rol** y recibirás un error 403. Solución:

```bash
# Opción 1: renovar sin re-login (recomendado)
curl -X POST 'https://lsg.diinf.usach.cl/lsg-auth/token/refresh' \
  -H 'Authorization: Bearer <token_antiguo>'

# Opción 2: hacer login nuevamente
curl -X POST 'https://lsg.diinf.usach.cl/lsg-auth/login' \
  -d 'username=tu@email.cl&password=tu_contraseña'
```

Usa el nuevo `access_token` en Swagger: botón **Authorize** → `Bearer <nuevo_token>`.


---

## 10. Errores frecuentes

| Código | Significado | Solución |
|--------|-------------|----------|
| 401 Unauthorized | Token ausente o expirado | Hacer nuevo `POST /login` en lsg-auth |
| 403 Forbidden | Rol insuficiente para esta operación | Verificar que tu rol tiene acceso |
| 404 Not Found | El recurso no existe | Verificar el ID en la URL |
| 400 Bad Request | Datos de entrada incorrectos | Revisar el body JSON según el manual |
| 207 Multi-Status | Respuesta parcial (offline sync) | Revisar el campo `results` por ítem |
| 503 Service Unavailable | BD no disponible | Reportar al equipo técnico |

---

## 11. Códigos de seudonimización (LSG-PXXX)

En todas las exportaciones de investigación, la identidad de los participantes se reemplaza por un código estable del tipo `LSG-P001`, `LSG-P002`, etc. Este código:
- Es único por participante.
- Se mantiene igual en todas las exportaciones.
- No se puede revertir al nombre/email real en los archivos de exportación.

Para saber qué `LSG-PXXX` corresponde a cada participante, solo el administrador del sistema tiene acceso a la tabla de correspondencia (`research_pseudonym` en la base de datos).