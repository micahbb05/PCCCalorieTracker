import Foundation
import CoreMotion
import Combine

@MainActor
final class StepActivityService: ObservableObject {
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
    @Published private(set) var lastErrorMessage: String?

    let stepCalorieFactor: Double = 0.04

    private let pedometer = CMPedometer()
    private let calendar: Calendar

    init() {
        var centralCalendar = Calendar(identifier: .gregorian)
        centralCalendar.timeZone = TimeZone(identifier: "America/Chicago") ?? .current
        calendar = centralCalendar
        authorizationState = Self.resolveAuthorizationState()
    }

    var estimatedCaloriesToday: Int {
        Int((Double(todayStepCount) * stepCalorieFactor).rounded())
    }

    func refreshIfAuthorized() {
        authorizationState = Self.resolveAuthorizationState()
        guard authorizationState == .authorized else {
            if authorizationState != .notDetermined {
                todayStepCount = 0
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
            }
            return
        }

        lastErrorMessage = nil
        todayStepCount = data?.numberOfSteps.intValue ?? 0
        authorizationState = Self.resolveAuthorizationState(afterSuccessfulQuery: true)
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
