"""Cliente HTTP para la API de producción de LifeSyncGames."""

import httpx

from api.models import Dimension, UserProfile
from auth.login import get_player_info
from config import AUTH_BASE_URL, CORE_BASE_URL, BG3_GAME_ID


class APIClient:
    """Cliente HTTP autenticado para la API de producción LSG.

    Attributes:
        access_token: JWT de acceso vigente.
        player_id: ID del jugador autenticado (id_players).
    """

    def __init__(self, access_token: str, player_id: int) -> None:
        self.access_token = access_token
        self.player_id = player_id

    def _auth_headers(self) -> dict:
        return {"Authorization": f"Bearer {self.access_token}"}

    async def _get(self, url: str) -> object:
        async with httpx.AsyncClient() as client:
            response = await client.get(url, headers=self._auth_headers(), timeout=15.0)
            response.raise_for_status()
            return response.json()

    async def _post(self, url: str, body: dict) -> dict:
        async with httpx.AsyncClient() as client:
            response = await client.post(
                url, json=body, headers=self._auth_headers(), timeout=15.0
            )
            response.raise_for_status()
            return response.json()

    async def _patch(self, url: str, body: dict) -> dict:
        async with httpx.AsyncClient() as client:
            response = await client.patch(
                url, json=body, headers=self._auth_headers(), timeout=15.0
            )
            response.raise_for_status()
            return response.json()

    # ------------------------------------------------------------------
    # Perfil y dimensiones
    # ------------------------------------------------------------------

    async def get_user_profile(self) -> UserProfile:
        """Obtiene el perfil del jugador con su balance multidimensional."""
        info = await get_player_info(self.access_token)
        name = str(info.get("name") or "")
        email = str(info.get("email") or "")
        dimensions = await self.get_point_balance()
        return UserProfile(
            player_id=self.player_id,
            name=name,
            email=email,
            dimensions=dimensions,
        )

    async def get_point_balance(self) -> list[Dimension]:
        """Consulta el balance de atributos del jugador.

        Usa /players/{id}/attributes/points que devuelve los 5 atributos
        (Social, Fisico, Afectivo, Mental, Linguistico) con su balance_ledger.

        Returns:
            Lista de Dimension con id_attributes, nombre normalizado y balance.
        """
        data = await self._get(
            f"{CORE_BASE_URL}/players/{self.player_id}/attributes/points"
        )
        return _parse_attribute_points(data)

    async def get_ingest_events(self) -> list[dict]:
        """Obtiene los eventos de sensores ingeridos del jugador.

        Usa /sensors/players/{id}/ingest-events, que devuelve los eventos
        registrados por los sensores online (EggSys, LSG-Routes, ...) con
        raw_payload {event_type, payload, awarded_points, ...} y occurred_at.

        Returns:
            Lista de eventos en formato raw de la API.
        """
        data = await self._get(
            f"{CORE_BASE_URL}/sensors/players/{self.player_id}/ingest-events"
        )
        if isinstance(data, list):
            return data
        if isinstance(data, dict):
            return data.get("events") or data.get("items") or []
        return []

    # ------------------------------------------------------------------
    # Mecánicas / catálogo
    # ------------------------------------------------------------------

    async def get_mechanics(self) -> list[dict]:
        """Obtiene las mecánicas del videojuego BG3 (configurado en BG3_GAME_ID).

        Returns:
            Lista de mecánicas en formato raw de la API, o lista vacía si el
            juego no tiene mecánicas configuradas.
        """
        data = await self._get(
            f"{CORE_BASE_URL}/videogames/{BG3_GAME_ID}/mechanics"
        )
        if isinstance(data, list):
            return data
        if isinstance(data, dict):
            return data.get("mechanics") or data.get("items") or []
        return []

    # ------------------------------------------------------------------
    # Conexión al videojuego
    # ------------------------------------------------------------------

    async def connect_player(self, plugin_version: str = "1.0.0") -> dict:
        """Registra que el jugador está usando el mod LSG en BG3.

        Debe llamarse al iniciar el juego con el mod activo.
        """
        return await self._post(
            f"{CORE_BASE_URL}/videogames/{BG3_GAME_ID}/players/{self.player_id}/connect",
            {"lsg_enabled": True, "plugin_version": plugin_version},
        )

    # ------------------------------------------------------------------
    # Sesiones de juego
    # ------------------------------------------------------------------

    async def start_game_session(self) -> dict:
        """Abre una sesión de juego. Retorna el objeto de sesión con su id."""
        return await self._post(
            f"{CORE_BASE_URL}/videogames/{BG3_GAME_ID}/players/{self.player_id}/sessions",
            {},
        )

    async def end_game_session(self, session_id: int) -> dict:
        """Cierra la sesión de juego indicada."""
        return await self._patch(
            f"{CORE_BASE_URL}/videogames/{BG3_GAME_ID}/players/{self.player_id}/sessions/{session_id}/end",
            {},
        )

    # ------------------------------------------------------------------
    # Canje (redeem)
    # ------------------------------------------------------------------

    async def preview_redeem(
        self, mmvg_id: int, dimension_id: int, amount: int
    ) -> dict:
        """Previsualiza un canje sin ejecutarlo (verificación de saldo)."""
        return await self._post(
            f"{CORE_BASE_URL}/videogames/{BG3_GAME_ID}/players/{self.player_id}/redeem/preview",
            {
                "modifiable_mechanic_videogame_id": mmvg_id,
                "point_dimension_id": dimension_id,
                "amount": amount,
            },
        )

    async def sync_offline_events(
        self, player_id: int, game_id: int | None, events: list[dict]
    ) -> dict:
        """Sincroniza un lote de eventos offline vía POST /offline/sync.

        El servidor valida cada evento (ventana 30 días, saldo suficiente,
        idempotencia por client_ref) y devuelve HTTP 207 con el estado
        individual: SYNCED, REJECTED o DUPLICATE.

        Args:
            player_id: ID del jugador (id_players).
            game_id:   ID del videojuego registrado en LSG; puede ser None.
            events:    Lista de eventos con campos de la API offline.

        Returns:
            Respuesta 207 con {total, synced, rejected, duplicate, results}.
        """
        body: dict = {
            "player_id": player_id,
            "game_id":   game_id,
            "events":    events,
        }
        async with httpx.AsyncClient() as client:
            response = await client.post(
                f"{CORE_BASE_URL}/offline/sync",
                json=body,
                headers=self._auth_headers(),
                timeout=30.0,
            )
            # 207 Multi-Status es respuesta válida; raise_for_status solo lanza en 4xx/5xx
            response.raise_for_status()
            return response.json()

    async def redeem_mechanic(
        self, mmvg_id: int, dimension_id: int, amount: int, metadata: dict | None = None
    ) -> dict:
        """Ejecuta el canje de una mecánica descontando puntos de la dimensión indicada.

        Args:
            mmvg_id: modifiable_mechanic_videogame_id de la mecánica.
            dimension_id: id_point_dimension de la dimensión a descontar.
            amount: Cantidad de veces a canjear.
            metadata: Datos adicionales opcionales.

        Raises:
            httpx.HTTPStatusError 400/422: Saldo insuficiente u otro error de negocio.
            httpx.HTTPStatusError 401: Token expirado.
        """
        body: dict = {
            "modifiable_mechanic_videogame_id": mmvg_id,
            "point_dimension_id": dimension_id,
            "amount": amount,
        }
        if metadata:
            body["metadata"] = metadata

        return await self._post(
            f"{CORE_BASE_URL}/videogames/{BG3_GAME_ID}/players/{self.player_id}/redeem",
            body,
        )


# ------------------------------------------------------------------
# Parseo de /players/{id}/attributes/points
# ------------------------------------------------------------------

def _parse_attribute_points(data: object) -> list[Dimension]:
    """Convierte la respuesta de /attributes/points en lista de Dimension.

    Formato esperado:
        [{id_attributes, attribute_name, balance_ledger, ...}, ...]

    El campo id_attributes coincide con id_point_dimension para los 5
    atributos (Social=1, Fisico=2, Afectivo=3, Mental=4, Linguistico=5).
    """
    if not isinstance(data, list):
        return []

    dimensions: list[Dimension] = []
    for item in data:
        if not isinstance(item, dict):
            continue
        dim_id = int(item.get("id_attributes") or 0)
        dim_name = _normalize_name(str(item.get("attribute_name") or f"dim_{dim_id}"))
        # balance_ledger es el saldo acumulado real
        dim_balance = int(item.get("balance_ledger") or item.get("snapshot_points") or 0)
        if dim_id:
            dimensions.append(Dimension(id=dim_id, name=dim_name, balance=dim_balance))

    # Ordenar por id para presentación consistente
    dimensions.sort(key=lambda d: d.id)
    return dimensions


def _normalize_name(name: str) -> str:
    """Normaliza el nombre de un atributo para uso como clave JSON (lowercase, sin tildes)."""
    replacements = {
        "á": "a", "é": "e", "í": "i", "ó": "o", "ú": "u",
        "Á": "a", "É": "e", "Í": "i", "Ó": "o", "Ú": "u",
        "ñ": "n", "Ñ": "n", " ": "_",
    }
    result = name.lower()
    for src, dst in replacements.items():
        result = result.replace(src, dst)
    return result
