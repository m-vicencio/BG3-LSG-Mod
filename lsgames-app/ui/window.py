"""Interfaz gráfica principal de LifeSyncGames usando customtkinter."""

import asyncio
import json
import subprocess
import threading
from datetime import datetime
from pathlib import Path
from typing import Optional

import customtkinter as ctk

from api.client import APIClient
from api.models import UserProfile
from auth.login import login, refresh_token, get_player_info
from auth.token_store import (
    save_access_token, load_access_token, delete_access_token,
    save_email, load_email, clear_all,
    save_locale, load_locale,
)
from config import SE_CATALOG_PATH, SE_LOCALE_PATH, BG3_GAME_ID, DEFAULT_LOCALE
from i18n import t, t_dim, set_locale, current_locale
from session.atomic import write_atomic
from session.catalog import fetch_and_write_catalog
from session.game_session import read_game_start_signal, read_refresh_request
from session.ingest_events import fetch_and_write_events
from session.inventory import write_notify
from session.offline_sync import read_pending_offline_sync, write_sync_result
from session.purchase import read_pending_purchase
from session.transactions import record as record_transaction
from session.writer import write_session


def _run_async(coro) -> object:
    """Ejecuta una coroutine en un event loop temporal de un hilo separado."""
    loop = asyncio.new_event_loop()
    try:
        return loop.run_until_complete(coro)
    finally:
        loop.close()


def _load_catalog_from_file() -> list[dict]:
    try:
        path = Path(SE_CATALOG_PATH)
        if path.exists():
            return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        pass
    return []


_COLOR_OK      = "#2CC985"
_COLOR_ERROR   = "#E74C3C"
_COLOR_NEUTRAL = "gray"


class LifeSyncGamesApp(ctk.CTk):
    """Ventana principal de la aplicación LifeSyncGames.

    Flujo:
    1. Carga la preferencia de idioma desde keyring y aplica la localización.
    2. Auto-login con el access token guardado (GET /whoami).
    3. Si falla, muestra formulario de login (POST /login).
    4. Muestra el Gemelo Digital Simplificado con las dimensiones LSG.
    5. Sondea pending_purchase.json y pending_offline_sync.json cada 3 s.
    """

    def __init__(self) -> None:
        super().__init__()

        # Cargar preferencia de idioma antes de construir la UI
        saved_locale = load_locale() or DEFAULT_LOCALE
        set_locale(saved_locale)

        self.title("LifeSyncGames")
        self.geometry("440x580")
        self.resizable(False, False)

        ctk.set_appearance_mode("dark")
        ctk.set_default_color_theme("blue")

        self._access_token: Optional[str]     = None
        self._api_client:   Optional[APIClient] = None
        self._session_expires: Optional[int]  = None
        self._profile:      Optional[UserProfile] = None
        self._catalog:      list[dict]         = []
        self._game_session_id: Optional[int]  = None

        self._build_ui()

        self.after(100,  self._attempt_auto_login)
        self.after(3000, self._poll_pending_purchase)
        self.after(3000, self._poll_game_start_signal)
        self.after(3000, self._poll_offline_sync)
        self.after(3000, self._poll_refresh_request)
        self.after(5000, self._poll_ingest_events)

    # ------------------------------------------------------------------
    # Construcción de la UI
    # ------------------------------------------------------------------

    def _build_ui(self) -> None:
        # Botón de idioma (fila propia, alineado a la derecha)
        lang_row = ctk.CTkFrame(self, fg_color="transparent")
        lang_row.pack(fill="x", padx=20, pady=(10, 0))

        self._btn_lang = ctk.CTkButton(
            lang_row,
            text=t("btn_language"),
            width=50,
            height=28,
            fg_color="transparent",
            border_width=1,
            command=self._toggle_locale,
        )
        self._btn_lang.pack(side="right")

        # Título centrado
        ctk.CTkLabel(
            self,
            text="LifeSyncGames",
            font=ctk.CTkFont(size=26, weight="bold"),
        ).pack(pady=(8, 0))

        # Estado
        self._label_status = ctk.CTkLabel(
            self,
            text=t("status_connecting"),
            font=ctk.CTkFont(size=13),
            text_color=_COLOR_NEUTRAL,
        )
        self._label_status.pack(pady=(6, 18))

        # Formulario de login
        self._frame_login = ctk.CTkFrame(self)
        self._frame_login.pack(fill="x", padx=40, pady=6)

        self._lbl_email_field = ctk.CTkLabel(
            self._frame_login, text=t("label_email")
        )
        self._lbl_email_field.pack(anchor="w", padx=18, pady=(18, 3))

        self._entry_email = ctk.CTkEntry(
            self._frame_login, placeholder_text=t("placeholder_email")
        )
        self._entry_email.pack(fill="x", padx=18, pady=(0, 10))
        saved_email = load_email()
        if saved_email:
            self._entry_email.insert(0, saved_email)

        self._lbl_password_field = ctk.CTkLabel(
            self._frame_login, text=t("label_password")
        )
        self._lbl_password_field.pack(anchor="w", padx=18, pady=(0, 3))

        self._entry_password = ctk.CTkEntry(
            self._frame_login,
            placeholder_text=t("placeholder_password"),
            show="*",
        )
        self._entry_password.pack(fill="x", padx=18, pady=(0, 12))

        self._entry_email.bind("<Return>",    lambda _: self._on_login())
        self._entry_password.bind("<Return>", lambda _: self._on_login())

        self._btn_login = ctk.CTkButton(
            self._frame_login, text=t("btn_login"), command=self._on_login
        )
        self._btn_login.pack(padx=18, pady=(0, 18))

        # Panel de sesión activa
        self._frame_session = ctk.CTkFrame(self)

        self._label_playername = ctk.CTkLabel(
            self._frame_session,
            text="",
            font=ctk.CTkFont(size=15, weight="bold"),
        )
        self._label_playername.pack(pady=(18, 2))

        self._label_email = ctk.CTkLabel(
            self._frame_session,
            text="",
            font=ctk.CTkFont(size=11),
            text_color="gray",
        )
        self._label_email.pack(pady=(0, 12))

        self._frame_dimensions = ctk.CTkFrame(
            self._frame_session, fg_color="transparent"
        )
        self._frame_dimensions.pack(pady=(0, 8), fill="x", padx=18)

        self._label_expiry = ctk.CTkLabel(
            self._frame_session,
            text="",
            font=ctk.CTkFont(size=11),
            text_color="gray",
        )
        self._label_expiry.pack(pady=(0, 12))

        self._btn_refresh = ctk.CTkButton(
            self._frame_session,
            text=t("btn_refresh"),
            command=self._on_refresh_session,
        )
        self._btn_refresh.pack(pady=(0, 6))

        self._btn_logout = ctk.CTkButton(
            self._frame_session,
            text=t("btn_logout"),
            fg_color="transparent",
            border_width=1,
            command=self._on_logout,
        )
        self._btn_logout.pack(pady=(0, 20))

    # ------------------------------------------------------------------
    # Localización
    # ------------------------------------------------------------------

    def _toggle_locale(self) -> None:
        """Alterna entre los idiomas disponibles en locales/."""
        locales = [l for l in ["es", "en"] if l != current_locale()]
        new_lang = locales[0] if locales else "es"
        set_locale(new_lang)
        save_locale(new_lang)
        self._write_mod_locale(new_lang)
        self._apply_locale()

    def _write_mod_locale(self, lang: str) -> None:
        """Escribe locale.json en el directorio del mod BG3 para que Locale.lua lo lea."""
        try:
            write_atomic(Path(SE_LOCALE_PATH), json.dumps({"lang": lang}))
        except Exception:
            pass

    def _apply_locale(self) -> None:
        """Actualiza en caliente todos los textos estáticos de la UI."""
        self._btn_lang.configure(text=t("btn_language"))
        self._lbl_email_field.configure(text=t("label_email"))
        self._lbl_password_field.configure(text=t("label_password"))
        self._entry_email.configure(placeholder_text=t("placeholder_email"))
        self._entry_password.configure(placeholder_text=t("placeholder_password"))
        self._btn_login.configure(text=t("btn_login"))
        self._btn_refresh.configure(text=t("btn_refresh"))
        self._btn_logout.configure(text=t("btn_logout"))
        self._rebuild_dimensions_frame()
        self._refresh_session_label()
        if not self._profile:
            self._set_status(t("status_please_login"))

    # ------------------------------------------------------------------
    # Helpers de UI
    # ------------------------------------------------------------------

    def _set_status(self, text: str, color: str = _COLOR_NEUTRAL) -> None:
        self._label_status.configure(text=text, text_color=color)

    def _show_login_form(self) -> None:
        self._frame_session.pack_forget()
        self._frame_login.pack(fill="x", padx=40, pady=6)

    def _show_session_panel(self) -> None:
        self._frame_login.pack_forget()
        self._frame_session.pack(fill="x", padx=40, pady=6)

    _DIM_COLORS = {
        "social":      "#2ECC71",
        "fisico":      "#E74C3C",
        "afectivo":    "#9B59B6",
        "mental":      "#3498DB",
        "linguistico": "#F39C12",
    }

    def _rebuild_dimensions_frame(self) -> None:
        for widget in self._frame_dimensions.winfo_children():
            widget.destroy()

        if not self._profile or not self._profile.dimensions:
            ctk.CTkLabel(
                self._frame_dimensions,
                text=t("label_no_dimensions"),
                text_color="gray",
            ).pack()
            return

        for dim in self._profile.dimensions:
            color = self._DIM_COLORS.get(dim.name, "#F4C430")
            ctk.CTkLabel(
                self._frame_dimensions,
                text=f"{t_dim(dim.name)}: {dim.balance:,} pts",
                font=ctk.CTkFont(size=13),
                text_color=color,
            ).pack(anchor="w", pady=1)

    def _refresh_session_label(self) -> None:
        if self._profile is not None:
            self._label_playername.configure(text=self._profile.name)
            self._label_email.configure(text=self._profile.email)
            self._rebuild_dimensions_frame()

        if self._session_expires is not None:
            expiry_str = datetime.fromtimestamp(self._session_expires).strftime(
                "%d/%m/%Y %H:%M"
            )
            self._label_expiry.configure(
                text=t("label_session_expires", expiry=expiry_str)
            )

    # ------------------------------------------------------------------
    # Auto-login
    # ------------------------------------------------------------------

    def _attempt_auto_login(self) -> None:
        stored_token = load_access_token()
        if not stored_token:
            self._set_status(t("status_please_login"))
            self._show_login_form()
            return

        self._set_status(t("status_verifying"))

        def _task() -> None:
            try:
                info      = _run_async(get_player_info(stored_token))
                player_id = int(info["id_players"])
                self._access_token = stored_token
                self._api_client   = APIClient(stored_token, player_id)

                profile = _run_async(self._api_client.get_user_profile())
                expires = write_session(profile)
                self._session_expires = expires
                self._profile  = profile
                self._catalog  = _run_async(fetch_and_write_catalog(self._api_client))
                write_notify(catalog_updated=True)
                self.after(0, self._on_auto_login_success)
            except Exception as exc:
                self.after(0, lambda e=exc: self._on_auto_login_failure(e))

        threading.Thread(target=_task, daemon=True).start()

    def _on_auto_login_success(self) -> None:
        self._set_status(t("status_session_active"), _COLOR_OK)
        self._show_session_panel()
        self._refresh_session_label()

    def _on_auto_login_failure(self, exc: Exception) -> None:
        delete_access_token()
        self._set_status(t("status_please_login"))
        self._show_login_form()

    # ------------------------------------------------------------------
    # Login manual
    # ------------------------------------------------------------------

    def _on_login(self) -> None:
        email    = self._entry_email.get().strip()
        password = self._entry_password.get()

        if not email or not password:
            self._set_status(t("status_enter_credentials"), _COLOR_ERROR)
            return

        self._btn_login.configure(state="disabled", text=t("btn_login_loading"))
        self._set_status(t("status_authenticating"))

        def _task() -> None:
            try:
                access_token = _run_async(login(email, password))
                info         = _run_async(get_player_info(access_token))
                player_id    = int(info["id_players"])

                save_access_token(access_token)
                save_email(email)

                self._access_token = access_token
                self._api_client   = APIClient(access_token, player_id)

                profile = _run_async(self._api_client.get_user_profile())
                expires = write_session(profile)
                self._session_expires = expires
                self._profile  = profile
                self._catalog  = _run_async(fetch_and_write_catalog(self._api_client))
                write_notify(catalog_updated=True)
                self.after(0, self._on_login_success)
            except Exception as exc:
                self.after(0, lambda e=exc: self._on_login_failure(e))

        threading.Thread(target=_task, daemon=True).start()

    def _on_login_success(self) -> None:
        self._btn_login.configure(state="normal", text=t("btn_login"))
        self._entry_password.delete(0, "end")
        self._set_status(t("status_session_active"), _COLOR_OK)
        self._show_session_panel()
        self._refresh_session_label()

    def _on_login_failure(self, exc: Exception) -> None:
        self._btn_login.configure(state="normal", text=t("btn_login"))
        self._set_status(t("status_error", name=type(exc).__name__), _COLOR_ERROR)

    # ------------------------------------------------------------------
    # Actualización de sesión
    # ------------------------------------------------------------------

    def _on_refresh_session(self) -> None:
        if self._api_client is None:
            return

        self._btn_refresh.configure(state="disabled", text=t("btn_refresh_loading"))
        self._set_status(t("status_updating"))

        def _task() -> None:
            try:
                prev_balance = self._profile.balance_dict() if self._profile else {}
                profile = _run_async(self._api_client.get_user_profile())

                # Deltas positivos entre lecturas = puntos ganados por actividad
                # externa en LifeSyncGames (los canjes registran su propio gasto).
                for dim in profile.dimensions:
                    delta = dim.balance - prev_balance.get(dim.name, dim.balance)
                    if delta > 0:
                        record_transaction(
                            "ingreso", "Actividad LifeSyncGames",
                            dim.name, dim.id, delta, dim.balance,
                        )

                expires = write_session(profile)
                self._session_expires = expires
                self._profile  = profile
                self._catalog  = _run_async(fetch_and_write_catalog(self._api_client))
                write_notify(catalog_updated=True)
                self.after(0, self._on_refresh_success)
            except Exception as exc:
                self.after(0, lambda e=exc: self._on_refresh_failure(e))

        threading.Thread(target=_task, daemon=True).start()

    def _on_refresh_success(self) -> None:
        self._btn_refresh.configure(state="normal", text=t("btn_refresh"))
        self._set_status(t("status_session_updated"), _COLOR_OK)
        self._refresh_session_label()

    def _on_refresh_failure(self, exc: Exception) -> None:
        self._btn_refresh.configure(state="normal", text=t("btn_refresh"))
        is_401 = "401" in str(exc) or "Unauthorized" in str(exc)

        if is_401 and self._access_token:
            self._set_status(t("status_token_refreshing"))
            self._try_token_refresh()
        elif is_401:
            delete_access_token()
            self._set_status(t("status_token_expired"), _COLOR_ERROR)
            self.after(2000, self._on_logout)
        else:
            self._set_status(t("status_update_error", name=type(exc).__name__), _COLOR_ERROR)

    def _try_token_refresh(self) -> None:
        """Renueva el token silenciosamente usando POST /token/refresh."""
        old_token = self._access_token

        def _task() -> None:
            try:
                new_token = _run_async(refresh_token(old_token))
                save_access_token(new_token)
                self._access_token = new_token
                if self._api_client:
                    self._api_client.access_token = new_token
                self.after(0, self._on_refresh_session)
            except Exception:
                delete_access_token()
                self.after(0, lambda: self._set_status(
                    t("status_token_expired"), _COLOR_ERROR
                ))
                self.after(2000, self._on_logout)

        threading.Thread(target=_task, daemon=True).start()

    # ------------------------------------------------------------------
    # Cierre de sesión
    # ------------------------------------------------------------------

    def _on_logout(self) -> None:
        clear_all()
        self._access_token    = None
        self._api_client      = None
        self._session_expires = None
        self._profile         = None
        self._catalog         = []
        self._set_status(t("status_please_login"))
        self._show_login_form()

    # ------------------------------------------------------------------
    # Sesión de juego BG3
    # ------------------------------------------------------------------

    @staticmethod
    def _is_bg3_running() -> bool:
        try:
            result = subprocess.run(
                ["tasklist", "/FI", "IMAGENAME eq bg3.exe", "/NH"],
                capture_output=True, text=True, timeout=5,
            )
            output = result.stdout.lower()
            return "bg3.exe" in output or "bg3_dx11.exe" in output
        except Exception:
            return False

    def _poll_game_start_signal(self) -> None:
        if self._api_client is not None and self._game_session_id is None:
            if read_game_start_signal():
                self._start_game_session()
        self.after(3000, self._poll_game_start_signal)

    def _poll_refresh_request(self) -> None:
        if self._api_client is not None and read_refresh_request():
            self._on_refresh_session()
        self.after(3000, self._poll_refresh_request)

    def _start_game_session(self) -> None:
        def _task() -> None:
            try:
                _run_async(self._api_client.connect_player())
                result     = _run_async(self._api_client.start_game_session())
                session_id = int(result.get("id_session") or 0)
                if session_id:
                    self._game_session_id = session_id
                    self.after(5000, self._monitor_bg3_process)
                    self.after(0, lambda: self._set_status(
                        t("status_game_started"), _COLOR_OK
                    ))
            except Exception as exc:
                self.after(0, lambda e=exc: self._set_status(
                    t("status_game_start_error", name=type(e).__name__), _COLOR_ERROR
                ))

        threading.Thread(target=_task, daemon=True).start()

    def _monitor_bg3_process(self) -> None:
        if self._game_session_id is None:
            return
        if self._is_bg3_running():
            self.after(5000, self._monitor_bg3_process)
        else:
            self._end_game_session()

    def _end_game_session(self) -> None:
        session_id            = self._game_session_id
        self._game_session_id = None

        def _task() -> None:
            try:
                _run_async(self._api_client.end_game_session(session_id))
                self.after(0, lambda: self._set_status(
                    t("status_game_ended"), _COLOR_NEUTRAL
                ))
            except Exception as exc:
                self.after(0, lambda e=exc: self._set_status(
                    t("status_game_end_error", name=type(e).__name__), _COLOR_ERROR
                ))

        threading.Thread(target=_task, daemon=True).start()

    # ------------------------------------------------------------------
    # Sincronización offline
    # ------------------------------------------------------------------

    def _poll_offline_sync(self) -> None:
        if self._api_client is not None:
            sync_req = read_pending_offline_sync()
            if sync_req:
                self._process_offline_sync(sync_req)
        self.after(3000, self._poll_offline_sync)

    def _record_synced_events(self, result: dict, events: list, profile) -> None:
        """Registra en transactions.json los eventos offline confirmados (SYNCED)."""
        status_by_ref = {
            r.get("client_ref"): r.get("status")
            for r in (result.get("results") or [])
            if isinstance(r, dict)
        }
        dim_names = {d.id: d.name for d in profile.dimensions}
        balances  = profile.balance_dict()

        for ev in events:
            if not isinstance(ev, dict):
                continue
            if status_by_ref.get(ev.get("client_ref")) != "SYNCED":
                continue

            dim_id   = int(ev.get("point_dimension_id") or 0)
            dim_name = dim_names.get(dim_id, f"dim_{dim_id}")
            amount   = int(ev.get("amount") or 0)
            payload  = ev.get("payload") or {}
            balance  = int(balances.get(dim_name, 0))

            if ev.get("direction") == "CREDIT":
                trigger = payload.get("trigger") or "actividad"
                record_transaction(
                    "ingreso", f"Actividad: {trigger}",
                    dim_name, dim_id, amount, balance,
                )
            else:
                mech_id = payload.get("mechanic_id")
                desc = "Canje"
                for entry in (self._catalog or _load_catalog_from_file()):
                    if mech_id is not None and entry.get("mmvgId") == mech_id:
                        desc = str(entry.get("name") or "Canje")
                        break
                record_transaction(
                    "gasto", desc, dim_name, dim_id, -amount, balance,
                )

    def _process_offline_sync(self, sync_req: dict) -> None:
        player_id = int(sync_req.get("player_id") or self._api_client.player_id)
        game_id   = sync_req.get("game_id") or BG3_GAME_ID
        events    = sync_req.get("events", [])

        def _task() -> None:
            try:
                result   = _run_async(
                    self._api_client.sync_offline_events(player_id, int(game_id), events)
                )
                write_sync_result(result)

                synced   = int(result.get("synced",   0))
                total    = int(result.get("total",    len(events)))
                rejected = int(result.get("rejected", 0))

                if synced > 0:
                    profile = _run_async(self._api_client.get_user_profile())
                    expires = write_session(profile)
                    self._session_expires = expires
                    self._profile = profile
                    self._record_synced_events(result, events, profile)
                    write_notify(catalog_updated=False)
                    self.after(0, self._refresh_session_label)

                if rejected:
                    msg   = t("status_sync_partial", synced=synced, total=total, rejected=rejected)
                    color = _COLOR_ERROR
                else:
                    msg   = t("status_sync_ok", synced=synced, total=total)
                    color = _COLOR_OK
                self.after(0, lambda m=msg, c=color: self._set_status(m, c))

            except Exception as exc:
                self.after(0, lambda e=exc: self._set_status(
                    t("status_sync_error", name=type(e).__name__), _COLOR_ERROR
                ))

        threading.Thread(target=_task, daemon=True).start()

    # ------------------------------------------------------------------
    # Sondeo de eventos de sensores (buffs por actividad real)
    # ------------------------------------------------------------------

    _INGEST_POLL_MS = 60000

    def _poll_ingest_events(self) -> None:
        """Descarga los ingest-events y publica recent_events.json para el mod.

        Cadencia de 60 s: cubre login, post-sync y actividad en vivo sin
        martillar la API. Los errores de red se ignoran (el mod simplemente
        no ve eventos nuevos hasta el próximo poll exitoso).
        """
        if self._api_client is not None:
            def _task() -> None:
                try:
                    _run_async(fetch_and_write_events(self._api_client))
                except Exception:
                    pass
            threading.Thread(target=_task, daemon=True).start()
        self.after(self._INGEST_POLL_MS, self._poll_ingest_events)

    # ------------------------------------------------------------------
    # Sondeo de canjes pendientes
    # ------------------------------------------------------------------

    def _poll_pending_purchase(self) -> None:
        if self._api_client is not None:
            purchase = read_pending_purchase()
            if purchase:
                self._process_purchase(purchase)
        self.after(3000, self._poll_pending_purchase)

    def _find_mechanic(self, item_id: str) -> dict | None:
        catalog = self._catalog or _load_catalog_from_file()
        for entry in catalog:
            if str(entry.get("itemId", "")) == str(item_id):
                return entry
        return None

    def _process_purchase(self, purchase: dict) -> None:
        item_id = str(purchase.get("itemId", ""))
        amount  = int(purchase.get("amount", 1))

        mechanic = self._find_mechanic(item_id)
        if not mechanic:
            self.after(0, lambda: self._set_status(
                t("status_error", name=f"mechanic not found: {item_id}"), _COLOR_ERROR
            ))
            return

        mmvg_id       = int(mechanic["mmvgId"])
        dimension_id  = int(mechanic["dimensionId"])
        mechanic_name = mechanic.get("name", item_id)
        is_test       = mmvg_id == -1

        def _task() -> None:
            try:
                if is_test:
                    msg = t("status_redeem_test", amount=amount, name=mechanic_name)
                else:
                    result = _run_async(
                        self._api_client.redeem_mechanic(mmvg_id, dimension_id, amount)
                    )
                    msg = result.get("message") or t(
                        "status_redeem_ok", amount=amount, name=mechanic_name
                    )

                profile = _run_async(self._api_client.get_user_profile())
                expires = write_session(profile)
                self._session_expires = expires
                self._profile = profile

                dim_name = str(mechanic.get("dimensionName") or f"dim_{dimension_id}")
                cost = int(mechanic.get("cost") or 0)
                record_transaction(
                    "gasto", f"{mechanic_name} x{amount}",
                    dim_name, dimension_id, -(cost * amount),
                    int(profile.balance_dict().get(dim_name, 0)),
                )
                write_notify(catalog_updated=False)

                self.after(0, lambda m=msg: self._set_status(m, _COLOR_OK))
                self.after(0, self._refresh_session_label)
            except Exception as exc:
                err_str = str(exc)
                if "401" in err_str:
                    self.after(0, lambda: self._set_status(
                        t("status_token_expired"), _COLOR_ERROR
                    ))
                else:
                    self.after(0, lambda e=err_str: self._set_status(
                        t("status_redeem_error", msg=e[:60]), _COLOR_ERROR
                    ))

        threading.Thread(target=_task, daemon=True).start()
