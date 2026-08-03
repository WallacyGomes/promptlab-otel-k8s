package com.promptlab.catalog;

import java.util.List;

public record Prompt(
    int id,
    int categoryId,
    String categoryName,
    String title,
    String description,
    String promptText,
    int priceCents,
    List<String> tags) {
}
