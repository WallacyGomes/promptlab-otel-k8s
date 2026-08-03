package com.promptlab.catalog;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;

class StructuredLogTest {
  private static final ObjectMapper JSON = new ObjectMapper();

  @Test
  void httpLogsUseJsonAndExpectedSeverities() throws Exception {
    for (var sample : new Object[][] {
        {200, "INFO", 9},
        {400, "WARN", 13},
        {500, "ERROR", 17},
    }) {
      var status = (int) sample[0];
      var node = JSON.readTree(StructuredLog.httpRequestJson("GET", "/prompts", status, 12.345));

      assertEquals(sample[1], node.get("severity").asText());
      assertEquals(sample[2], node.get("severity_number").asInt());
      assertEquals("http.server.request.completed", node.get("event.name").asText());
      assertEquals(status, node.get("http.response.status_code").asInt());
      assertEquals(12.35, node.get("duration_ms").asDouble());
      assertTrue(node.get("timestamp").asText().endsWith("Z"));
    }
  }

  @Test
  void healthChecksAreNotLogged() {
    assertNull(StructuredLog.httpRequestJson("GET", "/health", 200, 1));
  }

  private static void assertTrue(boolean condition) {
    if (!condition) {
      throw new AssertionError("Expected condition to be true");
    }
  }
}
