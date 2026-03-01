import Foundation

struct OpenFoodFactsProduct {
    let barcode: String
    let name: String
    let calories: Int
    let nutrientValues: [String: Int]
    let servingAmount: Double
    let servingUnit: String
    let servingDescription: String?
    let imageURL: URL?
}

enum OpenFoodFactsError: LocalizedError {
    case invalidBarcode
    case invalidURL
    case networkFailure
    case fetchFailed(statusCode: Int)
    case invalidPayload
    case productNotFound
    case productMissingNutrition

    var errorDescription: String? {
        switch self {
        case .invalidBarcode:
            return "That barcode is not valid."
        case .invalidURL:
            return "Could not build the barcode lookup URL."
        case .networkFailure:
            return "Could not reach Open Food Facts. Check your internet connection."
        case let .fetchFailed(statusCode):
            return "Open Food Facts lookup failed (HTTP \(statusCode))."
        case .invalidPayload:
            return "Open Food Facts returned malformed product data."
        case .productNotFound:
            return "That barcode was not found in Open Food Facts."
        case .productMissingNutrition:
            return "That product does not include enough nutrition data to autofill."
        }
    }
}

final class OpenFoodFactsService {
    private struct ProductResponse: Decodable {
        struct Product: Decodable {
            struct Nutriments: Decodable {
                struct DynamicCodingKeys: CodingKey {
                    let stringValue: String
                    init?(stringValue: String) { self.stringValue = stringValue }
                    let intValue: Int? = nil
                    init?(intValue: Int) { return nil }
                }

                let values: [String: Double]

                init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: DynamicCodingKeys.self)
                    var values: [String: Double] = [:]

                    for key in container.allKeys {
                        if let value = try? container.decode(Double.self, forKey: key) {
                            values[key.stringValue] = value
                        } else if let intValue = try? container.decode(Int.self, forKey: key) {
                            values[key.stringValue] = Double(intValue)
                        } else if let stringValue = try? container.decode(String.self, forKey: key),
                                  let numeric = Double(stringValue) {
                            values[key.stringValue] = numeric
                        }
                    }

                    self.values = values
                }
            }

            let productName: String?
            let genericName: String?
            let nutriments: Nutriments?
            let servingQuantity: Double?
            let servingQuantityUnit: String?
            let servingSize: String?
            let imageFrontSmallURL: String?
            let imageFrontURL: String?

            enum CodingKeys: String, CodingKey {
                case productName = "product_name"
                case genericName = "generic_name"
                case nutriments
                case servingQuantity = "serving_quantity"
                case servingQuantityUnit = "serving_quantity_unit"
                case servingSize = "serving_size"
                case imageFrontSmallURL = "image_front_small_url"
                case imageFrontURL = "image_front_url"
            }
        }

        let code: String?
        let status: Int?
        let product: Product?
    }

    func fetchProduct(for barcode: String) async throws -> OpenFoodFactsProduct {
        let normalizedBarcode = barcode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedBarcode.isEmpty else {
            throw OpenFoodFactsError.invalidBarcode
        }

        let fields = [
            "code",
            "product_name",
            "generic_name",
            "serving_quantity",
            "serving_quantity_unit",
            "serving_size",
            "image_front_small_url",
            "image_front_url",
            "nutriments"
        ].joined(separator: ",")

        guard var components = URLComponents(string: "https://world.openfoodfacts.org/api/v2/product/\(normalizedBarcode)") else {
            throw OpenFoodFactsError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "fields", value: fields)
        ]
        guard let url = components.url else {
            throw OpenFoodFactsError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("CalorieTracker/1.0 (micahbb05@icloud.com)", forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw OpenFoodFactsError.networkFailure
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenFoodFactsError.invalidPayload
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw OpenFoodFactsError.fetchFailed(statusCode: httpResponse.statusCode)
        }

        let decoded: ProductResponse
        do {
            decoded = try JSONDecoder().decode(ProductResponse.self, from: data)
        } catch {
            throw OpenFoodFactsError.invalidPayload
        }

        guard decoded.status == 1, let product = decoded.product else {
            throw OpenFoodFactsError.productNotFound
        }

        let name = [product.productName, product.genericName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? "Scanned food"

        let servingQuantity = normalizedServingAmount(from: product.servingQuantity)
        let servingUnit = normalizedServingUnit(from: product.servingQuantityUnit)
        let servingDescription = product.servingSize?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
        let mappedNutrients = mapNutrients(
            from: product.nutriments?.values ?? [:],
            preferServingValues: servingDescription != nil || product.servingQuantity != nil
        )
        let calories = mappedNutrients["calories"] ?? 0

        guard calories > 0 || mappedNutrients.contains(where: { $0.key != "calories" && $0.value > 0 }) else {
            throw OpenFoodFactsError.productMissingNutrition
        }

        return OpenFoodFactsProduct(
            barcode: decoded.code ?? normalizedBarcode,
            name: name,
            calories: calories,
            nutrientValues: mappedNutrients.filter { $0.key != "calories" },
            servingAmount: servingQuantity,
            servingUnit: servingUnit,
            servingDescription: servingDescription,
            imageURL: URL(string: product.imageFrontSmallURL ?? product.imageFrontURL ?? "")
        )
    }

    private func mapNutrients(from nutriments: [String: Double], preferServingValues: Bool) -> [String: Int] {
        var mapped: [String: Int] = [:]

        func value(for candidates: [String]) -> Double? {
            for key in candidates {
                if let value = nutriments[key], value >= 0 {
                    return value
                }
            }
            return nil
        }

        func set(_ key: String, value: Double?, multiplier: Double = 1.0) {
            guard let value, value >= 0 else { return }
            mapped[key] = Int((value * multiplier).rounded())
        }

        func candidates(_ serving: String, _ perHundred: String, _ base: String) -> [String] {
            preferServingValues ? [serving, perHundred, base] : [perHundred, base, serving]
        }

        set("calories", value: value(for: candidates("energy-kcal_serving", "energy-kcal_100g", "energy-kcal")))
        set("g_protein", value: value(for: candidates("proteins_serving", "proteins_100g", "proteins")))
        set("g_carbs", value: value(for: candidates("carbohydrates_serving", "carbohydrates_100g", "carbohydrates")))
        set("g_fat", value: value(for: candidates("fat_serving", "fat_100g", "fat")))
        set("g_saturated_fat", value: value(for: candidates("saturated-fat_serving", "saturated-fat_100g", "saturated-fat")))
        set("g_trans_fat", value: value(for: candidates("trans-fat_serving", "trans-fat_100g", "trans-fat")))
        set("g_fiber", value: value(for: candidates("fiber_serving", "fiber_100g", "fiber")))
        set("g_sugar", value: value(for: candidates("sugars_serving", "sugars_100g", "sugars")))
        set("g_added_sugar", value: value(for: candidates("added-sugars_serving", "added-sugars_100g", "added-sugars")))
        set("mg_sodium", value: value(for: candidates("sodium_serving", "sodium_100g", "sodium")), multiplier: 1000)
        set("mg_cholesterol", value: value(for: candidates("cholesterol_serving", "cholesterol_100g", "cholesterol")))
        set("mg_potassium", value: value(for: candidates("potassium_serving", "potassium_100g", "potassium")))
        set("mg_calcium", value: value(for: candidates("calcium_serving", "calcium_100g", "calcium")))
        set("mg_iron", value: value(for: candidates("iron_serving", "iron_100g", "iron")))
        set("mg_vitamin_c", value: value(for: candidates("vitamin-c_serving", "vitamin-c_100g", "vitamin-c")))
        set("mcg_vitamin_a", value: value(for: candidates("vitamin-a_serving", "vitamin-a_100g", "vitamin-a")))
        set("mcg_vitamin_d", value: value(for: candidates("vitamin-d_serving", "vitamin-d_100g", "vitamin-d")))

        return mapped
    }

    private func normalizedServingAmount(from value: Double?) -> Double {
        guard let value, value > 0 else { return 1.0 }
        return value
    }

    private func normalizedServingUnit(from value: String?) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "serving" : trimmed
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
