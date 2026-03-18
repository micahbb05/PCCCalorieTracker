import Foundation

/// Calls the app's backend to generate a short weekly insight via Gemini.
/// API key and prompt are stored on the server, similar to plate estimation.
struct WeeklyInsightSummaryPayload: Codable {
    struct Day: Codable {
        let dayIdentifier: String   // "YYYY-MM-DD"
        let date: Date
        let caloriesIn: Int
        let caloriesBurned: Int
        let weightPounds: Double?
        let netCalories: Int
    }

    struct LoggedFoodEntry: Codable, Equatable {
        let dayIdentifier: String
        let createdAt: Date
        let mealGroup: String
        let name: String
        let calories: Int
        let protein: Int
        let loggedCount: Int?
    }

    struct RepeatedFoodPattern: Codable, Equatable {
        let name: String
        let overGoalDayCount: Int
        let totalCalories: Int
        let dominantMealGroup: String
    }

    // Category 1: Week Overview
    struct WeekOverview: Codable {
        let daysInPeriod: Int
        let mealLoggedDays: Int
        let weightLoggedDays: Int
    }

    // Category 2: Calorie Intake
    struct CalorieIntake: Codable {
        let averageCaloriesIn: Int
        let minCaloriesIn: Int
        let maxCaloriesIn: Int
        let averageGoalCalories: Int
        let overGoalDays: Int
        let underGoalDays: Int
        let biggestOverage: Int?
        let biggestUnderage: Int?

        // How far off-target you were on the days you exceeded your goal.
        let averageOverageOnOverGoalDays: Int?

        // Likely drivers: top calorie contributors on over-goal days.
        struct TopFood: Codable, Equatable {
            let name: String
            let calories: Int
        }

        struct TopMealGroup: Codable, Equatable {
            let mealGroup: String
            let calories: Int
        }

        let topFoodsOnOverGoalDays: [TopFood]
        let topMealGroupsOnOverGoalDays: [TopMealGroup]
    }

    // Category 3: Activity & Calories Burned (incl. HealthKit-derived burned calories)
    struct Activity: Codable {
        let averageCaloriesBurned: Int
        let minCaloriesBurned: Int
        let maxCaloriesBurned: Int
        let burnedReliability: BurnedReliability
    }

    struct BurnedReliability: Codable {
        // For completed days in the last 7-day window:
        // reliableBurnedDays: pulled from `dailyBurnedCalorieArchive` (stored burned calories)
        // compatibilityFallbackDays: pulled from older stored intake goal as a burned proxy
        // bmrFallbackDays: missing stored burned/goal data, so it used fallback BMR estimate
        let reliableBurnedDays: Int
        let compatibilityFallbackDays: Int
        let bmrFallbackDays: Int
    }

    // Category 4: Calorie Balance (net)
    struct CalorieBalance: Codable {
        let averageNetCalories: Int
        let netDeficitDays: Int
        let netSurplusDays: Int
        let minNetCalories: Int
        let maxNetCalories: Int

        // Intake vs net contradictions (helps explain confusion instead of hand-waving).
        let deficitDaysWhereIntakeWasOverGoal: Int
        let surplusDaysWhereIntakeWasUnderGoal: Int
    }

    // Category 5: Weight Trend
    struct WeightTrend: Codable {
        let weightDaysUsed: Int
        let startWeightPounds: Double?
        let endWeightPounds: Double?
        let weightChangePounds: Double?
    }

    // Category 6: Logging & Data Quality
    struct DataQuality: Codable {
        let missingMealDays: Int
        let missingWeightDays: Int
        let estimatedBurnedDays: Int
    }

    // Category 7: Macro / Nutrient Pattern (we start with protein since it's tracked)
    struct MacroPattern: Codable {
        let proteinGoalGrams: Int?
        let proteinDaysLogged: Int
        let proteinDaysHitGoal: Int
        let averageProteinGrams: Int
        let minProteinGrams: Int
        let maxProteinGrams: Int
    }

    struct CrossWeekPatterns: Codable {
        struct RecentWeek: Codable, Equatable {
            let label: String
            let startDayIdentifier: String
            let endDayIdentifier: String
            let averageCaloriesIn: Int
            let averageCaloriesBurned: Int
            let averageNetCalories: Int
            let overGoalDays: Int
            let underGoalDays: Int
            let mealLoggedDays: Int
            let exerciseDays: Int
            let averageExerciseMinutes: Int
            let averageProteinGrams: Int
            let weightLoggedDays: Int
            let weightChangePounds: Double?
        }

        let recentWeeks: [RecentWeek]
        let currentVsPreviousCaloriesDelta: Int?
        let currentVsPreviousNetDelta: Int?
        let currentVsPreviousProteinDelta: Int?
        let currentVsPreviousOverGoalDayDelta: Int?
        let currentVsPreviousExerciseDayDelta: Int?
    }

    struct HabitPatterns: Codable {
        struct MealPattern: Codable, Equatable {
            let mealGroup: String
            let averageCaloriesPerLoggedDay: Int
            let loggedDays: Int
            let totalCalories: Int
        }

        struct ExercisePattern: Codable, Equatable {
            let exerciseType: String
            let days: Int
            let sessions: Int
            let averageDurationMinutes: Int
            let totalCalories: Int
        }

        let averageEveningCalories: Int
        let averageEveningSharePercent: Int
        let breakfastLoggedDays: Int
        let lunchLoggedDays: Int
        let dinnerLoggedDays: Int
        let snackLoggedDays: Int
        let lateLogDays: Int
        let exerciseDays: Int
        let averageExerciseMinutesOnExerciseDays: Int
        let mealPatterns: [MealPattern]
        let exercisePatterns: [ExercisePattern]
        let repeatedOverGoalFoods: [RepeatedFoodPattern]
    }

    let days: [Day]
    let weekOverview: WeekOverview
    let intake: CalorieIntake
    let activity: Activity
    let balance: CalorieBalance
    let weightTrend: WeightTrend
    let dataQuality: DataQuality
    let macros: MacroPattern
    let crossWeekPatterns: CrossWeekPatterns
    let habitPatterns: HabitPatterns
    let loggedFoods: [LoggedFoodEntry]
}

final class GeminiWeeklyInsightService {

    private let backendBaseURL: URL
    private let session: URLSession

    init(backendBaseURL: URL? = nil, session: URLSession = .shared) {
        self.backendBaseURL = backendBaseURL ?? URL(string: "https://us-central1-calorie-tracker-364e3.cloudfunctions.net")!
        self.session = session
    }

    /// - Parameter summary: Aggregated 7-day history for Gemini.
    /// - Returns: A short coaching string (plain text or lightweight markdown).
    func generateWeeklyInsight(summary: WeeklyInsightSummaryPayload) async throws -> String {
        do {
            return try await performWeeklyInsightRequest(summary: summary, forceRefreshAppCheck: false)
        } catch let error as GeminiWeeklyInsightError {
            guard error.message == "Invalid App Check token." else { throw error }
            return try await performWeeklyInsightRequest(summary: summary, forceRefreshAppCheck: true)
        } catch {
            throw error
        }
    }

    private func performWeeklyInsightRequest(
        summary: WeeklyInsightSummaryPayload,
        forceRefreshAppCheck: Bool
    ) async throws -> String {
        let url = backendBaseURL.appendingPathComponent("generateWeeklyInsight")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try await BackendRequestAuth.applyHeaders(to: &request, forcingRefresh: forceRefreshAppCheck)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(summary)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GeminiWeeklyInsightError.apiError("Invalid response")
        }

        guard (200...299).contains(http.statusCode) else {
            if let errJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let message = errJson["error"] as? String, !message.isEmpty {
                throw GeminiWeeklyInsightError.apiError(message)
            }
            throw GeminiWeeklyInsightError.httpError(http.statusCode)
        }

        if let decoded = try? JSONDecoder().decode(WeeklyInsightResponse.self, from: data) {
            return decoded.insight.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let fallback = String(data: data, encoding: .utf8), !fallback.isEmpty {
            return fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        throw GeminiWeeklyInsightError.apiError("Empty insight response")
    }
}

private struct WeeklyInsightResponse: Decodable {
    let insight: String
}

struct GeminiWeeklyInsightError: LocalizedError {
    let message: String
    static func apiError(_ msg: String) -> GeminiWeeklyInsightError { GeminiWeeklyInsightError(message: msg) }
    static func httpError(_ code: Int) -> GeminiWeeklyInsightError { GeminiWeeklyInsightError(message: "HTTP \(code)") }
    var errorDescription: String? { message }
}
