// Calorie Tracker 2026

import SwiftUI

extension ContentView {

    var syncedHealthSourceDeviceType: CloudSyncOriginDeviceType {
        CloudSyncOriginDeviceType(rawValue: storedSyncedHealthSourceDeviceTypeRaw) ?? .unknown
    }

    var effectiveHealthProfile: HealthKitService.SyncedProfile? {
        if let profile = healthKitService.profile {
            return profile
        }
        return cloudSyncedHealthProfile
    }

    var isUsingSyncedHealthFallback: Bool {
        healthKitService.profile == nil && cloudSyncedHealthProfile != nil
    }

    var shouldUseIPhoneExerciseSource: Bool {
        currentCloudOriginDeviceType != .iphone && syncedHealthSourceDeviceType == .iphone
    }

    var effectiveTodayHealthWorkouts: [ExerciseEntry] {
        let local = workoutsForToday(healthKitService.todayWorkouts)
        let synced = workoutsForToday(cloudSyncedTodayWorkouts)

        // Use cached iPhone-synced workouts while local HealthKit refresh is in flight to avoid launch flicker.
        if currentCloudOriginDeviceType == .iphone {
            if local.isEmpty {
                return synced
            }
            if synced.isEmpty {
                return local
            }
            return mergedWorkoutEntries(primary: local, secondary: synced)
        }

        if shouldUseIPhoneExerciseSource {
            return synced
        }

        if local.isEmpty {
            return synced
        }
        if synced.isEmpty {
            return local
        }
        return mergedWorkoutEntries(primary: local, secondary: synced)
    }

    func workoutsForToday(_ workouts: [ExerciseEntry]) -> [ExerciseEntry] {
        workouts.filter { entry in
            guard centralDayIdentifier(for: entry.createdAt) == todayDayIdentifier else { return false }
            // Walking calories are already accounted for via step activity, so skip walking workouts.
            guard entry.symbolName != "figure.walk" else { return false }
            return true
        }
    }

    var resolvedBMRProfile: BMRProfile? { effectiveHealthProfile?.bmrProfile }
    var isUsingHealthDerivedBMR: Bool {
        guard bmrSource == .automatic else { return false }
        return resolvedBMRProfile.flatMap(calculatedBMR(for:)) != nil
    }
    var resolvedBMRCalories: Int {
        if bmrSource == .manual {
            return manualBMRCalories
        }
        return resolvedBMRProfile.flatMap(calculatedBMR(for:)) ?? manualBMRCalories
    }
    var archivedSyncedBurnedCaloriesToday: Int? {
        guard shouldUseIPhoneExerciseSource else { return nil }
        return dailyBurnedCalorieArchive[todayDayIdentifier]
    }

    var syncedActivityCaloriesToday: Int? {
        guard let archivedBurned = archivedSyncedBurnedCaloriesToday else { return nil }
        let effectiveOffset = (calibrationState.isEnabled && goalType != .fixed) ? calibrationState.calibrationOffsetCalories : 0
        let baselineBurned = max(archivedBurned - effectiveOffset, 1)
        let syncedExerciseCalories = exercises.reduce(0) { $0 + $1.calories }
            + effectiveTodayHealthWorkouts.reduce(0) { $0 + $1.calories }
        return max(baselineBurned - resolvedBMRCalories - syncedExerciseCalories, 0)
    }

    var activityCaloriesToday: Int {
        if let syncedActivityCaloriesToday {
            return syncedActivityCaloriesToday
        }
        return stepActivityService.estimatedCaloriesToday(profile: resolvedBMRProfile)
    }

    var reclassifiedWalkingCaloriesToday: Int {
        let totalRequestedReclassification = (exercises + effectiveTodayHealthWorkouts)
            .reduce(0) { $0 + requestedWalkingReclassification(for: $1) }
        return min(totalRequestedReclassification, activityCaloriesToday)
    }

    var effectiveActivityCaloriesToday: Int {
        max(activityCaloriesToday - reclassifiedWalkingCaloriesToday, 0)
    }

    var hasResolvedInitialLiveCalorieInputsThisLaunch: Bool {
        healthKitService.hasLoadedFreshHealthDataThisLaunch
            && stepActivityService.hasLoadedFreshStepDataThisLaunch
    }

    /// True when any activity (steps, HealthKit workout, or manual exercise) has been
    /// recorded today. The archive is only written — and read on launch — when this is true,
    /// so zero-step HealthKit results can never seed or corrupt today's burned/goal values.
    var activityDetectedToday: Bool {
        activityDetectedDayIdentifier == todayDayIdentifier
    }

    /// True when we should show nil/spinner instead of a calorie value: HealthKit hasn't
    /// resolved yet and no activity has been detected for today (so there is no valid
    /// archive to fall back on).
    var shouldDeferCalorieDisplay: Bool {
        !hasResolvedInitialLiveCalorieInputsThisLaunch && !activityDetectedToday
    }

    var exerciseCaloriesToday: Int {
        let manual = exercises.reduce(0) { $0 + $1.calories }
        let health = effectiveTodayHealthWorkouts.reduce(0) { $0 + $1.calories }
        return manual + health
    }
    var currentDailyCalorieModel: DailyCalorieModel {
        // Before HealthKit resolves, use the archive as the initial display value —
        // but only if activity has been detected today, meaning the archive was written
        // with real data (non-zero steps or a workout). Without that guard a zero-step
        // HealthKit result could seed a BMR-only value into the archive on launch.
        let shouldUseArchive = !hasResolvedInitialLiveCalorieInputsThisLaunch || shouldUseIPhoneExerciseSource
        if shouldUseArchive,
           activityDetectedToday,
           let archivedGoal = dailyCalorieGoalArchive[todayDayIdentifier],
           let archivedBurned = dailyBurnedCalorieArchive[todayDayIdentifier] {
            let effectiveOffset = (calibrationState.isEnabled && goalType != .fixed) ? calibrationState.calibrationOffsetCalories : 0
            let dayGoalType = goalTypeForDay(todayDayIdentifier)
            let resolvedGoal = dayGoalType == .fixed ? fixedGoalCalories : archivedGoal
            return DailyCalorieModel(
                bmr: resolvedBMRCalories,
                burned: archivedBurned,
                burnedBaseline: max(archivedBurned - effectiveOffset, 1),
                goal: resolvedGoal,
                deficit: deficitForDay(todayDayIdentifier),
                usesBMR: isUsingHealthDerivedBMR
            )
        }

        let bmr = resolvedBMRCalories
        let burnedBaseline = max(bmr + effectiveActivityCaloriesToday + exerciseCaloriesToday, 1)
        let effectiveOffset = (calibrationState.isEnabled && goalType != .fixed) ? calibrationState.calibrationOffsetCalories : 0
        let burned = max(burnedBaseline + effectiveOffset, 1)
        let dayGoalType = goalTypeForDay(todayDayIdentifier)
        let amount = deficitForDay(todayDayIdentifier)
        let goal: Int
        if dayGoalType == .fixed {
            goal = fixedGoalCalories
        } else if dayGoalType == .surplus {
            goal = max(burned + amount, 1)
        } else {
            goal = max(burned - amount, 1)
        }
        return DailyCalorieModel(
            bmr: bmr,
            burned: burned,
            burnedBaseline: burnedBaseline,
            goal: goal,
            deficit: amount,
            usesBMR: isUsingHealthDerivedBMR
        )
    }
    var burnedCaloriesToday: Int { currentDailyCalorieModel.burned }
    var calorieGoal: Int { currentDailyCalorieModel.goal }
    var displayedCalorieGoal: Int? {
        shouldDeferCalorieDisplay ? nil : calorieGoal
    }
    var displayedCaloriesLeft: Int? {
        shouldDeferCalorieDisplay ? nil : caloriesLeft
    }
    var calorieHeroDisplay: (value: Int?, title: String) {
        if shouldDeferCalorieDisplay {
            return (nil, "Syncing Health activity...")
        }

        let dayGoalType = goalTypeForDay(todayDayIdentifier)
        let consumed = totalCalories
        let goal = calorieGoal
        let burned = burnedCaloriesToday

        switch dayGoalType {
        case .deficit:
            if consumed <= goal {
                return (max(goal - consumed, 0), "Calories Left")
            }
            if consumed <= burned {
                return (max(burned - consumed, 0), "Until Burned")
            }
            return (max(consumed - burned, 0), "Over Burned")
        case .surplus:
            if consumed > goal {
                return (max(consumed - goal, 0), "Over Goal")
            }
            return (max(goal - consumed, 0), "Calories Left")
        case .fixed:
            if consumed > goal {
                return (max(consumed - goal, 0), "Over Goal")
            }
            return (max(goal - consumed, 0), "Calories Left")
        }
    }
    var displayedCalorieProgress: Double {
        shouldDeferCalorieDisplay ? 0 : calorieProgress
    }
    var calibrationOffsetCalories: Int { calibrationState.calibrationOffsetCalories }
    var calibrationConfidence: CalibrationConfidence {
        let checks = max(calibrationState.dataQualityChecks, 1)
        let passRate = Double(calibrationState.dataQualityPasses) / Double(checks)
        let recent = calibrationState.recentDailyErrors.suffix(4)
        guard !recent.isEmpty else { return .low }
        let mean = recent.reduce(0, +) / Double(recent.count)
        let variance = recent.reduce(0.0) { partial, value in
            let delta = value - mean
            return partial + (delta * delta)
        } / Double(recent.count)
        let stdDev = sqrt(variance)

        if passRate >= 0.8, stdDev <= 20, recent.count >= 3 {
            return .high
        }
        if passRate >= 0.5, stdDev <= 40 {
            return .medium
        }
        return .low
    }

    var calibrationStatusText: String {
        guard calibrationState.isEnabled else { return "Off" }
        switch calibrationState.lastRunStatus {
        case .never: return "Not enough data yet"
        case .applied: return "Applied"
        case .skipped: return "Skipped"
        }
    }

    var calibrationLastRunText: String {
        guard let lastRunDate = calibrationState.lastRunDate else { return "--" }
        return lastRunDate.formatted(date: .abbreviated, time: .omitted)
    }

    var calibrationNextRunText: String {
        guard let next = nextCalibrationRunDate(from: Date()) else { return "--" }
        return next.formatted(date: .abbreviated, time: .omitted)
    }

    private func requestedWalkingReclassification(for entry: ExerciseEntry) -> Int {
        guard entry.exerciseType == .running else {
            return max(entry.reclassifiedWalkingCalories, 0)
        }

        let weightPounds = resolvedBMRProfile?.weightPounds ?? 170
        let inferredWalkingEquivalent = ExerciseCalorieService.walkingEquivalentCalories(
            type: .running,
            durationMinutes: entry.durationMinutes,
            distanceMiles: entry.distanceMiles,
            weightPounds: weightPounds
        )

        // Prefer stored value when present, but recover from stale/legacy zero values.
        return max(entry.reclassifiedWalkingCalories, inferredWalkingEquivalent)
    }

}
