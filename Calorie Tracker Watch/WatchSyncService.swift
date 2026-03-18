import Foundation
import WatchConnectivity
import WatchKit
import WidgetKit

@MainActor
final class WatchSyncService: NSObject, ObservableObject {
    static let shared = WatchSyncService()

    private weak var store: WatchCalorieStore?
    private var hasReceivedPayload = false
    private var pendingConnectivityTasks = [WKWatchConnectivityRefreshBackgroundTask]()
    private var connectivityTaskTimeoutTask: Task<Void, Never>?
    private var pendingPayload: PendingPayload?
    private var pendingApplyTask: Task<Void, Never>?
    private var lastAppliedPayloadData: Data?
    private var lastAppliedSyncSentAt: TimeInterval = 0
    private var lastAppliedRichnessScore: Int = 0
    private let syncTimestampEpsilon: TimeInterval = 0.0001

    private struct PendingPayload {
        let raw: [String: Any]
        let encoded: Data?
        let syncSentAt: TimeInterval
        let richnessScore: Int
    }

    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func start(with store: WatchCalorieStore) {
        self.store = store
        guard WCSession.isSupported() else { return }

        let session = WCSession.default
        if session.delegate == nil {
            session.delegate = self
        }
        if session.activationState != .activated {
            session.activate()
        }
        if !session.receivedApplicationContext.isEmpty {
            consume(payload: session.receivedApplicationContext)
        }
        requestSnapshotIfPossible(from: session)
        startSnapshotRetryLoop(session: session)
    }

    func handle(_ backgroundTask: WKWatchConnectivityRefreshBackgroundTask) {
        pendingConnectivityTasks.append(backgroundTask)
        scheduleConnectivityTaskTimeout()
    }

    private func completePendingTasksIfNeeded() {
        guard WCSession.isSupported() else {
            completeAllPendingConnectivityTasks()
            return
        }
        guard !WCSession.default.hasContentPending else { return }
        completeAllPendingConnectivityTasks()
    }

    private func completeAllPendingConnectivityTasks() {
        connectivityTaskTimeoutTask?.cancel()
        connectivityTaskTimeoutTask = nil
        let tasks = pendingConnectivityTasks
        pendingConnectivityTasks.removeAll()
        for task in tasks {
            task.setTaskCompletedWithSnapshot(false)
        }
    }

    private func scheduleConnectivityTaskTimeout() {
        connectivityTaskTimeoutTask?.cancel()
        connectivityTaskTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard let self else { return }
            guard !Task.isCancelled else { return }
            self.completeAllPendingConnectivityTasks()
        }
    }

    private func requestSnapshotIfPossible(from session: WCSession) {
        guard session.activationState == .activated else { return }
        session.sendMessage(
            ["request": "watchSnapshot"],
            replyHandler: { [weak self] payload in
                Task { @MainActor in
                    self?.consume(payload: payload)
                }
            },
            errorHandler: nil
        )
    }

    private func consume(payload: [String: Any]) {
        hasReceivedPayload = true
        let candidate = makePendingPayload(from: payload)
        guard shouldQueue(candidate) else { return }
        pendingPayload = candidate
        schedulePendingApply()
    }

    private func makePendingPayload(from payload: [String: Any]) -> PendingPayload {
        let syncSentAt = payload["syncSentAt"] as? TimeInterval ?? 0
        let richnessScore = payload.keys.reduce(0) { partialResult, key in
            switch key {
            case "venueMenuItems":
                return partialResult + 4
            case "entries":
                return partialResult + 2
            case "activityCalories", "currentMealTitle":
                return partialResult + 1
            default:
                return partialResult
            }
        }
        return PendingPayload(
            raw: payload,
            encoded: normalizedPayloadData(from: payload),
            syncSentAt: syncSentAt,
            richnessScore: richnessScore
        )
    }

    private func normalizedPayloadData(from payload: [String: Any]) -> Data? {
        try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    }

    private func shouldQueue(_ candidate: PendingPayload) -> Bool {
        // Ignore payloads that are clearly older than the last applied sync.
        if lastAppliedSyncSentAt > 0, candidate.syncSentAt > 0,
           candidate.syncSentAt + syncTimestampEpsilon < lastAppliedSyncSentAt {
            return false
        }

        // If we already applied timestamped data, skip undated payloads to avoid regressions.
        if lastAppliedSyncSentAt > 0, candidate.syncSentAt <= 0 {
            return false
        }

        // For equivalent timestamps, ignore less-rich payloads than what is already applied.
        if lastAppliedSyncSentAt > 0,
           abs(candidate.syncSentAt - lastAppliedSyncSentAt) <= syncTimestampEpsilon,
           candidate.richnessScore < lastAppliedRichnessScore {
            return false
        }

        if
            let encoded = candidate.encoded,
            let lastAppliedPayloadData,
            encoded == lastAppliedPayloadData,
            abs(candidate.syncSentAt - lastAppliedSyncSentAt) <= syncTimestampEpsilon
        {
            return false
        }

        guard let existing = pendingPayload else { return true }
        if candidate.syncSentAt > existing.syncSentAt + syncTimestampEpsilon {
            return true
        }
        if candidate.syncSentAt + syncTimestampEpsilon < existing.syncSentAt {
            return false
        }
        if candidate.richnessScore > existing.richnessScore {
            return true
        }
        if candidate.richnessScore < existing.richnessScore {
            return false
        }
        return true
    }

    private func schedulePendingApply() {
        pendingApplyTask?.cancel()
        pendingApplyTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 50_000_000)  // 50ms for immediate complication updates
            guard !Task.isCancelled else { return }
            applyPendingPayloadIfNeeded()
        }
    }

    private func applyPendingPayloadIfNeeded() {
        guard let pending = pendingPayload else { return }
        pendingPayload = nil

        let payload = pending.raw
        guard let goal = payload["goalCalories"] as? Int else { return }
        let activeStore = store ?? WatchCalorieStore.shared
        let activity = payload["activityCalories"] as? Int ?? activeStore.activityCalories
        let mealTitle = payload["currentMealTitle"] as? String ?? activeStore.currentMealTitle
        let goalTypeRaw = payload["goalTypeRaw"] as? String ?? activeStore.goalTypeRaw
        let selectedAppIconChoiceRaw = payload["selectedAppIconChoiceRaw"] as? String ?? activeStore.selectedAppIconChoiceRaw
        let venueMenuItems = payload["venueMenuItems"] as? [String: [String]] ?? activeStore.venueMenuItems

        let rawEntries = payload["entries"] as? [[String: Any]] ?? []
        let mapped: [WatchMealEntry] = rawEntries.compactMap { raw in
            guard
                let idString = raw["id"] as? String,
                let id = UUID(uuidString: idString),
                let name = raw["name"] as? String,
                let calories = raw["calories"] as? Int,
                let timestamp = raw["createdAt"] as? TimeInterval
            else {
                return nil
            }

            return WatchMealEntry(
                id: id,
                name: name,
                calories: calories,
                createdAt: Date(timeIntervalSince1970: timestamp)
            )
        }

        activeStore.applySync(
            goalCalories: goal,
            activityCalories: activity,
            currentMealTitle: mealTitle,
            goalTypeRaw: goalTypeRaw,
            selectedAppIconChoiceRaw: selectedAppIconChoiceRaw,
            venueMenuItems: venueMenuItems,
            entries: mapped
        )
        lastAppliedPayloadData = pending.encoded
        lastAppliedSyncSentAt = pending.syncSentAt
        lastAppliedRichnessScore = pending.richnessScore

        // Force complication to refresh immediately after receiving new data
        WidgetCenter.shared.reloadTimelines(ofKind: "CalorieTrackerCalorieWidget")
        WidgetCenter.shared.reloadAllTimelines()

        // Only complete background tasks after we have genuinely applied the sync and widgets reloaded
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.completePendingTasksIfNeeded()
        }
    }

    private func startSnapshotRetryLoop(session: WCSession) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            for _ in 0..<6 {
                if self.hasReceivedPayload { return }
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                self.requestSnapshotIfPossible(from: session)
            }
        }
    }
}

extension WatchSyncService: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        guard error == nil else { return }
        Task { @MainActor in
            requestSnapshotIfPossible(from: session)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            consume(payload: message)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            self.consume(payload: applicationContext)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any] = [:]) {
        Task { @MainActor in
            self.consume(payload: userInfo)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveComplicationUserInfo complicationUserInfo: [String : Any] = [:]) {
        Task { @MainActor in
            self.consume(payload: complicationUserInfo)
        }
    }
}
