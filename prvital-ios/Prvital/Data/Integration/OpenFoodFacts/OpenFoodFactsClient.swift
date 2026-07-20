import Foundation

/// A normalized food looked up from Open Food Facts — the fields Prvital needs to
/// log carbs, with everything but the name and carbohydrate figure optional.
struct OpenFoodFactsProduct: Sendable, Equatable, Identifiable {
    var barcode: String?
    var name: String
    var brand: String?
    var carbsPer100g: Double
    var fiberPer100g: Double?
    var sugarsPer100g: Double?
    var proteinPer100g: Double?
    var fatPer100g: Double?
    var energyKcalPer100g: Double?
    var servingSizeGrams: Double?

    var id: String { barcode ?? name }
}

/// Reads food nutrition from the public Open Food Facts database. On-demand and
/// UI-triggered (not part of the periodic glucose sync), so it is a plain value
/// type mirroring the other integration clients: build a request, validate the
/// response, decode. No API key is required.
struct OpenFoodFactsClient: Sendable {
    var baseURL = URL(string: "https://world.openfoodfacts.org")!

    /// Looks up a single product by its barcode. Returns nil when the barcode is
    /// unknown or the product carries no usable carbohydrate figure.
    func product(barcode: String) async throws -> OpenFoodFactsProduct? {
        let trimmed = barcode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent("api/v2/product/\(trimmed).json"),
            resolvingAgainstBaseURL: false
        ) else { throw SourceError.underlying("Invalid Open Food Facts URL.") }
        components.queryItems = [URLQueryItem(name: "fields", value: Self.fields)]
        guard let url = components.url else { throw SourceError.underlying("Invalid Open Food Facts URL.") }

        let response: OFFProductResponse = try await get(url)
        guard response.status == 1, let dto = response.product else { return nil }
        return OpenFoodFactsParsing.product(from: dto, fallbackBarcode: trimmed)
    }

    /// Searches foods by name, returning those with a usable carbohydrate figure.
    func search(name: String, pageSize: Int = 20) async throws -> [OpenFoodFactsProduct] {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent("cgi/search.pl"),
            resolvingAgainstBaseURL: false
        ) else { throw SourceError.underlying("Invalid Open Food Facts URL.") }
        components.queryItems = [
            URLQueryItem(name: "search_terms", value: trimmed),
            URLQueryItem(name: "search_simple", value: "1"),
            URLQueryItem(name: "action", value: "process"),
            URLQueryItem(name: "json", value: "1"),
            URLQueryItem(name: "page_size", value: String(max(1, min(pageSize, 50)))),
            URLQueryItem(name: "fields", value: Self.fields),
        ]
        guard let url = components.url else { throw SourceError.underlying("Invalid Open Food Facts URL.") }

        let response: OFFSearchResponse = try await get(url)
        return OpenFoodFactsParsing.products(from: response)
    }

    private static let fields = "code,product_name,brands,serving_quantity,nutriments"

    private func get<T: Decodable>(_ url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // Open Food Facts asks callers to identify themselves via User-Agent.
        request.setValue("Prvital - iOS - diabetes journal", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SourceError.underlying("No response from Open Food Facts.")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw SourceError.underlying("Open Food Facts returned HTTP \(http.statusCode).")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

// MARK: - Wire types

/// Open Food Facts is loose with types — a number may arrive as a JSON number or
/// as a string. This decodes either into a Double.
struct OFFDouble: Decodable, Sendable {
    let value: Double?
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = Double(string.replacingOccurrences(of: ",", with: "."))
        } else {
            value = nil
        }
    }
}

struct OFFNutriments: Decodable, Sendable {
    let carbs: OFFDouble?
    let fiber: OFFDouble?
    let sugars: OFFDouble?
    let proteins: OFFDouble?
    let fat: OFFDouble?
    let energyKcal: OFFDouble?

    enum CodingKeys: String, CodingKey {
        case carbs = "carbohydrates_100g"
        case fiber = "fiber_100g"
        case sugars = "sugars_100g"
        case proteins = "proteins_100g"
        case fat = "fat_100g"
        case energyKcal = "energy-kcal_100g"
    }
}

struct OFFProduct: Decodable, Sendable {
    let code: String?
    let productName: String?
    let brands: String?
    let servingQuantity: OFFDouble?
    let nutriments: OFFNutriments?

    enum CodingKeys: String, CodingKey {
        case code
        case productName = "product_name"
        case brands
        case servingQuantity = "serving_quantity"
        case nutriments
    }
}

struct OFFProductResponse: Decodable, Sendable {
    let status: Int?
    let code: String?
    let product: OFFProduct?
}

struct OFFSearchResponse: Decodable, Sendable {
    let products: [OFFProduct]?
}

// MARK: - Parsing

/// Pure mapping from Open Food Facts wire types to `OpenFoodFactsProduct`, kept
/// separate so it can be unit-tested against literal JSON payloads.
enum OpenFoodFactsParsing {

    /// Maps a decoded product, requiring a name and a carbohydrate figure (a food
    /// with no carbs data can't be used to log carbs). `fallbackBarcode` fills in
    /// when the payload omits the code.
    static func product(from dto: OFFProduct, fallbackBarcode: String?) -> OpenFoodFactsProduct? {
        let name = dto.productName?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let name, !name.isEmpty else { return nil }
        guard let carbs = dto.nutriments?.carbs?.value, carbs >= 0 else { return nil }

        let brand = dto.brands?
            .split(separator: ",").first
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .flatMap { $0.isEmpty ? nil : $0 }

        return OpenFoodFactsProduct(
            barcode: dto.code ?? fallbackBarcode,
            name: name,
            brand: brand,
            carbsPer100g: carbs,
            fiberPer100g: dto.nutriments?.fiber?.value,
            sugarsPer100g: dto.nutriments?.sugars?.value,
            proteinPer100g: dto.nutriments?.proteins?.value,
            fatPer100g: dto.nutriments?.fat?.value,
            energyKcalPer100g: dto.nutriments?.energyKcal?.value,
            servingSizeGrams: dto.servingQuantity?.value
        )
    }

    static func products(from response: OFFSearchResponse) -> [OpenFoodFactsProduct] {
        (response.products ?? []).compactMap { product(from: $0, fallbackBarcode: nil) }
    }
}
