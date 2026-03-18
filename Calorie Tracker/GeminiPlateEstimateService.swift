import Foundation
import UIKit

/// Calls the app's backend (same pattern as USDA) to estimate plate portion sizes via Gemini. API key is stored on the server.
final class GeminiPlateEstimateService {

    private let backendBaseURL: URL
    private let session: URLSession

    init(backendBaseURL: URL? = nil, session: URLSession = .shared) {
        self.backendBaseURL = backendBaseURL ?? URL(string: "https://us-central1-calorie-tracker-364e3.cloudfunctions.net")!
        self.session = session
    }

    /// - Parameters:
    ///   - imageData: JPEG or PNG data of the plate photo.
    ///   - items: Menu items with name, calories, servingAmount, servingUnit — gives Gemini context to infer oz for unclear servings.
    /// - Returns: ozByName, countByName (for discrete items), baseOzByName (inferred base serving in oz for "1 each" etc.), and raw Gemini text (for debugging).
    func estimatePortions(imageData: Data, items: [MenuItem]) async throws -> (ozByName: [String: Double], countByName: [String: Int], baseOzByName: [String: Double], rawText: String?) {
        let base64 = imageData.base64EncodedString()
        let mimeType = imageData.count >= 8 && imageData[0] == 0x89 && imageData[1] == 0x50 && imageData[2] == 0x4E ? "image/png" : "image/jpeg"

        let foodItems = items.map { item -> [String: Any] in
            [
                "name": item.name,
                "calories": item.calories,
                "servingAmount": item.servingAmount,
                "servingUnit": item.servingUnit
            ]
        }

        let url = backendBaseURL.appendingPathComponent("estimatePlatePortions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try await BackendRequestAuth.applyHeaders(to: &request)

        let body: [String: Any] = [
            "imageBase64": base64,
            "mimeType": mimeType,
            "foodItems": foodItems
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GeminiPlateError.apiError("Invalid response")
        }

        if (200...299).contains(http.statusCode) {
            let decoded = try JSONDecoder().decode(EstimatePlatePortionsResponse.self, from: data)
            let countDict = decoded.countByFoodName ?? [:]
            let countByName = Dictionary(uniqueKeysWithValues: countDict.map { ($0.key, Int($0.value)) })
            return (decoded.ozByFoodName ?? [:], countByName, decoded.baseOzByFoodName ?? [:], decoded.rawText)
        }

        if let errJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let message = errJson["error"] as? String, !message.isEmpty {
            throw GeminiPlateError.apiError(message)
        }
        throw GeminiPlateError.httpError(http.statusCode)
    }
}

private struct EstimatePlatePortionsResponse: Decodable {
    let ozByFoodName: [String: Double]?
    let countByFoodName: [String: Double]?
    let baseOzByFoodName: [String: Double]?
    let rawText: String?

    enum CodingKeys: String, CodingKey {
        case ozByFoodName
        case countByFoodName
        case baseOzByFoodName
        case rawText
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ozByFoodName = try container.decodeIfPresent([String: Double].self, forKey: .ozByFoodName)
        countByFoodName = try container.decodeIfPresent([String: Double].self, forKey: .countByFoodName)
        baseOzByFoodName = try container.decodeIfPresent([String: Double].self, forKey: .baseOzByFoodName)
        rawText = try container.decodeIfPresent(String.self, forKey: .rawText)
    }
}

struct GeminiPlateError: LocalizedError {
    let message: String
    static func apiError(_ msg: String) -> GeminiPlateError { GeminiPlateError(message: msg) }
    static func httpError(_ code: Int) -> GeminiPlateError { GeminiPlateError(message: "HTTP \(code)") }
    var errorDescription: String? { message }
}
