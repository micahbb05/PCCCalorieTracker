// Calorie Tracker 2026

import SwiftUI

extension ContentView {

    var calorieGraphPoints: [CalorieGraphPoint] {
        graphPoints(dayCount: 7)
    }

    var expandedCalorieGraphPoints: [CalorieGraphPoint] {
        graphPoints(for: expandedHistoryChartRange)
    }

    func graphPoints(for range: HistoryChartRange) -> [CalorieGraphPoint] {
        graphPoints(dayCount: range.dayCount)
    }

    func graphPoints(for dayIdentifiers: [String]) -> [CalorieGraphPoint] {
        dayIdentifiers.compactMap { identifier in
            guard let date = date(fromCentralDayIdentifier: identifier) else {
                return nil
            }
            return CalorieGraphPoint(
                dayIdentifier: identifier,
                date: date,
                calories: dailyCalories(for: identifier),
                goal: calorieGoalForDay(identifier),
                burned: burnedCaloriesForDay(identifier)
            )
        }
    }

    func graphPoints(dayCount: Int) -> [CalorieGraphPoint] {
        let today = centralCalendar.startOfDay(for: Date())
        // Use completed days only: last `dayCount` days, excluding today
        return (0..<dayCount).compactMap { offset in
            guard let date = centralCalendar.date(byAdding: .day, value: -(dayCount - offset), to: today) else {
                return nil
            }
            let identifier = centralDayIdentifier(for: date)
            return CalorieGraphPoint(
                dayIdentifier: identifier,
                date: date,
                calories: dailyCalories(for: identifier),
                goal: calorieGoalForDay(identifier),
                burned: burnedCaloriesForDay(identifier)
            )
        }
    }

    struct WeeklyInsightWindow {
        let label: String
        let dayIdentifiers: [String]
    }

    func sundayStartOfWeek(containing date: Date) -> Date {
        let startOfDay = centralCalendar.startOfDay(for: date)
        let weekday = centralCalendar.component(.weekday, from: startOfDay)
        let daysFromSunday = (weekday + 6) % 7
        return centralCalendar.date(byAdding: .day, value: -daysFromSunday, to: startOfDay) ?? startOfDay
    }

    func dayIdentifiers(from start: Date, to endExclusive: Date) -> [String] {
        let startOfStart = centralCalendar.startOfDay(for: start)
        let startOfEnd = centralCalendar.startOfDay(for: endExclusive)
        guard startOfStart < startOfEnd else { return [] }

        var identifiers: [String] = []
        var cursor = startOfStart
        while cursor < startOfEnd {
            identifiers.append(centralDayIdentifier(for: cursor))
            guard let next = centralCalendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return identifiers
    }

    func weeklyInsightWindows(limit: Int = 4) -> [WeeklyInsightWindow] {
        let today = centralCalendar.startOfDay(for: Date())
        let currentWeekStart = sundayStartOfWeek(containing: today)
        let isSunday = centralCalendar.component(.weekday, from: today) == 1

        let primaryStart: Date
        let primaryEndExclusive: Date
        let primaryLabel: String

        if isSunday {
            primaryStart = centralCalendar.date(byAdding: .day, value: -7, to: currentWeekStart) ?? currentWeekStart
            primaryEndExclusive = currentWeekStart
            primaryLabel = "Last Week"
        } else {
            primaryStart = currentWeekStart
            primaryEndExclusive = today
            primaryLabel = "Current Week"
        }

        var windows: [WeeklyInsightWindow] = []
        let primaryIdentifiers = dayIdentifiers(from: primaryStart, to: primaryEndExclusive)
        if !primaryIdentifiers.isEmpty {
            windows.append(WeeklyInsightWindow(label: primaryLabel, dayIdentifiers: primaryIdentifiers))
        }

        var windowEndExclusive = primaryStart
        guard limit > 1 else { return windows }

        for index in 1..<limit {
            guard let windowStart = centralCalendar.date(byAdding: .day, value: -7, to: windowEndExclusive) else { break }
            let identifiers = dayIdentifiers(from: windowStart, to: windowEndExclusive)
            guard !identifiers.isEmpty else { break }

            let label: String
            if isSunday {
                label = "\(index + 1) Weeks Ago"
            } else if index == 1 {
                label = "Last Week"
            } else {
                label = "\(index) Weeks Ago"
            }

            windows.append(WeeklyInsightWindow(label: label, dayIdentifiers: identifiers))
            windowEndExclusive = windowStart
        }

        return windows
    }

    func makeWeeklyInsightSummaryPayload() -> WeeklyInsightSummaryPayload? {
        let windowsNewestFirst = weeklyInsightWindows(limit: 4)
        guard let currentWindow = windowsNewestFirst.first else { return nil }

        let points = graphPoints(for: currentWindow.dayIdentifiers)
        guard !points.isEmpty else { return nil }

        let windowsOldestFirst = Array(windowsNewestFirst.reversed())
        let recentTrendPoints = windowsOldestFirst.flatMap { graphPoints(for: $0.dayIdentifiers) }
        let daysInPeriod = points.count
        let daysInPeriodDouble = Double(daysInPeriod)

        let storedWeighInsByDay: [String: Double] = Dictionary(
            uniqueKeysWithValues: healthWeighIns.map { ($0.dayIdentifier, $0.representativePounds) }
        )
        let freshWeighInsByDay: [String: Double] = Dictionary(
            uniqueKeysWithValues: healthKitService.reducedBodyMassHistory.map { ($0.dayIdentifier, $0.representativePounds) }
        )
        let weighInsByDay = freshWeighInsByDay.merging(storedWeighInsByDay) { fresh, _ in fresh }

        let proteinKey = "g_protein"
        let proteinGoalGrams = nutrientGoals[proteinKey] ?? max(legacyStoredProteinGoal, 1)

        var mealLoggedDays = 0
        var weightLoggedDays = 0

        var reliableBurnedDays = 0
        var compatibilityFallbackDays = 0
        var bmrFallbackDays = 0

        var proteinGramsValues: [Int] = []
        var proteinDaysLogged = 0
        var proteinDaysHitGoal = 0

        var caloriesInValues: [Int] = []
        var caloriesBurnedValues: [Int] = []
        var netCaloriesValues: [Int] = []

        var days: [WeeklyInsightSummaryPayload.Day] = []
        days.reserveCapacity(daysInPeriod)

        for point in points {
            let id = point.dayIdentifier
            let entriesForDay = entries(forDayIdentifier: id)
            let caloriesIn = point.calories
            if !entriesForDay.isEmpty && caloriesIn > 0 {
                mealLoggedDays += 1
            }

            let weight = weighInsByDay[id]
            if weight != nil {
                weightLoggedDays += 1
            }

            let caloriesBurned = point.burned
            let hasStoredBurned = dailyBurnedCalorieArchive[id] != nil
            let hasCompatibilityFallback = !hasStoredBurned && dailyCalorieGoalArchive[id] != nil
            if hasStoredBurned {
                reliableBurnedDays += 1
            } else if hasCompatibilityFallback {
                compatibilityFallbackDays += 1
            } else {
                bmrFallbackDays += 1
            }

            let net = caloriesIn - caloriesBurned

            let totals = nutrientTotals(for: id)
            let protein = totals[proteinKey] ?? 0
            proteinGramsValues.append(protein)
            if protein > 0 {
                proteinDaysLogged += 1
            }
            if proteinGoalGrams > 0, protein >= proteinGoalGrams {
                proteinDaysHitGoal += 1
            }

            caloriesInValues.append(caloriesIn)
            caloriesBurnedValues.append(caloriesBurned)
            netCaloriesValues.append(net)

            days.append(
                WeeklyInsightSummaryPayload.Day(
                    dayIdentifier: id,
                    date: point.date,
                    caloriesIn: caloriesIn,
                    caloriesBurned: caloriesBurned,
                    weightPounds: weight,
                    netCalories: net
                )
            )
        }

        // Calorie intake alignment vs your saved per-day calorie goal.
        var overGoalDays = 0
        var underGoalDays = 0
        var biggestOverage: Int?
        var biggestUnderoage: Int?

        var overGoalDayIdentifiers: [String] = []
        var underGoalDayIdentifiers: [String] = []
        var overageSum = 0
        var overageCount = 0
        var deficitDaysWhereIntakeWasOverGoal = 0
        var surplusDaysWhereIntakeWasUnderGoal = 0
        var goalValues: [Int] = []
        goalValues.reserveCapacity(daysInPeriod)

        for point in points {
            let delta = point.calories - point.goal
            let net = point.calories - point.burned
            goalValues.append(point.goal)
            if delta > 0 {
                overGoalDays += 1
                overGoalDayIdentifiers.append(point.dayIdentifier)
                overageSum += delta
                overageCount += 1
                if net < 0 {
                    deficitDaysWhereIntakeWasOverGoal += 1
                }
                biggestOverage = max(biggestOverage ?? delta, delta)
            } else if delta < 0 {
                underGoalDays += 1
                underGoalDayIdentifiers.append(point.dayIdentifier)
                if net > 0 {
                    surplusDaysWhereIntakeWasUnderGoal += 1
                }
                biggestUnderoage = min(biggestUnderoage ?? delta, delta)
            }
        }

        let avgCaloriesIn = Int((Double(caloriesInValues.reduce(0, +)) / daysInPeriodDouble).rounded())
        let avgCaloriesBurned = Int((Double(caloriesBurnedValues.reduce(0, +)) / daysInPeriodDouble).rounded())
        let avgNetCalories = Int((Double(netCaloriesValues.reduce(0, +)) / daysInPeriodDouble).rounded())

        let minCaloriesIn = caloriesInValues.min() ?? 0
        let maxCaloriesIn = caloriesInValues.max() ?? 0
        let minCaloriesBurned = caloriesBurnedValues.min() ?? 0
        let maxCaloriesBurned = caloriesBurnedValues.max() ?? 0
        let minNetCalories = netCaloriesValues.min() ?? 0
        let maxNetCalories = netCaloriesValues.max() ?? 0

        let averageGoalCalories = Int((Double(goalValues.reduce(0, +)) / daysInPeriodDouble).rounded())

        // Weight trend (oldest->newest).
        let weights = days.compactMap { $0.weightPounds }
        let startWeight = weights.first
        let endWeight = weights.last
        let weightChange = (startWeight != nil && endWeight != nil) ? (endWeight! - startWeight!) : nil

        // Likely drivers: top foods + meal groups on over-goal days.
        var caloriesByFoodName: [String: Int] = [:]
        var caloriesByMealGroupRaw: [String: Int] = [:]
        for dayID in overGoalDayIdentifiers {
            let dayEntries = entries(forDayIdentifier: dayID)
            for entry in dayEntries where entry.calories > 0 {
                caloriesByFoodName[entry.name, default: 0] += entry.calories
                caloriesByMealGroupRaw[entry.mealGroup.rawValue, default: 0] += entry.calories
            }
        }
        let topFoodsOnOverGoalDays: [WeeklyInsightSummaryPayload.CalorieIntake.TopFood] = caloriesByFoodName
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { WeeklyInsightSummaryPayload.CalorieIntake.TopFood(name: $0.key, calories: $0.value) }

        let topMealGroupsOnOverGoalDays: [WeeklyInsightSummaryPayload.CalorieIntake.TopMealGroup] = caloriesByMealGroupRaw
            .sorted { $0.value > $1.value }
            .prefix(3)
            .map { WeeklyInsightSummaryPayload.CalorieIntake.TopMealGroup(mealGroup: $0.key, calories: $0.value) }

        let averageOverageOnOverGoalDays: Int? = overageCount > 0 ? Int((Double(overageSum) / Double(overageCount)).rounded()) : nil

        let weekOverview = WeeklyInsightSummaryPayload.WeekOverview(
            daysInPeriod: daysInPeriod,
            mealLoggedDays: mealLoggedDays,
            weightLoggedDays: weightLoggedDays
        )

        let intake = WeeklyInsightSummaryPayload.CalorieIntake(
            averageCaloriesIn: avgCaloriesIn,
            minCaloriesIn: minCaloriesIn,
            maxCaloriesIn: maxCaloriesIn,
            averageGoalCalories: averageGoalCalories,
            overGoalDays: overGoalDays,
            underGoalDays: underGoalDays,
            biggestOverage: biggestOverage,
            biggestUnderage: biggestUnderoage,
            averageOverageOnOverGoalDays: averageOverageOnOverGoalDays,
            topFoodsOnOverGoalDays: topFoodsOnOverGoalDays,
            topMealGroupsOnOverGoalDays: topMealGroupsOnOverGoalDays
        )

        let activity = WeeklyInsightSummaryPayload.Activity(
            averageCaloriesBurned: avgCaloriesBurned,
            minCaloriesBurned: minCaloriesBurned,
            maxCaloriesBurned: maxCaloriesBurned,
            burnedReliability: WeeklyInsightSummaryPayload.BurnedReliability(
                reliableBurnedDays: reliableBurnedDays,
                compatibilityFallbackDays: compatibilityFallbackDays,
                bmrFallbackDays: bmrFallbackDays
            )
        )

        let balance = WeeklyInsightSummaryPayload.CalorieBalance(
            averageNetCalories: avgNetCalories,
            netDeficitDays: netCaloriesValues.filter { $0 < 0 }.count,
            netSurplusDays: netCaloriesValues.filter { $0 > 0 }.count,
            minNetCalories: minNetCalories,
            maxNetCalories: maxNetCalories,
            deficitDaysWhereIntakeWasOverGoal: deficitDaysWhereIntakeWasOverGoal,
            surplusDaysWhereIntakeWasUnderGoal: surplusDaysWhereIntakeWasUnderGoal
        )

        let weightTrend = WeeklyInsightSummaryPayload.WeightTrend(
            weightDaysUsed: weightLoggedDays,
            startWeightPounds: startWeight,
            endWeightPounds: endWeight,
            weightChangePounds: weightChange
        )

        let estimatedBurnedDays = compatibilityFallbackDays + bmrFallbackDays
        let dataQuality = WeeklyInsightSummaryPayload.DataQuality(
            missingMealDays: max(daysInPeriod - mealLoggedDays, 0),
            missingWeightDays: max(daysInPeriod - weightLoggedDays, 0),
            estimatedBurnedDays: estimatedBurnedDays
        )

        let avgProtein = Int((Double(proteinGramsValues.reduce(0, +)) / daysInPeriodDouble).rounded())
        let minProtein = proteinGramsValues.min() ?? 0
        let maxProtein = proteinGramsValues.max() ?? 0

        let macros = WeeklyInsightSummaryPayload.MacroPattern(
            proteinGoalGrams: proteinGoalGrams > 0 ? proteinGoalGrams : nil,
            proteinDaysLogged: proteinDaysLogged,
            proteinDaysHitGoal: proteinDaysHitGoal,
            averageProteinGrams: avgProtein,
            minProteinGrams: minProtein,
            maxProteinGrams: maxProtein
        )

        let recentWeeks: [WeeklyInsightSummaryPayload.CrossWeekPatterns.RecentWeek] = windowsOldestFirst.compactMap { window in
            let weekPoints = graphPoints(for: window.dayIdentifiers)
            guard let firstPoint = weekPoints.first, let lastPoint = weekPoints.last else { return nil }

            let weekCaloriesIn = weekPoints.map(\.calories)
            let weekCaloriesBurned = weekPoints.map(\.burned)
            let weekNet = weekPoints.map { $0.calories - $0.burned }
            let weekGoalDeltas = weekPoints.map { $0.calories - $0.goal }
            let weekProtein = weekPoints.map { nutrientTotals(for: $0.dayIdentifier)["g_protein"] ?? 0 }
            let mealLoggedDays = weekPoints.filter { !entries(forDayIdentifier: $0.dayIdentifier).isEmpty && $0.calories > 0 }.count
            let exerciseEntries = weekPoints.flatMap { exercises(forDayIdentifier: $0.dayIdentifier) }
            let exerciseDays = weekPoints.filter { !exercises(forDayIdentifier: $0.dayIdentifier).isEmpty }.count
            let averageExerciseMinutes = exerciseDays > 0
                ? Int((Double(exerciseEntries.reduce(0) { $0 + $1.durationMinutes }) / Double(exerciseDays)).rounded())
                : 0
            let weekWeights = weekPoints.compactMap { point in
                weighInsByDay[point.dayIdentifier]
            }
            let weekWeightChange: Double? = {
                guard let startWeight = weekWeights.first, let endWeight = weekWeights.last else { return nil }
                return endWeight - startWeight
            }()

            let weekDayCountDouble = Double(weekPoints.count)

            return WeeklyInsightSummaryPayload.CrossWeekPatterns.RecentWeek(
                label: window.label,
                startDayIdentifier: firstPoint.dayIdentifier,
                endDayIdentifier: lastPoint.dayIdentifier,
                averageCaloriesIn: Int((Double(weekCaloriesIn.reduce(0, +)) / weekDayCountDouble).rounded()),
                averageCaloriesBurned: Int((Double(weekCaloriesBurned.reduce(0, +)) / weekDayCountDouble).rounded()),
                averageNetCalories: Int((Double(weekNet.reduce(0, +)) / weekDayCountDouble).rounded()),
                overGoalDays: weekGoalDeltas.filter { $0 > 0 }.count,
                underGoalDays: weekGoalDeltas.filter { $0 < 0 }.count,
                mealLoggedDays: mealLoggedDays,
                exerciseDays: exerciseDays,
                averageExerciseMinutes: averageExerciseMinutes,
                averageProteinGrams: Int((Double(weekProtein.reduce(0, +)) / weekDayCountDouble).rounded()),
                weightLoggedDays: weekWeights.count,
                weightChangePounds: weekWeightChange
            )
        }

        let currentWeekTrend = recentWeeks.last
        let previousWeekTrend = recentWeeks.dropLast().last
        let crossWeekPatterns = WeeklyInsightSummaryPayload.CrossWeekPatterns(
            recentWeeks: recentWeeks,
            currentVsPreviousCaloriesDelta: {
                guard let currentWeekTrend, let previousWeekTrend else { return nil }
                return currentWeekTrend.averageCaloriesIn - previousWeekTrend.averageCaloriesIn
            }(),
            currentVsPreviousNetDelta: {
                guard let currentWeekTrend, let previousWeekTrend else { return nil }
                return currentWeekTrend.averageNetCalories - previousWeekTrend.averageNetCalories
            }(),
            currentVsPreviousProteinDelta: {
                guard let currentWeekTrend, let previousWeekTrend else { return nil }
                return currentWeekTrend.averageProteinGrams - previousWeekTrend.averageProteinGrams
            }(),
            currentVsPreviousOverGoalDayDelta: {
                guard let currentWeekTrend, let previousWeekTrend else { return nil }
                return currentWeekTrend.overGoalDays - previousWeekTrend.overGoalDays
            }(),
            currentVsPreviousExerciseDayDelta: {
                guard let currentWeekTrend, let previousWeekTrend else { return nil }
                return currentWeekTrend.exerciseDays - previousWeekTrend.exerciseDays
            }()
        )

        var mealTotalsByGroup: [MealGroup: Int] = [:]
        var mealLoggedDaysByGroup: [MealGroup: Int] = [:]
        var lateLogDayIdentifiers = Set<String>()
        var exerciseDayIdentifiers = Set<String>()
        var exerciseStatsByType: [ExerciseType: (days: Set<String>, sessions: Int, totalMinutes: Int, totalCalories: Int)] = [:]
        var overGoalFoodStats: [String: (name: String, dayIdentifiers: Set<String>, totalCalories: Int, mealGroups: [String: Int])] = [:]

        for point in recentTrendPoints {
            let dayIdentifier = point.dayIdentifier
            let dayEntries = entries(forDayIdentifier: dayIdentifier)
            let groupedEntries = Dictionary(grouping: dayEntries, by: \.mealGroup)
            for group in MealGroup.logDisplayOrder {
                let groupEntries = groupedEntries[group] ?? []
                let groupCalories = groupEntries.reduce(0) { $0 + $1.calories }
                if groupCalories > 0 {
                    mealTotalsByGroup[group, default: 0] += groupCalories
                    mealLoggedDaysByGroup[group, default: 0] += 1
                }
            }

            if dayEntries.contains(where: {
                let hour = centralCalendar.component(.hour, from: $0.createdAt)
                return hour >= 20
            }) {
                lateLogDayIdentifiers.insert(dayIdentifier)
            }

            let dayExercises = exercises(forDayIdentifier: dayIdentifier)
            if !dayExercises.isEmpty {
                exerciseDayIdentifiers.insert(dayIdentifier)
            }
            for exercise in dayExercises {
                var stats = exerciseStatsByType[exercise.exerciseType] ?? (
                    days: Set<String>(),
                    sessions: 0,
                    totalMinutes: 0,
                    totalCalories: 0
                )
                stats.days.insert(dayIdentifier)
                stats.sessions += 1
                stats.totalMinutes += exercise.durationMinutes
                stats.totalCalories += exercise.calories
                exerciseStatsByType[exercise.exerciseType] = stats
            }

            if point.calories > point.goal {
                for entry in dayEntries where entry.calories > 0 {
                    let key = entry.name.lowercased()
                    var stats = overGoalFoodStats[key] ?? (
                        name: entry.name,
                        dayIdentifiers: Set<String>(),
                        totalCalories: 0,
                        mealGroups: [:]
                    )
                    stats.dayIdentifiers.insert(dayIdentifier)
                    stats.totalCalories += entry.calories
                    stats.mealGroups[entry.mealGroup.rawValue, default: 0] += entry.calories
                    overGoalFoodStats[key] = stats
                }
            }
        }

        let totalRecentCalories = recentTrendPoints.reduce(0) { $0 + $1.calories }
        let eveningCalories = recentTrendPoints.reduce(0) { partialResult, point in
            let eveningGroupCalories = entries(forDayIdentifier: point.dayIdentifier)
                .filter { $0.mealGroup == .dinner || $0.mealGroup == .snack }
                .reduce(0) { $0 + $1.calories }
            return partialResult + eveningGroupCalories
        }

        let mealPatterns: [WeeklyInsightSummaryPayload.HabitPatterns.MealPattern] = MealGroup.logDisplayOrder.compactMap { group in
            let loggedDays = mealLoggedDaysByGroup[group, default: 0]
            let totalCalories = mealTotalsByGroup[group, default: 0]
            guard loggedDays > 0, totalCalories > 0 else { return nil }
            return WeeklyInsightSummaryPayload.HabitPatterns.MealPattern(
                mealGroup: group.rawValue,
                averageCaloriesPerLoggedDay: Int((Double(totalCalories) / Double(loggedDays)).rounded()),
                loggedDays: loggedDays,
                totalCalories: totalCalories
            )
        }

        let exercisePatterns: [WeeklyInsightSummaryPayload.HabitPatterns.ExercisePattern] = ExerciseType.allCases.compactMap { type in
            guard let stats = exerciseStatsByType[type], !stats.days.isEmpty else { return nil }
            return WeeklyInsightSummaryPayload.HabitPatterns.ExercisePattern(
                exerciseType: type.rawValue,
                days: stats.days.count,
                sessions: stats.sessions,
                averageDurationMinutes: Int((Double(stats.totalMinutes) / Double(stats.sessions)).rounded()),
                totalCalories: stats.totalCalories
            )
        }

        let repeatedOverGoalFoods: [WeeklyInsightSummaryPayload.RepeatedFoodPattern] = overGoalFoodStats.values
            .filter { $0.dayIdentifiers.count >= 2 }
            .sorted {
                if $0.dayIdentifiers.count == $1.dayIdentifiers.count {
                    return $0.totalCalories > $1.totalCalories
                }
                return $0.dayIdentifiers.count > $1.dayIdentifiers.count
            }
            .prefix(5)
            .map { stats in
                WeeklyInsightSummaryPayload.RepeatedFoodPattern(
                    name: stats.name,
                    overGoalDayCount: stats.dayIdentifiers.count,
                    totalCalories: stats.totalCalories,
                    dominantMealGroup: stats.mealGroups.max(by: { $0.value < $1.value })?.key ?? MealGroup.snack.rawValue
                )
            }

        let habitPatterns = WeeklyInsightSummaryPayload.HabitPatterns(
            averageEveningCalories: Int((Double(eveningCalories) / Double(max(recentTrendPoints.count, 1))).rounded()),
            averageEveningSharePercent: totalRecentCalories > 0 ? Int((Double(eveningCalories) / Double(totalRecentCalories) * 100.0).rounded()) : 0,
            breakfastLoggedDays: mealLoggedDaysByGroup[.breakfast, default: 0],
            lunchLoggedDays: mealLoggedDaysByGroup[.lunch, default: 0],
            dinnerLoggedDays: mealLoggedDaysByGroup[.dinner, default: 0],
            snackLoggedDays: mealLoggedDaysByGroup[.snack, default: 0],
            lateLogDays: lateLogDayIdentifiers.count,
            exerciseDays: exerciseDayIdentifiers.count,
            averageExerciseMinutesOnExerciseDays: exerciseDayIdentifiers.isEmpty
                ? 0
                : Int((Double(exerciseStatsByType.values.reduce(0) { $0 + $1.totalMinutes }) / Double(exerciseDayIdentifiers.count)).rounded()),
            mealPatterns: mealPatterns,
            exercisePatterns: exercisePatterns,
            repeatedOverGoalFoods: repeatedOverGoalFoods
        )

        return WeeklyInsightSummaryPayload(
            days: days,
            weekOverview: weekOverview,
            intake: intake,
            activity: activity,
            balance: balance,
            weightTrend: weightTrend,
            dataQuality: dataQuality,
            macros: macros,
            crossWeekPatterns: crossWeekPatterns,
            habitPatterns: habitPatterns,
            loggedFoods: []
        )
    }


}
