import json
import logging
import sys
from datetime import datetime, timezone


SEVERITY_NUMBERS = {
    logging.DEBUG: 5,
    logging.INFO: 9,
    logging.WARNING: 13,
    logging.ERROR: 17,
    logging.CRITICAL: 21,
}

SEVERITY_NAMES = {
    logging.DEBUG: "DEBUG",
    logging.INFO: "INFO",
    logging.WARNING: "WARN",
    logging.ERROR: "ERROR",
    logging.CRITICAL: "FATAL",
}


class JsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        payload = {
            "timestamp": datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z"),
            "severity": SEVERITY_NAMES.get(record.levelno, record.levelname),
            "severity_number": SEVERITY_NUMBERS.get(record.levelno, record.levelno),
            "message": record.getMessage(),
        }
        payload.update(getattr(record, "attributes", {}))
        if record.exc_info:
            payload["exception.stacktrace"] = self.formatException(record.exc_info)
        return json.dumps(payload, ensure_ascii=False, separators=(",", ":"))


def configure_logging() -> None:
    root = logging.getLogger()
    root.setLevel(logging.INFO)
    if any(getattr(handler, "promptlab_json", False) for handler in root.handlers):
        return

    handler = logging.StreamHandler(sys.stdout)
    handler.promptlab_json = True
    handler.setFormatter(JsonFormatter())
    root.addHandler(handler)


def http_log_attributes(method: str, path: str, status: int, duration_ms: float) -> dict[str, object] | None:
    if path == "/health":
        return None
    return {
        "event.name": "http.server.request.completed",
        "http.request.method": method,
        "url.path": path,
        "http.response.status_code": status,
        "duration_ms": round(duration_ms, 2),
    }


def log_http_request(logger: logging.Logger, method: str, path: str, status: int, duration_ms: float) -> None:
    attributes = http_log_attributes(method, path, status, duration_ms)
    if attributes is None:
        return
    level = logging.ERROR if status >= 500 else logging.WARNING if status >= 400 else logging.INFO
    logger.log(level, "http.server.request.completed", extra={"attributes": attributes})


def log_exception(logger: logging.Logger, error: Exception, method: str, path: str, status: int) -> None:
    logger.error(
        "error.exception",
        exc_info=(type(error), error, error.__traceback__),
        extra={
            "attributes": {
                "event.name": "error.exception",
                "http.request.method": method,
                "url.path": path,
                "http.response.status_code": status,
                "error.type": type(error).__name__,
                "error.message": str(error),
            }
        },
    )
