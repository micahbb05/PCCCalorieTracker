// Calorie Tracker 2026

import SwiftUI

extension ContentView {

    func generateWeeklyInsight() async {
        guard !isWeeklyInsightLoading else { return }

        let cachedInsight = weeklyInsightCachedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let todayDayIdentifier = centralDayIdentifier(for: Date())
        if weeklyInsightCachedDayIdentifier == todayDayIdentifier,
           !cachedInsight.isEmpty {
            weeklyInsightText = cachedInsight
            weeklyInsightErrorMessage = nil
            isWeeklyInsightPresented = true
            return
        }

        isWeeklyInsightLoading = true
        weeklyInsightErrorMessage = nil

        defer {
            isWeeklyInsightLoading = false
        }

        guard let summary = makeWeeklyInsightSummaryPayload() else {
            if !cachedInsight.isEmpty {
                weeklyInsightText = cachedInsight
                weeklyInsightErrorMessage = nil
            } else {
                weeklyInsightText = nil
                weeklyInsightErrorMessage = "Not enough recent data to generate an insight yet."
            }
            isWeeklyInsightPresented = true
            return
        }

        do {
            let insight = try await weeklyInsightService.generateWeeklyInsight(summary: summary)
            weeklyInsightText = insight
            weeklyInsightCachedDayIdentifier = todayDayIdentifier
            weeklyInsightCachedText = insight
            isWeeklyInsightPresented = true
        } catch {
            if !cachedInsight.isEmpty {
                weeklyInsightText = cachedInsight
                weeklyInsightErrorMessage = nil
            } else {
                weeklyInsightText = nil
                weeklyInsightErrorMessage = error.localizedDescription
            }
            isWeeklyInsightPresented = true
        }
    }

    func weightChangeComparisonPoints(for range: NetHistoryRange) -> [WeightChangePoint] {
        let aggregation = weightChangeAggregation(for: range)
        return expectedWeightChangePoints(for: range, aggregation: aggregation)
            + actualWeightChangePoints(for: range, aggregation: aggregation)
    }

    func expectedWeightChangePoints(
        for range: NetHistoryRange,
        aggregation: WeightChangeAggregation = .daily
    ) -> [WeightChangePoint] {
        let dates: [Date] = dayIdentifiers(forLast: range.dayCount).compactMap { identifier in
            guard let date = date(fromCentralDayIdentifier: identifier) else {
                return nil
            }
            return date
        }

        var runningChange = 0.0
        var points: [WeightChangePoint] = []
        points.reserveCapacity(dates.count)

        for date in dates {
            let identifier = centralDayIdentifier(for: date)
            if hasExpectedWeightChangeData(for: identifier) {
                let netCalories = dailyCalories(for: identifier) - burnedCaloriesForDay(identifier)
                runningChange += Double(netCalories) / 3500.0
            }

            points.append(
                WeightChangePoint(
                    date: date,
                    change: runningChange,
                    series: .expected
                )
            )
        }

        return aggregatedWeightChangePoints(points, aggregation: aggregation)
    }

    func actualWeightChangePoints(
        for range: NetHistoryRange,
        aggregation: WeightChangeAggregation = .daily
    ) -> [WeightChangePoint] {
        let identifiers = dayIdentifiers(forLast: range.dayCount)
        guard
            let firstIdentifier = identifiers.first,
            let lastIdentifier = identifiers.last,
            let startDate = date(fromCentralDayIdentifier: firstIdentifier),
            let lastDate = date(fromCentralDayIdentifier: lastIdentifier),
            let endDate = centralCalendar.date(byAdding: .day, value: 1, to: lastDate)
        else {
            return []
        }

        let weighIns = healthWeighIns
            .sorted { $0.selectedSampleDate < $1.selectedSampleDate }

        guard let baseline = weighIns.last(where: { $0.selectedSampleDate < startDate })
            ?? weighIns.first(where: { $0.selectedSampleDate >= startDate && $0.selectedSampleDate < endDate }) else {
            return []
        }

        let baselineWeight = baseline.representativePounds
        let rangedWeighIns = weighIns.filter { $0.selectedSampleDate >= startDate && $0.selectedSampleDate < endDate }
        guard !rangedWeighIns.isEmpty else { return [] }

        var points: [WeightChangePoint] = []

        if baseline.selectedSampleDate < startDate {
            points.append(
                WeightChangePoint(
                    date: startDate,
                    change: 0,
                    series: .actual
                )
            )
        }

        for weighIn in rangedWeighIns {
            points.append(
                WeightChangePoint(
                    date: weighIn.selectedSampleDate,
                    change: weighIn.representativePounds - baselineWeight,
                    series: .actual
                )
            )
        }

        return aggregatedWeightChangePoints(points, aggregation: aggregation)
    }

    func expectedWeightChangeSummary(for range: NetHistoryRange) -> Double {
        expectedWeightChangePoints(for: range, aggregation: .daily).last?.change ?? 0
    }

    func actualWeightChangeSummary(for range: NetHistoryRange) -> Double? {
        let points = actualWeightChangePoints(for: range, aggregation: .daily)
        guard points.count > 1 else { return nil }
        return points.last?.change
    }

    func hasExpectedWeightChangeData(for identifier: String) -> Bool {
        !(dailyEntryArchive[identifier] ?? []).isEmpty
    }

    var netCalorieSummary: (net: Int, hasData: Bool) {
        let identifiers = dayIdentifiers(forLast: netHistoryRange.dayCount)
            .filter { dailyCalories(for: $0) > 0 }
        guard !identifiers.isEmpty else {
            return (net: 0, hasData: false)
        }

        let dayCount = identifiers.count
        let totalConsumed = identifiers.reduce(0) { $0 + dailyCalories(for: $1) }
        let totalBurned = identifiers.reduce(0) { $0 + burnedCaloriesForDay($1) }
        let totalNet = totalConsumed - totalBurned
        let averageNet = Int((Double(totalNet) / Double(dayCount)).rounded())

        return (net: averageNet, hasData: true)
    }

    var historyAverageMealDistribution: [(group: MealGroup, calories: Int)] {
        let identifiers = dayIdentifiers(forLast: historyDistributionRange.dayCount)
            .filter { dailyCalories(for: $0) > 0 }
        guard !identifiers.isEmpty else { return [] }

        return MealGroup.logDisplayOrder.compactMap { group in
            let totalGroupCalories = identifiers.reduce(0) { partialResult, identifier in
                let dayCalories = entries(forDayIdentifier: identifier)
                    .filter { $0.mealGroup == group }
                    .reduce(0) { $0 + $1.calories }
                return partialResult + dayCalories
            }
            let averageCalories = Int((Double(totalGroupCalories) / Double(identifiers.count)).rounded())
            guard averageCalories > 0 else { return nil }
            return (group, averageCalories)
        }
    }

    var parsedEntryCalories: Int? { parseInputValue(entryCaloriesText) }

    var parsedNutrientInputs: [String: Int]? {
        var result: [String: Int] = [:]
        for nutrient in activeNutrients {
            let text = nutrientInputTexts[nutrient.key] ?? ""
            guard let parsed = parseInputValue(text) else { return nil }
            result[nutrient.key] = parsed
        }
        return result
    }

    var hasTypedManualNutritionInput: Bool {
        if !entryCaloriesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        return activeNutrients.contains {
            !(nutrientInputTexts[$0.key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    var entryError: String? {
        guard hasTypedManualNutritionInput else {
            return nil
        }

        guard parsedEntryCalories != nil, let nutrientMap = parsedNutrientInputs else {
            return "Use non-negative whole numbers."
        }

        let nutrientSum = nutrientMap.values.reduce(0, +)
        let calories = parsedEntryCalories ?? 0
        if calories + nutrientSum == 0 {
            return "Enter calories or a nutrient above 0."
        }

        return nil
    }

    var canAddEntry: Bool {
        guard let calories = parsedEntryCalories, let nutrientMap = parsedNutrientInputs else {
            return false
        }
        return calories + nutrientMap.values.reduce(0, +) > 0
    }


}
