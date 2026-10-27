"""Almacenamiento seguro del access token y email usando el keyring del sistema operativo."""

from typing import Optional

import keyring
import keyring.errors

from config import KEYRING_SERVICE, KEYRING_USERNAME, KEYRING_USERNAME_EMAIL

KEYRING_LOCALE = "locale"


def save_access_token(token: str) -> None:
    """Persiste el access token JWT en el almacén de credenciales del SO."""
    keyring.set_password(KEYRING_SERVICE, KEYRING_USERNAME, token)


def load_access_token() -> Optional[str]:
    """Carga el access token desde el almacén de credenciales del SO.

    Returns:
        El access token almacenado, o None si no existe ninguno guardado.
    """
    return keyring.get_password(KEYRING_SERVICE, KEYRING_USERNAME)


def delete_access_token() -> None:
    """Elimina el access token del almacén de credenciales del SO."""
    try:
        keyring.delete_password(KEYRING_SERVICE, KEYRING_USERNAME)
    except keyring.errors.PasswordDeleteError:
        pass


def save_email(email: str) -> None:
    """Persiste el email del jugador para mostrar en el auto-login."""
    keyring.set_password(KEYRING_SERVICE, KEYRING_USERNAME_EMAIL, email)


def load_email() -> Optional[str]:
    """Carga el email guardado del jugador."""
    return keyring.get_password(KEYRING_SERVICE, KEYRING_USERNAME_EMAIL)


def delete_email() -> None:
    """Elimina el email guardado."""
    try:
        keyring.delete_password(KEYRING_SERVICE, KEYRING_USERNAME_EMAIL)
    except keyring.errors.PasswordDeleteError:
        pass


def clear_all() -> None:
    """Elimina todos los datos de sesión almacenados."""
    delete_access_token()
    delete_email()


def save_locale(lang: str) -> None:
    """Persiste la preferencia de idioma del usuario."""
    keyring.set_password(KEYRING_SERVICE, KEYRING_LOCALE, lang)


def load_locale() -> Optional[str]:
    """Carga la preferencia de idioma guardada, o None si no existe."""
    return keyring.get_password(KEYRING_SERVICE, KEYRING_LOCALE)
