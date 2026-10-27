"""Fixtures compartidas para la suite de pruebas de integración LSGames.

Uso:
    Crear un archivo .env en la carpeta tests/ con:
        TEST_LSG_EMAIL=tu@email.com
        TEST_LSG_PASSWORD=tu_contraseña
        TEST_LSG_BG3_GAME_ID=1

    O bien definir las variables de entorno antes de ejecutar:
        set TEST_LSG_EMAIL=tu@email.com
        pytest tests/
"""

import asyncio
import os
import sys
from pathlib import Path

import pytest

# Asegurar que lsgames-app esté en el path
sys.path.insert(0, str(Path(__file__).parent.parent / "lsgames-app"))

try:
    from dotenv import load_dotenv
    load_dotenv(Path(__file__).parent / ".env")
except ImportError:
    pass


def _get_credentials() -> tuple[str, str]:
    email = os.environ.get("TEST_LSG_EMAIL", "")
    password = os.environ.get("TEST_LSG_PASSWORD", "")
    if not email or not password:
        pytest.skip(
            "Credenciales de prueba no configuradas. "
            "Define TEST_LSG_EMAIL y TEST_LSG_PASSWORD."
        )
    return email, password


@pytest.fixture(scope="session")
def event_loop():
    loop = asyncio.new_event_loop()
    yield loop
    loop.close()


@pytest.fixture(scope="session")
def credentials():
    return _get_credentials()


@pytest.fixture(scope="session")
async def auth_token(credentials):
    from auth.login import login
    email, password = credentials
    token = await login(email, password)
    assert token, "Login no devolvió access_token"
    return token


@pytest.fixture(scope="session")
async def api_client(auth_token):
    from api.client import APIClient
    from auth.login import get_player_info
    info = await get_player_info(auth_token)
    player_id = int(info["id_players"])
    return APIClient(access_token=auth_token, player_id=player_id)
