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
            centralDayIdentifier(for: entry.createdAt) == todayDayIdentifier
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
            .reduce(0) { $0 + $1.reclassifiedWalkingCalories }
        return min(totalRequestedReclassification, activityCaloriesToday)
    }

    var effectiveActivityCaloriesToday: Int {
        max(activityCaloriesToday - reclassifiedWalkingCaloriesToday, 0)
    }

    var hasResolvedInitialLiveCalorieInputsThisLaunch: Bool {
        healthKitService.hasLoadedFreshHealthDataThisLaunch
            && stepActivityService.hasLoadedFreshStepDataThisLaunch
    }

    var hasTodayArchive: Bool {
        dailyCalorieGoalArchive[todayDayIdentifier] != nil
            && dailyBurnedCalorieArchive[todayDayIdentifier] != nil
    }

    var shouldDeferForHealthRefreshWithoutTodayArchive: Bool {
        guard !hasResolvedInitialLiveCalorieInputsThisLaunch else {
            return false
        }
        return !hasTodayArchive
    }

    var cachedTodayDailyCalorieModel: DailyCalorieModel? {
        guard cachedCaloriesDayIdentifier == todayDayIdentifier else { return nil }
        guard cachedBurnedCaloriesToday > 0, cachedCalorieGoalToday > 0 else { return nil }
        let effectiveOffset = (calibrationState.isEnabled && goalType != .fixed) ? calibrationState.calibrationOffsetCalories : 0
        return DailyCalorieModel(
            bmr: resolvedBMRCalories,
            burned: cachedBurnedCaloriesToday,
            burnedBaseline: max(cachedBurnedCaloriesToday - effectiveOffset, 1),
            goal: cachedCalorieGoalToday,
            deficit: deficitForDay(todayDayIdentifier),
            usesBMR: isUsingHealthDerivedBMR
        )
    }

    var shouldUseCachedBurnModelOnLaunch: Bool {
        guard !hasResolvedInitialLiveCalorieInputsThisLaunch else { return false }
        return cachedTodayDailyCalorieModel != nil
    }

    var exerciseCaloriesToday: Int {
        let manual = exercises.reduce(0) { $0 + $1.calories }
        let health = effectiveTodayHealthWorkouts.reduce(0) { $0 + $1.calories }
        return manual + health
    }
    var currentDailyCalorieModel: DailyCalorieModel {
        if shouldUseCachedBurnModelOnLaunch, let cachedModel = cachedTodayDailyCalorieModel {
            // Background refresh may have already advanced today's archive (steps/workouts)
            // beyond the last foreground cache. Floor launch cache against archive so the
            // app never dips on open before live HealthKit queries complete.
            if let archivedGoal = dailyCalorieGoalArchive[todayDayIdentifier],
               let archivedBurned = dailyBurnedCalorieArchive[todayDayIdentifier] {
                let effectiveOffset = (calibrationState.isEnabled && goalType != .fixed) ? calibrationState.calibrationOffsetCalories : 0
                let dayGoalType = goalTypeForDay(todayDayIdentifier)
                let safeBurned = max(cachedModel.burned, archivedBurned)
                let safeGoal: Int
                if dayGoalType == .fixed {
                    safeGoal = fixedGoalCalories
                } else {
                    safeGoal = max(cachedModel.goal, archivedGoal)
                }
                return DailyCalorieModel(
                    bmr: resolvedBMRCalories,
                    burned: safeBurned,
                    burnedBaseline: max(safeBurned - effectiveOffset, 1),
                    goal: safeGoal,
                    deficit: deficitForDay(todayDayIdentifier),
                    usesBMR: isUsingHealthDerivedBMR
                )
            }
            return cachedModel
        }
              
        // Use archived goal/burned for today while HealthKit hasn't loaded, to avoid flash of fallback value
        let shouldPreferIPhoneTodayArchive = shouldUseIPhoneExerciseSource
        let shouldUseTodayArchive =
                  !hasResolvedInitialLiveCalorieInputsThisLaunch
            || shouldPreferIPhoneTodayArchive
        if shouldUseTodayArchive,
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
        shouldDeferForHealthRefreshWithoutTodayArchive ? nil : calorieGoal
    }
    var displayedCaloriesLeft: Int? {
        shouldDeferForHealthRefreshWithoutTodayArchive ? nil : caloriesLeft
    }
    var calorieHeroDisplay: (value: Int?, title: String) {
        if shouldDeferForHealthRefreshWithoutTodayArchive {
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
        shouldDeferForHealthRefreshWithoutTodayArchive ? 0 : calorieProgress
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

}
