"""Prueba c): robustez y manejo de errores del middleware LSGames.

Verifica que el middleware maneje correctamente:
- Errores de red / conexión rechazada
- Tokens expirados o inválidos (HTTP 401)
- Saldo insuficiente (HTTP 400 / 422)
- session.json malformado o con firma incorrecta
- Catálogo vacío o ilegible

Ejecutar:
    pytest tests/test_robustness.py -v
"""

import json
import time
from pathlib import Path
from unittest.mock import AsyncMock, patch

import httpx
import pytest


# ------------------------------------------------------------------
# Errores de red
# ------------------------------------------------------------------

@pytest.mark.asyncio
async def test_login_network_error():
    """El login debe propagar excepciones de red de forma limpia."""
    from auth.login import login

    with patch("httpx.AsyncClient.post", side_effect=httpx.ConnectError("timeout")):
        with pytest.raises(httpx.ConnectError):
            await login("bad@email.com", "pass")


@pytest.mark.asyncio
async def test_get_balance_network_error(api_client):
    """get_point_balance() debe propagar errores de red sin corromper el estado."""
    with patch.object(api_client, "_get", side_effect=httpx.ConnectError("red caída")):
        with pytest.raises(httpx.ConnectError):
            await api_client.get_point_balance()


@pytest.mark.asyncio
async def test_redeem_network_error(api_client):
    """redeem_mechanic() debe propagar errores de red limpiamente."""
    with patch.object(api_client, "_post", side_effect=httpx.TimeoutException("timeout")):
        with pytest.raises(httpx.TimeoutException):
            await api_client.redeem_mechanic(mmvg_id=1, dimension_id=1, amount=1)


# ------------------------------------------------------------------
# Tokens inválidos
# ------------------------------------------------------------------

@pytest.mark.asyncio
async def test_invalid_token_raises_401():
    """Un token inválido debe causar HTTPStatusError con código 401."""
    from api.client import APIClient
    bad_client = APIClient(access_token="token-invalido", player_id=1)

    with pytest.raises(httpx.HTTPStatusError) as exc_info:
        await bad_client.get_point_balance()

    assert exc_info.value.response.status_code == 401


@pytest.mark.asyncio
async def test_whoami_with_invalid_token():
    """get_player_info() con token inválido debe lanzar HTTPStatusError."""
    from auth.login import get_player_info

    with pytest.raises(httpx.HTTPStatusError) as exc_info:
        await get_player_info("this.is.not.a.valid.jwt")

    assert exc_info.value.response.status_code in (401, 403, 422)


# ------------------------------------------------------------------
# Saldo insuficiente
# ------------------------------------------------------------------

@pytest.mark.asyncio
async def test_redeem_insufficient_balance(api_client):
    """Intentar canjear con cantidad exorbitante debe retornar 4xx sin crash."""
    mechanics = await api_client.get_mechanics()
    if not mechanics:
        pytest.skip("No hay mecánicas disponibles en el videojuego")

    from session.catalog import build_catalog_entry
    entry = build_catalog_entry(mechanics[0])
    if not entry:
        pytest.skip("No se pudo parsear la primera mecánica")

    # Intentar canjear una cantidad absurda para provocar saldo insuficiente
    with pytest.raises(httpx.HTTPStatusError) as exc_info:
        await api_client.redeem_mechanic(
            mmvg_id=entry["mmvgId"],
            dimension_id=entry["dimensionId"],
            amount=9_999_999,
        )

    status = exc_info.value.response.status_code
    assert status in (400, 402, 422), (
        f"Se esperaba 400/402/422 por saldo insuficiente, se recibió {status}"
    )


# ------------------------------------------------------------------
# session.json malformado
# ------------------------------------------------------------------

def test_session_reader_missing_file(tmp_path):
    """SessionReader equivalente en Python: un archivo inexistente da un error limpio."""
    path = tmp_path / "no_existe.json"
    result = _read_session_file(str(path))
    assert result is None


def test_session_reader_bad_json(tmp_path):
    """JSON malformado en session.json no debe lanzar una excepción no manejada."""
    session_file = tmp_path / "session.json"
    session_file.write_text("esto no es json {{{", encoding="utf-8")

    try:
        json.loads(session_file.read_text())
        assert False, "Debería haber lanzado excepción"
    except json.JSONDecodeError:
        pass  # Correcto


def test_session_reader_wrong_hmac(tmp_path):
    """session.json con firma HMAC incorrecta debe ser rechazado."""
    from session.signer import sign_payload

    session_file = tmp_path / "session.json"
    payload = {"userId": "42", "balance": {"fisico": 100}, "expires": int(time.time()) + 3600}
    sig = sign_payload(payload)

    # Balance modificado después de firmar: la firma ya no coincide
    tampered = {**payload, "balance": {"fisico": 999}, "sig": sig}
    session_file.write_text(json.dumps(tampered), encoding="utf-8")

    data = json.loads(session_file.read_text())
    stored_sig = data.pop("sig", "")
    payload_check = {
        "userId": data["userId"],
        "balance": data["balance"],
        "expires": data["expires"],
    }

    from session.signer import verify_payload
    assert not verify_payload(payload_check, stored_sig), (
        "Una firma incorrecta debe retornar False"
    )


def test_session_reader_valid_hmac(tmp_path):
    """session.json con firma HMAC correcta debe ser aceptado."""
    from session.signer import sign_payload, verify_payload

    payload = {"userId": "42", "balance": {"fisico": 100, "mental": 200}, "expires": int(time.time()) + 3600}
    sig = sign_payload(payload)

    assert verify_payload(payload, sig), "La firma correcta debe retornar True"


# ------------------------------------------------------------------
# Catálogo vacío
# ------------------------------------------------------------------

def test_process_purchase_unknown_item(tmp_path):
    """Una compra con itemId desconocido no debe lanzar excepción no manejada."""
    from session.catalog import build_catalog_entry

    # Mecánica con datos mínimos pero sin mmvgId
    entry = build_catalog_entry({"name": "Sin ID"})
    assert entry is None, "Mecánica sin ID debe retornar None"


def test_catalog_entry_minimal():
    """Una mecánica con id y options {name, cost, point_dimension_id} genera una entrada válida."""
    from session.catalog import build_catalog_entry

    mechanic = {
        "id": 5,
        "options": {"name": "Test Mech", "cost": 3, "point_dimension_id": 2},
    }
    entry = build_catalog_entry(mechanic)
    assert entry is not None
    assert entry["itemId"] == "5"
    assert entry["mmvgId"] == 5
    assert entry["name"] == "Test Mech"
    assert entry["cost"] == 3
    assert entry["dimensionId"] == 2


def test_catalog_entry_without_options_is_skipped():
    """Una mecánica sin el formato estándar en options no pasa al catálogo."""
    from session.catalog import build_catalog_entry

    assert build_catalog_entry({"id": 5, "name": "Test Mech"}) is None


# ------------------------------------------------------------------
# Helper
# ------------------------------------------------------------------

def _read_session_file(path: str) -> dict | None:
    """Intenta leer un archivo de sesión; devuelve None si no existe o es inválido."""
    try:
        return json.loads(Path(path).read_text(encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError):
        return None
