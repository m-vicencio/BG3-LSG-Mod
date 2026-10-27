"""Historial de movimientos de puntos para la pestaña Transacciones del mod BG3.

Cada canje (gasto) o acreditación (ingreso) se antepone a transactions.json,
que el mod lee para poblar la tabla de la Tienda de puntos. El archivo se capa
a las últimas 100 entradas.
"""

import json
import logging
import threading
import time
from pathlib import Path

from config import SE_TRANSACTIONS_PATH
from session.atomic import write_atomic

logger = logging.getLogger(__name__)

# Basta un lock en memoria: solo este proceso escribe el archivo.
_lock = threading.Lock()

_MAX_ENTRIES = 100

# Reasignable en tests para no tocar el archivo real
_PATH = Path(SE_TRANSACTIONS_PATH)


def record(
    tx_type: str,
    description: str,
    dimension_name: str,
    dimension_id: int,
    amount: int,
    balance: int,
) -> None:
    """Antepone un movimiento a transactions.json.

    Args:
        tx_type: "gasto" o "ingreso".
        description: Texto visible (ej. "Poción de Conexión x2", "Actividad: Caminar").
        dimension_name: Nombre de la dimensión LSG (ej. "social").
        dimension_id: ID de la dimensión (point_dimension_id).
        amount: Monto con signo (negativo para gastos, positivo para ingresos).
        balance: Saldo resultante de la dimensión tras el movimiento.
    """
    # Leer, insertar y escribir bajo el lock: varios hilos del middleware
    # (canje, sync offline, refresco) registran movimientos a la vez.
    with _lock:
        try:
            txs = json.loads(_PATH.read_text(encoding="utf-8")) if _PATH.exists() else []
        except Exception as exc:
            logger.warning("transactions.json ilegible, se reinicia: %s", exc)
            txs = []
        if not isinstance(txs, list):
            txs = []

        txs.insert(0, {
            "ts":            int(time.time()),
            "type":          tx_type,
            "description":   str(description),
            "dimensionName": str(dimension_name),
            "dimensionId":   int(dimension_id),
            "amount":        int(amount),
            "balance":       int(balance),
        })
        del txs[_MAX_ENTRIES:]

        try:
            write_atomic(_PATH, json.dumps(txs, ensure_ascii=False, indent=2))
        except Exception as exc:
            logger.warning("No se pudo escribir transactions.json: %s", exc)
