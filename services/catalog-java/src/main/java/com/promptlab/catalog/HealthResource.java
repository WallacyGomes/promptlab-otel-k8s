package com.promptlab.catalog;

import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import java.util.Map;

@Path("/health")
public class HealthResource {
  @GET
  public Map<String, String> health() {
    return Map.of("status", "ok", "service", "catalog-java");
  }
}
