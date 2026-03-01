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
                return "Connect Apple Health to read height, weight, sex, age, and activity burn."
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
    @Published private(set) var activeCaloriesToday: Int = 0
    @Published private(set) var lastErrorMessage: String?

    private let healthStore = HKHealthStore()
    private let calendar: Calendar

    init() {
        var centralCalendar = Calendar(identifier: .gregorian)
        centralCalendar.timeZone = TimeZone(identifier: "America/Chicago") ?? .current
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
            activeCaloriesToday = 0
            return
        }

        do {
            let status = try await authorizationRequestStatus()
            authorizationState = (status == .unnecessary) ? .connected : .notConnected
            guard authorizationState == .connected else {
                profile = nil
                activeCaloriesToday = 0
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
        async let fetchedProfile = fetchProfile()
        async let fetchedActiveCalories = fetchActiveCaloriesToday()

        let profile = await fetchedProfile
        let activeCalories = await fetchedActiveCalories

        self.profile = profile
        activeCaloriesToday = activeCalories
        lastErrorMessage = nil
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

    private func fetchActiveCaloriesToday() async -> Int {
        let startOfDay = calendar.startOfDay(for: Date())
        let now = Date()
        guard
            let quantityType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)
        else {
            return 0
        }

        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now)
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: quantityType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, statistics, _ in
                let total = statistics?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
                continuation.resume(returning: max(Int(total.rounded()), 0))
            }
            healthStore.execute(query)
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
        if let activeEnergy = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) {
            types.insert(activeEnergy)
        }

        return types
    }
}
