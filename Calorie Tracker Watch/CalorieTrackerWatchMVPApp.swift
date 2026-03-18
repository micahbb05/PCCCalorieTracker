import SwiftUI
import WatchConnectivity
import WatchKit

private final class WatchConnectivityLifecycleDelegate: NSObject, WKExtensionDelegate {
    private var connectivityTasks = [WKWatchConnectivityRefreshBackgroundTask]()

    func applicationDidFinishLaunching() {
        Task { @MainActor in
            WatchSyncService.shared.start(with: WatchCalorieStore.shared)
        }
    }

    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            switch task {
            case let connectivityTask as WKWatchConnectivityRefreshBackgroundTask:
                Task { @MainActor in
                    WatchSyncService.shared.start(with: WatchCalorieStore.shared)
                }
                WatchSyncService.shared.handle(connectivityTask)
            case let appRefreshTask as WKApplicationRefreshBackgroundTask:
                appRefreshTask.setTaskCompletedWithSnapshot(false)
            case let snapshotTask as WKSnapshotRefreshBackgroundTask:
                snapshotTask.setTaskCompleted(
                    restoredDefaultState: true,
                    estimatedSnapshotExpiration: .distantFuture,
                    userInfo: nil
                )
            default:
                task.setTaskCompletedWithSnapshot(false)
            }
        }
    }
}

private enum WatchPayloadParser {
    struct ParsedPayload {
        let goalCalories: Int
        let activityCalories: Int
        let currentMealTitle: String
        let venueMenuItems: [String: [String]]
        let entries: [WatchMealEntry]
    }

    static func parse(payload: [String: Any]) -> ParsedPayload? {
        guard let goal = payload["goalCalories"] as? Int else { return nil }
        let activity = payload["activityCalories"] as? Int ?? 0
        let mealTitle = payload["currentMealTitle"] as? String ?? "Lunch"
        let venueMenuItems = payload["venueMenuItems"] as? [String: [String]] ?? [:]

        let rawEntries = payload["entries"] as? [[String: Any]] ?? []
        let entries: [WatchMealEntry] = rawEntries.compactMap { raw in
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

        return ParsedPayload(
            goalCalories: goal,
            activityCalories: activity,
            currentMealTitle: mealTitle,
            venueMenuItems: venueMenuItems,
            entries: entries
        )
    }
}

@main
struct CalorieTrackerWatchMVPApp: App {
    @WKExtensionDelegateAdaptor(WatchConnectivityLifecycleDelegate.self) private var lifecycleDelegate
    @StateObject private var store = WatchCalorieStore.shared
    @StateObject private var syncService = WatchSyncService.shared

    var body: some Scene {
        WindowGroup {
            DashboardView()
                .environmentObject(store)
                .onAppear {
                    syncService.start(with: store)
                }
        }
    }
}
