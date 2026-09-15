from __future__ import annotations

import socket
import sys
from pathlib import Path

import google.auth
import pytest


ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))


@pytest.fixture(autouse=True)
def disable_application_default_credentials(monkeypatch):
    """Tests must not discover developer credentials or contact GCP metadata."""
    def no_credentials(*args, **kwargs):
        raise google.auth.exceptions.DefaultCredentialsError("ADC is disabled in tests")

    monkeypatch.setattr(google.auth, "default", no_credentials)


@pytest.fixture(autouse=True)
def block_network_connections(monkeypatch):
    """Unit/API tests use in-process transports and must never reach real APIs."""
    original_connect = socket.socket.connect
    original_connect_ex = socket.socket.connect_ex

    def guard(method):
        def connect(sock, address):
            if sock.family in (socket.AF_INET, socket.AF_INET6):
                raise AssertionError("Network access is disabled in tests; mock the external client")
            return method(sock, address)
        return connect

    monkeypatch.setattr(socket.socket, "connect", guard(original_connect))
    monkeypatch.setattr(socket.socket, "connect_ex", guard(original_connect_ex))
