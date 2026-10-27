"""Construcción y escritura del archivo de sesión firmado para el Script Extender."""

import json
import time
from pathlib import Path
from typing import Any

from api.models import UserProfile
from config import SE_SESSION_PATH, SESSION_TTL_SECONDS
from session.atomic import write_atomic
from session.signer import sign_payload


def build_session_payload(profile: UserProfile) -> dict[str, Any]:
    """Construye el payload de sesión a partir del perfil del jugador.

    El balance se representa como diccionario {nombre_dimensión: puntos}
    con los atributos LSG (social, fisico, afectivo, mental, linguistico).

    Args:
        profile: Perfil del jugador obtenido desde la API de producción.

    Returns:
        Diccionario con userId, balance (dimensional), expires.
        No incluye 'sig' (se añade en write_session).
    """
    expires = int(time.time()) + SESSION_TTL_SECONDS
    return {
        "userId": str(profile.player_id),
        "balance": profile.balance_dict(),
        "expires": expires,
    }


def write_session(profile: UserProfile) -> int:
    """Construye, firma y escribe session.json en la ruta del Script Extender.

    Formato resultante:
        {
          "userId": "42",
          "playerName": "Juan García",
          "balance": {"social": 150, "fisico": 100, "mental": 200, ...},
          "dimensions": [{"id":1,"name":"social","balance":150}, ...],
          "expires": 1234567890,
          "sig": "hmac-sha256..."
        }

    Args:
        profile: Perfil del jugador con dimensiones actualizadas.

    Returns:
        Timestamp Unix de expiración de la sesión recién escrita.
    """
    payload = build_session_payload(profile)
    signature = sign_payload(payload)

    signed: dict[str, Any] = {**payload, "sig": signature}

    # Datos adicionales fuera del HMAC (no alteran la firma)
    signed["playerName"] = profile.name
    signed["dimensions"] = [
        {"id": dim.id, "name": dim.name, "balance": dim.balance}
        for dim in profile.dimensions
    ]

    write_atomic(
        Path(SE_SESSION_PATH), json.dumps(signed, indent=2, ensure_ascii=False)
    )

    return payload["expires"]
