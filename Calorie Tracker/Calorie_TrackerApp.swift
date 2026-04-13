//
//  Calorie_TrackerApp.swift
//  Calorie Tracker
//
//  Created by Micah Bockisch on 2/27/26.
//

import SwiftUI
import UIKit
import BackgroundTasks
final class AppDelegate: NSObject, UIApplicationDelegate {
    private let menuRefreshTaskIdentifier = "Micah.Calorie-Tracker.refreshMenu"

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        registerBackgroundTasks()
        FirebaseBootstrap.configureIfAvailable()
        application.registerForRemoteNotifications()
        application.setMinimumBackgroundFetchInterval(UIApplication.backgroundFetchIntervalMinimum)
        HealthKitBackgroundObserver.shared.start()
        Task(priority: .utility) {
            _ = await BackgroundWidgetRefreshService.shared.refreshSnapshot()
        }
        scheduleMenuRefreshForNextMidnight()
        return true
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        if AppCloudSyncService.isAppStateChangeNotification(userInfo: userInfo) {
            NotificationCenter.default.post(name: .cloudKitAppStateDidChange, object: nil)
            completionHandler(.newData)
        } else {
            completionHandler(.noData)
        }
    }

    func application(
        _ application: UIApplication,
        performFetchWithCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        Task {
            async let didUpdateMenus = AppMenuPreloadService.shared.preloadTodayMenus()
            async let didUpdateWidget = BackgroundWidgetRefreshService.shared.refreshSnapshot()
            let menusUpdated = await didUpdateMenus
            let widgetUpdated = await didUpdateWidget
            completionHandler(menusUpdated || widgetUpdated ? .newData : .noData)
        }
    }

    private func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: menuRefreshTaskIdentifier, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            self.handleMenuRefresh(task: refreshTask)
        }
    }

    private func handleMenuRefresh(task: BGAppRefreshTask) {
        scheduleMenuRefreshForNextMidnight()

        let work = Task(priority: .utility) { () -> Bool in
            return await AppMenuPreloadService.shared.preloadTodayMenus()
        }

        task.expirationHandler = {
            work.cancel()
        }

        Task { @MainActor in
            let success = (await work.value) && !work.isCancelled
            task.setTaskCompleted(success: success)
        }
    }

    private func scheduleMenuRefreshForNextMidnight() {
        let request = BGAppRefreshTaskRequest(identifier: menuRefreshTaskIdentifier)
        request.earliestBeginDate = nextLocalMidnight()
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Best-effort scheduling; iOS may reject if disabled or too many pending requests.
        }
    }

    private func nextLocalMidnight(now: Date = Date()) -> Date {
        let cal = Calendar.autoupdatingCurrent
        let startOfToday = cal.startOfDay(for: now)
        return cal.date(byAdding: .day, value: 1, to: startOfToday) ?? now.addingTimeInterval(60 * 60 * 24)
    }
}

@main
struct Calorie_TrackerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("appThemeStyle") private var appThemeStyleRaw: String = AppThemeStyle.ember.rawValue

    init() {
        AppTheme.applyControlAppearance(style: AppThemeStyle.active)
    }

    private var accentColor: Color {
        appThemeStyleRaw == AppThemeStyle.blueprint.rawValue
            ? Color(red: 0.20, green: 0.50, blue: 0.98)
            : Color(red: 0.722, green: 0.573, blue: 0.290)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
                .tint(accentColor)
                .onAppear {
                    AppTheme.applyControlAppearance(style: AppThemeStyle(rawValue: appThemeStyleRaw) ?? .ember)
                }
                .onChange(of: appThemeStyleRaw) { _, newValue in
                    AppTheme.applyControlAppearance(style: AppThemeStyle(rawValue: newValue) ?? .ember)
                }
        }
    }
}
