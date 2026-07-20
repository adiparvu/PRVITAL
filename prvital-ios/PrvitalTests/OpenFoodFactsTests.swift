import XCTest
@testable import Prvital

final class OpenFoodFactsTests: XCTestCase {

    private func decodeProduct(_ json: String) throws -> OFFProductResponse {
        try JSONDecoder().decode(OFFProductResponse.self, from: Data(json.utf8))
    }

    func testParsesNumericNutriments() throws {
        let json = """
        {
          "status": 1,
          "code": "12345",
          "product": {
            "product_name": "Oat biscuits",
            "brands": "Acme, Other",
            "serving_quantity": 30,
            "nutriments": {
              "carbohydrates_100g": 62.5,
              "fiber_100g": 6,
              "sugars_100g": 20,
              "proteins_100g": 8,
              "fat_100g": 14,
              "energy-kcal_100g": 450
            }
          }
        }
        """
        let response = try decodeProduct(json)
        let product = OpenFoodFactsParsing.product(from: try XCTUnwrap(response.product), fallbackBarcode: "12345")
        let p = try XCTUnwrap(product)
        XCTAssertEqual(p.name, "Oat biscuits")
        XCTAssertEqual(p.brand, "Acme") // first brand only
        XCTAssertEqual(p.carbsPer100g, 62.5, accuracy: 1e-6)
        XCTAssertEqual(p.fiberPer100g ?? 0, 6, accuracy: 1e-6)
        XCTAssertEqual(p.servingSizeGrams ?? 0, 30, accuracy: 1e-6)
        XCTAssertEqual(p.energyKcalPer100g ?? 0, 450, accuracy: 1e-6)
    }

    func testParsesStringNutriments() throws {
        // Open Food Facts sometimes returns numbers as strings.
        let json = """
        {
          "status": 1,
          "product": {
            "product_name": "Juice",
            "serving_quantity": "250",
            "nutriments": { "carbohydrates_100g": "10.5" }
          }
        }
        """
        let response = try decodeProduct(json)
        let p = try XCTUnwrap(OpenFoodFactsParsing.product(from: try XCTUnwrap(response.product), fallbackBarcode: "9"))
        XCTAssertEqual(p.carbsPer100g, 10.5, accuracy: 1e-6)
        XCTAssertEqual(p.servingSizeGrams ?? 0, 250, accuracy: 1e-6)
        XCTAssertEqual(p.barcode, "9") // fallback used when code missing
    }

    func testRejectsProductWithoutCarbs() throws {
        let json = """
        { "status": 1, "product": { "product_name": "Water", "nutriments": {} } }
        """
        let response = try decodeProduct(json)
        XCTAssertNil(OpenFoodFactsParsing.product(from: try XCTUnwrap(response.product), fallbackBarcode: nil))
    }

    func testRejectsProductWithoutName() throws {
        let json = """
        { "status": 1, "product": { "nutriments": { "carbohydrates_100g": 5 } } }
        """
        let response = try decodeProduct(json)
        XCTAssertNil(OpenFoodFactsParsing.product(from: try XCTUnwrap(response.product), fallbackBarcode: nil))
    }

    func testSearchFiltersUnusableProducts() throws {
        let json = """
        {
          "products": [
            { "product_name": "Bread", "nutriments": { "carbohydrates_100g": 45 } },
            { "product_name": "Water", "nutriments": {} },
            { "nutriments": { "carbohydrates_100g": 5 } }
          ]
        }
        """
        let response = try JSONDecoder().decode(OFFSearchResponse.self, from: Data(json.utf8))
        let products = OpenFoodFactsParsing.products(from: response)
        XCTAssertEqual(products.count, 1)
        XCTAssertEqual(products.first?.name, "Bread")
    }

    func testNotFoundStatusHasNilProduct() throws {
        let json = """
        { "status": 0, "code": "0000", "product": null }
        """
        let response = try decodeProduct(json)
        XCTAssertEqual(response.status, 0)
        XCTAssertNil(response.product)
    }
}
