"""Punto de entrada principal de la aplicación LifeSyncGames.

Ejecutar directamente::

    python main.py

O compilar con PyInstaller usando ``build.spec``::

    pyinstaller build.spec
"""

from ui.window import LifeSyncGamesApp


def main() -> None:
    """Inicializa y arranca la ventana principal de LifeSyncGames."""
    app = LifeSyncGamesApp()
    app.mainloop()


if __name__ == "__main__":
    main()
