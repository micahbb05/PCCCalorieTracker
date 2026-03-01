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
    private struct SearchRequestErrorResponse: Decodable {
        let error: String?
    }

    private struct SearchResponse: Decodable {
        struct Food: Decodable {
            let fdcId: Int
            let name: String
            let brand: String?
            let calories: Int
            let nutrientValues: [String: Int]
            let servingAmount: Double
            let servingUnit: String
            let servingDescription: String?
        }

        let foods: [Food]
    }

    private let backendBaseURL: URL

    init(backendBaseURL: URL? = nil) {
        self.backendBaseURL = backendBaseURL ?? URL(string: "https://us-central1-calorie-tracker-364e3.cloudfunctions.net")!
    }

    func searchFoods(query: String) async throws -> [USDAFoodSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw USDAFoodError.invalidQuery
        }

        guard var components = URLComponents(url: backendBaseURL.appendingPathComponent("searchUSDAFoods"), resolvingAgainstBaseURL: false) else {
            throw USDAFoodError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "query", value: trimmed)
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
            if let decodedError = try? JSONDecoder().decode(SearchRequestErrorResponse.self, from: data),
               let message = decodedError.error?.trimmingCharacters(in: .whitespacesAndNewlines),
               !message.isEmpty {
                throw NSError(domain: "USDAFoodService", code: httpResponse.statusCode, userInfo: [
                    NSLocalizedDescriptionKey: message
                ])
            }
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
        let nutrientValues = food.nutrientValues
        let calories = max(food.calories, 0)

        guard calories > 0 || nutrientValues.contains(where: { $0.key != "calories" && $0.value > 0 }) else {
            return nil
        }

        return USDAFoodSearchResult(
            fdcId: food.fdcId,
            name: food.name.trimmingCharacters(in: .whitespacesAndNewlines),
            brand: food.brand?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            calories: calories,
            nutrientValues: nutrientValues.filter { $0.key != "calories" },
            servingAmount: max(food.servingAmount, 0),
            servingUnit: food.servingUnit.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            servingDescription: food.servingDescription?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        )
    }

}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
