import Foundation
import HealthKit
import CoreMotion

@MainActor
final class BackgroundWidgetRefreshService {
    static let shared = BackgroundWidgetRefreshService()

    private struct StoredState {
        enum GoalType: String {
            case deficit
            case surplus
        }

        let entries: [MealEntry]
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
        let calibrationState: CalibrationState
    }

    private struct StepMetrics {
        let steps: Int
        let distanceMeters: Double
    }

    private static let fallbackAverageBMR = 1800
    private static let defaultWeightPounds = 170.0
    private static let defaultHeightInches = 68.0
    private static let netWalkingCaloriesPerKgPerKm = 0.50
    private static let strideMultiplier = 0.415

    private let healthStore = HKHealthStore()
    private let pedometer = CMPedometer()
    private let defaults = UserDefaults.standard
    private let decoder = JSONDecoder()

    func refreshSnapshot() async -> Bool {
        let state = loadState()
        let profile = await fetchProfile()
        let healthWorkouts = await fetchTodayWorkouts(profile: profile)
        let stepMetrics = await fetchStepMetrics()
        let snapshot = makeSnapshot(
            from: state,
            profile: profile,
            healthWorkouts: healthWorkouts,
            stepMetrics: stepMetrics
        )

        if WidgetSnapshotStore.load() == snapshot {
            return false
        }

        persistDailyTotals(goal: snapshot.goalCalories, burned: snapshot.burnedCalories)
        WidgetSnapshotStore.save(snapshot)
        return true
    }

    private func makeSnapshot(
        from state: StoredState,
        profile: BMRProfile?,
        healthWorkouts: [ExerciseEntry],
        stepMetrics: StepMetrics
    ) -> WidgetCalorieSnapshot {
        let todayID = centralDayIdentifier(for: Date())
        let manualExercises = state.exercisesByDay[todayID] ?? []
        let allExercises = manualExercises + healthWorkouts
        let totalCalories = max(state.entries.reduce(0) { $0 + $1.calories }, 0)

        let activityCalories = estimatedActivityCalories(stepMetrics: stepMetrics, profile: profile)
        let reclassifiedWalkingCalories = min(
            allExercises.reduce(0) { $0 + $1.reclassifiedWalkingCalories },
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

        let safeGoal = max(calorieModel.goal, 1)
        let burned = max(calorieModel.burned, 0)
        let nutrientTotals = nutrientTotals(from: state.entries)
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
            progress: min(max(Double(totalCalories) / Double(safeGoal), 0), 1),
            trackedNutrients: Array(trackedNutrients)
        )
    }

    private func persistDailyTotals(goal: Int, burned: Int) {
        let todayID = centralDayIdentifier(for: Date())

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
        if profile == nil,
           let archivedGoal = state.dailyCalorieGoalArchive[dayIdentifier],
           let archivedBurned = state.dailyBurnedCalorieArchive[dayIdentifier] {
            return (
                burned: max(archivedBurned, 1),
                goal: max(archivedGoal, 1)
            )
        }

        let bmr = calculatedBMR(for: profile) ?? Self.fallbackAverageBMR
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
            if stepMetrics.distanceMeters > 0 {
                return stepMetrics.distanceMeters / 1000
            }
            let strideMeters = estimatedStrideMeters(heightMeters: resolvedHeightMeters(profile: profile))
            let estimatedDistanceMeters = Double(stepMetrics.steps) * strideMeters
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

        return StoredState(
            entries: entries,
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
                let entries = workouts.map { workout -> ExerciseEntry in
                    HealthKitWorkoutMapper.makeExerciseEntry(from: workout, profile: profile)
                }
                continuation.resume(returning: entries)
            }
            healthStore.execute(query)
        }
    }

    private func fetchStepMetrics() async -> StepMetrics {
        let pedometerMetrics = await fetchPedometerStepMetrics()
        if pedometerMetrics.steps > 0 || pedometerMetrics.distanceMeters > 0 {
            return pedometerMetrics
        }

        let stepCount = await todayQuantitySum(for: .stepCount, unit: .count())
        let distanceMeters = await todayQuantitySum(for: .distanceWalkingRunning, unit: .meter())
        if stepCount > 0 || distanceMeters > 0 {
            return StepMetrics(
                steps: max(Int(stepCount.rounded()), 0),
                distanceMeters: max(distanceMeters, 0)
            )
        }

        return StepMetrics(steps: 0, distanceMeters: 0)
    }

    private func todayQuantitySum(for identifier: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else {
            return 0
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        let startOfDay = calendar.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: Date(), options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, statistics, _ in
                let value = statistics?.sumQuantity()?.doubleValue(for: unit) ?? 0
                continuation.resume(returning: max(value, 0))
            }
            healthStore.execute(query)
        }
    }

    private func fetchPedometerStepMetrics() async -> StepMetrics {
        guard CMPedometer.isStepCountingAvailable() else {
            return StepMetrics(steps: 0, distanceMeters: 0)
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        let startOfDay = calendar.startOfDay(for: Date())
        let now = Date()

        return await withCheckedContinuation { continuation in
            pedometer.queryPedometerData(from: startOfDay, to: now) { data, _ in
                let steps = max(data?.numberOfSteps.intValue ?? 0, 0)
                let distance = max(data?.distance?.doubleValue ?? 0, 0)
                continuation.resume(returning: StepMetrics(steps: steps, distanceMeters: distance))
            }
        }
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

        healthStore.enableBackgroundDelivery(for: sampleType, frequency: .immediate) { _, _ in }
    }
}
