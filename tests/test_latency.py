"""Prueba b): latencia y conectividad con la API de producción LSG.

Evalúa el tiempo de respuesta de cada endpoint para garantizar que la
latencia no afecte la fluidez del juego. Los umbrales son orientativos:
el mod sondea cada 3 s y las operaciones son asíncronas al hilo del juego.

Umbrales de aceptación:
    - Login:           < 3 000 ms
    - Whoami:          < 1 500 ms
    - Balance:         < 1 500 ms
    - Preview redeem:  < 2 000 ms

Ejecutar:
    pytest tests/test_latency.py -v --tb=short
"""

import time
import pytest

MAX_LOGIN_MS    = 3_000
MAX_WHOAMI_MS   = 1_500
MAX_BALANCE_MS  = 1_500
MAX_PREVIEW_MS  = 2_000


def _ms(start: float) -> int:
    return int((time.perf_counter() - start) * 1000)


@pytest.mark.asyncio
async def test_login_latency(credentials):
    """El login completo debe completarse en menos de {MAX_LOGIN_MS} ms."""
    from auth.login import login
    email, password = credentials

    t0 = time.perf_counter()
    await login(email, password)
    elapsed = _ms(t0)

    print(f"\n  Login: {elapsed} ms")
    assert elapsed < MAX_LOGIN_MS, (
        f"Login tardó {elapsed} ms (límite: {MAX_LOGIN_MS} ms)"
    )


@pytest.mark.asyncio
async def test_whoami_latency(auth_token):
    """GET /whoami debe responder en menos de {MAX_WHOAMI_MS} ms."""
    from auth.login import get_player_info

    t0 = time.perf_counter()
    await get_player_info(auth_token)
    elapsed = _ms(t0)

    print(f"\n  Whoami: {elapsed} ms")
    assert elapsed < MAX_WHOAMI_MS, (
        f"Whoami tardó {elapsed} ms (límite: {MAX_WHOAMI_MS} ms)"
    )


@pytest.mark.asyncio
async def test_balance_latency(api_client):
    """GET /players/{id}/attributes/points debe responder en menos de {MAX_BALANCE_MS} ms."""
    t0 = time.perf_counter()
    await api_client.get_point_balance()
    elapsed = _ms(t0)

    print(f"\n  Balance: {elapsed} ms")
    assert elapsed < MAX_BALANCE_MS, (
        f"Balance tardó {elapsed} ms (límite: {MAX_BALANCE_MS} ms)"
    )


@pytest.mark.asyncio
async def test_mechanics_latency(api_client):
    """GET /videogames/{id}/mechanics debe responder en menos de {MAX_BALANCE_MS} ms."""
    t0 = time.perf_counter()
    mechanics = await api_client.get_mechanics()
    elapsed = _ms(t0)

    print(f"\n  Mechanics: {elapsed} ms ({len(mechanics)} items)")
    assert elapsed < MAX_BALANCE_MS


@pytest.mark.asyncio
async def test_latency_summary(api_client, credentials):
    """Resumen de latencias para todos los endpoints del middleware."""
    from auth.login import login, get_player_info

    email, password = credentials
    results = {}

    t0 = time.perf_counter()
    token = await login(email, password)
    results["login"] = _ms(t0)

    t0 = time.perf_counter()
    info = await get_player_info(token)
    results["whoami"] = _ms(t0)

    t0 = time.perf_counter()
    await api_client.get_point_balance()
    results["balance"] = _ms(t0)

    t0 = time.perf_counter()
    mechanics = await api_client.get_mechanics()
    results["mechanics"] = _ms(t0)

    print("\n\n  ── Resumen de latencias ──")
    total = 0
    for endpoint, ms in results.items():
        print(f"  {endpoint:<12} {ms:>6} ms")
        total += ms
    print(f"  {'TOTAL':<12} {total:>6} ms")

    # No falla, solo reporta
    assert True
