package com.promptlab.catalog;

import jakarta.inject.Inject;
import jakarta.ws.rs.BadRequestException;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.InternalServerErrorException;
import jakarta.ws.rs.NotFoundException;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.Response;
import java.sql.SQLException;
import java.util.List;
import java.util.Map;

@Path("/")
public class CatalogResource {
  @Inject
  CatalogRepository repository;

  @GET
  @Path("/categories")
  public List<Category> categories() throws SQLException {
    return repository.categories();
  }

  @GET
  @Path("/prompts")
  public List<Prompt> prompts(@QueryParam("categoryId") Integer categoryId, @QueryParam("q") String query)
      throws SQLException {
    return repository.prompts(categoryId, query);
  }

  @GET
  @Path("/prompts/{id}")
  public Prompt prompt(@PathParam("id") int id) throws SQLException {
    var prompt = repository.prompt(id);
    if (prompt == null) {
      throw new NotFoundException("Prompt not found");
    }
    return prompt;
  }

  @GET
  @Path("/lab/status/{code}")
  public Response labStatus(@PathParam("code") int code) {
    var enabled = Boolean.parseBoolean(
        System.getProperty("LAB_MODE", System.getenv().getOrDefault("LAB_MODE", "false")));
    if (!enabled) {
      throw new NotFoundException();
    }
    if (code == 400) {
      return Response.status(Response.Status.BAD_REQUEST)
          .entity(Map.of("error", "Synthetic lab bad request"))
          .build();
    }
    if (code == 500) {
      throw new InternalServerErrorException("Synthetic lab internal error");
    }
    throw new BadRequestException("Only status codes 400 and 500 are supported");
  }
}
