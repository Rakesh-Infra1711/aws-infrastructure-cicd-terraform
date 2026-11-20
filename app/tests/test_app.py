"""Unit tests run by the CI pipeline before any infrastructure change."""

import os
import sys
from unittest import mock

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

import app as app_module  # noqa: E402
import pytest  # noqa: E402


@pytest.fixture(autouse=True)
def reset_runtime_cache():
    """runtime_info() caches its result; clear it so tests don't affect each other."""
    app_module._runtime_cache.clear()
    yield
    app_module._runtime_cache.clear()


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


def test_index_on_ecs_uses_task_metadata(monkeypatch):
    monkeypatch.setenv("ECS_CONTAINER_METADATA_URI_V4", "http://169.254.170.2/v4/abc")
    task = b'{"TaskARN": "arn:aws:ecs:ap-south-1:1:task/cluster/task123", "AvailabilityZone": "ap-south-1b"}'
    fake = mock.MagicMock()
    fake.read.return_value = task
    with mock.patch.object(app_module.urllib.request, "urlopen", return_value=fake), \
         mock.patch.object(app_module, "record_visit", return_value=(1, "8.4.0")):
        resp = client().get("/")
    assert b"task123" in resp.data
    assert b"ap-south-1b" in resp.data
    assert b"ECS Fargate" in resp.data


def test_local_credentials_used_without_secret_arn(monkeypatch):
    monkeypatch.setattr(app_module, "DB_SECRET_ARN", "")
    monkeypatch.setenv("DB_USER", "app")
    monkeypatch.setenv("DB_PASSWORD", "local-only")
    assert app_module.get_db_credentials() == {"username": "app", "password": "local-only"}
