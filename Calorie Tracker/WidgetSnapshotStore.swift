import Foundation
import WidgetKit

struct WidgetCalorieSnapshot: Codable, Equatable {
    struct TrackedNutrient: Codable, Equatable {
        let key: String
        let name: String
        let unit: String
        let total: Int
        let goal: Int
        let progress: Double
    }

    let updatedAt: Date
    let consumedCalories: Int
    let goalCalories: Int
    let burnedCalories: Int
    let caloriesLeft: Int
    let progress: Double
    let goalTypeRaw: String
    let selectedAppIconChoiceRaw: String
    let trackedNutrients: [TrackedNutrient]

    private enum CodingKeys: String, CodingKey {
        case updatedAt
        case consumedCalories
        case goalCalories
        case burnedCalories
        case caloriesLeft
        case progress
        case goalTypeRaw
        case selectedAppIconChoiceRaw
        case trackedNutrients
    }

    init(
        updatedAt: Date,
        consumedCalories: Int,
        goalCalories: Int,
        burnedCalories: Int,
        caloriesLeft: Int,
        progress: Double,
        goalTypeRaw: String,
        selectedAppIconChoiceRaw: String,
        trackedNutrients: [TrackedNutrient]
    ) {
        self.updatedAt = updatedAt
        self.consumedCalories = consumedCalories
        self.goalCalories = goalCalories
        self.burnedCalories = burnedCalories
        self.caloriesLeft = caloriesLeft
        self.progress = progress
        self.goalTypeRaw = goalTypeRaw
        self.selectedAppIconChoiceRaw = selectedAppIconChoiceRaw
        self.trackedNutrients = trackedNutrients
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        consumedCalories = try container.decode(Int.self, forKey: .consumedCalories)
        goalCalories = try container.decode(Int.self, forKey: .goalCalories)
        burnedCalories = try container.decode(Int.self, forKey: .burnedCalories)
        caloriesLeft = try container.decode(Int.self, forKey: .caloriesLeft)
        progress = try container.decode(Double.self, forKey: .progress)
        goalTypeRaw = try container.decodeIfPresent(String.self, forKey: .goalTypeRaw)
            ?? Self.inferredGoalTypeRaw(goalCalories: goalCalories, burnedCalories: burnedCalories)
        selectedAppIconChoiceRaw = try container.decodeIfPresent(String.self, forKey: .selectedAppIconChoiceRaw) ?? AppIconChoice.standard.rawValue
        trackedNutrients = try container.decode([TrackedNutrient].self, forKey: .trackedNutrients)
    }

    private static func inferredGoalTypeRaw(goalCalories: Int, burnedCalories: Int) -> String {
        if goalCalories > burnedCalories { return "surplus" }
        if goalCalories == burnedCalories { return "fixed" }
        return "deficit"
    }
}

enum WidgetSnapshotStore {
    static let appGroupID = "group.Micah.Calorie-Tracker"
    private static let snapshotKey = "widget.calorieSnapshot"
    private static let progressTolerance = 0.0001

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    static func save(_ snapshot: WidgetCalorieSnapshot) {
        if let existing = load(), isEquivalentContent(existing, snapshot) {
            return
        }
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: snapshotKey)
        WidgetCenter.shared.reloadTimelines(ofKind: CalorieWidgetData.kind)
        WidgetCenter.shared.reloadTimelines(ofKind: CalorieWidgetData.dashboardKind)
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func load() -> WidgetCalorieSnapshot? {
        guard
            let data = defaults.data(forKey: snapshotKey),
            let snapshot = try? JSONDecoder().decode(WidgetCalorieSnapshot.self, from: data)
        else {
            return nil
        }
        return snapshot
    }

    private static func isEquivalentContent(_ lhs: WidgetCalorieSnapshot, _ rhs: WidgetCalorieSnapshot) -> Bool {
        guard lhs.consumedCalories == rhs.consumedCalories else { return false }
        guard lhs.goalCalories == rhs.goalCalories else { return false }
        guard lhs.burnedCalories == rhs.burnedCalories else { return false }
        guard lhs.caloriesLeft == rhs.caloriesLeft else { return false }
        guard abs(lhs.progress - rhs.progress) <= progressTolerance else { return false }
        guard lhs.goalTypeRaw == rhs.goalTypeRaw else { return false }
        guard lhs.selectedAppIconChoiceRaw == rhs.selectedAppIconChoiceRaw else { return false }
        return areEquivalentNutrients(lhs.trackedNutrients, rhs.trackedNutrients)
    }

    private static func areEquivalentNutrients(
        _ lhs: [WidgetCalorieSnapshot.TrackedNutrient],
        _ rhs: [WidgetCalorieSnapshot.TrackedNutrient]
    ) -> Bool {
        guard lhs.count == rhs.count else { return false }
        for (left, right) in zip(lhs, rhs) {
            guard left.key == right.key else { return false }
            guard left.name == right.name else { return false }
            guard left.unit == right.unit else { return false }
            guard left.total == right.total else { return false }
            guard left.goal == right.goal else { return false }
            guard abs(left.progress - right.progress) <= progressTolerance else { return false }
        }
        return true
    }
}

enum CalorieWidgetData {
    static let kind = "CalorieTrackerCalorieWidget"
    static let dashboardKind = "CalorieTrackerDashboardWidget"
}
