import Foundation
import SwiftData

struct PersistentAppStateSnapshot: Equatable, Codable {
    var hasCompletedOnboarding: Bool
    var deficitCalories: Int
    var useWeekendDeficit: Bool
    var weekendDeficitCalories: Int
    var goalTypeRaw: String
    var surplusCalories: Int
    var fixedGoalCalories: Int
    var dailyGoalTypeArchiveData: String
    var proteinGoal: Int
    var mealEntriesData: String
    var trackedNutrientsData: String
    var nutrientGoalsData: String
    var lastCentralDayIdentifier: String
    var selectedAppIconChoiceRaw: String
    var dailyEntryArchiveData: String
    var dailyCalorieGoalArchiveData: String
    var dailyBurnedCalorieArchiveData: String
    var dailyExerciseArchiveData: String
    var venueMenusData: String
    var venueMenuSignaturesData: String
    var quickAddFoodsData: String
    var calibrationStateData: String
    var healthWeighInsData: String
    var cloudSyncLocalModifiedAt: Double
    var useAIBaseServings: Bool

    var hasMeaningfulData: Bool {
        if hasCompletedOnboarding { return true }
        if !mealEntriesData.isEmpty { return true }
        if !dailyEntryArchiveData.isEmpty { return true }
        if !dailyExerciseArchiveData.isEmpty { return true }
        if !quickAddFoodsData.isEmpty { return true }
        if !trackedNutrientsData.isEmpty { return true }
        if !nutrientGoalsData.isEmpty { return true }
        if !healthWeighInsData.isEmpty { return true }
        if !calibrationStateData.isEmpty { return true }
        if !venueMenusData.isEmpty { return true }
        if !venueMenuSignaturesData.isEmpty { return true }
        if !lastCentralDayIdentifier.isEmpty { return true }
        return false
    }

    /// Higher score indicates denser persisted history; used to avoid replacing richer state with sparse state.
    var persistenceScore: Int {
        mealEntriesData.count
        + dailyEntryArchiveData.count
        + dailyExerciseArchiveData.count
        + dailyCalorieGoalArchiveData.count
        + dailyBurnedCalorieArchiveData.count
        + quickAddFoodsData.count
        + healthWeighInsData.count
        + calibrationStateData.count
        + trackedNutrientsData.count
        + nutrientGoalsData.count
    }
}

@Model
final class PersistentAppStateRecord {
    @Attribute(.unique) var id: String
    var hasCompletedOnboarding: Bool
    var deficitCalories: Int
    var useWeekendDeficit: Bool
    var weekendDeficitCalories: Int
    var goalTypeRaw: String
    var surplusCalories: Int
    var fixedGoalCalories: Int
    var dailyGoalTypeArchiveData: String
    var proteinGoal: Int
    var mealEntriesData: String
    var trackedNutrientsData: String
    var nutrientGoalsData: String
    var lastCentralDayIdentifier: String
    var selectedAppIconChoiceRaw: String
    var dailyEntryArchiveData: String
    var dailyCalorieGoalArchiveData: String
    var dailyBurnedCalorieArchiveData: String
    var dailyExerciseArchiveData: String
    var venueMenusData: String
    var venueMenuSignaturesData: String
    var quickAddFoodsData: String
    var calibrationStateData: String
    var healthWeighInsData: String
    var cloudSyncLocalModifiedAt: Double
    var useAIBaseServings: Bool
    var updatedAt: Date

    init(id: String, snapshot: PersistentAppStateSnapshot) {
        self.id = id
        hasCompletedOnboarding = snapshot.hasCompletedOnboarding
        deficitCalories = snapshot.deficitCalories
        useWeekendDeficit = snapshot.useWeekendDeficit
        weekendDeficitCalories = snapshot.weekendDeficitCalories
        goalTypeRaw = snapshot.goalTypeRaw
        surplusCalories = snapshot.surplusCalories
        fixedGoalCalories = snapshot.fixedGoalCalories
        dailyGoalTypeArchiveData = snapshot.dailyGoalTypeArchiveData
        proteinGoal = snapshot.proteinGoal
        mealEntriesData = snapshot.mealEntriesData
        trackedNutrientsData = snapshot.trackedNutrientsData
        nutrientGoalsData = snapshot.nutrientGoalsData
        lastCentralDayIdentifier = snapshot.lastCentralDayIdentifier
        selectedAppIconChoiceRaw = snapshot.selectedAppIconChoiceRaw
        dailyEntryArchiveData = snapshot.dailyEntryArchiveData
        dailyCalorieGoalArchiveData = snapshot.dailyCalorieGoalArchiveData
        dailyBurnedCalorieArchiveData = snapshot.dailyBurnedCalorieArchiveData
        dailyExerciseArchiveData = snapshot.dailyExerciseArchiveData
        venueMenusData = snapshot.venueMenusData
        venueMenuSignaturesData = snapshot.venueMenuSignaturesData
        quickAddFoodsData = snapshot.quickAddFoodsData
        calibrationStateData = snapshot.calibrationStateData
        healthWeighInsData = snapshot.healthWeighInsData
        cloudSyncLocalModifiedAt = snapshot.cloudSyncLocalModifiedAt
        useAIBaseServings = snapshot.useAIBaseServings
        updatedAt = Date()
    }

    func apply(_ snapshot: PersistentAppStateSnapshot) {
        hasCompletedOnboarding = snapshot.hasCompletedOnboarding
        deficitCalories = snapshot.deficitCalories
        useWeekendDeficit = snapshot.useWeekendDeficit
        weekendDeficitCalories = snapshot.weekendDeficitCalories
        goalTypeRaw = snapshot.goalTypeRaw
        surplusCalories = snapshot.surplusCalories
        fixedGoalCalories = snapshot.fixedGoalCalories
        dailyGoalTypeArchiveData = snapshot.dailyGoalTypeArchiveData
        proteinGoal = snapshot.proteinGoal
        mealEntriesData = snapshot.mealEntriesData
        trackedNutrientsData = snapshot.trackedNutrientsData
        nutrientGoalsData = snapshot.nutrientGoalsData
        lastCentralDayIdentifier = snapshot.lastCentralDayIdentifier
        selectedAppIconChoiceRaw = snapshot.selectedAppIconChoiceRaw
        dailyEntryArchiveData = snapshot.dailyEntryArchiveData
        dailyCalorieGoalArchiveData = snapshot.dailyCalorieGoalArchiveData
        dailyBurnedCalorieArchiveData = snapshot.dailyBurnedCalorieArchiveData
        dailyExerciseArchiveData = snapshot.dailyExerciseArchiveData
        venueMenusData = snapshot.venueMenusData
        venueMenuSignaturesData = snapshot.venueMenuSignaturesData
        quickAddFoodsData = snapshot.quickAddFoodsData
        calibrationStateData = snapshot.calibrationStateData
        healthWeighInsData = snapshot.healthWeighInsData
        cloudSyncLocalModifiedAt = snapshot.cloudSyncLocalModifiedAt
        useAIBaseServings = snapshot.useAIBaseServings
        updatedAt = Date()
    }

    var snapshot: PersistentAppStateSnapshot {
        PersistentAppStateSnapshot(
            hasCompletedOnboarding: hasCompletedOnboarding,
            deficitCalories: deficitCalories,
            useWeekendDeficit: useWeekendDeficit,
            weekendDeficitCalories: weekendDeficitCalories,
            goalTypeRaw: goalTypeRaw,
            surplusCalories: surplusCalories,
            fixedGoalCalories: fixedGoalCalories,
            dailyGoalTypeArchiveData: dailyGoalTypeArchiveData,
            proteinGoal: proteinGoal,
            mealEntriesData: mealEntriesData,
            trackedNutrientsData: trackedNutrientsData,
            nutrientGoalsData: nutrientGoalsData,
            lastCentralDayIdentifier: lastCentralDayIdentifier,
            selectedAppIconChoiceRaw: selectedAppIconChoiceRaw,
            dailyEntryArchiveData: dailyEntryArchiveData,
            dailyCalorieGoalArchiveData: dailyCalorieGoalArchiveData,
            dailyBurnedCalorieArchiveData: dailyBurnedCalorieArchiveData,
            dailyExerciseArchiveData: dailyExerciseArchiveData,
            venueMenusData: venueMenusData,
            venueMenuSignaturesData: venueMenuSignaturesData,
            quickAddFoodsData: quickAddFoodsData,
            calibrationStateData: calibrationStateData,
            healthWeighInsData: healthWeighInsData,
            cloudSyncLocalModifiedAt: cloudSyncLocalModifiedAt,
            useAIBaseServings: useAIBaseServings
        )
    }
}

@MainActor
final class PersistentAppStateStore {
    static let shared = PersistentAppStateStore()
    static let recordID = "main"

    private let container: ModelContainer?
    private let context: ModelContext?

    private init() {
        let storeURL = Self.makeStoreURL()
        let configuration = ModelConfiguration(url: storeURL)

        if let loaded = try? ModelContainer(for: PersistentAppStateRecord.self, configurations: configuration) {
            container = loaded
            context = ModelContext(loaded)
            return
        }

        // If the on-disk schema is incompatible/corrupt, rebuild this auxiliary store.
        Self.removeStoreFiles(at: storeURL)
        if let reloaded = try? ModelContainer(for: PersistentAppStateRecord.self, configurations: configuration) {
            container = reloaded
            context = ModelContext(reloaded)
            return
        }

        // Keep app functional without SwiftData persistence if container still fails.
        container = nil
        context = nil
    }

    func bootstrapSnapshot(defaults: UserDefaults, fallback: PersistentAppStateSnapshot) -> PersistentAppStateSnapshot {
        let defaultsSnapshot = snapshotFromUserDefaults(defaults: defaults, fallback: fallback)
        let hasDefaultsData = defaultsSnapshot.hasMeaningfulData

        if let persisted = loadSnapshot() {
            let selected: PersistentAppStateSnapshot
            if !hasDefaultsData {
                selected = persisted
            } else if persisted.persistenceScore >= defaultsSnapshot.persistenceScore {
                selected = persisted
            } else {
                selected = defaultsSnapshot
                saveSnapshot(selected)
            }
            writeSnapshotToUserDefaults(selected, defaults: defaults)
            return selected
        }

        if hasDefaultsData {
            saveSnapshot(defaultsSnapshot)
            return defaultsSnapshot
        }

        saveSnapshot(fallback)
        return fallback
    }

    func saveSnapshot(_ snapshot: PersistentAppStateSnapshot) {
        guard context != nil else { return }
        if let record = fetchRecord() {
            record.apply(snapshot)
        } else {
            let record = PersistentAppStateRecord(id: Self.recordID, snapshot: snapshot)
            context?.insert(record)
        }

        do {
            try context?.save()
        } catch {
            // Keep local app flow resilient; UserDefaults remains as compatibility fallback.
        }
    }

    func loadSnapshot() -> PersistentAppStateSnapshot? {
        fetchRecord()?.snapshot
    }

    /// Read-only export of the full user snapshot.
    /// This does not write to SwiftData or UserDefaults; it only reads and returns the richest available snapshot.
    func exportSnapshot(defaults: UserDefaults) -> PersistentAppStateSnapshot? {
        let persisted = loadSnapshot()
        let fallback = persisted ?? Self.makeExportFallbackSnapshot()
        let defaultsSnapshot = snapshotFromUserDefaults(defaults: defaults, fallback: fallback)

        if let persisted {
            // Prefer whichever contains more historical archive data.
            return (persisted.persistenceScore >= defaultsSnapshot.persistenceScore) ? persisted : defaultsSnapshot
        }

        return defaultsSnapshot.hasMeaningfulData ? defaultsSnapshot : nil
    }

    private static func makeExportFallbackSnapshot() -> PersistentAppStateSnapshot {
        PersistentAppStateSnapshot(
            hasCompletedOnboarding: false,
            deficitCalories: 500,
            useWeekendDeficit: false,
            weekendDeficitCalories: 0,
            goalTypeRaw: "deficit",
            surplusCalories: 300,
            fixedGoalCalories: 2000,
            dailyGoalTypeArchiveData: "",
            proteinGoal: 150,
            mealEntriesData: "",
            trackedNutrientsData: "",
            nutrientGoalsData: "",
            lastCentralDayIdentifier: "",
            selectedAppIconChoiceRaw: "standard",
            dailyEntryArchiveData: "",
            dailyCalorieGoalArchiveData: "",
            dailyBurnedCalorieArchiveData: "",
            dailyExerciseArchiveData: "",
            venueMenusData: "",
            venueMenuSignaturesData: "",
            quickAddFoodsData: "",
            calibrationStateData: "",
            healthWeighInsData: "",
            cloudSyncLocalModifiedAt: 0,
            useAIBaseServings: true
        )
    }

    private func fetchRecord() -> PersistentAppStateRecord? {
        guard let context else { return nil }
        let targetID = Self.recordID
        let descriptor = FetchDescriptor<PersistentAppStateRecord>(
            predicate: #Predicate<PersistentAppStateRecord> { $0.id == targetID }
        )
        do {
            return try context.fetch(descriptor).first
        } catch {
            return nil
        }
    }

    private static func makeStoreURL() -> URL {
        let fm = FileManager.default
        let appSupport = (try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fm.temporaryDirectory
        return appSupport.appendingPathComponent("PersistentAppState.sqlite")
    }

    private static func removeStoreFiles(at baseURL: URL) {
        let fm = FileManager.default
        let urls = [
            baseURL,
            URL(fileURLWithPath: baseURL.path + "-shm"),
            URL(fileURLWithPath: baseURL.path + "-wal")
        ]
        for url in urls where fm.fileExists(atPath: url.path) {
            try? fm.removeItem(at: url)
        }
    }

    private func snapshotFromUserDefaults(defaults: UserDefaults, fallback: PersistentAppStateSnapshot) -> PersistentAppStateSnapshot {
        PersistentAppStateSnapshot(
            hasCompletedOnboarding: bool(forKey: "hasCompletedOnboarding", defaults: defaults, fallback: fallback.hasCompletedOnboarding),
            deficitCalories: int(forKey: "deficitCalories", defaults: defaults, fallback: fallback.deficitCalories),
            useWeekendDeficit: bool(forKey: "useWeekendDeficit", defaults: defaults, fallback: fallback.useWeekendDeficit),
            weekendDeficitCalories: int(forKey: "weekendDeficitCalories", defaults: defaults, fallback: fallback.weekendDeficitCalories),
            goalTypeRaw: string(forKey: "goalTypeRaw", defaults: defaults, fallback: fallback.goalTypeRaw),
            surplusCalories: int(forKey: "surplusCalories", defaults: defaults, fallback: fallback.surplusCalories),
            fixedGoalCalories: int(forKey: "fixedGoalCalories", defaults: defaults, fallback: fallback.fixedGoalCalories),
            dailyGoalTypeArchiveData: string(forKey: "dailyGoalTypeArchiveData", defaults: defaults, fallback: fallback.dailyGoalTypeArchiveData),
            proteinGoal: int(forKey: "proteinGoal", defaults: defaults, fallback: fallback.proteinGoal),
            mealEntriesData: string(forKey: "mealEntriesData", defaults: defaults, fallback: fallback.mealEntriesData),
            trackedNutrientsData: string(forKey: "trackedNutrientsData", defaults: defaults, fallback: fallback.trackedNutrientsData),
            nutrientGoalsData: string(forKey: "nutrientGoalsData", defaults: defaults, fallback: fallback.nutrientGoalsData),
            lastCentralDayIdentifier: string(forKey: "lastCentralDayIdentifier", defaults: defaults, fallback: fallback.lastCentralDayIdentifier),
            selectedAppIconChoiceRaw: string(forKey: "selectedAppIconChoice", defaults: defaults, fallback: fallback.selectedAppIconChoiceRaw),
            dailyEntryArchiveData: string(forKey: "dailyEntryArchiveData", defaults: defaults, fallback: fallback.dailyEntryArchiveData),
            dailyCalorieGoalArchiveData: string(forKey: "dailyCalorieGoalArchiveData", defaults: defaults, fallback: fallback.dailyCalorieGoalArchiveData),
            dailyBurnedCalorieArchiveData: string(forKey: "dailyBurnedCalorieArchiveData", defaults: defaults, fallback: fallback.dailyBurnedCalorieArchiveData),
            dailyExerciseArchiveData: string(forKey: "dailyExerciseArchiveData", defaults: defaults, fallback: fallback.dailyExerciseArchiveData),
            venueMenusData: string(forKey: "venueMenusData", defaults: defaults, fallback: fallback.venueMenusData),
            venueMenuSignaturesData: string(forKey: "venueMenuSignaturesData", defaults: defaults, fallback: fallback.venueMenuSignaturesData),
            quickAddFoodsData: string(forKey: "quickAddFoodsData", defaults: defaults, fallback: fallback.quickAddFoodsData),
            calibrationStateData: string(forKey: "calibrationStateData", defaults: defaults, fallback: fallback.calibrationStateData),
            healthWeighInsData: string(forKey: "healthWeighInsData", defaults: defaults, fallback: fallback.healthWeighInsData),
            cloudSyncLocalModifiedAt: double(forKey: "cloudSyncLocalModifiedAt", defaults: defaults, fallback: fallback.cloudSyncLocalModifiedAt),
            useAIBaseServings: bool(forKey: "useAIBaseServings", defaults: defaults, fallback: fallback.useAIBaseServings)
        )
    }

    private func writeSnapshotToUserDefaults(_ snapshot: PersistentAppStateSnapshot, defaults: UserDefaults) {
        defaults.set(snapshot.hasCompletedOnboarding, forKey: "hasCompletedOnboarding")
        defaults.set(snapshot.deficitCalories, forKey: "deficitCalories")
        defaults.set(snapshot.useWeekendDeficit, forKey: "useWeekendDeficit")
        defaults.set(snapshot.weekendDeficitCalories, forKey: "weekendDeficitCalories")
        defaults.set(snapshot.goalTypeRaw, forKey: "goalTypeRaw")
        defaults.set(snapshot.surplusCalories, forKey: "surplusCalories")
        defaults.set(snapshot.fixedGoalCalories, forKey: "fixedGoalCalories")
        defaults.set(snapshot.dailyGoalTypeArchiveData, forKey: "dailyGoalTypeArchiveData")
        defaults.set(snapshot.proteinGoal, forKey: "proteinGoal")
        defaults.set(snapshot.mealEntriesData, forKey: "mealEntriesData")
        defaults.set(snapshot.trackedNutrientsData, forKey: "trackedNutrientsData")
        defaults.set(snapshot.nutrientGoalsData, forKey: "nutrientGoalsData")
        defaults.set(snapshot.lastCentralDayIdentifier, forKey: "lastCentralDayIdentifier")
        defaults.set(snapshot.selectedAppIconChoiceRaw, forKey: "selectedAppIconChoice")
        defaults.set(snapshot.dailyEntryArchiveData, forKey: "dailyEntryArchiveData")
        defaults.set(snapshot.dailyCalorieGoalArchiveData, forKey: "dailyCalorieGoalArchiveData")
        defaults.set(snapshot.dailyBurnedCalorieArchiveData, forKey: "dailyBurnedCalorieArchiveData")
        defaults.set(snapshot.dailyExerciseArchiveData, forKey: "dailyExerciseArchiveData")
        defaults.set(snapshot.venueMenusData, forKey: "venueMenusData")
        defaults.set(snapshot.venueMenuSignaturesData, forKey: "venueMenuSignaturesData")
        defaults.set(snapshot.quickAddFoodsData, forKey: "quickAddFoodsData")
        defaults.set(snapshot.calibrationStateData, forKey: "calibrationStateData")
        defaults.set(snapshot.healthWeighInsData, forKey: "healthWeighInsData")
        defaults.set(snapshot.cloudSyncLocalModifiedAt, forKey: "cloudSyncLocalModifiedAt")
        defaults.set(snapshot.useAIBaseServings, forKey: "useAIBaseServings")
    }

    private func string(forKey key: String, defaults: UserDefaults, fallback: String) -> String {
        if let value = defaults.object(forKey: key) as? String {
            return value
        }
        return fallback
    }

    private func int(forKey key: String, defaults: UserDefaults, fallback: Int) -> Int {
        if let value = defaults.object(forKey: key) as? NSNumber {
            return value.intValue
        }
        return fallback
    }

    private func double(forKey key: String, defaults: UserDefaults, fallback: Double) -> Double {
        if let value = defaults.object(forKey: key) as? NSNumber {
            return value.doubleValue
        }
        return fallback
    }

    private func bool(forKey key: String, defaults: UserDefaults, fallback: Bool) -> Bool {
        if let value = defaults.object(forKey: key) as? NSNumber {
            return value.boolValue
        }
        return fallback
    }
}
