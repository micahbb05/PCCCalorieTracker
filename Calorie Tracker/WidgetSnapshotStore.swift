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
    let trackedNutrients: [TrackedNutrient]
}

enum WidgetSnapshotStore {
    static let appGroupID = "group.Micah.Calorie-Tracker"
    private static let snapshotKey = "widget.calorieSnapshot"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    static func save(_ snapshot: WidgetCalorieSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: snapshotKey)
        WidgetCenter.shared.reloadTimelines(ofKind: CalorieWidgetData.kind)
        WidgetCenter.shared.reloadTimelines(ofKind: CalorieWidgetData.dashboardKind)
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
}

enum CalorieWidgetData {
    static let kind = "CalorieTrackerCalorieWidget"
    static let dashboardKind = "CalorieTrackerDashboardWidget"
}
