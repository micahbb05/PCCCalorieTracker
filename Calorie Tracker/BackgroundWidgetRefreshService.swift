import Foundation
import HealthKit
import SwiftUI

@MainActor
final class BackgroundWidgetRefreshService {
    static let shared = BackgroundWidgetRefreshService()

    private struct StoredState {
        enum GoalType: String {
            case deficit
            case surplus
        }

        let entries: [MealEntry]
        let dailyEntryArchive: [String: [MealEntry]]
        let exercisesByDay: [String: [ExerciseEntry]]
        let dailyCalorieGoalArchive: [String: Int]
        let dailyBurnedCalorieArchive: [String: Int]
        let trackedNutrientKeys: [String]
        let nutrientGoals: [String: Int]
        let goalType: GoalType
        let goalTypeByDay: [String: String]
        let deficitCalories: Int
        let surplusCalories: Int
        let useWeekendDeficit: Bool
        let weekendDeficitCalories: Int
        let manualBMRCalories: Int
        let calibrationState: CalibrationState
    }

    private struct StepMetrics {
        let steps: Int
        let distanceMeters: Double
    }

    private static let defaultWeightPounds = 170.0
    private static let defaultHeightInches = 68.0
    private static let netWalkingCaloriesPerKgPerKm = 0.50
    private static let strideMultiplier = 0.415
    private static let maxDistanceToStepEstimateMultiplier = 1.15

    private let healthStore = HKHealthStore()
    private let defaults = UserDefaults.standard
    private let decoder = JSONDecoder()

    func refreshSnapshot() async -> Bool {
        let state = loadState()

        let todayID = centralDayIdentifier(for: Date())

        // Match ContentView's "effective profile + effective workouts" strategy:
        // - localHealthProfile may be nil on some devices/conditions
        // - cloudSynced profile/workouts can provide fallback values
        // - local workouts should still be mapped using the local profile (if nil, mapping uses nil),
        //   but BMR/step-calorie estimation can use the effective (cloud) profile.
        let localProfile = await fetchProfile()
        let cloudSyncedBMRProfile = loadCloudSyncedBMRProfile()
        let effectiveProfile = localProfile ?? cloudSyncedBMRProfile

        // Map local workouts using localProfile (not effectiveProfile) to mirror ContentView.
        let localHealthWorkouts = await fetchTodayWorkouts(profile: localProfile)
        let cloudSyncedTodayWorkouts = loadCloudSyncedTodayWorkouts(for: todayID)
        let effectiveHealthWorkouts = effectiveTodayHealthWorkouts(
            todayID: todayID,
            local: localHealthWorkouts,
            synced: cloudSyncedTodayWorkouts
        )

        let stepMetrics = await fetchStepMetrics()

        // Activity is detected when steps or workouts are present. The archive and the
        // activityDetectedDayIdentifier flag are only written when this is true, so
        // zero-step results can never corrupt today's burned/goal baseline.
        let hasActivity = stepMetrics.steps > 0 || !effectiveHealthWorkouts.isEmpty

        let snapshot = makeSnapshot(
            from: state,
            todayID: todayID,
            profile: effectiveProfile,
            healthWorkouts: effectiveHealthWorkouts,
            stepMetrics: stepMetrics,
            hasActivity: hasActivity
        )

        if WidgetSnapshotStore.load() == snapshot {
            return false
        }

        if hasActivity {
            persistDailyTotals(goal: snapshot.goalCalories, burned: snapshot.burnedCalories, todayID: todayID)
            defaults.set(todayID, forKey: "activityDetectedDayIdentifier")
        }
        WidgetSnapshotStore.save(snapshot)
        WatchAppSyncService.shared.push(context: makeWatchSyncContext(from: snapshot, state: state))
        return true
    }

    private func makeSnapshot(
        from state: StoredState,
        todayID: String,
        profile: BMRProfile?,
        healthWorkouts: [ExerciseEntry],
        stepMetrics: StepMetrics,
        hasActivity: Bool
    ) -> WidgetCalorieSnapshot {
        let todayEntries = todayEntries(from: state, todayID: todayID)
        let totalCalories = max(todayEntries.reduce(0) { $0 + $1.calories }, 0)

        let (safeGoal, burned): (Int, Int)
        if hasActivity {
            let manualExercises = state.exercisesByDay[todayID] ?? []
            let allExercises = manualExercises + healthWorkouts
            let activityCalories = estimatedActivityCalories(stepMetrics: stepMetrics, profile: profile)
            let reclassifiedWalkingCalories = min(
                allExercises.reduce(0) { $0 + requestedWalkingReclassification(for: $1, profile: profile) },
                activityCalories
            )
            let effectiveActivityCalories = max(activityCalories - reclassifiedWalkingCalories, 0)
            let exerciseCalories = allExercises.reduce(0) { $0 + $1.calories }
            let calorieModel = dailyCalorieModel(
                state: state,
                dayIdentifier: todayID,
                profile: profile,
                exerciseCalories: exerciseCalories,
                effectiveActivityCalories: effectiveActivityCalories
            )
            safeGoal = max(calorieModel.goal, 1)
            burned = max(calorieModel.burned, 0)
        } else {
            // No activity from HealthKit — use the foreground cache written by the main
            // app when it last had real data, falling back to today's archive, then BMR.
            let foregroundCache = loadCachedCalorieModelForToday()
            let bmr = calculatedBMR(for: profile) ?? state.manualBMRCalories
            let fallbackBurned = foregroundCache?.burned ?? state.dailyBurnedCalorieArchive[todayID] ?? bmr
            let fallbackGoal = foregroundCache?.goal ?? state.dailyCalorieGoalArchive[todayID] ?? max(bmr - deficitForDay(state: state, dayIdentifier: todayID), 1)
            burned = max(fallbackBurned, 0)
            safeGoal = max(fallbackGoal, 1)
        }

        let nutrientTotals = nutrientTotals(from: todayEntries)
        let trackedNutrients = state.trackedNutrientKeys
            .filter { !NutrientCatalog.nonTrackableKeys.contains($0.lowercased()) }
            .prefix(3)
            .map { key -> WidgetCalorieSnapshot.TrackedNutrient in
                let definition = NutrientCatalog.definition(for: key)
                let total = max(nutrientTotals[key, default: 0], 0)
                let goal = max(state.nutrientGoals[key] ?? definition.defaultGoal, 1)
                let nutrientProgress = min(max(Double(total) / Double(goal), 0), 9.99)
                return .init(
                    key: key,
                    name: definition.name,
                    unit: definition.unit,
                    total: total,
                    goal: goal,
                    progress: nutrientProgress
                )
            }

        return WidgetCalorieSnapshot(
            updatedAt: Date(),
            consumedCalories: totalCalories,
            goalCalories: safeGoal,
            burnedCalories: burned,
            caloriesLeft: max(safeGoal - totalCalories, 0),
            progress: max(Double(totalCalories) / Double(safeGoal), 0),
            goalTypeRaw: state.goalType.rawValue,
            selectedAppIconChoiceRaw: defaults.string(forKey: "selectedAppIconChoice") ?? AppIconChoice.standard.rawValue,
            trackedNutrients: Array(trackedNutrients)
        )
    }

    private func todayEntries(from state: StoredState, todayID: String) -> [MealEntry] {
        if let archived = state.dailyEntryArchive[todayID] {
            return archived
        }

        return state.entries.filter { entry in
            centralDayIdentifier(for: entry.createdAt) == todayID
        }
    }

    private func currentCloudOriginDeviceType() -> CloudSyncOriginDeviceType {
        switch UIDevice.current.userInterfaceIdiom {
        case .phone:
            return .iphone
        case .pad:
            return .ipad
        case .mac:
            return .mac
        default:
            return .unknown
        }
    }

    private func syncedHealthSourceDeviceType() -> CloudSyncOriginDeviceType {
        let raw = defaults.string(forKey: "syncedHealthSourceDeviceTypeRaw") ?? ""
        return CloudSyncOriginDeviceType(rawValue: raw) ?? .unknown
    }

    private func loadCloudSyncedBMRProfile() -> BMRProfile? {
        guard
            let raw = defaults.string(forKey: "syncedHealthProfileData"),
            !raw.isEmpty,
            let data = raw.data(using: .utf8),
            let decoded = try? decoder.decode(HealthKitService.SyncedProfile.self, from: data)
        else {
            return nil
        }
        return decoded.bmrProfile
    }

    private func loadCloudSyncedTodayWorkouts(for todayID: String) -> [ExerciseEntry] {
        guard
            let raw = defaults.string(forKey: "syncedTodayWorkoutsData"),
            !raw.isEmpty,
            let data = raw.data(using: .utf8),
            let decoded = try? decoder.decode([ExerciseEntry].self, from: data)
        else {
            return []
        }

        return decoded.filter { entry in
            centralDayIdentifier(for: entry.createdAt) == todayID
        }
    }

    private func effectiveTodayHealthWorkouts(
        todayID: String,
        local: [ExerciseEntry],
        synced: [ExerciseEntry]
    ) -> [ExerciseEntry] {
        // Filter local as a safety net (even though fetchTodayWorkouts queries only today).
        let localFiltered = local.filter { entry in
            centralDayIdentifier(for: entry.createdAt) == todayID
        }
        let syncedFiltered = synced

        if currentCloudOriginDeviceType() == .iphone {
            if localFiltered.isEmpty {
                return syncedFiltered
            }
            if syncedFiltered.isEmpty {
                return localFiltered
            }
            return mergedWorkoutEntries(primary: localFiltered, secondary: syncedFiltered)
        }

        let shouldUseIPhoneExerciseSource =
            currentCloudOriginDeviceType() != .iphone && syncedHealthSourceDeviceType() == .iphone

        if shouldUseIPhoneExerciseSource {
            return syncedFiltered
        }

        if localFiltered.isEmpty {
            return syncedFiltered
        }
        if syncedFiltered.isEmpty {
            return localFiltered
        }
        return mergedWorkoutEntries(primary: localFiltered, secondary: syncedFiltered)
    }

    private func mergedWorkoutEntries(primary: [ExerciseEntry], secondary: [ExerciseEntry]) -> [ExerciseEntry] {
        var mergedByKey: [String: ExerciseEntry] = [:]

        for entry in (primary + secondary) {
            let key = workoutMergeKey(for: entry)
            guard let existing = mergedByKey[key] else {
                mergedByKey[key] = entry
                continue
            }

            // Keep the duplicate that preserves the larger step-overlap reclassification.
            if entry.reclassifiedWalkingCalories > existing.reclassifiedWalkingCalories {
                mergedByKey[key] = entry
            }
        }

        return mergedByKey.values.sorted(by: { $0.createdAt > $1.createdAt })
    }

    private func workoutMergeKey(for entry: ExerciseEntry) -> String {
        let roundedTimestamp = Int(entry.createdAt.timeIntervalSince1970.rounded())
        let distanceBucket = Int(((entry.distanceMiles ?? 0) * 100).rounded())
        let name = (entry.customName ?? "")
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(entry.exerciseType.rawValue)|\(name)|\(entry.durationMinutes)|\(entry.calories)|\(distanceBucket)|\(roundedTimestamp)"
    }

    private func requestedWalkingReclassification(for entry: ExerciseEntry, profile: BMRProfile?) -> Int {
        guard entry.exerciseType == .running else {
            return max(entry.reclassifiedWalkingCalories, 0)
        }

        let weightPounds = profile?.weightPounds ?? Int(Self.defaultWeightPounds.rounded())
        let inferredWalkingEquivalent = ExerciseCalorieService.walkingEquivalentCalories(
            type: .running,
            durationMinutes: entry.durationMinutes,
            distanceMiles: entry.distanceMiles,
            weightPounds: weightPounds
        )
        return max(entry.reclassifiedWalkingCalories, inferredWalkingEquivalent)
    }

    private func makeWatchSyncContext(from snapshot: WidgetCalorieSnapshot, state: StoredState) -> [String: Any] {
        let todayEntries = state.entries
            .filter { Calendar.autoupdatingCurrent.isDateInToday($0.createdAt) }
            .sorted(by: { $0.createdAt > $1.createdAt })
            .prefix(12)
            .map { entry in
                [
                    "id": entry.id.uuidString,
                    "name": entry.name,
                    "calories": max(entry.calories, 0),
                    "createdAt": entry.createdAt.timeIntervalSince1970
                ] as [String: Any]
            }

        return [
            "goalCalories": max(snapshot.goalCalories, 1),
            "activityCalories": max(snapshot.burnedCalories, 0),
            "currentMealTitle": "Lunch",
            "goalTypeRaw": snapshot.goalTypeRaw,
            "selectedAppIconChoiceRaw": snapshot.selectedAppIconChoiceRaw,
            "venueMenuItems": [String: [String]](),
            "entries": todayEntries
        ]
    }

    private func persistDailyTotals(goal: Int, burned: Int, todayID: String) {
        // Only called when activity has been detected, so no high-water mark is needed —
        // zero-step results are rejected upstream and never reach here.
        var goalArchive: [String: Int] = decodeStringBackedJSON(forKey: "dailyCalorieGoalArchiveData", fallback: [:])
        goalArchive[todayID] = max(goal, 1)
        if let encodedGoals = try? JSONEncoder().encode(goalArchive) {
            defaults.set(String(decoding: encodedGoals, as: UTF8.self), forKey: "dailyCalorieGoalArchiveData")
        }

        var burnedArchive: [String: Int] = decodeStringBackedJSON(forKey: "dailyBurnedCalorieArchiveData", fallback: [:])
        burnedArchive[todayID] = max(burned, 1)
        if let encodedBurned = try? JSONEncoder().encode(burnedArchive) {
            defaults.set(String(decoding: encodedBurned, as: UTF8.self), forKey: "dailyBurnedCalorieArchiveData")
        }
    }

    private func dailyCalorieModel(
        state: StoredState,
        dayIdentifier: String,
        profile: BMRProfile?,
        exerciseCalories: Int,
        effectiveActivityCalories: Int
    ) -> (burned: Int, goal: Int) {
        let bmr = calculatedBMR(for: profile) ?? state.manualBMRCalories
        let burnedBaseline = max(bmr + exerciseCalories + effectiveActivityCalories, 1)
        let offset = state.calibrationState.isEnabled ? state.calibrationState.calibrationOffsetCalories : 0
        let burned = max(burnedBaseline + offset, 1)

        let dayGoalType = goalTypeForDay(state: state, dayIdentifier: dayIdentifier)
        let amount = deficitForDay(state: state, dayIdentifier: dayIdentifier)
        let goal: Int
        if dayGoalType == .surplus {
            goal = max(burned + amount, 1)
        } else {
            goal = max(burned - amount, 1)
        }
        return (burned: burned, goal: goal)
    }

    private func goalTypeForDay(state: StoredState, dayIdentifier: String) -> StoredState.GoalType {
        let todayID = centralDayIdentifier(for: Date())
        if dayIdentifier == todayID {
            return state.goalType
        }
        if let raw = state.goalTypeByDay[dayIdentifier], let parsed = StoredState.GoalType(rawValue: raw) {
            return parsed
        }
        return state.goalType
    }

    private func deficitForDay(state: StoredState, dayIdentifier: String) -> Int {
        let normalizedDeficit = min(max(state.deficitCalories, 0), 2500)
        let normalizedSurplus = min(max(state.surplusCalories, 0), 2500)
        let normalizedWeekendDeficit = min(max(state.weekendDeficitCalories, 0), 2500)
        let resolvedGoalType = goalTypeForDay(state: state, dayIdentifier: dayIdentifier)

        guard state.useWeekendDeficit else {
            return resolvedGoalType == .surplus ? normalizedSurplus : normalizedDeficit
        }

        guard let date = date(fromCentralDayIdentifier: dayIdentifier) else {
            return resolvedGoalType == .surplus ? normalizedSurplus : normalizedDeficit
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        let weekday = calendar.component(.weekday, from: date)
        let isWeekend = weekday == 1 || weekday == 7
        if isWeekend {
            return normalizedWeekendDeficit
        }
        return resolvedGoalType == .surplus ? normalizedSurplus : normalizedDeficit
    }

    private func nutrientTotals(from entries: [MealEntry]) -> [String: Int] {
        entries.reduce(into: [:]) { partialResult, entry in
            for (key, value) in entry.nutrientValues {
                partialResult[key, default: 0] += value
            }
        }
    }

    private func estimatedActivityCalories(stepMetrics: StepMetrics, profile: BMRProfile?) -> Int {
        guard stepMetrics.steps > 0 else {
            return 0
        }

        let distanceKm: Double = {
            let strideMeters = estimatedStrideMeters(heightMeters: resolvedHeightMeters(profile: profile))
            let estimatedDistanceMeters = Double(stepMetrics.steps) * strideMeters
            guard estimatedDistanceMeters > 0 else { return 0 }

            if stepMetrics.distanceMeters > 0 {
                let maxPlausibleDistanceMeters = estimatedDistanceMeters * Self.maxDistanceToStepEstimateMultiplier
                let cappedDistanceMeters = min(stepMetrics.distanceMeters, maxPlausibleDistanceMeters)
                return max(cappedDistanceMeters / 1000, 0)
            }

            return max(estimatedDistanceMeters / 1000, 0)
        }()
        guard distanceKm > 0 else {
            return 0
        }

        let weightKg = resolvedWeightKg(profile: profile)
        return max(Int((weightKg * distanceKm * Self.netWalkingCaloriesPerKgPerKm).rounded()), 0)
    }

    private func resolvedWeightKg(profile: BMRProfile?) -> Double {
        let weightPounds = Double(profile?.weightPounds ?? 0)
        let resolved = weightPounds > 0 ? weightPounds : Self.defaultWeightPounds
        return resolved * 0.45359237
    }

    private func resolvedHeightMeters(profile: BMRProfile?) -> Double {
        let feet = Double(profile?.heightFeet ?? 0)
        let inches = Double(profile?.heightInches ?? 0)
        let totalInches = (feet > 0 || inches > 0) ? max((feet * 12) + inches, 0) : Self.defaultHeightInches
        return totalInches * 0.0254
    }

    private func estimatedStrideMeters(heightMeters: Double) -> Double {
        max(heightMeters * Self.strideMultiplier, 0)
    }

    private func calculatedBMR(for profile: BMRProfile?) -> Int? {
        guard let profile, profile.isComplete else { return nil }
        let weightKg = Double(profile.weightPounds) * 0.45359237
        let totalInches = (profile.heightFeet * 12) + profile.heightInches
        let heightCm = Double(totalInches) * 2.54
        let sexConstant = profile.sex == .male ? 5.0 : -161.0
        let raw = (10.0 * weightKg) + (6.25 * heightCm) - (5.0 * Double(profile.age)) + sexConstant
        return max(Int(raw.rounded()), 800)
    }

    private func centralDayIdentifier(for date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        let startOfDay = calendar.startOfDay(for: date)
        let components = calendar.dateComponents([.year, .month, .day], from: startOfDay)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 1, components.day ?? 1)
    }

    private func date(fromCentralDayIdentifier identifier: String) -> Date? {
        let parts = identifier.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        let components = DateComponents(timeZone: calendar.timeZone, year: parts[0], month: parts[1], day: parts[2])
        return calendar.date(from: components)
    }

    private func loadState() -> StoredState {
        let entries: [MealEntry] = decodeStringBackedJSON(forKey: "mealEntriesData", fallback: [])
        let dailyEntryArchive: [String: [MealEntry]] = decodeStringBackedJSON(forKey: "dailyEntryArchiveData", fallback: [:])
        let exercisesByDay: [String: [ExerciseEntry]] = decodeStringBackedJSON(forKey: "dailyExerciseArchiveData", fallback: [:])
        let dailyCalorieGoalArchive: [String: Int] = decodeStringBackedJSON(forKey: "dailyCalorieGoalArchiveData", fallback: [:])
        let dailyBurnedCalorieArchive: [String: Int] = decodeStringBackedJSON(forKey: "dailyBurnedCalorieArchiveData", fallback: [:])
        let trackedNutrientKeys: [String] = decodeStringBackedJSON(forKey: "trackedNutrientsData", fallback: ["g_protein"])
        let nutrientGoals: [String: Int] = decodeStringBackedJSON(forKey: "nutrientGoalsData", fallback: [:])
        let goalTypeByDay: [String: String] = decodeStringBackedJSON(forKey: "dailyGoalTypeArchiveData", fallback: [:])
        let calibrationState: CalibrationState = decodeStringBackedJSON(forKey: "calibrationStateData", fallback: .default)

        let goalTypeRaw = defaults.string(forKey: "goalTypeRaw") ?? "deficit"
        let goalType = StoredState.GoalType(rawValue: goalTypeRaw) ?? .deficit
        let deficitCalories = defaults.integer(forKey: "deficitCalories")
        let surplusCalories = defaults.integer(forKey: "surplusCalories")
        let useWeekendDeficit = defaults.bool(forKey: "useWeekendDeficit")
        let weekendDeficitCalories = defaults.integer(forKey: "weekendDeficitCalories")
        let manualBMRCalories = min(max(defaults.integer(forKey: "manualBMRCalories"), 800), 4000)

        return StoredState(
            entries: entries,
            dailyEntryArchive: dailyEntryArchive,
            exercisesByDay: exercisesByDay,
            dailyCalorieGoalArchive: dailyCalorieGoalArchive,
            dailyBurnedCalorieArchive: dailyBurnedCalorieArchive,
            trackedNutrientKeys: trackedNutrientKeys,
            nutrientGoals: nutrientGoals,
            goalType: goalType,
            goalTypeByDay: goalTypeByDay,
            deficitCalories: deficitCalories,
            surplusCalories: surplusCalories,
            useWeekendDeficit: useWeekendDeficit,
            weekendDeficitCalories: weekendDeficitCalories,
            manualBMRCalories: manualBMRCalories,
            calibrationState: calibrationState
        )
    }

    private func decodeStringBackedJSON<T: Decodable>(forKey key: String, fallback: T) -> T {
        guard
            let stored = defaults.string(forKey: key),
            !stored.isEmpty,
            let data = stored.data(using: .utf8),
            let decoded = try? decoder.decode(T.self, from: data)
        else {
            return fallback
        }
        return decoded
    }

    private func fetchProfile() async -> BMRProfile? {
        guard HKHealthStore.isHealthDataAvailable() else {
            return nil
        }

        do {
            let sexObject = try healthStore.biologicalSex()
            let dateOfBirth = try healthStore.dateOfBirthComponents()

            guard
                let sex = mapSex(sexObject.biologicalSex),
                let birthDate = Calendar.autoupdatingCurrent.date(from: dateOfBirth)
            else {
                return nil
            }

            let age = max(Calendar.autoupdatingCurrent.dateComponents([.year], from: birthDate, to: Date()).year ?? 0, 0)
            guard age > 0 else { return nil }

            async let heightInches = latestQuantityValue(for: .height, unit: .inch())
            async let weightPounds = latestQuantityValue(for: .bodyMass, unit: .pound())

            guard
                let totalHeightInches = await heightInches,
                let weight = await weightPounds
            else {
                return nil
            }

            let roundedHeight = max(Int(totalHeightInches.rounded()), 0)
            let roundedWeight = max(Int(weight.rounded()), 0)
            guard roundedHeight > 0, roundedWeight > 0 else {
                return nil
            }

            return BMRProfile(
                age: age,
                sex: sex,
                heightFeet: roundedHeight / 12,
                heightInches: roundedHeight % 12,
                weightPounds: roundedWeight
            )
        } catch {
            return nil
        }
    }

    private func latestQuantityValue(for identifier: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double? {
        guard let quantityType = HKObjectType.quantityType(forIdentifier: identifier) else {
            return nil
        }
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let predicate = HKQuery.predicateForSamples(withStart: nil, end: Date())

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: quantityType, predicate: predicate, limit: 1, sortDescriptors: [sortDescriptor]) { _, samples, _ in
                let value = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit)
                continuation.resume(returning: value)
            }
            healthStore.execute(query)
        }
    }

    private func mapSex(_ sex: HKBiologicalSex) -> BMRSex? {
        switch sex {
        case .male:
            return .male
        case .female:
            return .female
        default:
            return nil
        }
    }

    private func fetchTodayWorkouts(profile: BMRProfile?) async -> [ExerciseEntry] {
        let workoutType = HKObjectType.workoutType()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        let startOfToday = calendar.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: startOfToday, end: Date(), options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: workoutType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, _ in
                let workouts = (samples as? [HKWorkout]) ?? []
                let preferredWorkouts = Self.preferredIPhoneSamples(from: workouts)
                let entries = preferredWorkouts.map { workout -> ExerciseEntry in
                    HealthKitWorkoutMapper.makeExerciseEntry(from: workout, profile: profile)
                }
                continuation.resume(returning: entries)
            }
            healthStore.execute(query)
        }
    }

    nonisolated private static func preferredIPhoneSamples<T: HKSample>(from samples: [T]) -> [T] {
        let iPhoneSamples = samples.filter { isIPhoneSourceRevision($0.sourceRevision) }
        return iPhoneSamples.isEmpty ? samples : iPhoneSamples
    }

    nonisolated private static func isIPhoneSourceRevision(_ sourceRevision: HKSourceRevision) -> Bool {
        if let productType = sourceRevision.productType?.lowercased(), productType.contains("iphone") {
            return true
        }
        if sourceRevision.source.name.lowercased().contains("iphone") {
            return true
        }
        if sourceRevision.source.bundleIdentifier.lowercased().contains("iphone") {
            return true
        }
        return false
    }

    private func fetchStepMetrics() async -> StepMetrics {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        let metrics = await HealthKitStepMetricsLogic.fetchTodayStepMetrics(
            healthStore: healthStore,
            calendar: calendar
        )

        if metrics.stepError == nil {
            return StepMetrics(steps: metrics.steps, distanceMeters: metrics.distanceMeters)
        }

        // Background HealthKit query failed — fall back to the last step count the
        // foreground app successfully cached so the widget doesn't show 0-step calories.
        if let cached = loadCachedStepMetricsForToday() {
            return cached
        }
        return StepMetrics(steps: 0, distanceMeters: 0)
    }

    private func loadCachedStepMetricsForToday() -> StepMetrics? {
        guard
            let raw = defaults.string(forKey: "cachedTodayStepMetrics"),
            let data = raw.data(using: .utf8),
            let cached = try? decoder.decode(CachedStepMetrics.self, from: data),
            cached.dayIdentifier == centralDayIdentifier(for: Date())
        else {
            return nil
        }
        return StepMetrics(steps: cached.steps, distanceMeters: cached.distanceMeters)
    }

    private func loadCachedCalorieModelForToday() -> CachedCalorieModel? {
        guard
            let raw = defaults.string(forKey: "cachedTodayCalorieModel"),
            let data = raw.data(using: .utf8),
            let cached = try? decoder.decode(CachedCalorieModel.self, from: data),
            cached.dayIdentifier == centralDayIdentifier(for: Date())
        else {
            return nil
        }
        return cached
    }
}

@MainActor
final class HealthKitBackgroundObserver {
    static let shared = HealthKitBackgroundObserver()

    private let healthStore = HKHealthStore()
    private var observerQueries: [HKObserverQuery] = []
    private var isStarted = false

    func start() {
        guard HKHealthStore.isHealthDataAvailable(), !isStarted else { return }
        isStarted = true

        let sampleTypes = observedSampleTypes()
        for type in sampleTypes {
            registerObserver(for: type)
        }
    }

    private func observedSampleTypes() -> [HKSampleType] {
        var types: [HKSampleType] = [HKObjectType.workoutType()]
        if let stepCount = HKObjectType.quantityType(forIdentifier: .stepCount) {
            types.append(stepCount)
        }
        if let walkingDistance = HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning) {
            types.append(walkingDistance)
        }
        return types
    }

    private func registerObserver(for sampleType: HKSampleType) {
        let query = HKObserverQuery(sampleType: sampleType, predicate: nil) { _, completionHandler, _ in
            Task { @MainActor in
                _ = await BackgroundWidgetRefreshService.shared.refreshSnapshot()
                completionHandler()
            }
        }
        healthStore.execute(query)
        observerQueries.append(query)
    }
}
