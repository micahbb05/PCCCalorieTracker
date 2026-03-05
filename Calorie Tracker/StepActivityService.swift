import Foundation
import CoreMotion
import Combine

@MainActor
final class StepActivityService: ObservableObject {
    private static let defaultWeightPounds = 170.0
    private static let defaultHeightInches = 68.0
    // Net walking-energy approximation used because BMR is already counted separately.
    // Calibrated slightly lower to avoid mild overestimation for typical daily walking.
    private static let netWalkingCaloriesPerKgPerKm = 0.75
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
                return "Step tracking is not available on this device."
            case .notDetermined:
                return "Allow Motion & Fitness access to adjust your calorie goal from steps."
            case .denied:
                return "Turn on Motion & Fitness access in Settings to use step-based calories."
            case .authorized:
                return "Today's step count is being used to adjust your calorie goal."
            }
        }
    }

    @Published private(set) var authorizationState: AuthorizationState
    @Published private(set) var todayStepCount: Int = 0
    @Published private(set) var todayDistanceMeters: Double = 0
    @Published private(set) var lastErrorMessage: String?

    private let pedometer = CMPedometer()
    private let calendar: Calendar

    init() {
        var centralCalendar = Calendar(identifier: .gregorian)
        centralCalendar.timeZone = .autoupdatingCurrent
        calendar = centralCalendar
        authorizationState = Self.resolveAuthorizationState()
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
        authorizationState = Self.resolveAuthorizationState()
        guard authorizationState == .authorized else {
            if authorizationState != .notDetermined {
                todayStepCount = 0
                todayDistanceMeters = 0
            }
            return
        }

        queryTodaySteps()
    }

    func requestAccessAndRefresh() {
        authorizationState = Self.resolveAuthorizationState()
        guard authorizationState != .unavailable else {
            lastErrorMessage = AuthorizationState.unavailable.detail
            return
        }

        queryTodaySteps()
    }

    private func queryTodaySteps() {
        let startOfDay = calendar.startOfDay(for: Date())
        let now = Date()

        pedometer.queryPedometerData(from: startOfDay, to: now) { [weak self] data, error in
            Task { @MainActor in
                guard let self else { return }
                self.handleQueryResult(data: data, error: error)
            }
        }
    }

    private func handleQueryResult(data: CMPedometerData?, error: Error?) {
        authorizationState = Self.resolveAuthorizationState()

        if let error {
            lastErrorMessage = error.localizedDescription
            if authorizationState != .authorized {
                todayStepCount = 0
                todayDistanceMeters = 0
            }
            return
        }

        lastErrorMessage = nil
        todayStepCount = data?.numberOfSteps.intValue ?? 0
        todayDistanceMeters = max(data?.distance?.doubleValue ?? 0, 0)
        authorizationState = Self.resolveAuthorizationState(afterSuccessfulQuery: true)
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

    private static func resolveAuthorizationState(afterSuccessfulQuery: Bool = false) -> AuthorizationState {
        guard CMPedometer.isStepCountingAvailable() else {
            return .unavailable
        }

        switch CMPedometer.authorizationStatus() {
        case .authorized:
            return .authorized
        case .denied, .restricted:
            return .denied
        case .notDetermined:
            return afterSuccessfulQuery ? .authorized : .notDetermined
        @unknown default:
            return .notDetermined
        }
    }
}
