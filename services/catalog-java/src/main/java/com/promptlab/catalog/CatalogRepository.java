package com.promptlab.catalog;

import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import java.sql.Array;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.ArrayList;
import java.util.List;
import javax.sql.DataSource;

@ApplicationScoped
public class CatalogRepository {
  @Inject
  DataSource dataSource;

  public List<Category> categories() throws SQLException {
    var sql = "SELECT id, name, slug, description FROM categories ORDER BY name";
    try (var connection = dataSource.getConnection();
        var statement = connection.prepareStatement(sql);
        var rs = statement.executeQuery()) {
      var items = new ArrayList<Category>();
      while (rs.next()) {
        items.add(new Category(
            rs.getInt("id"),
            rs.getString("name"),
            rs.getString("slug"),
            rs.getString("description")));
      }
      return items;
    }
  }

  public List<Prompt> prompts(Integer categoryId, String query) throws SQLException {
    var where = new StringBuilder("WHERE p.active = true");
    var params = new ArrayList<Object>();
    if (categoryId != null) {
      where.append(" AND p.category_id = ?");
      params.add(categoryId);
    }
    if (query != null && !query.isBlank()) {
      where.append(" AND (p.title ILIKE ? OR p.description ILIKE ? OR EXISTS (SELECT 1 FROM unnest(p.tags) tag WHERE tag ILIKE ?))");
      var pattern = "%" + query.trim() + "%";
      params.add(pattern);
      params.add(pattern);
      params.add(pattern);
    }

    var sql = """
        SELECT p.id, p.category_id, c.name AS category_name, p.title, p.description,
               p.prompt_text, p.price_cents, p.tags
        FROM prompts p
        JOIN categories c ON c.id = p.category_id
        %s
        ORDER BY p.created_at DESC, p.id DESC
        """.formatted(where);

    try (var connection = dataSource.getConnection();
        var statement = connection.prepareStatement(sql)) {
      for (var i = 0; i < params.size(); i++) {
        statement.setObject(i + 1, params.get(i));
      }
      try (var rs = statement.executeQuery()) {
        var items = new ArrayList<Prompt>();
        while (rs.next()) {
          items.add(mapPrompt(rs));
        }
        return items;
      }
    }
  }

  public Prompt prompt(int id) throws SQLException {
    var sql = """
        SELECT p.id, p.category_id, c.name AS category_name, p.title, p.description,
               p.prompt_text, p.price_cents, p.tags
        FROM prompts p
        JOIN categories c ON c.id = p.category_id
        WHERE p.active = true AND p.id = ?
        """;
    try (var connection = dataSource.getConnection();
        var statement = connection.prepareStatement(sql)) {
      statement.setInt(1, id);
      try (var rs = statement.executeQuery()) {
        return rs.next() ? mapPrompt(rs) : null;
      }
    }
  }

  private Prompt mapPrompt(ResultSet rs) throws SQLException {
    return new Prompt(
        rs.getInt("id"),
        rs.getInt("category_id"),
        rs.getString("category_name"),
        rs.getString("title"),
        rs.getString("description"),
        rs.getString("prompt_text"),
        rs.getInt("price_cents"),
        toList(rs.getArray("tags")));
  }

  private List<String> toList(Array sqlArray) throws SQLException {
    if (sqlArray == null) {
      return List.of();
    }
    var values = (String[]) sqlArray.getArray();
    return List.of(values);
  }
}
