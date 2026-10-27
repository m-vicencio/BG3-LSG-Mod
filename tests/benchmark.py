"""Evaluación de rendimiento: benchmark del middleware LSGames.

Mide el impacto en recursos del sistema (CPU, RAM) y los tiempos de respuesta
durante una secuencia de canjes múltiples contra el servidor real y localmente.

Ejecutar:
    python tests/benchmark.py

    O con credenciales explícitas:
    TEST_LSG_EMAIL=tu@email.com TEST_LSG_PASSWORD=tu_pass python tests/benchmark.py

Requisitos adicionales:
    pip install psutil
"""

import asyncio
import json
import os
import statistics
import sys
import tempfile
import time
from pathlib import Path
from typing import Callable

# Configurar path para importar desde lsgames-app
sys.path.insert(0, str(Path(__file__).parent.parent / "lsgames-app"))

try:
    import psutil
    _HAS_PSUTIL = True
except ImportError:
    _HAS_PSUTIL = False
    print("[WARN] psutil no instalado — métricas de CPU/RAM no disponibles")
    print("       pip install psutil")

try:
    from dotenv import load_dotenv
    load_dotenv(Path(__file__).parent / ".env")
except ImportError:
    pass


# ------------------------------------------------------------------
# Configuración
# ------------------------------------------------------------------

EMAIL    = os.environ.get("TEST_LSG_EMAIL", "")
PASSWORD = os.environ.get("TEST_LSG_PASSWORD", "")
RUNS     = int(os.environ.get("BENCH_RUNS", "5"))         # repeticiones por endpoint
WARMUP   = int(os.environ.get("BENCH_WARMUP", "1"))       # llamadas de calentamiento


# ------------------------------------------------------------------
# Helpers de medición
# ------------------------------------------------------------------

class ResourceSnapshot:
    """Captura CPU% y RSS (RAM) del proceso actual."""

    def __init__(self):
        if _HAS_PSUTIL:
            self._proc = psutil.Process()
            self._cpu_before = self._proc.cpu_percent(interval=None)
            self._mem_before = self._proc.memory_info().rss / 1024 / 1024  # MB
        self.cpu_delta = 0.0
        self.mem_delta = 0.0

    def stop(self):
        if _HAS_PSUTIL:
            cpu_after = self._proc.cpu_percent(interval=None)
            mem_after = self._proc.memory_info().rss / 1024 / 1024
            self.cpu_delta = cpu_after - self._cpu_before
            self.mem_delta = mem_after - self._mem_before


async def measure_latency(coro_factory: Callable, n: int) -> list[float]:
    """Ejecuta una coroutine n veces y retorna lista de latencias en ms."""
    latencies = []
    for _ in range(n):
        t0 = time.perf_counter()
        try:
            await coro_factory()
        except Exception as exc:
            print(f"  [ERROR] {type(exc).__name__}: {exc}")
        latencies.append((time.perf_counter() - t0) * 1000)
    return latencies


def _stats(latencies: list[float]) -> dict:
    if not latencies:
        return {"n": 0}
    return {
        "n":      len(latencies),
        "min":    min(latencies),
        "max":    max(latencies),
        "mean":   statistics.mean(latencies),
        "median": statistics.median(latencies),
        "stdev":  statistics.stdev(latencies) if len(latencies) > 1 else 0.0,
    }


def _print_stats(label: str, stats: dict) -> None:
    if stats.get("n", 0) == 0:
        print(f"  {label:<30} — sin datos")
        return
    print(
        f"  {label:<30}  "
        f"median={stats['median']:6.0f} ms  "
        f"mean={stats['mean']:6.0f} ms  "
        f"min={stats['min']:5.0f}  "
        f"max={stats['max']:5.0f}  "
        f"σ={stats['stdev']:5.0f}  "
        f"n={stats['n']}"
    )


# ------------------------------------------------------------------
# Benchmark principal
# ------------------------------------------------------------------

async def run_benchmark():
    if not EMAIL or not PASSWORD:
        print("ERROR: Define TEST_LSG_EMAIL y TEST_LSG_PASSWORD antes de ejecutar.")
        sys.exit(1)

    print("=" * 70)
    print("  LSGames Middleware — Benchmark de rendimiento")
    print(f"  Servidor: producción | Repeticiones: {RUNS} | Warmup: {WARMUP}")
    print("=" * 70)

    # Login para obtener token
    print("\n[1/4] Autenticando...")
    from auth.login import login, get_player_info
    from api.client import APIClient

    token = await login(EMAIL, PASSWORD)
    info = await get_player_info(token)
    player_id = int(info["id_players"])
    client = APIClient(access_token=token, player_id=player_id)
    print(f"  Jugador autenticado: id={player_id}")

    # Obtener mecánicas disponibles
    mechanics_raw = await client.get_mechanics()
    from session.catalog import build_catalog_entry
    catalog = [build_catalog_entry(m) for m in mechanics_raw]
    catalog = [e for e in catalog if e]
    print(f"  Mecánicas disponibles: {len(catalog)}")

    results = {}
    snap = ResourceSnapshot()

    # Benchmark: login
    print(f"\n[2/4] Benchmark login ({RUNS} repeticiones)...")
    for _ in range(WARMUP):
        await login(EMAIL, PASSWORD)

    login_lat = await measure_latency(
        lambda: login(EMAIL, PASSWORD), RUNS
    )
    results["login"] = _stats(login_lat)

    # Benchmark: lectura de balance
    print(f"[3/4] Benchmark balance ({RUNS} repeticiones)...")
    for _ in range(WARMUP):
        await client.get_point_balance()

    balance_lat = await measure_latency(
        lambda: client.get_point_balance(), RUNS
    )
    results["balance"] = _stats(balance_lat)

    # Benchmark: canje de mecánica (si hay una disponible)
    if catalog:
        entry = catalog[0]
        mmvg_id = entry["mmvgId"]
        dim_id  = entry["dimensionId"]
        name    = entry.get("name", "?")

        print(f"[4/4] Benchmark redeem/preview — '{name}' ({RUNS} repeticiones)...")
        print("      (Usando preview para no consumir puntos reales)")

        for _ in range(WARMUP):
            try:
                await client.preview_redeem(mmvg_id, dim_id, 1)
            except Exception:
                pass

        preview_lat = await measure_latency(
            lambda: client.preview_redeem(mmvg_id, dim_id, 1), RUNS
        )
        results["redeem/preview"] = _stats(preview_lat)
    else:
        print("[4/4] Sin mecánicas disponibles — omitiendo benchmark de canje")

    # Benchmark local: escritura de session.json
    print("\n[+] Benchmark local: escritura de session.json...")
    profile = await client.get_user_profile()
    write_lat = []
    for _ in range(20):
        t0 = time.perf_counter()
        try:
            # Medir solo la escritura en un temporal
            with tempfile.NamedTemporaryFile(mode="w", suffix=".json") as f:
                data = {
                    "userId": str(profile.player_id),
                    "balance": profile.balance_dict(),
                    "expires": int(time.time()) + 3600,
                }
                json.dump(data, f)
            write_lat.append((time.perf_counter() - t0) * 1000)
        except Exception:
            pass
    results["write_session (local)"] = _stats(write_lat)

    snap.stop()

    # Reporte final
    print("\n" + "=" * 70)
    print("  Resultados de latencia (ms)")
    print("=" * 70)
    for label, stats in results.items():
        _print_stats(label, stats)

    if _HAS_PSUTIL:
        print(f"\n  CPU delta:  {snap.cpu_delta:+.1f}%")
        print(f"  RAM delta:  {snap.mem_delta:+.1f} MB")

    # Evaluación final
    print("\n" + "=" * 70)
    issues = []
    if results.get("login", {}).get("median", 9999) > 3000:
        issues.append("Login lento (>3 s)")
    if results.get("balance", {}).get("median", 9999) > 1500:
        issues.append("Balance lento (>1.5 s)")
    if results.get("redeem/preview", {}).get("median", 9999) > 2000:
        issues.append("Preview lento (>2 s)")

    if issues:
        print("  ALERTAS DE RENDIMIENTO:")
        for issue in issues:
            print(f"    ⚠  {issue}")
    else:
        print("  OK — Todos los endpoints dentro de los umbrales aceptables.")
    print("=" * 70)


if __name__ == "__main__":
    asyncio.run(run_benchmark())
