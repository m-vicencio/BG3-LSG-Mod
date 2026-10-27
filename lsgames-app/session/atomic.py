"""Escritura atómica de archivos para el intercambio con el mod BG3.

El mod lee los archivos de LSGMod/ con Ext.IO.LoadFile en cualquier momento.
Escribir directo sobre el destino (truncar y luego escribir) le permitiría leer
un archivo vacío o a medio escribir. Aquí se escribe primero en un temporal con
nombre único (varios hilos del middleware pueden escribir el mismo destino) y
luego se reemplaza el destino con os.replace, que en Windows (MoveFileEx) es
atómico dentro del mismo volumen: el mod ve la versión anterior completa o la
nueva completa, nunca una intermedia.
"""

import contextlib
import os
import tempfile
import time
from pathlib import Path


def write_atomic(path, text: str, retries: int = 5, delay: float = 0.05) -> None:
    """Escribe ``text`` en ``path`` de forma atómica.

    Args:
        path: Archivo destino (str o Path). Se crea la carpeta si no existe.
        text: Contenido a escribir (UTF-8, modo texto como ``Path.write_text``).
        retries: Intentos de reemplazo si el destino está abierto por el juego.
        delay: Espera en segundos entre intentos.

    Raises:
        OSError: Si no se pudo escribir o reemplazar tras todos los intentos.
            El temporal se elimina antes de propagar la excepción.
    """
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    # Temporal en la misma carpeta: mismo volumen, requisito del reemplazo atómico.
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=path.name + ".", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(text)
        for attempt in range(retries):
            try:
                os.replace(tmp, path)
                return
            except PermissionError:
                # Ext.IO.LoadFile abre sin FILE_SHARE_DELETE: si el mod está
                # leyendo justo ahora, el reemplazo falla. Sus lecturas duran
                # microsegundos, así que basta con reintentar.
                if attempt == retries - 1:
                    raise
                time.sleep(delay)
    except BaseException:
        with contextlib.suppress(OSError):
            os.unlink(tmp)
        raise
    # Sin fsync ni limpieza de .tmp huérfanos al arrancar: solo quedarían si el
    # proceso muere entre escribir y reemplazar, y el mod lee nombres fijos.
