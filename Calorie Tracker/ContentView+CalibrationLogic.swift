// Calorie Tracker 2026

import SwiftUI

extension ContentView {

    func scheduleCalibrationEvaluation(force: Bool = false) {
        guard calibrationState.isEnabled else { return }
        guard goalType != .fixed else { return }
        guard healthKitService.authorizationState == .connected else { return }
        if !force, let last = lastCalibrationEvaluationAt, Date().timeIntervalSince(last) < 60 * 60 * 6 {
            return
        }

        calibrationEvaluationTask?.cancel()
        calibrationEvaluationTask = Task(priority: .utility) {
            let reducedWeights = await healthKitService.fetchReducedBodyMassHistory(days: 21)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                lastCalibrationEvaluationAt = Date()
                healthWeighIns = reducedWeights
                saveHealthWeighIns()
                evaluateWeeklyCalibrationIfNeeded(referenceDate: Date())
            }
        }
    }

    func evaluateWeeklyCalibrationIfNeeded(referenceDate: Date) {
        guard calibrationState.isEnabled else { return }
        guard goalType != .fixed else { return }
        let minimumWeeklyWeighIns = 3
        let weekID = calibrationWeekID(for: referenceDate)
        if calibrationState.lastAppliedWeekID == weekID {
            return
        }

        let currentWeekIDs = trailingDayIdentifiers(endingAt: referenceDate, count: 7, endingOffsetDays: 0)
        let priorWeekIDs = trailingDayIdentifiers(endingAt: referenceDate, count: 7, endingOffsetDays: 7)
        guard currentWeekIDs.count == 7, priorWeekIDs.count == 7 else {
            markCalibrationSkipped(reason: "Unable to build weekly windows.")
            return
        }

        let combinedDayIDs = priorWeekIDs + currentWeekIDs
        let weightByDay = Dictionary(uniqueKeysWithValues: healthWeighIns.map { ($0.dayIdentifier, $0.representativePounds) })
        let spikeExcludedDays = spikeExcludedDayIDs(orderedDayIDs: combinedDayIDs, weightByDay: weightByDay)

        let validPriorWeights = priorWeekIDs.compactMap { dayID -> Double? in
            guard !spikeExcludedDays.contains(dayID) else { return nil }
            return weightByDay[dayID]
        }
        let validCurrentWeights = currentWeekIDs.compactMap { dayID -> Double? in
            guard !spikeExcludedDays.contains(dayID) else { return nil }
            return weightByDay[dayID]
        }
        guard validPriorWeights.count >= minimumWeeklyWeighIns else {
            markCalibrationSkipped(reason: "Need at least \(minimumWeeklyWeighIns) valid Health weigh-ins in the prior week.")
            return
        }
        guard validCurrentWeights.count >= minimumWeeklyWeighIns else {
            markCalibrationSkipped(reason: "Need at least \(minimumWeeklyWeighIns) valid Health weigh-ins in the current week.")
            return
        }

        let intakeLoggedDays = currentWeekIDs.filter { dailyCalories(for: $0) > 0 }.count
        let intakeCompleteness = Double(intakeLoggedDays) / 7.0
        guard intakeCompleteness >= 0.85 else {
            markCalibrationSkipped(reason: "Intake logging is below 85% for the week.")
            return
        }

        let currentWeekBaselineBurns = currentWeekIDs.map { burnedBaselineForCalibration(dayIdentifier: $0) }
        let missingBurnDays = currentWeekBaselineBurns.filter { $0 == nil }.count
        guard missingBurnDays <= 2 else {
            markCalibrationSkipped(reason: "Burn baseline is missing for too many days this week.")
            return
        }

        let wPrev = validPriorWeights.reduce(0, +) / Double(validPriorWeights.count)
        let wCurr = validCurrentWeights.reduce(0, +) / Double(validCurrentWeights.count)
        let jumpLimit = max(wPrev * 0.025, 0.01)
        guard abs(wCurr - wPrev) <= jumpLimit else {
            markCalibrationSkipped(reason: "Week-over-week average weight jump exceeded 2.5%.")
            return
        }

        let fallbackBurn = {
            let available = currentWeekBaselineBurns.compactMap { $0 }
            if available.isEmpty { return manualBMRCalories }
            let avg = Double(available.reduce(0, +)) / Double(available.count)
            return max(Int(avg.rounded()), 1)
        }()

        let predictedDeltaKcal = currentWeekIDs.reduce(0.0) { partial, dayID in
            let intake = Double(dailyCalories(for: dayID))
            let burned = Double(burnedBaselineForCalibration(dayIdentifier: dayID) ?? fallbackBurn)
            return partial + (intake - burned)
        }
        let actualDeltaKcal = (wCurr - wPrev) * 3500.0
        let dailyError = (actualDeltaKcal - predictedDeltaKcal) / 7.0

        var recentErrors = calibrationState.recentDailyErrors
        recentErrors.append(dailyError)
        if recentErrors.count > 4 {
            recentErrors = Array(recentErrors.suffix(4))
        }

        let isFastStart = calibrationState.appliedWeekCount < 3
        let adjustmentParams = calibrationAdjustmentParameters(recentErrors: recentErrors, isFastStart: isFastStart)
        let smoothedDailyError = clamp(
            weightedErrorMean(recentErrors),
            lower: -adjustmentParams.errorClamp,
            upper: adjustmentParams.errorClamp
        )
        // Invert correction sign: positive error implies burn was overestimated, so offset must decrease.
        let offsetStep = clamp(
            (-smoothedDailyError) * adjustmentParams.alpha,
            lower: -adjustmentParams.maxStep,
            upper: adjustmentParams.maxStep
        )
        let newOffset = Int(
            clamp(
                Double(calibrationState.calibrationOffsetCalories) + offsetStep,
                lower: -adjustmentParams.offsetLimit,
                upper: adjustmentParams.offsetLimit
            ).rounded()
        )

        calibrationState.calibrationOffsetCalories = newOffset
        calibrationState.recentDailyErrors = recentErrors
        calibrationState.appliedWeekCount += 1
        calibrationState.lastAppliedWeekID = weekID
        calibrationState.lastRunDate = Date()
        calibrationState.lastRunStatus = .applied
        calibrationState.lastSkipReason = nil
        calibrationState.dataQualityChecks += 1
        calibrationState.dataQualityPasses += 1
        saveCalibrationState()
        syncCurrentDayGoalArchive()
    }

    func markCalibrationSkipped(reason: String) {
        calibrationState.lastRunDate = Date()
        calibrationState.lastRunStatus = .skipped
        calibrationState.lastSkipReason = reason
        calibrationState.dataQualityChecks += 1
        saveCalibrationState()
    }

    func burnedBaselineForCalibration(dayIdentifier: String) -> Int? {
        if dayIdentifier == todayDayIdentifier {
            return currentDailyCalorieModel.burnedBaseline
        }
        guard let burned = dailyBurnedCalorieArchive[dayIdentifier] else { return nil }
        let effectiveOffset = calibrationState.isEnabled ? calibrationState.calibrationOffsetCalories : 0
        return max(burned - effectiveOffset, 1)
    }

    func trailingDayIdentifiers(endingAt referenceDate: Date, count: Int, endingOffsetDays: Int) -> [String] {
        guard count > 0 else { return [] }
        let referenceDay = centralCalendar.startOfDay(for: referenceDate)
        guard let endingDay = centralCalendar.date(byAdding: .day, value: -endingOffsetDays, to: referenceDay) else {
            return []
        }

        return (0..<count).compactMap { index in
            let offset = -(count - 1 - index)
            guard let day = centralCalendar.date(byAdding: .day, value: offset, to: endingDay) else { return nil }
            return centralDayIdentifier(for: day)
        }
    }

    func spikeExcludedDayIDs(orderedDayIDs: [String], weightByDay: [String: Double]) -> Set<String> {
        guard orderedDayIDs.count > 1 else { return [] }
        var excluded: Set<String> = []
        for index in 1..<orderedDayIDs.count {
            let previous = orderedDayIDs[index - 1]
            let current = orderedDayIDs[index]
            guard let previousWeight = weightByDay[previous], let currentWeight = weightByDay[current] else {
                continue
            }
            if abs(currentWeight - previousWeight) > 4.0 {
                excluded.insert(current)
            }
        }
        return excluded
    }

    func weightedErrorMean(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let trimmed = Array(values.suffix(Self.calibrationErrorWeights.count))
        let weights = Array(Self.calibrationErrorWeights.suffix(trimmed.count))
        let weightedSum = zip(trimmed, weights).reduce(0.0) { partial, element in
            partial + (element.0 * element.1)
        }
        let totalWeight = weights.reduce(0, +)
        guard totalWeight > 0 else { return 0 }
        return weightedSum / totalWeight
    }

    struct CalibrationAdjustmentParameters {
        let errorClamp: Double
        let alpha: Double
        let maxStep: Double
        let offsetLimit: Double
    }

    func calibrationAdjustmentParameters(recentErrors: [Double], isFastStart: Bool) -> CalibrationAdjustmentParameters {
        let defaultParams = CalibrationAdjustmentParameters(
            errorClamp: 100,
            alpha: isFastStart ? 0.5 : 0.2,
            maxStep: isFastStart ? 60 : 40,
            offsetLimit: 300
        )

        let trailing = Array(recentErrors.suffix(3))
        guard trailing.count == 3 else { return defaultParams }

        let signs = trailing.map { value -> Int in
            if value > 0 { return 1 }
            if value < 0 { return -1 }
            return 0
        }
        guard let firstSign = signs.first, firstSign != 0, signs.allSatisfy({ $0 == firstSign }) else {
            return defaultParams
        }

        let absErrors = trailing.map { abs($0) }
        guard absErrors.allSatisfy({ $0 >= 250 }) else { return defaultParams }

        let meanAbs = absErrors.reduce(0, +) / Double(absErrors.count)
        let intensity = clamp((meanAbs - 250) / 600 + 1, lower: 1, upper: 2)

        return CalibrationAdjustmentParameters(
            errorClamp: 100 * intensity,
            alpha: (isFastStart ? 0.5 : 0.2) + (isFastStart ? 0.1 : 0.15) * (intensity - 1),
            maxStep: (isFastStart ? 60 : 40) * intensity,
            offsetLimit: 300 + (300 * (intensity - 1))
        )
    }

    func calibrationWeekID(for date: Date) -> String {
        let components = centralCalendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        let year = components.yearForWeekOfYear ?? 0
        let week = components.weekOfYear ?? 0
        return String(format: "%04d-W%02d", year, week)
    }

    func nextCalibrationRunDate(from date: Date) -> Date? {
        let startOfDay = centralCalendar.startOfDay(for: date)
        guard let startOfWeek = centralCalendar.dateInterval(of: .weekOfYear, for: startOfDay)?.start else {
            return nil
        }
        return centralCalendar.date(byAdding: .day, value: 7, to: startOfWeek)
    }

    func clamp(_ value: Double, lower: Double, upper: Double) -> Double {
        min(max(value, lower), upper)
    }

}
