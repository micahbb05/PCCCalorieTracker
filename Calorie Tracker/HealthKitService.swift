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

    struct SyncedProfile: Equatable {
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

    /// Today's workouts from Health, mapped to ExerciseEntry for calorie integration.
    @Published private(set) var todayWorkouts: [ExerciseEntry] = []

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
        guard HKHealthStore.isHealthDataAvailable() else {
            authorizationState = .unavailable
            profile = nil
            return
        }

        do {
            let status = try await authorizationRequestStatus()
            authorizationState = (status == .unnecessary) ? .connected : .notConnected
            guard authorizationState == .connected else {
                profile = nil
                return
            }
            await loadHealthData()
        } catch {
            lastErrorMessage = error.localizedDescription
            authorizationState = .notConnected
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
        profile = await fetchProfile()
        todayWorkouts = await fetchTodayWorkouts()
        lastErrorMessage = nil
    }

    func refreshWorkouts() async {
        guard authorizationState == .connected else { return }
        todayWorkouts = await fetchTodayWorkouts()
    }

    private func fetchTodayWorkouts() async -> [ExerciseEntry] {
        let workoutType = HKObjectType.workoutType()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        let startOfToday = calendar.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: startOfToday, end: Date(), options: .strictStartDate)
        let profileSnapshot = profile

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: workoutType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, samples, _ in
                let workouts = (samples as? [HKWorkout]) ?? []
                let entries = workouts.compactMap { workout -> ExerciseEntry? in
                    Self.mapWorkoutToExercise(workout, profile: profileSnapshot)
                }
                continuation.resume(returning: entries)
            }
            healthStore.execute(query)
        }
    }

    private nonisolated static func mapWorkoutToExercise(_ workout: HKWorkout, profile: SyncedProfile?) -> ExerciseEntry? {
        guard let type = mapActivityType(workout.workoutActivityType) else { return nil }
        let durationMinutes = max(Int(workout.duration / 60), 1)
        let weight = profile?.weightPounds ?? 170
        let distanceMiles: Double? = nil
        let calories = ExerciseCalorieService.calories(type: type, durationMinutes: durationMinutes, distanceMiles: distanceMiles, weightPounds: weight)
        return ExerciseEntry(
            id: UUID(),
            exerciseType: type,
            durationMinutes: durationMinutes,
            distanceMiles: distanceMiles,
            calories: calories,
            reclassifiedWalkingCalories: 0,
            createdAt: workout.startDate
        )
    }

    private nonisolated static func mapActivityType(_ activity: HKWorkoutActivityType) -> ExerciseType? {
        switch activity {
        case .running: return .running
        case .cycling, .handCycling: return .cycling
        case .swimming: return .swimming
        case .traditionalStrengthTraining, .functionalStrengthTraining, .crossTraining, .highIntensityIntervalTraining: return .weightLifting
        default: return nil
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
        types.insert(HKObjectType.workoutType())
        return types
    }
}
