//
//  Calorie_TrackerApp.swift
//  Calorie Tracker
//
//  Created by Micah Bockisch on 2/27/26.
//

import SwiftUI
import UIKit
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        application.registerForRemoteNotifications()
        application.setMinimumBackgroundFetchInterval(UIApplication.backgroundFetchIntervalMinimum)
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
            let didUpdateMenus = await AppMenuPreloadService.shared.preloadTodayMenus()
            completionHandler(didUpdateMenus ? .newData : .noData)
        }
    }
}

@main
struct Calorie_TrackerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
    }
}
