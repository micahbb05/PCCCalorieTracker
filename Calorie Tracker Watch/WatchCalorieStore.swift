import Foundation
import Combine
import WatchKit
import WidgetKit

struct WatchMealEntry: Identifiable, Codable, Equatable {
    let id: UUID
    let name: String
    let calories: Int
    let createdAt: Date
}

struct WatchDailySnapshot: Codable, Equatable {
    var goalCalories: Int
    var activityCalories: Int
    var currentMealTitle: String
    var goalTypeRaw: String
    var selectedAppIconChoiceRaw: String
    var venueMenuItems: [String: [String]]
    var entries: [WatchMealEntry]

    private enum CodingKeys: String, CodingKey {
        case goalCalories
        case activityCalories
        case currentMealTitle
        case goalTypeRaw
        case selectedAppIconChoiceRaw
        case venueMenuItems
        case entries
    }

    init(
        goalCalories: Int,
        activityCalories: Int,
        currentMealTitle: String,
        goalTypeRaw: String,
        selectedAppIconChoiceRaw: String,
        venueMenuItems: [String: [String]],
        entries: [WatchMealEntry]
    ) {
        self.goalCalories = goalCalories
        self.activityCalories = activityCalories
        self.currentMealTitle = currentMealTitle
        self.goalTypeRaw = goalTypeRaw
        self.selectedAppIconChoiceRaw = selectedAppIconChoiceRaw
        self.venueMenuItems = venueMenuItems
        self.entries = entries
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        goalCalories = try container.decode(Int.self, forKey: .goalCalories)
        activityCalories = try container.decodeIfPresent(Int.self, forKey: .activityCalories) ?? 0
        currentMealTitle = try container.decodeIfPresent(String.self, forKey: .currentMealTitle) ?? "Lunch"
        goalTypeRaw = try container.decodeIfPresent(String.self, forKey: .goalTypeRaw)
            ?? Self.inferredGoalTypeRaw(goalCalories: goalCalories, activityCalories: activityCalories)
        selectedAppIconChoiceRaw = try container.decodeIfPresent(String.self, forKey: .selectedAppIconChoiceRaw) ?? "standard"
        venueMenuItems = try container.decodeIfPresent([String: [String]].self, forKey: .venueMenuItems) ?? [:]
        entries = try container.decodeIfPresent([WatchMealEntry].self, forKey: .entries) ?? []
    }

    static func inferredGoalTypeRaw(goalCalories: Int, activityCalories: Int) -> String {
        if goalCalories > activityCalories { return "surplus" }
        if goalCalories == activityCalories { return "fixed" }
        return "deficit"
    }

    static let empty = WatchDailySnapshot(
        goalCalories: 2200,
        activityCalories: 0,
        currentMealTitle: "Lunch",
        goalTypeRaw: "deficit",
        selectedAppIconChoiceRaw: "standard",
        venueMenuItems: [:],
        entries: []
    )
}

@MainActor
final class WatchCalorieStore: ObservableObject {
    static let shared = WatchCalorieStore()

    @Published private(set) var entries: [WatchMealEntry] = []
    @Published var dailyGoal: Int = 2200
    @Published var activityCalories: Int = 0
    @Published var currentMealTitle: String = "Lunch"
    @Published var goalTypeRaw: String = "deficit"
    @Published var selectedAppIconChoiceRaw: String = "standard"
    @Published var venueMenuItems: [String: [String]] = [:]

    private enum Keys {
        static let appGroup = "group.Micah.Calorie-Tracker"
        static let standaloneSnapshot = "watchDailySnapshot"
        static let widgetSnapshot = "widget.calorieSnapshot"
    }

    private enum WidgetKinds {
        static let calories = "CalorieTrackerCalorieWidget"
    }
    private static let progressTolerance = 0.0001

    private let calendar = Calendar.current
    private var defaults: UserDefaults

    init(defaults: UserDefaults? = nil) {
        if let defaults {
            self.defaults = defaults
        } else if let shared = UserDefaults(suiteName: Keys.appGroup) {
            self.defaults = shared
        } else {
            self.defaults = .standard
        }
        load()
    }

    var todaysCalories: Int {
        entries.reduce(0) { $0 + $1.calories }
    }

    var remainingCalories: Int {
        max(dailyGoal - todaysCalories, 0)
    }

    var progress: Double {
        guard dailyGoal > 0 else { return 0 }
        return max(Double(todaysCalories) / Double(dailyGoal), 0)
    }

    var recentEntries: [WatchMealEntry] {
        entries
            .sorted(by: { $0.createdAt > $1.createdAt })
            .prefix(6)
            .map { $0 }
    }

    func addQuickCalories(_ calories: Int) {
        guard calories > 0 else { return }
        let entry = WatchMealEntry(
            id: UUID(),
            name: "Quick Add",
            calories: calories,
            createdAt: Date()
        )
        entries.append(entry)
        persist()
        WKInterfaceDevice.current().play(.success)
    }

    func addCustomCalories(_ calories: Int, label: String) {
        guard calories > 0 else { return }
        let cleanLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let entry = WatchMealEntry(
            id: UUID(),
            name: cleanLabel.isEmpty ? "Custom" : cleanLabel,
            calories: calories,
            createdAt: Date()
        )
        entries.append(entry)
        persist()
        WKInterfaceDevice.current().play(.success)
    }

    func setGoal(_ calories: Int) {
        dailyGoal = max(calories, 1)
        persist()
    }

    func applySync(
        goalCalories: Int,
        activityCalories: Int,
        currentMealTitle: String,
        goalTypeRaw: String,
        selectedAppIconChoiceRaw: String,
        venueMenuItems: [String: [String]],
        entries: [WatchMealEntry]
    ) {
        let normalizedGoal = max(goalCalories, 1)
        let normalizedActivity = max(activityCalories, 0)
        let normalizedMealTitle = currentMealTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Lunch"
            : currentMealTitle
        let normalizedGoalType = goalTypeRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? WatchDailySnapshot.inferredGoalTypeRaw(goalCalories: normalizedGoal, activityCalories: normalizedActivity)
            : goalTypeRaw
        let normalizedAppIconChoice = selectedAppIconChoiceRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "standard"
            : selectedAppIconChoiceRaw
        let normalizedEntries = entries.filter { calendar.isDateInToday($0.createdAt) }

        if dailyGoal == normalizedGoal,
           self.activityCalories == normalizedActivity,
           self.currentMealTitle == normalizedMealTitle,
           self.goalTypeRaw == normalizedGoalType,
           self.selectedAppIconChoiceRaw == normalizedAppIconChoice,
           self.venueMenuItems == venueMenuItems,
           self.entries == normalizedEntries {
            return
        }

        dailyGoal = normalizedGoal
        self.activityCalories = normalizedActivity
        self.currentMealTitle = normalizedMealTitle
        self.goalTypeRaw = normalizedGoalType
        self.selectedAppIconChoiceRaw = normalizedAppIconChoice
        self.venueMenuItems = venueMenuItems
        self.entries = normalizedEntries
        persist()
    }

    private func load() {
        guard let data = defaults.data(forKey: Keys.standaloneSnapshot) else {
            entries = []
            dailyGoal = 2200
            activityCalories = 0
            currentMealTitle = "Lunch"
            goalTypeRaw = "deficit"
            selectedAppIconChoiceRaw = "standard"
            venueMenuItems = [:]
            persistWidgetSnapshot()
            return
        }
        guard let snapshot = try? JSONDecoder().decode(WatchDailySnapshot.self, from: data) else {
            entries = []
            dailyGoal = 2200
            activityCalories = 0
            currentMealTitle = "Lunch"
            goalTypeRaw = "deficit"
            selectedAppIconChoiceRaw = "standard"
            venueMenuItems = [:]
            persistWidgetSnapshot()
            return
        }

        dailyGoal = max(snapshot.goalCalories, 1)
        activityCalories = max(snapshot.activityCalories, 0)
        currentMealTitle = snapshot.currentMealTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Lunch"
            : snapshot.currentMealTitle
        goalTypeRaw = snapshot.goalTypeRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? WatchDailySnapshot.inferredGoalTypeRaw(goalCalories: dailyGoal, activityCalories: activityCalories)
            : snapshot.goalTypeRaw
        selectedAppIconChoiceRaw = snapshot.selectedAppIconChoiceRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "standard"
            : snapshot.selectedAppIconChoiceRaw
        venueMenuItems = snapshot.venueMenuItems
        let today = Date()
        entries = snapshot.entries.filter { calendar.isDate($0.createdAt, inSameDayAs: today) }

        if entries.count != snapshot.entries.count {
            persist()
            return
        }
        persistWidgetSnapshot()
    }

    private func persist() {
        let snapshot = WatchDailySnapshot(
            goalCalories: dailyGoal,
            activityCalories: activityCalories,
            currentMealTitle: currentMealTitle,
            goalTypeRaw: goalTypeRaw,
            selectedAppIconChoiceRaw: selectedAppIconChoiceRaw,
            venueMenuItems: venueMenuItems,
            entries: entries
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: Keys.standaloneSnapshot)
        persistWidgetSnapshot()
    }

    private struct WidgetSnapshot: Codable {
        struct TrackedNutrient: Codable {
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
                ?? WatchDailySnapshot.inferredGoalTypeRaw(goalCalories: goalCalories, activityCalories: burnedCalories)
            selectedAppIconChoiceRaw = try container.decodeIfPresent(String.self, forKey: .selectedAppIconChoiceRaw) ?? "standard"
            trackedNutrients = try container.decodeIfPresent([TrackedNutrient].self, forKey: .trackedNutrients) ?? []
        }
    }

    private func persistWidgetSnapshot() {
        let safeGoal = max(dailyGoal, 1)
        let consumed = max(todaysCalories, 0)
        let snapshot = WidgetSnapshot(
            updatedAt: Date(),
            consumedCalories: consumed,
            goalCalories: safeGoal,
            burnedCalories: max(activityCalories, 0),
            caloriesLeft: max(safeGoal - consumed, 0),
            progress: max(Double(consumed) / Double(safeGoal), 0),
            goalTypeRaw: goalTypeRaw,
            selectedAppIconChoiceRaw: selectedAppIconChoiceRaw,
            trackedNutrients: []
        )
        if let existing = loadStoredWidgetSnapshot(), isEquivalentContent(existing, snapshot) {
            // Still reload so complication refreshes immediately if it had stale cache
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetKinds.calories)
            WidgetCenter.shared.reloadAllTimelines()
            return
        }
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: Keys.widgetSnapshot)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKinds.calories)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func loadStoredWidgetSnapshot() -> WidgetSnapshot? {
        guard let data = defaults.data(forKey: Keys.widgetSnapshot) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    private func isEquivalentContent(_ lhs: WidgetSnapshot, _ rhs: WidgetSnapshot) -> Bool {
        guard lhs.consumedCalories == rhs.consumedCalories else { return false }
        guard lhs.goalCalories == rhs.goalCalories else { return false }
        guard lhs.burnedCalories == rhs.burnedCalories else { return false }
        guard lhs.caloriesLeft == rhs.caloriesLeft else { return false }
        guard abs(lhs.progress - rhs.progress) <= Self.progressTolerance else { return false }
        guard lhs.selectedAppIconChoiceRaw == rhs.selectedAppIconChoiceRaw else { return false }
        return areEquivalentNutrients(lhs.trackedNutrients, rhs.trackedNutrients)
    }

    private func areEquivalentNutrients(
        _ lhs: [WidgetSnapshot.TrackedNutrient],
        _ rhs: [WidgetSnapshot.TrackedNutrient]
    ) -> Bool {
        guard lhs.count == rhs.count else { return false }
        for (left, right) in zip(lhs, rhs) {
            guard left.key == right.key else { return false }
            guard left.name == right.name else { return false }
            guard left.unit == right.unit else { return false }
            guard left.total == right.total else { return false }
            guard left.goal == right.goal else { return false }
            guard abs(left.progress - right.progress) <= Self.progressTolerance else { return false }
        }
        return true
    }
}
