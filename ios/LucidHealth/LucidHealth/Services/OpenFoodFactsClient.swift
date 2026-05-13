import Foundation

enum OpenFoodFactsError: LocalizedError {
    case notFound
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .notFound: return "Product not found in Open Food Facts database."
        case .networkError(let e): return e.localizedDescription
        }
    }
}

struct OpenFoodFactsProduct: Codable {
    var productName: String?
    var brand: String?
    var imageURL: String?
    var kcalPer100g: Double?
    var novaGroup: Int?
    var ingredientsText: String?
    var nutriscore: String?
    var servingSizeG: Int?
}

private struct OFFResponse: Decodable {
    let status: Int
    let product: OFFProduct?
}

private struct OFFProduct: Decodable {
    let product_name: String?
    let brands: String?
    let image_url: String?
    let nova_group: Int?
    let ingredients_text: String?
    let nutriscore_grade: String?
    let serving_size: String?
    let nutriments: OFFNutriments?
}

private struct OFFNutriments: Decodable {
    let energy_kcal_100g: Double?

    enum CodingKeys: String, CodingKey {
        case energy_kcal_100g = "energy-kcal_100g"
    }
}

struct OpenFoodFactsClient {
    static let shared = OpenFoodFactsClient()

    /// Try the world DB first, then de.openfoodfacts.org as a fallback.
    /// Same database, but the German subdomain biases the response toward
    /// German-product matches and sometimes returns hits that the world
    /// endpoint misses for store-brand / Aldi / Lidl SKUs.
    func lookup(barcode: String) async throws -> OpenFoodFactsProduct {
        do {
            return try await fetch(barcode: barcode, host: "world.openfoodfacts.org")
        } catch OpenFoodFactsError.notFound {
            LucidLog.log("Barcode", "world miss for \(barcode), trying de.openfoodfacts.org")
            return try await fetch(barcode: barcode, host: "de.openfoodfacts.org")
        }
    }

    private func fetch(barcode: String, host: String) async throws -> OpenFoodFactsProduct {
        let url = URL(string: "https://\(host)/api/v2/product/\(barcode).json")!
        let (data, _) = try await URLSession.shared.data(from: url)

        let resp = try JSONDecoder().decode(OFFResponse.self, from: data)
        guard resp.status == 1, let p = resp.product else {
            throw OpenFoodFactsError.notFound
        }

        // Parse serving size (e.g. "30 g" or "30g") to Int
        var servingGrams: Int? = nil
        if let raw = p.serving_size {
            let digits = raw.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
            servingGrams = Int(digits)
        }

        LucidLog.log("Barcode", "hit on \(host) for \(barcode): \(p.product_name ?? "no name")")

        return OpenFoodFactsProduct(
            productName: p.product_name,
            brand: p.brands,
            imageURL: p.image_url,
            kcalPer100g: p.nutriments?.energy_kcal_100g,
            novaGroup: p.nova_group,
            ingredientsText: p.ingredients_text,
            nutriscore: p.nutriscore_grade?.uppercased(),
            servingSizeG: servingGrams
        )
    }
}
