import json
import logging

from fastapi.testclient import TestClient

from app.logging_config import JsonFormatter, http_log_attributes
from app.main import app


def test_health():
    client = TestClient(app)
    response = client.get("/health")

    assert response.status_code == 200
    assert response.json()["status"] == "ok"


def test_lab_status_is_gated_and_returns_controlled_errors(monkeypatch):
    client = TestClient(app, raise_server_exceptions=False)

    monkeypatch.setenv("LAB_MODE", "false")
    assert client.get("/lab/status/400").status_code == 404

    monkeypatch.setenv("LAB_MODE", "true")
    assert client.get("/lab/status/400").status_code == 400
    assert client.get("/lab/status/500").status_code == 500


def test_http_log_contract_is_json_and_uses_expected_severity():
    formatter = JsonFormatter()
    for status, expected_severity, expected_number in ((200, "INFO", 9), (400, "WARN", 13), (500, "ERROR", 17)):
        record = logging.LogRecord(
            "promptlab.insights",
            {200: logging.INFO, 400: logging.WARNING, 500: logging.ERROR}[status],
            __file__,
            1,
            "http.server.request.completed",
            (),
            None,
        )
        record.attributes = http_log_attributes("GET", "/recommendations", status, 12.345)
        payload = json.loads(formatter.format(record))

        assert payload["severity"] == expected_severity
        assert payload["severity_number"] == expected_number
        assert payload["event.name"] == "http.server.request.completed"
        assert payload["http.response.status_code"] == status
        assert payload["duration_ms"] == 12.35
        assert payload["timestamp"].endswith("Z")

    assert http_log_attributes("GET", "/health", 200, 1) is None
