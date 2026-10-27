"""Prueba a): lectura de dimensiones del Gemelo Digital Simplificado.

Verifica que el middleware recupere correctamente los valores de las
dimensiones del perfil multidimensional (social, fisico, afectivo, mental,
linguistico) desde la API de producción de LSG.

Ejecutar desde la raíz del repositorio:
    pytest tests/test_dimensions.py -v
"""

import pytest


@pytest.mark.asyncio
async def test_login_returns_access_token(credentials):
    """El login con credenciales válidas debe retornar un JWT no vacío."""
    from auth.login import login
    email, password = credentials
    token = await login(email, password)
    assert isinstance(token, str), "access_token debe ser un string"
    assert len(token) > 20, "access_token parece demasiado corto"


@pytest.mark.asyncio
async def test_whoami_returns_player_id(auth_token):
    """GET /whoami debe retornar un id_players entero válido."""
    from auth.login import get_player_info
    info = await get_player_info(auth_token)
    assert "id_players" in info, "Respuesta de /whoami debe incluir id_players"
    assert isinstance(info["id_players"], int), "id_players debe ser entero"
    assert info["id_players"] > 0, "id_players debe ser positivo"


@pytest.mark.asyncio
async def test_point_balance_has_dimensions(api_client):
    """GET /players/{id}/attributes/points debe retornar al menos una dimensión con balance."""
    dimensions = await api_client.get_point_balance()
    assert isinstance(dimensions, list), "El balance debe ser una lista"
    assert len(dimensions) > 0, "Debe haber al menos una dimensión"

    for dim in dimensions:
        assert hasattr(dim, "id"), "Cada dimensión debe tener 'id'"
        assert hasattr(dim, "name"), "Cada dimensión debe tener 'name'"
        assert hasattr(dim, "balance"), "Cada dimensión debe tener 'balance'"
        assert isinstance(dim.id, int), f"dim.id debe ser entero, got {type(dim.id)}"
        assert isinstance(dim.name, str) and len(dim.name) > 0, "dim.name debe ser string no vacío"
        assert isinstance(dim.balance, int), f"dim.balance debe ser entero, got {type(dim.balance)}"
        assert dim.balance >= 0, f"Balance no puede ser negativo: {dim.balance}"


@pytest.mark.asyncio
async def test_user_profile_includes_dimensions(api_client):
    """get_user_profile() debe retornar un UserProfile con dimensiones."""
    profile = await api_client.get_user_profile()

    assert profile.player_id > 0
    assert isinstance(profile.name, str)
    assert isinstance(profile.email, str)
    assert len(profile.dimensions) > 0, "El perfil debe incluir dimensiones"

    balance_dict = profile.balance_dict()
    assert isinstance(balance_dict, dict), "balance_dict() debe retornar un dict"
    assert len(balance_dict) > 0, "balance_dict() no debe estar vacío"

    for key, value in balance_dict.items():
        assert isinstance(key, str), f"Clave de dimensión debe ser string: {key}"
        assert isinstance(value, int), f"Valor de dimensión debe ser entero: {value}"


@pytest.mark.asyncio
async def test_expected_dimensions_present(api_client):
    """El perfil debe incluir las dimensiones esperadas del sistema LSG."""
    profile = await api_client.get_user_profile()
    dim_names = {dim.name for dim in profile.dimensions}

    # Al menos una de las dimensiones conocidas debe estar presente
    known = {"social", "fisico", "afectivo", "mental", "linguistico"}
    found = dim_names & known
    assert len(found) > 0, (
        f"Ninguna dimensión conocida encontrada. Dimensiones recibidas: {dim_names}"
    )


@pytest.mark.asyncio
async def test_session_json_written_with_dimensions(api_client, tmp_path, monkeypatch):
    """write_session() debe escribir session.json con el balance dimensional."""
    import json
    from session.writer import write_session

    session_file = tmp_path / "session.json"
    monkeypatch.setattr("session.writer.SE_SESSION_PATH", str(session_file))
    monkeypatch.setattr("config.SE_SESSION_PATH", str(session_file))

    profile = await api_client.get_user_profile()
    write_session(profile)

    assert session_file.exists(), "session.json no fue creado"
    data = json.loads(session_file.read_text())

    assert "userId" in data
    assert "balance" in data
    assert isinstance(data["balance"], dict)
    assert len(data["balance"]) > 0
    assert "expires" in data
    assert "sig" in data
    assert "dimensions" in data
    assert isinstance(data["dimensions"], list)
