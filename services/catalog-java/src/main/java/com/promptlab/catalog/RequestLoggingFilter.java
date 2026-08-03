package com.promptlab.catalog;

import jakarta.ws.rs.container.ContainerRequestContext;
import jakarta.ws.rs.container.ContainerRequestFilter;
import jakarta.ws.rs.container.ContainerResponseContext;
import jakarta.ws.rs.container.ContainerResponseFilter;
import jakarta.ws.rs.ext.Provider;
import java.io.IOException;

@Provider
public class RequestLoggingFilter implements ContainerRequestFilter, ContainerResponseFilter {
  private static final String STARTED_AT = "promptlab.request.startedAt";

  @Override
  public void filter(ContainerRequestContext requestContext) throws IOException {
    requestContext.setProperty(STARTED_AT, System.nanoTime());
  }

  @Override
  public void filter(ContainerRequestContext requestContext, ContainerResponseContext responseContext)
      throws IOException {
    var startedAt = requestContext.getProperty(STARTED_AT);
    var durationMs = 0.0;
    if (startedAt instanceof Long startedAtNanos) {
      durationMs = (System.nanoTime() - startedAtNanos) / 1_000_000.0;
    }

    var method = requestContext.getMethod();
    var rawPath = requestContext.getUriInfo().getPath();
    var path = rawPath.startsWith("/") ? rawPath : "/" + rawPath;
    var status = responseContext.getStatus();

    StructuredLog.httpRequest(method, path, status, durationMs);
  }
}
