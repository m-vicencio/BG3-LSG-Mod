"""Pruebas locales del middleware (sin red ni credenciales).

Ejecutar:
    pytest tests/test_local.py -v
"""

import json
import threading

import pytest


def test_write_atomic_overwrites_without_leftovers(tmp_path):
    from session.atomic import write_atomic

    dest = tmp_path / "sub" / "session.json"
    write_atomic(dest, "uno")
    write_atomic(dest, "dos")
    assert dest.read_text(encoding="utf-8") == "dos"
    assert not list(dest.parent.glob("*.tmp"))


def test_write_atomic_waits_for_open_reader(tmp_path):
    """Un lector con el destino abierto (como el mod) bloquea el reemplazo hasta que lo suelta."""
    from session.atomic import write_atomic

    dest = tmp_path / "session.json"
    write_atomic(dest, "uno")
    fh = open(dest, encoding="utf-8")
    threading.Timer(0.1, fh.close).start()
    write_atomic(dest, "dos")
    assert dest.read_text(encoding="utf-8") == "dos"


def test_write_atomic_raises_and_cleans_up(tmp_path):
    from session.atomic import write_atomic

    dest = tmp_path / "session.json"
    write_atomic(dest, "uno")
    with open(dest, encoding="utf-8"):
        with pytest.raises(PermissionError):
            write_atomic(dest, "dos", retries=1)
    assert dest.read_text(encoding="utf-8") == "uno"
    assert not list(tmp_path.glob("*.tmp"))


def test_write_atomic_concurrent_writers(tmp_path):
    from session.atomic import write_atomic

    dest = tmp_path / "session.json"
    threads = [
        threading.Thread(target=write_atomic, args=(dest, json.dumps({"n": i, "pad": "x" * 5000})))
        for i in range(20)
    ]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    assert "n" in json.loads(dest.read_text(encoding="utf-8"))
    assert not list(tmp_path.glob("*.tmp"))


_SYNC_REQ = {
    "player_id": 42,
    "game_id": 23,
    "events": [{
        "client_ref": "ref-1", "point_dimension_id": 2, "direction": "CREDIT",
        "amount": 10, "source_type": "OFFLINE_GAME", "payload": {"trigger": "test"},
        "status": "PENDING", "seq": 1,
    }],
}


def _write_pending(monkeypatch, tmp_path, content):
    path = tmp_path / "pending_offline_sync.json"
    path.write_text(json.dumps(content), encoding="utf-8")
    monkeypatch.setattr("session.offline_sync.SE_OFFLINE_PENDING_PATH", str(path))
    return path


def test_offline_sync_accepts_signed_request(monkeypatch, tmp_path):
    from session.offline_sync import read_pending_offline_sync
    from session.signer import sign_text

    body = json.dumps(_SYNC_REQ)
    path = _write_pending(monkeypatch, tmp_path, {"body": body, "sig": sign_text(body)})

    req = read_pending_offline_sync()
    assert req["player_id"] == 42
    assert [e["client_ref"] for e in req["events"]] == ["ref-1"]
    assert "status" not in req["events"][0]  # solo campos que acepta la API
    assert not path.exists()


@pytest.mark.parametrize("content", [
    _SYNC_REQ,                                                   # formato sin firmar
    {"body": json.dumps(_SYNC_REQ), "sig": "0" * 64},            # firma incorrecta
    {"body": json.dumps(_SYNC_REQ)},                             # sin sig
])
def test_offline_sync_rejects_unsigned_or_bad_signature(monkeypatch, tmp_path, content):
    from session.offline_sync import read_pending_offline_sync

    path = _write_pending(monkeypatch, tmp_path, content)
    assert read_pending_offline_sync() is None
    assert not path.exists()


def test_offline_sync_rejects_tampered_body(monkeypatch, tmp_path):
    from session.offline_sync import read_pending_offline_sync
    from session.signer import sign_text

    body = json.dumps(_SYNC_REQ)
    tampered = body.replace('"amount": 10', '"amount": 9999')
    _write_pending(monkeypatch, tmp_path, {"body": tampered, "sig": sign_text(body)})
    assert read_pending_offline_sync() is None


@pytest.mark.parametrize("raw, expected", [
    ({"event_type": "budget.month_met"}, "budget.month_met"),
    ({"mode": "walking", "route_id": "abc-123"}, "route.completed.walking"),
    ({"mode": "walking", "route_id": "free_roam"}, "route.freeroam"),
    ({"mode": "jogging", "route_id": "free_roam"}, "route.freeroam"),
    ({}, ""),
])
def test_event_type(raw, expected):
    from session.ingest_events import _event_type

    assert _event_type(raw) == expected
