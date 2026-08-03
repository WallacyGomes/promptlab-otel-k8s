package com.promptlab.catalog;

import static io.restassured.RestAssured.given;
import static org.hamcrest.Matchers.equalTo;

import io.quarkus.test.junit.QuarkusTest;
import org.junit.jupiter.api.Test;

@QuarkusTest
class CatalogResourceTest {
  @Test
  void healthReturnsOk() {
    given()
        .when().get("/health")
        .then()
        .statusCode(200)
        .body("status", equalTo("ok"));
  }

  @Test
  void labStatusIsGatedAndReturnsControlledErrors() {
    var previous = System.getProperty("LAB_MODE");
    try {
      System.setProperty("LAB_MODE", "false");
      given().when().get("/lab/status/400").then().statusCode(404);

      System.setProperty("LAB_MODE", "true");
      given().when().get("/lab/status/400").then().statusCode(400);
      given().when().get("/lab/status/500").then().statusCode(500);
    } finally {
      if (previous == null) {
        System.clearProperty("LAB_MODE");
      } else {
        System.setProperty("LAB_MODE", previous);
      }
    }
  }
}
