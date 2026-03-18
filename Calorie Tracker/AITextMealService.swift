import Foundation

struct AITextMealAnalysisResult: Decodable {
    struct Item: Decodable, Identifiable {
        let id = UUID()
        let name: String
        let brand: String?
        let servingAmount: Double
        let servingUnit: String
        let servingItemsCount: Double?
        let estimatedServings: Double
        let estimatedItemCount: Double?
        let calories: Int
        let protein: Int
        let sourceType: String
        let nutrients: [String: Int]

        enum CodingKeys: String, CodingKey {
            case name
            case brand
            case servingAmount
            case servingUnit
            case servingItemsCount
            case estimatedServings
            case estimatedItemCount
            case calories
            case protein
            case sourceType
            case nutrients
        }
    }

    let items: [Item]
    let rawJson: String?
}

final class AITextMealService {
    private let backendBaseURL: URL
    private let session: URLSession

    init(backendBaseURL: URL? = nil, session: URLSession = .shared) {
        self.backendBaseURL = backendBaseURL ?? URL(string: "https://us-central1-calorie-tracker-364e3.cloudfunctions.net")!
        self.session = session
    }

    func analyze(mealText: String) async throws -> AITextMealAnalysisResult {
        let trimmedText = mealText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            throw AITextMealError.apiError("Enter what you ate.")
        }

        let url = backendBaseURL.appendingPathComponent("analyzeFoodText")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try await BackendRequestAuth.applyHeaders(to: &request)
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "mealText": trimmedText
        ])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AITextMealError.apiError("Invalid response")
        }

        if (200...299).contains(http.statusCode) {
            let decoded = try JSONDecoder().decode(AITextMealAnalysisResult.self, from: data)
            return decoded
        }

        if let errJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let message = errJson["error"] as? String,
           !message.isEmpty {
            throw AITextMealError.apiError(message)
        }

        throw AITextMealError.httpError(http.statusCode)
    }
}

struct AITextMealError: LocalizedError {
    let message: String

    static func apiError(_ message: String) -> AITextMealError {
        AITextMealError(message: message)
    }

    static func httpError(_ code: Int) -> AITextMealError {
        AITextMealError(message: "HTTP \(code)")
    }

    var errorDescription: String? { message }
}
