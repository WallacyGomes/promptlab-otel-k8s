import assert from "node:assert/strict";
import test from "node:test";
import { PassThrough } from "node:stream";

import request from "supertest";

import { createApp } from "../src/app.js";
import { createLogger, logHttpRequest } from "../src/logging.js";

function capturedLog(run) {
  const stream = new PassThrough();
  let output = "";
  stream.on("data", (chunk) => {
    output += chunk.toString();
  });
  const testLogger = createLogger(stream);
  run(testLogger);
  return output.trim().split("\n").filter(Boolean).map((line) => JSON.parse(line));
}

test("health endpoint returns ok", async () => {
  const response = await request(createApp()).get("/health");

  assert.equal(response.status, 200);
  assert.equal(response.body.status, "ok");
});

test("lab status endpoint is gated and returns controlled errors", async () => {
  const previous = process.env.LAB_MODE;
  try {
    process.env.LAB_MODE = "false";
    assert.equal((await request(createApp()).get("/lab/status/400")).status, 404);

    process.env.LAB_MODE = "true";
    assert.equal((await request(createApp()).get("/lab/status/400")).status, 400);
    assert.equal((await request(createApp()).get("/lab/status/500")).status, 500);
  } finally {
    if (previous === undefined) {
      delete process.env.LAB_MODE;
    } else {
      process.env.LAB_MODE = previous;
    }
  }
});

test("http logs are JSON, use the expected severity and skip health checks", () => {
  const records = capturedLog((testLogger) => {
    logHttpRequest(testLogger, { method: "GET", path: "/health", status: 200, durationMs: 1 });
    logHttpRequest(testLogger, { method: "GET", path: "/api/prompts", status: 200, durationMs: 1.2 });
    logHttpRequest(testLogger, { method: "GET", path: "/lab/status/400", status: 400, durationMs: 2.3 });
    logHttpRequest(testLogger, { method: "GET", path: "/lab/status/500", status: 500, durationMs: 3.4 });
  });

  assert.equal(records.length, 3);
  assert.deepEqual(records.map((record) => record.severity), ["INFO", "WARN", "ERROR"]);
  assert.deepEqual(records.map((record) => record.severity_number), [9, 13, 17]);
  for (const record of records) {
    assert.match(record.timestamp, /^\d{4}-\d{2}-\d{2}T/);
    assert.equal(record["event.name"], "http.server.request.completed");
    assert.equal(record.message, "http.server.request.completed");
    assert.equal(typeof record["http.response.status_code"], "number");
    assert.equal(record.remoteAddress, undefined);
  }
});
