// Calorie Tracker 2026

import Foundation
import WatchConnectivity

final class WatchAppSyncService: NSObject, WCSessionDelegate {
    static let shared = WatchAppSyncService()

    static let appGroupIdentifier = "group.Micah.Calorie-Tracker"
    static let sharedSnapshotKey = "watchDailySnapshot"
    private static let syncTimestampKey = "syncSentAt"

    private let session: WCSession? = WCSession.isSupported() ? WCSession.default : nil
    private var lastContextData: Data?
    private var lastComplicationData: Data?
    private var lastBackgroundUserInfoData: Data?
    private var latestContext: [String: Any] = [:]

    private struct SharedSnapshotEntry: Codable {
        let id: UUID
        let name: String
        let calories: Int
        let createdAt: Date
    }

    private struct SharedSnapshot: Codable {
        let goalCalories: Int
        let activityCalories: Int
        let currentMealTitle: String
        let goalTypeRaw: String
        let selectedAppIconChoiceRaw: String
        let venueMenuItems: [String: [String]]
        let entries: [SharedSnapshotEntry]
    }

    private override init() {
        super.init()
        session?.delegate = self
        session?.activate()
    }

    func push(context: [String: Any]) {
        let enrichedContext = enrichContextWithSyncTimestamp(context)
        let semanticContext = payloadWithoutSyncTimestamp(enrichedContext)
        guard let encoded = normalizedPayloadData(from: semanticContext) else {
            return
        }
        let realtimePayload = realtimeSyncPayload(from: enrichedContext)
        if let sharedDefaults = UserDefaults(suiteName: Self.appGroupIdentifier) {
            if let sharedSnapshotData = encodedSharedSnapshotData(from: enrichedContext) {
                sharedDefaults.set(sharedSnapshotData, forKey: Self.sharedSnapshotKey)
            }
        }
        guard let session else { return }
        latestContext = enrichedContext
        if encoded == lastContextData {
            return
        }

        do {
            try session.updateApplicationContext(enrichedContext)
            lastContextData = encoded
            transferComplicationIfNeeded(using: realtimePayload, session: session)
            transferBackgroundUserInfoIfNeeded(using: realtimePayload, session: session)
        } catch {
            // Fall back to lightweight background transfers to reduce drop risk.
            transferComplicationIfNeeded(using: realtimePayload, session: session)
            transferBackgroundUserInfoIfNeeded(using: realtimePayload, session: session)
        }
    }

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        guard error == nil, activationState == .activated, !latestContext.isEmpty else { return }
        let realtimePayload = realtimeSyncPayload(from: latestContext)
        do {
            try session.updateApplicationContext(latestContext)
            transferComplicationIfNeeded(
                using: realtimePayload,
                session: session
            )
            transferBackgroundUserInfoIfNeeded(
                using: realtimePayload,
                session: session
            )
        } catch {
            transferComplicationIfNeeded(
                using: realtimePayload,
                session: session
            )
            transferBackgroundUserInfoIfNeeded(
                using: realtimePayload,
                session: session
            )
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    private func realtimeSyncPayload(from context: [String: Any]) -> [String: Any] {
        // Keep the complication payload compact to maximize background delivery reliability.
        [
            "goalCalories": max(context["goalCalories"] as? Int ?? 0, 1),
            "activityCalories": max(context["activityCalories"] as? Int ?? 0, 0),
            "currentMealTitle": context["currentMealTitle"] as? String ?? "Lunch",
            "goalTypeRaw": context["goalTypeRaw"] as? String ?? "deficit",
            "selectedAppIconChoiceRaw": context["selectedAppIconChoiceRaw"] as? String ?? AppIconChoice.standard.rawValue,
            "entries": context["entries"] as? [[String: Any]] ?? [],
            Self.syncTimestampKey: context[Self.syncTimestampKey] as? TimeInterval ?? Date().timeIntervalSince1970
        ]
    }

    private func enrichContextWithSyncTimestamp(_ context: [String: Any]) -> [String: Any] {
        var enriched = context
        enriched[Self.syncTimestampKey] = Date().timeIntervalSince1970
        return enriched
    }

    private func normalizedPayloadData(from payload: [String: Any]) -> Data? {
        try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    }

    private func payloadWithoutSyncTimestamp(_ payload: [String: Any]) -> [String: Any] {
        var normalized = payload
        normalized.removeValue(forKey: Self.syncTimestampKey)
        return normalized
    }

    private func encodedSharedSnapshotData(from context: [String: Any]) -> Data? {
        let goalCalories = max(context["goalCalories"] as? Int ?? 0, 1)
        let activityCalories = max(context["activityCalories"] as? Int ?? 0, 0)
        let currentMealTitle = context["currentMealTitle"] as? String ?? "Lunch"
        let goalTypeRaw = context["goalTypeRaw"] as? String ?? "deficit"
        let selectedAppIconChoiceRaw = context["selectedAppIconChoiceRaw"] as? String ?? AppIconChoice.standard.rawValue
        let venueMenuItems = context["venueMenuItems"] as? [String: [String]] ?? [:]
        let rawEntries = context["entries"] as? [[String: Any]] ?? []
        let entries = rawEntries.compactMap { raw -> SharedSnapshotEntry? in
            guard
                let idString = raw["id"] as? String,
                let id = UUID(uuidString: idString),
                let name = raw["name"] as? String,
                let calories = raw["calories"] as? Int,
                let createdAtSeconds = raw["createdAt"] as? TimeInterval
            else {
                return nil
            }

            return SharedSnapshotEntry(
                id: id,
                name: name,
                calories: calories,
                createdAt: Date(timeIntervalSince1970: createdAtSeconds)
            )
        }

        let snapshot = SharedSnapshot(
            goalCalories: goalCalories,
            activityCalories: activityCalories,
            currentMealTitle: currentMealTitle,
            goalTypeRaw: goalTypeRaw,
            selectedAppIconChoiceRaw: selectedAppIconChoiceRaw,
            venueMenuItems: venueMenuItems,
            entries: entries
        )
        return try? JSONEncoder().encode(snapshot)
    }

    private func transferComplicationIfNeeded(using context: [String: Any], session: WCSession) {
        guard session.isPaired, session.isWatchAppInstalled else { return }
        guard session.isComplicationEnabled else { return }
        guard session.remainingComplicationUserInfoTransfers > 0 else { return }
        let semanticContext = payloadWithoutSyncTimestamp(context)
        if let encoded = normalizedPayloadData(from: semanticContext), encoded == lastComplicationData {
            return
        }
        session.transferCurrentComplicationUserInfo(context)
        lastComplicationData = normalizedPayloadData(from: semanticContext)
    }

    private func transferBackgroundUserInfoIfNeeded(using context: [String: Any], session: WCSession) {
        guard session.isPaired, session.isWatchAppInstalled else { return }
        let semanticContext = payloadWithoutSyncTimestamp(context)
        if let encoded = normalizedPayloadData(from: semanticContext), encoded == lastBackgroundUserInfoData {
            return
        }
        session.transferUserInfo(context)
        lastBackgroundUserInfoData = normalizedPayloadData(from: semanticContext)
    }

    func session(
        _ session: WCSession,
        didFinish userInfoTransfer: WCSessionUserInfoTransfer,
        error: Error?
    ) {
        // Keeping delegate method for required protocol conformance, but removing equality checking since it's obsolete.
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard (message["request"] as? String) == "watchSnapshot" else { return }
        guard !latestContext.isEmpty else { return }
        session.sendMessage(latestContext, replyHandler: nil, errorHandler: nil)
    }

    func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        guard (message["request"] as? String) == "watchSnapshot" else {
            replyHandler([:])
            return
        }

        if latestContext.isEmpty {
            replyHandler([:])
            return
        }

        replyHandler(latestContext)
    }
}
