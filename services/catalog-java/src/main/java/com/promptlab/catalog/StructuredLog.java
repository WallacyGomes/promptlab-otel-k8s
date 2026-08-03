package com.promptlab.catalog;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.Map;
import org.jboss.logging.Logger;

final class StructuredLog {
  private static final ObjectMapper JSON = new ObjectMapper();
  private static final Logger LOG = Logger.getLogger(StructuredLog.class);

  private StructuredLog() {}

  static void httpRequest(String method, String path, int status, double durationMs) {
    if ("/health".equals(path)) {
      return;
    }

    var fields = new LinkedHashMap<String, Object>();
    fields.put("timestamp", Instant.now().toString());
    fields.put("severity", severity(status));
    fields.put("severity_number", severityNumber(status));
    fields.put("message", "http.server.request.completed");
    fields.put("event.name", "http.server.request.completed");
    fields.put("http.request.method", method);
    fields.put("url.path", path);
    fields.put("http.response.status_code", status);
    fields.put("duration_ms", Math.round(durationMs * 100.0) / 100.0);
    log(status, toJson(fields));
  }

  static String httpRequestJson(String method, String path, int status, double durationMs) {
    if ("/health".equals(path)) {
      return null;
    }

    var fields = new LinkedHashMap<String, Object>();
    fields.put("timestamp", Instant.now().toString());
    fields.put("severity", severity(status));
    fields.put("severity_number", severityNumber(status));
    fields.put("message", "http.server.request.completed");
    fields.put("event.name", "http.server.request.completed");
    fields.put("http.request.method", method);
    fields.put("url.path", path);
    fields.put("http.response.status_code", status);
    fields.put("duration_ms", Math.round(durationMs * 100.0) / 100.0);
    return toJson(fields);
  }

  private static void log(int status, String message) {
    if (status >= 500) {
      LOG.error(message);
    } else if (status >= 400) {
      LOG.warn(message);
    } else {
      LOG.info(message);
    }
  }

  private static String severity(int status) {
    if (status >= 500) {
      return "ERROR";
    }
    if (status >= 400) {
      return "WARN";
    }
    return "INFO";
  }

  private static int severityNumber(int status) {
    if (status >= 500) {
      return 17;
    }
    if (status >= 400) {
      return 13;
    }
    return 9;
  }

  private static String toJson(Map<String, Object> fields) {
    try {
      return JSON.writeValueAsString(fields);
    } catch (JsonProcessingException error) {
      throw new IllegalStateException("Unable to serialize structured log", error);
    }
  }
}
