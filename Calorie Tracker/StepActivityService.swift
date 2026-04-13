import Foundation
import HealthKit
import Combine

/// Persisted by `StepActivityService` after every successful foreground query.
/// Read by `BackgroundWidgetRefreshService` as a fallback when its own
/// background HealthKit query fails, so the widget never shows 0-step calories.
struct CachedStepMetrics: Codable {
    let dayIdentifier: String
    let steps: Int
    let distanceMeters: Double
}

/// Persisted by `ContentView.syncCurrentDayGoalArchive()` after every foreground
/// calorie computation. Read by `BackgroundWidgetRefreshService` as a hard floor
/// so background runs can never write a goal/burned lower than what the foreground
/// last computed — even if profile, workout, or step queries all fail in background.
struct CachedCalorieModel: Codable {
    let dayIdentifier: String
    let goal: Int
    let burned: Int
}

enum HealthKitStepMetricsLogic {
    struct StepMetrics {
        let steps: Int
        let distanceMeters: Double
        let stepError: Error?
    }

    struct QuantityQueryResult {
        let value: Double
        let error: Error?
    }

    static func fetchTodayStepMetrics(healthStore: HKHealthStore, calendar: Calendar) async -> StepMetrics {
        async let stepResult = todayQuantitySum(
            for: .stepCount,
            unit: .count(),
            healthStore: healthStore,
            calendar: calendar
        )
        async let distanceResult = todayQuantitySum(
            for: .distanceWalkingRunning,
            unit: .meter(),
            healthStore: healthStore,
            calendar: calendar
        )

        let resolvedStepResult = await stepResult
        let resolvedDistanceResult = await distanceResult
        let stepCount = max(Int(resolvedStepResult.value.rounded()), 0)
        let distanceMeters = resolvedDistanceResult.error == nil ? max(resolvedDistanceResult.value, 0) : 0

        return StepMetrics(steps: stepCount, distanceMeters: distanceMeters, stepError: resolvedStepResult.error)
    }

    static func todayQuantitySum(
        for identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        healthStore: HKHealthStore,
        calendar: Calendar
    ) async -> QuantityQueryResult {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else {
            return QuantityQueryResult(value: 0, error: nil)
        }

        let startOfDay = calendar.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: Date(), options: [])

        let statsResult: QuantityQueryResult = await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, error in
                if let error {
                    continuation.resume(returning: QuantityQueryResult(value: 0, error: error))
                    return
                }
                let value = result?.sumQuantity()?.doubleValue(for: unit) ?? 0
                continuation.resume(returning: QuantityQueryResult(value: max(value, 0), error: nil))
            }
            healthStore.execute(query)
        }

        if statsResult.error != nil || statsResult.value > 0 {
            return statsResult
        }

        // Fallback path for datasets where cumulative stats can return 0 even though samples exist.
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    continuation.resume(returning: QuantityQueryResult(value: 0, error: error))
                    return
                }
                let quantitySamples = (samples as? [HKQuantitySample]) ?? []
                let value = quantitySamples.reduce(0.0) { partial, sample in
                    partial + sample.quantity.doubleValue(for: unit)
                }
                continuation.resume(returning: QuantityQueryResult(value: max(value, 0), error: nil))
            }
            healthStore.execute(query)
        }
    }
}

@MainActor
final class StepActivityService: ObservableObject {
    private static let defaultWeightPounds = 170.0
    private static let defaultHeightInches = 68.0
    // Net walking-energy approximation used because BMR is already counted separately.
    // Set to ACSM-style baseline for better average accuracy across users.
    private static let netWalkingCaloriesPerKgPerKm = 0.50
    private static let strideMultiplier = 0.415

    enum AuthorizationState: Equatable {
        case unavailable
        case notDetermined
        case denied
        case authorized

        var title: String {
            switch self {
            case .unavailable:
                return "Unavailable"
            case .notDetermined:
                return "Not Connected"
            case .denied:
                return "Permission Denied"
            case .authorized:
                return "Connected"
            }
        }

        var detail: String {
            switch self {
            case .unavailable:
                return "Apple Health is not available on this device."
            case .notDetermined:
                return "Connect Apple Health to adjust your calorie goal from steps."
            case .denied:
                return "Turn on Apple Health access in Settings to use step-based calories."
            case .authorized:
                return "Today's Apple Health step count is being used to adjust your calorie goal."
            }
        }
    }

    @Published private(set) var authorizationState: AuthorizationState
    @Published private(set) var todayStepCount: Int = 0
    @Published private(set) var todayDistanceMeters: Double = 0
    /// Used to prevent switching the UI from archived burned totals
    /// to "live" burned totals before initial step metrics have loaded.
    @Published private(set) var hasLoadedFreshStepDataThisLaunch: Bool = false
    @Published private(set) var lastErrorMessage: String?

    private let healthStore = HKHealthStore()
    private let calendar: Calendar
    private var observerQueries: [HKObserverQuery] = []

    init() {
        var centralCalendar = Calendar(identifier: .gregorian)
        centralCalendar.timeZone = .autoupdatingCurrent
        calendar = centralCalendar
        authorizationState = HKHealthStore.isHealthDataAvailable() ? .notDetermined : .unavailable
    }

    func estimatedCaloriesToday(profile: BMRProfile?) -> Int {
        guard todayStepCount > 0 else {
            return 0
        }

        let distanceKm = resolvedDistanceKm(profile: profile)
        guard distanceKm > 0 else {
            return 0
        }

        let weightKg = resolvedWeightKg(profile: profile)
        return max(Int((weightKg * distanceKm * Self.netWalkingCaloriesPerKgPerKm).rounded()), 0)
    }

    func refreshIfAuthorized() {
        guard HKHealthStore.isHealthDataAvailable() else {
            authorizationState = .unavailable
            hasLoadedFreshStepDataThisLaunch = true
            stopLiveUpdatesIfNeeded()
            todayStepCount = 0
            todayDistanceMeters = 0
            return
        }

        startLiveUpdatesIfNeeded()
        queryTodaySteps()
    }

    func requestAccessAndRefresh() {
        guard HKHealthStore.isHealthDataAvailable() else {
            authorizationState = .unavailable
            lastErrorMessage = AuthorizationState.unavailable.detail
            return
        }
        guard
            let stepType = HKObjectType.quantityType(forIdentifier: .stepCount),
            let distanceType = HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)
        else {
            authorizationState = .unavailable
            return
        }

        let readTypes: Set<HKObjectType> = [stepType, distanceType]
        healthStore.requestAuthorization(toShare: [], read: readTypes) { [weak self] _, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    self.lastErrorMessage = error.localizedDescription
                }
                self.refreshIfAuthorized()
            }
        }
    }

    private func queryTodaySteps() {
        Task {
            let metrics = await HealthKitStepMetricsLogic.fetchTodayStepMetrics(
                healthStore: healthStore,
                calendar: calendar
            )
            handleQueryResult(
                stepCount: metrics.steps,
                distanceMeters: metrics.distanceMeters,
                error: metrics.stepError
            )
        }
    }

    private func handleQueryResult(stepCount: Int, distanceMeters: Double, error: Error?) {
        if let error {
            lastErrorMessage = error.localizedDescription
            if let hkError = error as? HKError, hkError.code == .errorAuthorizationDenied {
                authorizationState = .denied
            } else if HKHealthStore.isHealthDataAvailable() {
                authorizationState = .notDetermined
            } else {
                authorizationState = .unavailable
            }
            stopLiveUpdatesIfNeeded()
            todayStepCount = 0
            todayDistanceMeters = 0
            hasLoadedFreshStepDataThisLaunch = true
            return
        }

        lastErrorMessage = nil
        todayStepCount = max(stepCount, 0)
        todayDistanceMeters = max(distanceMeters, 0)
        authorizationState = .authorized
        hasLoadedFreshStepDataThisLaunch = true
        if stepCount > 0 {
            cacheStepMetrics(steps: max(stepCount, 0), distanceMeters: max(distanceMeters, 0))
        }
    }

    private func cacheStepMetrics(steps: Int, distanceMeters: Double) {
        let components = calendar.dateComponents([.year, .month, .day], from: calendar.startOfDay(for: Date()))
        let dayID = String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 1, components.day ?? 1)
        let cached = CachedStepMetrics(dayIdentifier: dayID, steps: steps, distanceMeters: distanceMeters)
        if let data = try? JSONEncoder().encode(cached) {
            UserDefaults.standard.set(String(decoding: data, as: UTF8.self), forKey: "cachedTodayStepMetrics")
        }
    }

    private func startLiveUpdatesIfNeeded() {
        guard observerQueries.isEmpty else { return }
        guard HKHealthStore.isHealthDataAvailable() else { return }

        let identifiers: [HKQuantityTypeIdentifier] = [.stepCount, .distanceWalkingRunning]
        for identifier in identifiers {
            guard let quantityType = HKObjectType.quantityType(forIdentifier: identifier) else { continue }
            let observerQuery = HKObserverQuery(sampleType: quantityType, predicate: nil) { [weak self] _, completionHandler, error in
                Task { @MainActor in
                    defer { completionHandler() }
                    guard let self else { return }
                    if let error {
                        self.handleQueryResult(stepCount: self.todayStepCount, distanceMeters: self.todayDistanceMeters, error: error)
                    } else {
                        self.queryTodaySteps()
                    }
                }
            }
            healthStore.execute(observerQuery)
            observerQueries.append(observerQuery)
        }
    }

    private func stopLiveUpdatesIfNeeded() {
        guard !observerQueries.isEmpty else { return }
        for query in observerQueries {
            healthStore.stop(query)
        }
        observerQueries.removeAll()
    }

    deinit {
        for query in observerQueries {
            healthStore.stop(query)
        }
    }

    private func resolvedWeightKg(profile: BMRProfile?) -> Double {
        let weightPounds = Double(profile?.weightPounds ?? 0)
        let resolvedWeightPounds = weightPounds > 0 ? weightPounds : Self.defaultWeightPounds
        return resolvedWeightPounds * 0.45359237
    }

    private func resolvedHeightMeters(profile: BMRProfile?) -> Double {
        let feet = Double(profile?.heightFeet ?? 0)
        let inches = Double(profile?.heightInches ?? 0)
        let totalInches = feet > 0 || inches > 0 ? max((feet * 12) + inches, 0) : Self.defaultHeightInches
        return totalInches * 0.0254
    }

    private func resolvedDistanceKm(profile: BMRProfile?) -> Double {
        if todayDistanceMeters > 0 {
            return todayDistanceMeters / 1000
        }

        let strideMeters = estimatedStrideMeters(heightMeters: resolvedHeightMeters(profile: profile))
        let estimatedDistanceMeters = Double(todayStepCount) * strideMeters
        guard estimatedDistanceMeters > 0 else {
            return 0
        }

        return estimatedDistanceMeters / 1000
    }

    private func estimatedStrideMeters(heightMeters: Double) -> Double {
        max(heightMeters * Self.strideMultiplier, 0)
    }

}
