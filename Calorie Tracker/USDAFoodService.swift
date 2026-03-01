import Foundation

struct USDAFoodSearchResult: Identifiable, Hashable {
    let fdcId: Int
    let name: String
    let brand: String?
    let calories: Int
    let nutrientValues: [String: Int]
    let servingAmount: Double
    let servingUnit: String
    let servingDescription: String?

    var id: Int { fdcId }
}

enum USDAFoodError: LocalizedError {
    case invalidQuery
    case invalidURL
    case networkFailure
    case fetchFailed(statusCode: Int)
    case invalidPayload
    case noResults

    var errorDescription: String? {
        switch self {
        case .invalidQuery:
            return "Enter a food name to search."
        case .invalidURL:
            return "Could not build the USDA search URL."
        case .networkFailure:
            return "Could not reach USDA FoodData Central. Check your internet connection."
        case let .fetchFailed(statusCode):
            return "USDA search failed (HTTP \(statusCode))."
        case .invalidPayload:
            return "USDA returned malformed food data."
        case .noResults:
            return "No foods matched that search."
        }
    }
}

final class USDAFoodService {
    private struct SearchResponse: Decodable {
        struct Food: Decodable {
            struct FoodNutrient: Decodable {
                let nutrientNumber: String?
                let nutrientName: String?
                let unitName: String?
                let value: Double?
            }

            let fdcId: Int
            let description: String
            let brandOwner: String?
            let brandName: String?
            let servingSize: Double?
            let servingSizeUnit: String?
            let householdServingFullText: String?
            let foodNutrients: [FoodNutrient]?
        }

        let foods: [Food]
    }

    private let apiKey: String

    init(apiKey: String? = nil) {
        let bundledKey = Bundle.main.object(forInfoDictionaryKey: "USDA_API_KEY") as? String
        self.apiKey = apiKey ?? bundledKey ?? "DEMO_KEY"
    }

    func searchFoods(query: String) async throws -> [USDAFoodSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw USDAFoodError.invalidQuery
        }

        guard var components = URLComponents(string: "https://api.nal.usda.gov/fdc/v1/foods/search") else {
            throw USDAFoodError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "query", value: trimmed),
            URLQueryItem(name: "pageSize", value: "15")
        ]
        guard let url = components.url else {
            throw USDAFoodError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw USDAFoodError.networkFailure
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw USDAFoodError.invalidPayload
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw USDAFoodError.fetchFailed(statusCode: httpResponse.statusCode)
        }

        let decoded: SearchResponse
        do {
            decoded = try JSONDecoder().decode(SearchResponse.self, from: data)
        } catch {
            throw USDAFoodError.invalidPayload
        }

        let results = decoded.foods.compactMap(mapFood)
        guard !results.isEmpty else {
            throw USDAFoodError.noResults
        }
        return results
    }

    private func mapFood(_ food: SearchResponse.Food) -> USDAFoodSearchResult? {
        let nutrientValues = mapNutrients(food.foodNutrients ?? [])
        let calories = nutrientValues["calories"] ?? 0

        guard calories > 0 || nutrientValues.contains(where: { $0.key != "calories" && $0.value > 0 }) else {
            return nil
        }

        let servingDescription = food.householdServingFullText?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
        let servingAmount = normalizedServingAmount(food.servingSize, servingDescription: servingDescription)
        let servingUnit = normalizedServingUnit(food.servingSizeUnit, servingDescription: servingDescription)
        let brand = [food.brandOwner, food.brandName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
            .first

        return USDAFoodSearchResult(
            fdcId: food.fdcId,
            name: food.description.trimmingCharacters(in: .whitespacesAndNewlines),
            brand: brand,
            calories: calories,
            nutrientValues: nutrientValues.filter { $0.key != "calories" },
            servingAmount: servingAmount,
            servingUnit: servingUnit,
            servingDescription: servingDescription
        )
    }

    private func normalizedServingAmount(_ servingSize: Double?, servingDescription: String?) -> Double {
        if let servingSize, servingSize > 0 {
            return servingSize
        }
        return servingDescription == nil ? 100.0 : 1.0
    }

    private func normalizedServingUnit(_ unit: String?, servingDescription: String?) -> String {
        let trimmed = unit?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty {
            return trimmed.lowercased()
        }
        return servingDescription == nil ? "g" : "serving"
    }

    private func mapNutrients(_ nutrients: [SearchResponse.Food.FoodNutrient]) -> [String: Int] {
        var mapped: [String: Int] = [:]

        func set(_ key: String, from numbers: Set<String>) {
            guard let value = nutrients.first(where: { numbers.contains($0.nutrientNumber ?? "") })?.value,
                  value >= 0 else {
                return
            }
            mapped[key] = Int(value.rounded())
        }

        set("calories", from: ["208"])
        set("g_protein", from: ["203"])
        set("g_fat", from: ["204"])
        set("g_carbs", from: ["205"])
        set("g_fiber", from: ["291"])
        set("g_sugar", from: ["269"])
        set("mg_calcium", from: ["301"])
        set("mg_iron", from: ["303"])
        set("mg_potassium", from: ["306"])
        set("mg_sodium", from: ["307"])
        set("iu_vitamin_a", from: ["318"])
        set("mcg_vitamin_a", from: ["320"])
        set("mg_vitamin_c", from: ["401"])
        set("mg_cholesterol", from: ["601"])
        set("g_trans_fat", from: ["605"])
        set("g_saturated_fat", from: ["606"])
        set("mcg_vitamin_d", from: ["328"])

        return mapped
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
