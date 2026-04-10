import Foundation
import HealthKit
import Combine

@MainActor
final class HealthKitService: ObservableObject {
    enum AuthorizationState: Equatable {
        case unavailable
        case notConnected
        case connected

        var title: String {
            switch self {
            case .unavailable:
                return "Unavailable"
            case .notConnected:
                return "Connect Health"
            case .connected:
                return "Connected"
            }
        }

        var detail: String {
            switch self {
            case .unavailable:
                return "Health data is not available on this device."
            case .notConnected:
                return "Connect Apple Health to read height, weight, sex, and age for more accurate calorie estimates."
            case .connected:
                return "BMR is calculated from Health data."
            }
        }
    }

    struct SyncedProfile: Codable, Equatable {
        let age: Int
        let sex: BMRSex
        let heightFeet: Int
        let heightInches: Int
        let weightPounds: Int

        var bmrProfile: BMRProfile {
            BMRProfile(
                age: age,
                sex: sex,
                heightFeet: heightFeet,
                heightInches: heightInches,
                weightPounds: weightPounds
            )
        }

        var heightDisplay: String {
            "\(heightFeet) ft \(heightInches) in"
        }

        var weightDisplay: String {
            "\(weightPounds) lb"
        }
    }

    @Published private(set) var authorizationState: AuthorizationState = .notConnected
    @Published private(set) var profile: SyncedProfile?
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var isRefreshingHealthData: Bool = false
    @Published private(set) var hasLoadedFreshHealthDataThisLaunch: Bool = false

    /// Today's workouts from Health, mapped to ExerciseEntry for calorie integration.
    @Published private(set) var todayWorkouts: [ExerciseEntry] = []
    @Published private(set) var reducedBodyMassHistory: [HealthWeighInDay] = []

    private let healthStore = HKHealthStore()
    private let calendar: Calendar

    init() {
        var centralCalendar = Calendar(identifier: .gregorian)
        centralCalendar.timeZone = .autoupdatingCurrent
        calendar = centralCalendar

        if !HKHealthStore.isHealthDataAvailable() {
            authorizationState = .unavailable
        } else {
            Task {
                await refreshIfPossible()
            }
        }
    }

    func refreshIfPossible() async {
        isRefreshingHealthData = true
        defer { isRefreshingHealthData = false }

        guard HKHealthStore.isHealthDataAvailable() else {
            authorizationState = .unavailable
            profile = nil
            todayWorkouts = []
            reducedBodyMassHistory = []
            return
        }

        do {
            let status = try await authorizationRequestStatus()
            authorizationState = (status == .unnecessary || hasAnyReadAuthorization) ? .connected : .notConnected
            guard authorizationState == .connected else {
                profile = nil
                todayWorkouts = []
                hasLoadedFreshHealthDataThisLaunch = true
                return
            }
            await loadHealthData()
            hasLoadedFreshHealthDataThisLaunch = true
        } catch {
            lastErrorMessage = error.localizedDescription
            authorizationState = .notConnected
            hasLoadedFreshHealthDataThisLaunch = true
        }
    }

    func requestAccessAndRefresh() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            authorizationState = .unavailable
            return
        }

        do {
            try await requestAuthorization()
            await refreshIfPossible()
        } catch {
            lastErrorMessage = error.localizedDescription
            authorizationState = .notConnected
        }
    }

    private func requestAuthorization() async throws {
        let readTypes = Self.readTypes
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            healthStore.requestAuthorization(toShare: [], read: readTypes) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: NSError(domain: "HealthKitService", code: 1, userInfo: [
                        NSLocalizedDescriptionKey: "Health access was not granted."
                    ]))
                }
            }
        }
    }

    private func authorizationRequestStatus() async throws -> HKAuthorizationRequestStatus {
        let readTypes = Self.readTypes
        return try await withCheckedThrowingContinuation { continuation in
            healthStore.getRequestStatusForAuthorization(toShare: [], read: readTypes) { status, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: status)
                }
            }
        }
    }

    private func loadHealthData() async {
        let fetchedProfile = await fetchProfile()
        async let fetchedWorkouts = fetchTodayWorkouts(profile: fetchedProfile?.bmrProfile)
        async let fetchedReducedBodyMassHistory = fetchReducedBodyMassHistory(days: 21)

        let workouts = await fetchedWorkouts
        let history = await fetchedReducedBodyMassHistory

        profile = fetchedProfile
        todayWorkouts = workouts
        reducedBodyMassHistory = history
        lastErrorMessage = nil
    }

    func refreshWorkouts() async {
        guard authorizationState == .connected else { return }
        todayWorkouts = await fetchTodayWorkouts(profile: profile?.bmrProfile)
    }

    func fetchReducedBodyMassHistory(days: Int = 21) async -> [HealthWeighInDay] {
        guard authorizationState == .connected || profile != nil else {
            return []
        }
        guard
            let bodyMassType = HKObjectType.quantityType(forIdentifier: .bodyMass),
            days > 0
        else {
            return []
        }

        let startOfToday = calendar.startOfDay(for: Date())
        let startDate = calendar.date(byAdding: .day, value: -(days - 1), to: startOfToday) ?? startOfToday
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: Date(), options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        let samples: [HKQuantitySample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: bodyMassType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sortDescriptor]) { _, querySamples, _ in
                continuation.resume(returning: (querySamples as? [HKQuantitySample]) ?? [])
            }
            healthStore.execute(query)
        }

        let grouped = Dictionary(grouping: samples) { sample in
            centralDayIdentifier(for: sample.startDate)
        }

        let orderedDayIDs = grouped.keys.sorted()
        return orderedDayIDs.compactMap { dayID in
            guard let daySamples = grouped[dayID], !daySamples.isEmpty else { return nil }
            let preferredDaySamples = Self.preferredIPhoneSamples(from: daySamples)

            let sortedByTime = preferredDaySamples.sorted { $0.startDate < $1.startDate }
            let metadata = sortedByTime.map {
                HealthWeighInSampleMetadata(
                    timestamp: $0.startDate,
                    pounds: $0.quantity.doubleValue(for: .pound())
                )
            }

            let morningSamples = sortedByTime.filter { isMorningWindow(date: $0.startDate) }
            if let selected = morningSamples.first {
                return HealthWeighInDay(
                    dayIdentifier: dayID,
                    representativePounds: selected.quantity.doubleValue(for: .pound()),
                    selectedSampleDate: selected.startDate,
                    selectionMethod: .morningEarliest,
                    sampleCount: sortedByTime.count,
                    samples: metadata
                )
            }

            guard let selected = sortedByTime.min(by: { lhs, rhs in
                let left = lhs.quantity.doubleValue(for: .pound())
                let right = rhs.quantity.doubleValue(for: .pound())
                if left == right {
                    return lhs.startDate < rhs.startDate
                }
                return left < right
            }) else {
                return nil
            }

            return HealthWeighInDay(
                dayIdentifier: dayID,
                representativePounds: selected.quantity.doubleValue(for: .pound()),
                selectedSampleDate: selected.startDate,
                selectionMethod: .dayMinimum,
                sampleCount: sortedByTime.count,
                samples: metadata
            )
        }
    }

    private func fetchTodayWorkouts(profile: BMRProfile?) async -> [ExerciseEntry] {
        let workoutType = HKObjectType.workoutType()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        let startOfToday = calendar.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: startOfToday, end: Date(), options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: workoutType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, samples, _ in
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

    private func fetchProfile() async -> SyncedProfile? {
        do {
            let sexObject = try healthStore.biologicalSex()
            let dateOfBirth = try healthStore.dateOfBirthComponents()

            guard
                let sex = mapSex(sexObject.biologicalSex),
                let birthDate = calendar.date(from: dateOfBirth)
            else {
                return nil
            }

            let age = max(calendar.dateComponents([.year], from: birthDate, to: Date()).year ?? 0, 0)
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
            guard roundedHeight > 0, roundedWeight > 0 else { return nil }

            return SyncedProfile(
                age: age,
                sex: sex,
                heightFeet: roundedHeight / 12,
                heightInches: roundedHeight % 12,
                weightPounds: roundedWeight
            )
        } catch {
            lastErrorMessage = error.localizedDescription
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
            let query = HKSampleQuery(sampleType: quantityType, predicate: predicate, limit: 200, sortDescriptors: [sortDescriptor]) { _, samples, _ in
                let quantitySamples = (samples as? [HKQuantitySample]) ?? []
                let preferredSamples = Self.preferredIPhoneSamples(from: quantitySamples)
                let value = preferredSamples.first?.quantity.doubleValue(for: unit)
                continuation.resume(returning: value)
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

    private func centralDayIdentifier(for date: Date) -> String {
        let startOfDay = calendar.startOfDay(for: date)
        let components = calendar.dateComponents([.year, .month, .day], from: startOfDay)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 1, components.day ?? 1)
    }

    private func isMorningWindow(date: Date) -> Bool {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        let minutes = hour * 60 + minute
        return minutes >= 180 && minutes <= 720
    }

    private static var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = []

        if let biologicalSex = HKObjectType.characteristicType(forIdentifier: .biologicalSex) {
            types.insert(biologicalSex)
        }
        if let dateOfBirth = HKObjectType.characteristicType(forIdentifier: .dateOfBirth) {
            types.insert(dateOfBirth)
        }

        if let height = HKObjectType.quantityType(forIdentifier: .height) {
            types.insert(height)
        }
        if let weight = HKObjectType.quantityType(forIdentifier: .bodyMass) {
            types.insert(weight)
        }
        if let stepCount = HKObjectType.quantityType(forIdentifier: .stepCount) {
            types.insert(stepCount)
        }
        if let walkingDistance = HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning) {
            types.insert(walkingDistance)
        }
        types.insert(HKObjectType.workoutType())
        return types
    }

    /// `getRequestStatusForAuthorization` becomes `.shouldRequest` when new read types are added,
    /// even if the user has already granted previously-requested types (e.g. workouts).
    /// Keep the service connected when at least one key read type is already authorized.
    private var hasAnyReadAuthorization: Bool {
        let workoutAuthorized = healthStore.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized
        let bodyMassAuthorized: Bool = {
            guard let bodyMass = HKObjectType.quantityType(forIdentifier: .bodyMass) else { return false }
            return healthStore.authorizationStatus(for: bodyMass) == .sharingAuthorized
        }()
        let heightAuthorized: Bool = {
            guard let height = HKObjectType.quantityType(forIdentifier: .height) else { return false }
            return healthStore.authorizationStatus(for: height) == .sharingAuthorized
        }()
        return workoutAuthorized || bodyMassAuthorized || heightAuthorized
    }
}
