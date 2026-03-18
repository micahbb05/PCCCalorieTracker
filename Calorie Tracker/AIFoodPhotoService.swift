import Foundation

struct AIFoodPhotoAnalysisResult: Decodable {
    enum SourceType: String, Decodable {
        case real
        case estimated
    }

    enum Mode: String, Decodable {
        case foodPhoto = "food_photo"
        case nutritionLabel = "nutrition_label"
    }

    struct Item: Decodable, Identifiable {
        let id = UUID()
        let name: String
        let servingAmount: Double
        let servingUnit: String
        let servingItemsCount: Double?
        let estimatedServings: Double
        let estimatedItemCount: Double?
        let calories: Int
        let protein: Int
        let sourceType: SourceType
        let nutrients: [String: Int]

        enum CodingKeys: String, CodingKey {
            case name
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

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decode(String.self, forKey: .name)
            servingAmount = try container.decode(Double.self, forKey: .servingAmount)
            servingUnit = try container.decode(String.self, forKey: .servingUnit)
            servingItemsCount = try container.decodeIfPresent(Double.self, forKey: .servingItemsCount)
            estimatedServings = try container.decode(Double.self, forKey: .estimatedServings)
            estimatedItemCount = try container.decodeIfPresent(Double.self, forKey: .estimatedItemCount)
            calories = try container.decode(Int.self, forKey: .calories)
            protein = try container.decode(Int.self, forKey: .protein)
            sourceType = try container.decodeIfPresent(SourceType.self, forKey: .sourceType) ?? .estimated
            nutrients = try container.decode([String: Int].self, forKey: .nutrients)
        }
    }

    let mode: Mode
    let items: [Item]
    let rawJson: String?
}

final class AIFoodPhotoService {
    private let backendBaseURL: URL
    private let session: URLSession

    init(backendBaseURL: URL? = nil, session: URLSession = .shared) {
        self.backendBaseURL = backendBaseURL ?? URL(string: "https://us-central1-calorie-tracker-364e3.cloudfunctions.net")!
        self.session = session
    }

    func analyze(imageData: Data) async throws -> AIFoodPhotoAnalysisResult {
        let base64 = imageData.base64EncodedString()
        let mimeType = imageData.count >= 8 && imageData[0] == 0x89 && imageData[1] == 0x50 && imageData[2] == 0x4E ? "image/png" : "image/jpeg"

        let url = backendBaseURL.appendingPathComponent("analyzeFoodPhoto")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try await BackendRequestAuth.applyHeaders(to: &request)
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "imageBase64": base64,
            "mimeType": mimeType
        ])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AIFoodPhotoError.apiError("Invalid response")
        }

        if (200...299).contains(http.statusCode) {
            let decoded = try JSONDecoder().decode(AIFoodPhotoAnalysisResult.self, from: data)
            guard !decoded.items.isEmpty else {
                throw AIFoodPhotoError.apiError("AI did not return any foods.")
            }
            return decoded
        }

        if let errJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let message = errJson["error"] as? String,
           !message.isEmpty {
            throw AIFoodPhotoError.apiError(message)
        }

        throw AIFoodPhotoError.httpError(http.statusCode)
    }
}

struct AIFoodPhotoError: LocalizedError {
    let message: String

    static func apiError(_ message: String) -> AIFoodPhotoError {
        AIFoodPhotoError(message: message)
    }

    static func httpError(_ code: Int) -> AIFoodPhotoError {
        AIFoodPhotoError(message: "HTTP \(code)")
    }

    var errorDescription: String? { message }
}
