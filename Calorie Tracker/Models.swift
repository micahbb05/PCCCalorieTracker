import Foundation

enum MealGroup: String, Codable, CaseIterable, Identifiable {
    case breakfast
    case lunch
    case dinner
    case snack

    var id: String { rawValue }

    var title: String {
        switch self {
        case .breakfast:
            return "Breakfast"
        case .lunch:
            return "Lunch"
        case .dinner:
            return "Dinner"
        case .snack:
            return "Snack"
        }
    }

    var logSortRank: Int {
        switch self {
        case .breakfast:
            return 0
        case .lunch:
            return 1
        case .dinner:
            return 2
        case .snack:
            return 3
        }
    }

    static var logDisplayOrder: [MealGroup] {
        [breakfast, lunch, dinner, snack]
    }
}

enum BMRSex: String, Codable, CaseIterable, Identifiable {
    case male
    case female

    var id: String { rawValue }

    var title: String {
        switch self {
        case .male: return "Male"
        case .female: return "Female"
        }
    }
}

struct BMRProfile: Codable, Equatable {
    var age: Int
    var sex: BMRSex
    var heightFeet: Int
    var heightInches: Int
    var weightPounds: Int

    static let empty = BMRProfile(age: 0, sex: .male, heightFeet: 0, heightInches: 0, weightPounds: 0)

    var isComplete: Bool {
        age > 0 && heightFeet > 0 && heightInches >= 0 && heightInches < 12 && weightPounds > 0
    }
}

struct MealEntry: Identifiable, Codable, Equatable {
    let id: UUID
    let name: String
    let calories: Int
    let protein: Int
    let nutrientValues: [String: Int]
    let createdAt: Date
    let mealGroup: MealGroup

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case calories
        case protein
        case nutrientValues
        case createdAt
        case mealGroup
    }

    init(id: UUID, name: String, calories: Int, nutrientValues: [String: Int], createdAt: Date, mealGroup: MealGroup) {
        self.id = id
        self.name = MealEntry.normalizedName(name)
        self.calories = max(0, calories)
        self.nutrientValues = nutrientValues.mapValues { max(0, $0) }
        self.protein = self.nutrientValues["g_protein"] ?? 0
        self.createdAt = createdAt
        self.mealGroup = mealGroup
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        calories = max(0, try container.decode(Int.self, forKey: .calories))
        createdAt = try container.decode(Date.self, forKey: .createdAt)

        let decodedName = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        name = MealEntry.normalizedName(decodedName)

        var decodedNutrients = try container.decodeIfPresent([String: Int].self, forKey: .nutrientValues) ?? [:]
        let decodedProtein = max(0, try container.decodeIfPresent(Int.self, forKey: .protein) ?? 0)
        if decodedNutrients["g_protein"] == nil && decodedProtein > 0 {
            decodedNutrients["g_protein"] = decodedProtein
        }

        nutrientValues = decodedNutrients.mapValues { max(0, $0) }
        protein = nutrientValues["g_protein"] ?? decodedProtein
        mealGroup = try container.decodeIfPresent(MealGroup.self, forKey: .mealGroup)
            ?? MealEntry.inferredMealGroup(for: createdAt)
    }

    static func normalizedName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Unnamed food" : trimmed
    }

    static func inferredMealGroup(for date: Date) -> MealGroup {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        let totalMinutes = hour * 60 + minute

        if totalMinutes >= 240 && totalMinutes < 705 {
            return .breakfast
        }
        if totalMinutes >= 705 && totalMinutes < 840 {
            return .lunch
        }
        if totalMinutes >= 840 && totalMinutes < 1005 {
            return .snack
        }
        if totalMinutes >= 1005 && totalMinutes < 1200 {
            return .dinner
        }
        return .snack
    }
}

struct QuickAddFood: Identifiable, Codable, Equatable {
    let id: UUID
    let name: String
    let calories: Int
    let nutrientValues: [String: Int]
    let createdAt: Date

    init(id: UUID, name: String, calories: Int, nutrientValues: [String: Int], createdAt: Date) {
        self.id = id
        self.name = MealEntry.normalizedName(name)
        self.calories = max(0, calories)
        self.nutrientValues = nutrientValues.mapValues { max(0, $0) }
        self.createdAt = createdAt
    }
}

enum ExerciseType: String, Codable, Identifiable {
    case weightLifting
    case running
    case cycling
    case swimming
    case directCalories

    var id: String { rawValue }

    static var allCases: [ExerciseType] {
        [.weightLifting, .running, .cycling, .directCalories]
    }

    var title: String {
        switch self {
        case .weightLifting: return "Weight Lifting"
        case .running: return "Running"
        case .cycling: return "Cycling"
        case .swimming: return "Swimming"
        case .directCalories: return "Custom"
        }
    }

    var iconName: String {
        switch self {
        case .weightLifting: return "dumbbell.fill"
        case .running: return "figure.run"
        case .cycling: return "bicycle"
        case .swimming: return "figure.pool.swim"
        case .directCalories: return "flame.fill"
        }
    }
}

struct ExerciseEntry: Identifiable, Codable, Equatable {
    let id: UUID
    let exerciseType: ExerciseType
    let customName: String?
    let durationMinutes: Int
    let distanceMiles: Double?
    let calories: Int
    let reclassifiedWalkingCalories: Int
    let createdAt: Date

    private enum CodingKeys: String, CodingKey {
        case id, exerciseType, customName, durationMinutes, calories, createdAt
        case distanceMiles
        case reclassifiedWalkingCalories
        case intensity
    }

    init(
        id: UUID,
        exerciseType: ExerciseType,
        customName: String? = nil,
        durationMinutes: Int,
        distanceMiles: Double? = nil,
        calories: Int,
        reclassifiedWalkingCalories: Int = 0,
        createdAt: Date
    ) {
        self.id = id
        self.exerciseType = exerciseType
        let trimmedName = customName?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.customName = (trimmedName?.isEmpty == false) ? trimmedName : nil
        self.durationMinutes = durationMinutes
        self.distanceMiles = distanceMiles
        self.calories = calories
        self.reclassifiedWalkingCalories = max(reclassifiedWalkingCalories, 0)
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        exerciseType = try c.decode(ExerciseType.self, forKey: .exerciseType)
        let decodedCustomName = try c.decodeIfPresent(String.self, forKey: .customName)
        let trimmedName = decodedCustomName?.trimmingCharacters(in: .whitespacesAndNewlines)
        customName = (trimmedName?.isEmpty == false) ? trimmedName : nil
        durationMinutes = try c.decode(Int.self, forKey: .durationMinutes)
        distanceMiles = try c.decodeIfPresent(Double.self, forKey: .distanceMiles)
        calories = try c.decode(Int.self, forKey: .calories)
        reclassifiedWalkingCalories = try c.decodeIfPresent(Int.self, forKey: .reclassifiedWalkingCalories) ?? 0
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        _ = try c.decodeIfPresent(String.self, forKey: .intensity)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(exerciseType, forKey: .exerciseType)
        try c.encodeIfPresent(customName, forKey: .customName)
        try c.encode(durationMinutes, forKey: .durationMinutes)
        try c.encodeIfPresent(distanceMiles, forKey: .distanceMiles)
        try c.encode(calories, forKey: .calories)
        try c.encode(reclassifiedWalkingCalories, forKey: .reclassifiedWalkingCalories)
        try c.encode(createdAt, forKey: .createdAt)
    }

    var displayTitle: String {
        if exerciseType == .directCalories, let customName {
            return customName
        }
        return exerciseType.title
    }

    /// For running/cycling with distance; for weight lifting/walking or legacy entries, nil.
    var displayValue: String {
        if exerciseType == .directCalories {
            return "Custom entry"
        }
        if let miles = distanceMiles, miles > 0 {
            return String(format: "%.1f mi", miles)
        }
        return "\(durationMinutes) min"
    }
}

struct NutrientDefinition: Identifiable, Hashable {
    let key: String
    let name: String
    let unit: String
    let defaultGoal: Int
    let minGoal: Int
    let maxGoal: Int
    let step: Int

    var id: String { key }
}

enum CalibrationRunStatus: String, Codable, Equatable {
    case never
    case applied
    case skipped
}

struct CalibrationState: Codable, Equatable {
    var isEnabled: Bool
    var calibrationOffsetCalories: Int
    var recentDailyErrors: [Double]
    var appliedWeekCount: Int
    var lastAppliedWeekID: String?
    var lastRunDate: Date?
    var lastRunStatus: CalibrationRunStatus
    var lastSkipReason: String?
    var dataQualityPasses: Int
    var dataQualityChecks: Int

    static let `default` = CalibrationState(
        isEnabled: true,
        calibrationOffsetCalories: 0,
        recentDailyErrors: [],
        appliedWeekCount: 0,
        lastAppliedWeekID: nil,
        lastRunDate: nil,
        lastRunStatus: .never,
        lastSkipReason: nil,
        dataQualityPasses: 0,
        dataQualityChecks: 0
    )

    enum CodingKeys: String, CodingKey {
        case isEnabled
        case calibrationOffsetCalories
        case recentDailyErrors
        case appliedWeekCount
        case lastAppliedWeekID
        case lastRunDate
        case lastRunStatus
        case lastSkipReason
        case dataQualityPasses
        case dataQualityChecks
    }

    init(
        isEnabled: Bool,
        calibrationOffsetCalories: Int,
        recentDailyErrors: [Double],
        appliedWeekCount: Int,
        lastAppliedWeekID: String?,
        lastRunDate: Date?,
        lastRunStatus: CalibrationRunStatus,
        lastSkipReason: String?,
        dataQualityPasses: Int,
        dataQualityChecks: Int
    ) {
        self.isEnabled = isEnabled
        self.calibrationOffsetCalories = calibrationOffsetCalories
        self.recentDailyErrors = recentDailyErrors
        self.appliedWeekCount = appliedWeekCount
        self.lastAppliedWeekID = lastAppliedWeekID
        self.lastRunDate = lastRunDate
        self.lastRunStatus = lastRunStatus
        self.lastSkipReason = lastSkipReason
        self.dataQualityPasses = dataQualityPasses
        self.dataQualityChecks = dataQualityChecks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        self.calibrationOffsetCalories = try container.decode(Int.self, forKey: .calibrationOffsetCalories)
        self.recentDailyErrors = try container.decode([Double].self, forKey: .recentDailyErrors)
        self.appliedWeekCount = try container.decode(Int.self, forKey: .appliedWeekCount)
        self.lastAppliedWeekID = try container.decodeIfPresent(String.self, forKey: .lastAppliedWeekID)
        self.lastRunDate = try container.decodeIfPresent(Date.self, forKey: .lastRunDate)
        self.lastRunStatus = try container.decode(CalibrationRunStatus.self, forKey: .lastRunStatus)
        self.lastSkipReason = try container.decodeIfPresent(String.self, forKey: .lastSkipReason)
        self.dataQualityPasses = try container.decode(Int.self, forKey: .dataQualityPasses)
        self.dataQualityChecks = try container.decode(Int.self, forKey: .dataQualityChecks)
    }
}

enum HealthWeighInSelectionMethod: String, Codable, Equatable {
    case morningEarliest
    case dayMinimum
}

struct HealthWeighInSampleMetadata: Codable, Equatable {
    let timestamp: Date
    let pounds: Double
}

struct HealthWeighInDay: Codable, Equatable, Identifiable {
    let dayIdentifier: String
    let representativePounds: Double
    let selectedSampleDate: Date
    let selectionMethod: HealthWeighInSelectionMethod
    let sampleCount: Int
    let samples: [HealthWeighInSampleMetadata]

    var id: String { dayIdentifier }
}
