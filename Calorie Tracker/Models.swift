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
        case .dinner:
            return 0
        case .lunch:
            return 1
        case .breakfast:
            return 2
        case .snack:
            return 3
        }
    }

    static var logDisplayOrder: [MealGroup] {
        [dinner, lunch, breakfast, snack]
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

enum ExerciseType: String, Codable, CaseIterable, Identifiable {
    case weightLifting
    case running
    case cycling
    case swimming

    var id: String { rawValue }

    var title: String {
        switch self {
        case .weightLifting: return "Weight Lifting"
        case .running: return "Running"
        case .cycling: return "Cycling"
        case .swimming: return "Swimming"
        }
    }

    var iconName: String {
        switch self {
        case .weightLifting: return "dumbbell.fill"
        case .running: return "figure.run"
        case .cycling: return "bicycle"
        case .swimming: return "figure.pool.swim"
        }
    }
}

struct ExerciseEntry: Identifiable, Codable, Equatable {
    let id: UUID
    let exerciseType: ExerciseType
    let durationMinutes: Int
    let distanceMiles: Double?
    let calories: Int
    let createdAt: Date

    private enum CodingKeys: String, CodingKey {
        case id, exerciseType, durationMinutes, calories, createdAt
        case distanceMiles
        case intensity
    }

    init(id: UUID, exerciseType: ExerciseType, durationMinutes: Int, distanceMiles: Double? = nil, calories: Int, createdAt: Date) {
        self.id = id
        self.exerciseType = exerciseType
        self.durationMinutes = durationMinutes
        self.distanceMiles = distanceMiles
        self.calories = calories
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        exerciseType = try c.decode(ExerciseType.self, forKey: .exerciseType)
        durationMinutes = try c.decode(Int.self, forKey: .durationMinutes)
        distanceMiles = try c.decodeIfPresent(Double.self, forKey: .distanceMiles)
        calories = try c.decode(Int.self, forKey: .calories)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        _ = try c.decodeIfPresent(String.self, forKey: .intensity)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(exerciseType, forKey: .exerciseType)
        try c.encode(durationMinutes, forKey: .durationMinutes)
        try c.encodeIfPresent(distanceMiles, forKey: .distanceMiles)
        try c.encode(calories, forKey: .calories)
        try c.encode(createdAt, forKey: .createdAt)
    }

    /// For running/cycling with distance; for weight lifting/walking or legacy entries, nil.
    var displayValue: String {
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
