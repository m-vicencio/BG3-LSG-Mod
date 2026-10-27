# -*- mode: python ; coding: utf-8 -*-
# Especificación de PyInstaller para compilar LifeSyncGames como un ejecutable único.
#
# Uso:
#   pip install pyinstaller
#   pyinstaller build.spec

import os

import customtkinter

block_cipher = None

a = Analysis(
    ["main.py"],
    pathex=[],
    binaries=[],
    datas=[
        # Incluir los assets de customtkinter (temas e imágenes)
        (os.path.dirname(customtkinter.__file__), "customtkinter"),
    ],
    hiddenimports=[
        # Backend de keyring para Windows Credential Manager
        "keyring.backends.Windows",
        # Backends alternativos por si se compila en otras plataformas
        "keyring.backends.SecretService",
        "keyring.backends.Kwallet",
        "keyring.backends.macOS",
        # Submódulos de customtkinter cargados dinámicamente
        "customtkinter",
    ],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    win_no_prefer_redirects=False,
    win_private_assemblies=False,
    cipher=block_cipher,
    noarchive=False,
)

pyz = PYZ(a.pure, a.zipped_data, cipher=block_cipher)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.zipfiles,
    a.datas,
    [],
    name="LifeSyncGames",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    upx_exclude=[],
    runtime_tmpdir=None,
    # Sin consola: aplicación de escritorio pura
    console=False,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
    # Reemplazar con la ruta a tu ícono .ico si tienes uno:
    # icon="assets/icon.ico",
    icon=None,
)
