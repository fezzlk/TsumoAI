import socket

import google.auth
import pytest


def test_tests_cannot_discover_application_default_credentials():
    with pytest.raises(google.auth.exceptions.DefaultCredentialsError, match="ADC is disabled"):
        google.auth.default()


@pytest.mark.parametrize("method", ["connect", "connect_ex"])
def test_tests_cannot_connect_to_external_services(method):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        with pytest.raises(AssertionError, match="Network access is disabled"):
            getattr(sock, method)(("192.0.2.1", 443))
