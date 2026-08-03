import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const pino = require("pino");

const severityNumbers = {
  trace: 1,
  debug: 5,
  info: 9,
  warn: 13,
  error: 17,
  fatal: 21
};

const loggerOptions = {
  base: undefined,
  level: process.env.LOG_LEVEL || "info",
  messageKey: "message",
  timestamp: () => `,"timestamp":"${new Date().toISOString()}"`,
  formatters: {
    bindings() {
      return {};
    },
    level(label, number) {
      return {
        level: number,
        severity: label.toUpperCase(),
        severity_number: severityNumbers[label]
      };
    }
  }
};

export function createLogger(destination) {
  return destination ? pino(loggerOptions, destination) : pino(loggerOptions);
}

export const logger = createLogger();

function levelForStatus(status) {
  if (status >= 500) return "error";
  if (status >= 400) return "warn";
  return "info";
}

export function logHttpRequest(targetLogger, { method, path, status, durationMs, error }) {
  if (path === "/health") return;

  const fields = {
    "event.name": "http.server.request.completed",
    "http.request.method": method,
    "url.path": path,
    "http.response.status_code": status,
    duration_ms: durationMs
  };

  if (error) {
    fields["error.type"] = error.name;
    fields["error.message"] = error.message;
  }

  targetLogger[levelForStatus(status)](fields, "http.server.request.completed");
}

export function logException(targetLogger, error, { method, path, status }) {
  targetLogger.error({
    "event.name": "error.exception",
    "http.request.method": method,
    "url.path": path,
    "http.response.status_code": status,
    "error.type": error.name,
    "error.message": error.message,
    "exception.stacktrace": error.stack
  }, "error.exception");
}

export function httpLogger(req, res, next) {
  const startedAt = process.hrtime.bigint();
  res.on("finish", () => {
    const durationMs = Number(process.hrtime.bigint() - startedAt) / 1_000_000;
    logHttpRequest(logger, {
      method: req.method,
      path: req.path,
      status: res.statusCode,
      durationMs: Number(durationMs.toFixed(2)),
      error: res.locals.promptlabError
    });
  });
  next();
}
