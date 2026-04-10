// Calorie Tracker 2026

import SwiftUI

extension ContentView {

    private var isBlueprint: Bool { appThemeStyleRaw == AppThemeStyle.blueprint.rawValue }
    private var themeStyle: AppThemeStyle { isBlueprint ? .blueprint : .ember }

    var surfacePrimary: Color {
        colorScheme == .dark
            ? AppTheme.surfaceBase(for: themeStyle)
            : Color.white
    }

    var surfaceSecondary: Color {
        colorScheme == .dark
            ? AppTheme.inputSurface(for: themeStyle)
            : (isBlueprint ? Color(red: 0.96, green: 0.97, blue: 0.99) : Color(red: 0.97, green: 0.96, blue: 0.94))
    }

    var textPrimary: Color {
        colorScheme == .dark
            ? (isBlueprint ? Color(red: 0.95, green: 0.96, blue: 0.98) : Color(red: 0.961, green: 0.941, blue: 0.902))
            : (isBlueprint ? Color(red: 0.10, green: 0.11, blue: 0.14) : Color(red: 0.12, green: 0.10, blue: 0.08))
    }

    var textSecondary: Color {
        colorScheme == .dark
            ? AppTheme.secondaryText
            : (isBlueprint ? Color(red: 0.45, green: 0.47, blue: 0.52) : Color(red: 0.45, green: 0.42, blue: 0.38))
    }

    var accent: Color { AppTheme.accent }
    var dividerColor: Color { AppTheme.divider(for: themeStyle) }
    var inactiveControlFill: Color { AppTheme.inactiveFill(for: themeStyle) }

    var backgroundTop: Color {
        colorScheme == .dark
            ? (isBlueprint ? Color(red: 0.07, green: 0.08, blue: 0.12) : Color(red: 0.059, green: 0.051, blue: 0.039))
            : (isBlueprint ? Color(red: 0.96, green: 0.97, blue: 0.99) : Color(red: 0.97, green: 0.95, blue: 0.92))
    }

    var backgroundBottom: Color {
        colorScheme == .dark
            ? (isBlueprint ? Color(red: 0.10, green: 0.11, blue: 0.17) : Color(red: 0.078, green: 0.063, blue: 0.039))
            : (isBlueprint ? Color(red: 0.92, green: 0.93, blue: 0.97) : Color(red: 0.93, green: 0.90, blue: 0.86))
    }

    var centralCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        return calendar
    }

    var todayDayIdentifier: String {
        centralDayIdentifier(for: Date())
    }

    var currentHistoryMonthTitle: String {
        displayedHistoryMonth.formatted(.dateTime.month(.wide).year())
    }

    var historyMonthDays: [Date?] {
        guard
            let monthInterval = centralCalendar.dateInterval(of: .month, for: displayedHistoryMonth),
            let firstWeekInterval = centralCalendar.dateInterval(of: .weekOfMonth, for: monthInterval.start),
            let lastDayOfMonth = centralCalendar.date(byAdding: DateComponents(day: -1), to: monthInterval.end),
            let lastWeekInterval = centralCalendar.dateInterval(of: .weekOfMonth, for: lastDayOfMonth)
        else {
            return []
        }

        var days: [Date?] = []
        var cursor = firstWeekInterval.start
        while cursor < lastWeekInterval.end {
            if monthInterval.contains(cursor) {
                days.append(cursor)
            } else {
                days.append(nil)
            }

            guard let next = centralCalendar.date(byAdding: .day, value: 1, to: cursor) else {
                break
            }
            cursor = next
        }
        return days
    }

    var deficitCalories: Int { min(max(storedDeficitCalories, 0), 2500) }
    var surplusCalories: Int { min(max(storedSurplusCalories, 0), 2500) }
    var weekendDeficitCalories: Int { min(max(storedWeekendDeficitCalories, 0), 2500) }
    var fixedGoalCalories: Int { min(max(storedFixedGoalCalories, 1), 6000) }
    var manualBMRCalories: Int { min(max(storedManualBMRCalories, 800), 4000) }

    func goalTypeForDay(_ identifier: String) -> GoalType {
        if identifier == todayDayIdentifier {
            return goalType
        }
        if let raw = dailyGoalTypeArchive[identifier], let type = GoalType(rawValue: raw) {
            return type
        }
        return goalType
    }

    func deficitForDay(_ identifier: String) -> Int {
        if goalTypeForDay(identifier) == .fixed {
            return 0
        }
        guard useWeekendDeficit else {
            return goalTypeForDay(identifier) == .surplus ? surplusCalories : deficitCalories
        }
        guard let date = date(fromCentralDayIdentifier: identifier) else {
            return goalTypeForDay(identifier) == .surplus ? surplusCalories : deficitCalories
        }
        let weekday = centralCalendar.component(.weekday, from: date)
        let isWeekend = (weekday == 1) || (weekday == 7)
        return isWeekend ? weekendDeficitCalories : (goalTypeForDay(identifier) == .surplus ? surplusCalories : deficitCalories)
    }

}
