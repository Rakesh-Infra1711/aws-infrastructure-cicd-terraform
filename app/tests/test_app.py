"""Unit tests run by the CI pipeline before any infrastructure change."""

import os
import sys
from unittest import mock

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

import app as app_module  # noqa: E402


def client():
    app_module.app.config["TESTING"] = True
    return app_module.app.test_client()


def test_health_returns_ok_without_database():
    resp = client().get("/health")
    assert resp.status_code == 200
    assert resp.get_json()["status"] == "ok"


def test_db_check_reports_503_when_database_unreachable():
    with mock.patch.object(app_module, "record_visit", side_effect=ConnectionError("down")):
        resp = client().get("/db")
    assert resp.status_code == 503
    body = resp.get_json()
    assert body["database"] == "unavailable"
    assert "down" not in str(body)  # error details are not leaked


def test_db_check_success():
    with mock.patch.object(app_module, "record_visit", return_value=(42, "8.4.0")):
        resp = client().get("/db")
    assert resp.status_code == 200
    assert resp.get_json() == {"database": "connected", "mysql_version": "8.4.0", "total_visits": 42}


def test_index_renders_even_if_database_down():
    with mock.patch.object(app_module, "record_visit", side_effect=RuntimeError("x")), \
         mock.patch.object(app_module, "instance_metadata", return_value="i-test"):
        resp = client().get("/")
    assert resp.status_code == 200
    assert b"Database unavailable" in resp.data
    assert b"i-test" in resp.data
