// Calorie Tracker 2026

import Foundation
import UserNotifications

extension Notification.Name {
    static let cloudKitAppStateDidChange = Notification.Name("cloudKitAppStateDidChange")
}

typealias StoredVenueMenuCache = [DiningVenue: [NutrisliceMenuService.MenuType: NutrisliceMenu]]
typealias StoredVenueMenuSignatureCache = [DiningVenue: [NutrisliceMenuService.MenuType: String]]

final class SmartMealReminderService {
    static let shared = SmartMealReminderService()
    private let remindableMealGroups: [MealGroup] = MealGroup.logDisplayOrder.filter { $0 != .snack }

    private struct ReminderTarget {
        let mealGroup: MealGroup
        let expectedMinutes: Int
        let fireDate: Date
    }

    private let notificationCenter = UNUserNotificationCenter.current()
    private let notificationPrefix = "smart-meal-reminder."
    private let deliveredReminderDaysDefaultsKey = "smartMealReminderDeliveredDaysByMealGroup"
    private let lookbackDays = 14
    private let minimumLoggedDays = 4
    private let minimumFrequency = 0.30
    private let reminderDelayMinutes = 45
    private let catchUpDelaySeconds: TimeInterval = 90
    private let minimumLeadTimeSeconds: TimeInterval = 60

    private init() {}

    func requestAuthorizationIfNeeded(completion: @escaping (Bool) -> Void) {
        notificationCenter.getNotificationSettings { [weak self] settings in
            guard self != nil else {
                completion(false)
                return
            }

            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                completion(true)
            case .notDetermined:
                self?.notificationCenter.requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
                    completion(granted)
                }
            case .denied:
                completion(false)
            @unknown default:
                completion(false)
            }
        }
    }

    func refreshReminders(
        enabled: Bool,
        now: Date,
        calendar: Calendar,
        dailyEntryArchive: [String: [MealEntry]],
        todayDayIdentifier: String
    ) {
        let allIDs = MealGroup.allCases.map(notificationID(for:))
        guard enabled else {
            cancelNotificationRequests(ids: allIDs, includeDelivered: true)
            return
        }

        notificationCenter.getNotificationSettings { [weak self] settings in
            guard let self else { return }

            let isAuthorized: Bool
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                isAuthorized = true
            default:
                isAuthorized = false
            }

            guard isAuthorized else {
                self.cancelNotificationRequests(ids: allIDs, includeDelivered: true)
                return
            }

            self.notificationCenter.getDeliveredNotifications { notifications in
                let deliveredTodayGroups = self.deliveredReminderGroups(
                    from: notifications,
                    calendar: calendar,
                    todayDayIdentifier: todayDayIdentifier
                )
                let targets = self.buildReminderTargets(
                    now: now,
                    calendar: calendar,
                    dailyEntryArchive: dailyEntryArchive,
                    todayDayIdentifier: todayDayIdentifier,
                    alreadyDeliveredGroups: deliveredTodayGroups
                )

                self.cancelNotificationRequests(ids: allIDs)
                for target in targets {
                    self.scheduleNotification(for: target)
                }
            }
        }
    }

    private func cancelNotificationRequests(ids: [String], includeDelivered: Bool = false) {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: ids)
        guard includeDelivered else { return }
        notificationCenter.removeDeliveredNotifications(withIdentifiers: ids)
    }

    private func scheduleNotification(for target: ReminderTarget) {
        let content = UNMutableNotificationContent()
        content.title = "Time to log \(target.mealGroup.title.lowercased())?"
        content.body = "Add your meal when you're ready."
        content.sound = .default

        let fireTimeInterval = max(target.fireDate.timeIntervalSinceNow, minimumLeadTimeSeconds)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: fireTimeInterval, repeats: false)
        let request = UNNotificationRequest(
            identifier: notificationID(for: target.mealGroup),
            content: content,
            trigger: trigger
        )
        notificationCenter.add(request)
    }

    private func buildReminderTargets(
        now: Date,
        calendar: Calendar,
        dailyEntryArchive: [String: [MealEntry]],
        todayDayIdentifier: String,
        alreadyDeliveredGroups: Set<MealGroup>
    ) -> [ReminderTarget] {
        let todayEntries = dailyEntryArchive[todayDayIdentifier] ?? []
        let loggedTodayGroups = Set(todayEntries.map(\.mealGroup))
        let storedDeliveredGroups = reminderGroupsDelivered(on: todayDayIdentifier)
        let blockedGroups = loggedTodayGroups
            .union(alreadyDeliveredGroups)
            .union(storedDeliveredGroups)

        let historyByGroup = historicalFirstLogMinutesByMealGroup(
            now: now,
            calendar: calendar,
            dailyEntryArchive: dailyEntryArchive
        )
        let startOfToday = calendar.startOfDay(for: now)
        guard
            let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday),
            let latestReminderTime = calendar.date(byAdding: .minute, value: -15, to: startOfTomorrow)
        else {
            return []
        }

        var targets: [ReminderTarget] = []
        for group in remindableMealGroups {
            guard !blockedGroups.contains(group) else { continue }
            guard let sampleTimes = historyByGroup[group], qualifiesAsUsual(sampleTimes) else { continue }

            let expectedMinutes = median(sampleTimes)
            let triggerMinutes = min(expectedMinutes + reminderDelayMinutes, 23 * 60 + 45)

            guard let baselineDate = calendar.date(byAdding: .minute, value: triggerMinutes, to: startOfToday) else {
                continue
            }

            let fireDate: Date
            if baselineDate <= now {
                guard now < latestReminderTime else { continue }
                fireDate = now.addingTimeInterval(catchUpDelaySeconds)
            } else {
                fireDate = baselineDate
            }

            targets.append(
                ReminderTarget(
                    mealGroup: group,
                    expectedMinutes: expectedMinutes,
                    fireDate: fireDate
                )
            )
        }
        return targets.sorted { $0.fireDate < $1.fireDate }
    }

    private func historicalFirstLogMinutesByMealGroup(
        now: Date,
        calendar: Calendar,
        dailyEntryArchive: [String: [MealEntry]]
    ) -> [MealGroup: [Int]] {
        var historyByGroup: [MealGroup: [Int]] = [:]

        for offset in 1...lookbackDays {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: now) else { continue }
            let dayIdentifier = dayID(for: day, calendar: calendar)
            let entries = dailyEntryArchive[dayIdentifier] ?? []
            guard !entries.isEmpty else { continue }

            var firstLogMinutesByGroup: [MealGroup: Int] = [:]
            for entry in entries {
                let minutes = minutesIntoDay(entry.createdAt, calendar: calendar)
                if let existing = firstLogMinutesByGroup[entry.mealGroup] {
                    firstLogMinutesByGroup[entry.mealGroup] = min(existing, minutes)
                } else {
                    firstLogMinutesByGroup[entry.mealGroup] = minutes
                }
            }

            for (group, minutes) in firstLogMinutesByGroup {
                historyByGroup[group, default: []].append(minutes)
            }
        }

        return historyByGroup
    }

    private func qualifiesAsUsual(_ sampleTimes: [Int]) -> Bool {
        guard sampleTimes.count >= minimumLoggedDays else { return false }
        let frequency = Double(sampleTimes.count) / Double(lookbackDays)
        return frequency >= minimumFrequency
    }

    private func notificationID(for mealGroup: MealGroup) -> String {
        notificationPrefix + mealGroup.rawValue
    }

    private func deliveredReminderGroups(
        from notifications: [UNNotification],
        calendar: Calendar,
        todayDayIdentifier: String
    ) -> Set<MealGroup> {
        var storedDays = storedDeliveredReminderDaysByGroup()

        for notification in notifications {
            let identifier = notification.request.identifier
            guard let mealGroup = mealGroup(forNotificationID: identifier) else { continue }
            storedDays[mealGroup.rawValue] = dayID(for: notification.date, calendar: calendar)
        }

        saveDeliveredReminderDaysByGroup(storedDays)

        return Set(
            storedDays.compactMap { rawValue, dayIdentifier in
                guard dayIdentifier == todayDayIdentifier else { return nil }
                return MealGroup(rawValue: rawValue)
            }
        )
    }

    private func reminderGroupsDelivered(on dayIdentifier: String) -> Set<MealGroup> {
        Set(
            storedDeliveredReminderDaysByGroup().compactMap { rawValue, storedDayIdentifier in
                guard storedDayIdentifier == dayIdentifier else { return nil }
                return MealGroup(rawValue: rawValue)
            }
        )
    }

    private func storedDeliveredReminderDaysByGroup() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: deliveredReminderDaysDefaultsKey) as? [String: String] ?? [:]
    }

    private func saveDeliveredReminderDaysByGroup(_ storedDays: [String: String]) {
        UserDefaults.standard.set(storedDays, forKey: deliveredReminderDaysDefaultsKey)
    }

    private func mealGroup(forNotificationID identifier: String) -> MealGroup? {
        guard identifier.hasPrefix(notificationPrefix) else { return nil }
        let rawValue = String(identifier.dropFirst(notificationPrefix.count))
        return MealGroup(rawValue: rawValue)
    }

    private func dayID(for date: Date, calendar: Calendar) -> String {
        let startOfDay = calendar.startOfDay(for: date)
        let components = calendar.dateComponents([.year, .month, .day], from: startOfDay)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 1,
            components.day ?? 1
        )
    }

    private func minutesIntoDay(_ date: Date, calendar: Calendar) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    private func median(_ values: [Int]) -> Int {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    private func displayTime(for minutes: Int) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        let normalizedMinutes = max(0, min(minutes, 23 * 60 + 59))
        let hour = normalizedMinutes / 60
        let minute = normalizedMinutes % 60
        let components = DateComponents(year: 2026, month: 1, day: 1, hour: hour, minute: minute)
        guard let date = calendar.date(from: components) else {
            return "your usual time"
        }

        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.timeZone = .autoupdatingCurrent
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }

}
