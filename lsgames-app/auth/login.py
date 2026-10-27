"""Módulo de autenticación JWT contra la API de producción de LifeSyncGames."""

import httpx

from config import AUTH_BASE_URL


async def login(email: str, password: str) -> str:
    """Autentica al usuario con email y contraseña, devuelve el access token JWT.

    El endpoint acepta form-encoded con solo username (email) y password.
    No enviar campos OAuth2 extra (grant_type, scope, client_id, client_secret):
    la API los desconoce y responde 422.

    Args:
        email: Email del jugador registrado en LSG (campo 'username' de la API).
        password: Contraseña del jugador.

    Returns:
        String con el JWT de acceso (access_token).

    Raises:
        httpx.HTTPStatusError: 401 si credenciales incorrectas, 422 si formato inválido.
        httpx.RequestError: Si hay un problema de conexión con la API.
    """
    async with httpx.AsyncClient() as client:
        response = await client.post(
            f"{AUTH_BASE_URL}/login",
            data={
                "username": email,
                "password": password,
            },
            headers={"Content-Type": "application/x-www-form-urlencoded"},
            timeout=15.0,
        )
        response.raise_for_status()
        data = response.json()
        return str(data["access_token"])


async def refresh_token(current_token: str) -> str:
    """Renueva el token JWT usando el token vigente, sin re-ingresar credenciales.

    Útil para mantener sesión activa cuando el token está por vencer.
    Solo funciona si el token aún no ha expirado (ver GET /token/remaining).

    Args:
        current_token: JWT vigente (no expirado).

    Returns:
        Nuevo JWT de acceso.

    Raises:
        httpx.HTTPStatusError: 401 si el token ya expiró (usar login() en ese caso).
    """
    async with httpx.AsyncClient() as client:
        response = await client.post(
            f"{AUTH_BASE_URL}/token/refresh",
            headers={"Authorization": f"Bearer {current_token}"},
            timeout=15.0,
        )
        response.raise_for_status()
        data = response.json()
        return str(data["access_token"])


async def get_player_info(access_token: str) -> dict:
    """Obtiene la información del jugador autenticado desde /whoami.

    Args:
        access_token: JWT de acceso vigente.

    Returns:
        Diccionario con {id_players, name, email, age, roles}.

    Raises:
        httpx.HTTPStatusError: 401 si el token es inválido o expiró.
        httpx.RequestError: Si hay un problema de conexión.
    """
    async with httpx.AsyncClient() as client:
        response = await client.get(
            f"{AUTH_BASE_URL}/whoami",
            headers={"Authorization": f"Bearer {access_token}"},
            timeout=10.0,
        )
        response.raise_for_status()
        return response.json()
