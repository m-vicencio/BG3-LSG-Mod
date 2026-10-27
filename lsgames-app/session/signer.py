"""Firma y verificación HMAC-SHA256 para el payload de sesión."""

import hashlib
import hmac
import json
from typing import Any

from config import SHARED_SECRET


def sign_payload(payload: dict[str, Any]) -> str:
    """Genera la firma HMAC-SHA256 de un payload de sesión.

    El payload se serializa a JSON con claves ordenadas alfabéticamente para
    garantizar que la firma sea determinista independientemente del orden de
    inserción de los campos.

    Args:
        payload: Diccionario con los datos de la sesión. **No debe incluir**
            el campo ``"sig"`` para que la firma sea coherente.

    Returns:
        Cadena hexadecimal en minúsculas con la firma HMAC-SHA256.
    """
    # Serialización compacta con claves ordenadas: firma determinista
    canonical = json.dumps(payload, sort_keys=True, separators=(",", ":"))
    return sign_text(canonical)


def sign_text(text: str) -> str:
    """HMAC-SHA256 en hexadecimal de un texto tal cual (codificado en UTF-8)."""
    return hmac.new(
        SHARED_SECRET.encode("utf-8"),
        text.encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()


def verify_text(text: str, signature: object) -> bool:
    """Verifica en tiempo constante la firma de ``sign_text``."""
    return isinstance(signature, str) and hmac.compare_digest(sign_text(text), signature)


def verify_payload(payload: dict[str, Any], signature: str) -> bool:
    """Verifica que la firma HMAC-SHA256 de un payload sea válida.

    La comparación se realiza en tiempo constante (``hmac.compare_digest``)
    para evitar ataques de temporización.

    Args:
        payload: Diccionario con los datos de la sesión (sin el campo ``"sig"``).
        signature: Firma hexadecimal a comparar contra la esperada.

    Returns:
        ``True`` si la firma es válida, ``False`` en caso contrario.
    """
    expected = sign_payload(payload)
    return hmac.compare_digest(expected, signature)
