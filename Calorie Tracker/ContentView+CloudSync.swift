// Calorie Tracker 2026

import SwiftUI
import CloudKit

extension ContentView {

    func setCloudSyncStatus(
        level: CloudSyncStatusLevel,
        title: String,
        detail: String,
        markSuccessAt: Date? = nil
    ) {
        cloudSyncStatusLevel = level
        cloudSyncStatusTitle = title
        cloudSyncStatusDetail = detail
        if let markSuccessAt {
            cloudSyncLastSuccessAt = markSuccessAt
        }
    }

    func cloudSyncProgressDetail(for trigger: CloudSyncTrigger) -> String {
        switch trigger {
        case .launch:
            return "Checking iCloud for the latest data from your other devices."
        case .foreground:
            return "Refreshing iCloud data after the app became active."
        case .timer:
            return "Refreshing iCloud data in the background while the app is open."
        case .push:
            return "A CloudKit change arrived, so the app is pulling the newest data now."
        case .manual:
            return "Retrying iCloud sync now."
        }
    }

    func cloudSyncSuccessDetail(for trigger: CloudSyncTrigger, fallbackDetail: String? = nil) -> String {
        if let fallbackDetail, !fallbackDetail.isEmpty {
            return fallbackDetail
        }

        switch trigger {
        case .launch:
            return "This device finished its launch-time iCloud sync check."
        case .foreground:
            return "This device pulled the latest iCloud data after becoming active."
        case .timer:
            return "This device refreshed from iCloud while the app stayed open."
        case .push:
            return "A CloudKit push was received and the latest data was applied."
        case .manual:
            return "This device completed a manual iCloud sync refresh."
        }
    }

    func cloudSyncStatusPresentation(for error: Error) -> (CloudSyncStatusLevel, String, String) {
        if let syncError = error as? AppCloudSyncError {
            switch syncError {
            case .accountUnavailable(.noAccount):
                return (
                    .warning,
                    "iCloud sync is off",
                    "Sign into the same iCloud account on both devices, then reopen the app."
                )
            case let .accountUnavailable(status):
                return (
                    .warning,
                    "iCloud sync is unavailable",
                    AppCloudSyncError.accountUnavailable(status).errorDescription ?? "This device cannot reach iCloud right now."
                )
            case .cloudKitUnavailable:
                return (
                    .warning,
                    "iCloud sync unavailable in simulator",
                    "CloudKit sync is disabled for this simulator session. On-device sync remains available on physical iPhone and iPad hardware."
                )
            case .missingPayloadAsset:
                return (
                    .error,
                    "Synced data is incomplete",
                    "The CloudKit record exists but its payload is missing. Re-sync from another device may be required."
                )
            case .invalidPayload:
                return (
                    .error,
                    "Synced data could not be read",
                    "The CloudKit payload could not be decoded on this device."
                )
            }
        }

        if let ckError = error as? CKError {
            switch ckError.code {
            case .notAuthenticated:
                return (
                    .warning,
                    "iCloud sign-in is required",
                    "Sign into iCloud on this device, then open the app again."
                )
            case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited, .zoneBusy:
                return (
                    .warning,
                    "iCloud sync is temporarily unavailable",
                    ckError.localizedDescription
                )
            default:
                return (
                    .error,
                    "iCloud sync failed",
                    ckError.localizedDescription
                )
            }
        }

        return (
            .error,
            "iCloud sync failed",
            error.localizedDescription
        )
    }

    func updateCloudSyncStatusAfterFailure(_ error: Error) {
        let presentation = cloudSyncStatusPresentation(for: error)
        setCloudSyncStatus(level: presentation.0, title: presentation.1, detail: presentation.2)
    }

    func handleCloudSyncPayloadChange(oldPayload: CloudSyncPayload, newPayload: CloudSyncPayload) {
        guard hasBootstrappedCloudSync, !isApplyingCloudSync, oldPayload != newPayload else { return }
        scheduleCloudSyncUpload(for: newPayload)
    }

    func scheduleCloudSyncUpload(for payload: CloudSyncPayload) {
        let timestamp = Date().timeIntervalSince1970
        cloudSyncLocalModifiedAt = timestamp
        cloudSyncUploadTask?.cancel()
        isCloudSyncInFlight = true
        setCloudSyncStatus(
            level: .uploading,
            title: "Uploading to iCloud",
            detail: "Sending your latest changes so other devices can pick them up."
        )
        cloudSyncUploadTask = Task {
            do {
                try await Task.sleep(for: .seconds(1.0))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            do {
                try await AppCloudSyncService.shared.saveEnvelope(
                    CloudSyncEnvelope(
                        updatedAt: timestamp,
                        payload: payload,
                        storageVersion: Self.cloudSyncStorageVersion,
                        originDeviceType: currentCloudOriginDeviceType
                    )
                )
                await MainActor.run {
                    isCloudSyncInFlight = false
                    setCloudSyncStatus(
                        level: .synced,
                        title: "iCloud sync is working",
                        detail: "Your latest changes were uploaded to iCloud.",
                        markSuccessAt: Date(timeIntervalSince1970: timestamp)
                    )
                }
            } catch {
                await MainActor.run {
                    isCloudSyncInFlight = false
                    updateCloudSyncStatusAfterFailure(error)
                }
            }
        }
    }

    func mergedCloudSyncPayload(
        primary: CloudSyncPayload,
        secondary: CloudSyncPayload,
        primaryDeviceType: CloudSyncOriginDeviceType,
        secondaryDeviceType: CloudSyncOriginDeviceType
    ) -> CloudSyncPayload {
        let primaryIsPhone = primaryDeviceType == .iphone
        let secondaryIsPhone = secondaryDeviceType == .iphone

        guard primaryIsPhone != secondaryIsPhone else {
            return primary
        }

        if secondaryIsPhone {
            let preferredDayIdentifiers = Set(
                [todayDayIdentifier, primary.lastCentralDayIdentifier, secondary.lastCentralDayIdentifier]
                    .filter { !$0.isEmpty }
            )
            let mergedEntryArchiveData = mergedMealEntryArchiveData(
                primaryData: primary.dailyEntryArchiveData,
                secondaryData: secondary.dailyEntryArchiveData,
                preferSecondaryDayIdentifiers: preferredDayIdentifiers
            )
            let mergedMealEntriesData = mergedTodayEntriesData(
                todayIdentifier: todayDayIdentifier,
                archiveData: mergedEntryArchiveData,
                fallback: secondary.mealEntriesData
            )
            let mergedExerciseArchiveData = mergedExerciseArchiveData(
                primaryData: primary.dailyExerciseArchiveData,
                secondaryData: secondary.dailyExerciseArchiveData,
                preferSecondaryDayIdentifiers: preferredDayIdentifiers
            )
            let mergedGoalArchiveData = mergedIntegerArchiveData(
                primaryData: primary.dailyCalorieGoalArchiveData,
                secondaryData: secondary.dailyCalorieGoalArchiveData,
                preferSecondaryDayIdentifiers: preferredDayIdentifiers
            )
            let mergedBurnedArchiveData = mergedIntegerArchiveData(
                primaryData: primary.dailyBurnedCalorieArchiveData,
                secondaryData: secondary.dailyBurnedCalorieArchiveData,
                preferSecondaryDayIdentifiers: preferredDayIdentifiers
            )
            let mergedGoalTypeArchiveData = mergedStringArchiveData(
                primaryData: primary.dailyGoalTypeArchiveData,
                secondaryData: secondary.dailyGoalTypeArchiveData,
                preferSecondaryDayIdentifiers: preferredDayIdentifiers
            )
            return CloudSyncPayload(
                hasCompletedOnboarding: primary.hasCompletedOnboarding,
                deficitCalories: primary.deficitCalories,
                useWeekendDeficit: primary.useWeekendDeficit,
                weekendDeficitCalories: primary.weekendDeficitCalories,
                goalTypeRaw: primary.goalTypeRaw,
                surplusCalories: primary.surplusCalories,
                fixedGoalCalories: primary.fixedGoalCalories,
                dailyGoalTypeArchiveData: mergedGoalTypeArchiveData,
                proteinGoal: primary.proteinGoal,
                mealEntriesData: mergedMealEntriesData,
                trackedNutrientsData: primary.trackedNutrientsData,
                nutrientGoalsData: primary.nutrientGoalsData,
                lastCentralDayIdentifier: max(primary.lastCentralDayIdentifier, secondary.lastCentralDayIdentifier),
                selectedAppIconChoiceRaw: primary.selectedAppIconChoiceRaw,
                dailyEntryArchiveData: mergedEntryArchiveData,
                dailyCalorieGoalArchiveData: mergedGoalArchiveData,
                dailyBurnedCalorieArchiveData: mergedBurnedArchiveData,
                dailyExerciseArchiveData: mergedExerciseArchiveData,
                venueMenusData: primary.venueMenusData,
                venueMenuSignaturesData: primary.venueMenuSignaturesData,
                quickAddFoodsData: primary.quickAddFoodsData,
                useAIBaseServings: primary.useAIBaseServings,
                calibrationStateData: secondary.calibrationStateData,
                healthWeighInsData: secondary.healthWeighInsData,
                syncedHealthProfileData: secondary.syncedHealthProfileData,
                syncedTodayWorkoutsData: secondary.syncedTodayWorkoutsData,
                syncedHealthSourceDeviceTypeRaw: secondary.syncedHealthSourceDeviceTypeRaw
            )
        }

        return primary
    }

    func mergedMealEntryArchiveData(
        primaryData: String,
        secondaryData: String,
        preferSecondaryDayIdentifiers: Set<String>
    ) -> String {
        guard
            let primaryArchive = decodedArchive(primaryData, as: [String: [MealEntry]].self),
            let secondaryArchive = decodedArchive(secondaryData, as: [String: [MealEntry]].self)
        else {
            return primaryData
        }

        var merged = primaryArchive
        for dayIdentifier in preferSecondaryDayIdentifiers {
            let primaryEntries = primaryArchive[dayIdentifier] ?? []
            let secondaryEntries = secondaryArchive[dayIdentifier] ?? []
            merged[dayIdentifier] = mergedMealEntries(primary: primaryEntries, secondary: secondaryEntries)
        }

        return encodedArchive(merged, fallback: primaryData)
    }

    func mergedTodayEntriesData(todayIdentifier: String, archiveData: String, fallback: String) -> String {
        guard let archive = decodedArchive(archiveData, as: [String: [MealEntry]].self) else {
            return fallback
        }
        let entries = archive[todayIdentifier] ?? []
        return encodedArchive(entries, fallback: fallback)
    }

    func mergedExerciseArchiveData(
        primaryData: String,
        secondaryData: String,
        preferSecondaryDayIdentifiers: Set<String>
    ) -> String {
        guard
            let primaryArchive = decodedArchive(primaryData, as: [String: [ExerciseEntry]].self),
            let secondaryArchive = decodedArchive(secondaryData, as: [String: [ExerciseEntry]].self)
        else {
            return primaryData
        }

        var merged = primaryArchive
        for dayIdentifier in preferSecondaryDayIdentifiers {
            let primaryEntries = primaryArchive[dayIdentifier] ?? []
            let secondaryEntries = secondaryArchive[dayIdentifier] ?? []
            merged[dayIdentifier] = mergedExerciseEntriesForCloud(primary: primaryEntries, secondary: secondaryEntries)
        }

        return encodedArchive(merged, fallback: primaryData)
    }

    func mergedIntegerArchiveData(
        primaryData: String,
        secondaryData: String,
        preferSecondaryDayIdentifiers: Set<String>
    ) -> String {
        guard
            let primaryArchive = decodedArchive(primaryData, as: [String: Int].self),
            let secondaryArchive = decodedArchive(secondaryData, as: [String: Int].self)
        else {
            return primaryData
        }

        var merged = primaryArchive
        for dayIdentifier in preferSecondaryDayIdentifiers {
            if let secondaryValue = secondaryArchive[dayIdentifier] {
                merged[dayIdentifier] = secondaryValue
            }
        }
        return encodedArchive(merged, fallback: primaryData)
    }

    func mergedStringArchiveData(
        primaryData: String,
        secondaryData: String,
        preferSecondaryDayIdentifiers: Set<String>
    ) -> String {
        guard
            let primaryArchive = decodedArchive(primaryData, as: [String: String].self),
            let secondaryArchive = decodedArchive(secondaryData, as: [String: String].self)
        else {
            return primaryData
        }

        var merged = primaryArchive
        for dayIdentifier in preferSecondaryDayIdentifiers {
            if let secondaryValue = secondaryArchive[dayIdentifier] {
                merged[dayIdentifier] = secondaryValue
            }
        }
        return encodedArchive(merged, fallback: primaryData)
    }

    func decodedArchive<T: Decodable>(_ raw: String, as type: T.Type) -> T? {
        guard !raw.isEmpty, let data = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    func encodedArchive<T: Encodable>(_ value: T, fallback: String) -> String {
        guard let data = try? JSONEncoder().encode(value) else { return fallback }
        return String(decoding: data, as: UTF8.self)
    }

    func mergedMealEntries(primary: [MealEntry], secondary: [MealEntry]) -> [MealEntry] {
        var seen = Set<UUID>()
        var merged: [MealEntry] = []

        for entry in (secondary + primary).sorted(by: { $0.createdAt > $1.createdAt }) {
            guard !seen.contains(entry.id) else { continue }
            seen.insert(entry.id)
            merged.append(entry)
        }

        return merged
    }

    func mergedExerciseEntriesForCloud(primary: [ExerciseEntry], secondary: [ExerciseEntry]) -> [ExerciseEntry] {
        var seenIDs = Set<UUID>()
        var seenMergeKeys = Set<String>()
        var merged: [ExerciseEntry] = []

        for entry in (secondary + primary).sorted(by: { $0.createdAt > $1.createdAt }) {
            let mergeKey = workoutMergeKey(for: entry)
            guard !seenIDs.contains(entry.id), !seenMergeKeys.contains(mergeKey) else { continue }
            seenIDs.insert(entry.id)
            seenMergeKeys.insert(mergeKey)
            merged.append(entry)
        }

        return merged
    }

    func bootstrapCloudSync(trigger: CloudSyncTrigger = .foreground) async {
        guard !isCloudSyncInFlight else { return }
        defer {
            hasBootstrappedCloudSync = true
            isCloudSyncInFlight = false
        }

        isCloudSyncInFlight = true
        setCloudSyncStatus(
            level: .checking,
            title: "Checking iCloud sync",
            detail: cloudSyncProgressDetail(for: trigger)
        )

        var subscriptionWarning: String?

        do {
            try await AppCloudSyncService.shared.ensureSubscription()
        } catch {
            subscriptionWarning = "Sync can still work, but CloudKit background pushes may be delayed on this device."
        }

        let localPayload = cloudSyncPayload
        let localUpdatedAt = cloudSyncLocalModifiedAt
        let localDeviceType = currentCloudOriginDeviceType

        do {
            if let cloudEnvelope = try await AppCloudSyncService.shared.fetchEnvelope() {
                let cloudIsNewer = cloudEnvelope.updatedAt > localUpdatedAt
                let primaryPayload = cloudIsNewer ? cloudEnvelope.payload : localPayload
                let secondaryPayload = cloudIsNewer ? localPayload : cloudEnvelope.payload
                let primaryDeviceType = cloudIsNewer ? cloudEnvelope.originDeviceType : localDeviceType
                let secondaryDeviceType = cloudIsNewer ? localDeviceType : cloudEnvelope.originDeviceType
                let mergedPayload = mergedCloudSyncPayload(
                    primary: primaryPayload,
                    secondary: secondaryPayload,
                    primaryDeviceType: primaryDeviceType,
                    secondaryDeviceType: secondaryDeviceType
                )
                let mergedUpdatedAt = max(localUpdatedAt, cloudEnvelope.updatedAt)

                if mergedPayload != localPayload || mergedUpdatedAt > localUpdatedAt {
                    await MainActor.run {
                        applyCloudSyncPayload(mergedPayload, updatedAt: mergedUpdatedAt)
                    }
                }

                if cloudEnvelope.payload != mergedPayload
                    || cloudEnvelope.storageVersion < Self.cloudSyncStorageVersion
                    || cloudEnvelope.originDeviceType != localDeviceType
                    || localUpdatedAt > cloudEnvelope.updatedAt {
                    let timestamp = max(localUpdatedAt, Date().timeIntervalSince1970)
                    cloudSyncLocalModifiedAt = timestamp
                    try await AppCloudSyncService.shared.saveEnvelope(
                        CloudSyncEnvelope(
                            updatedAt: timestamp,
                            payload: mergedPayload,
                            storageVersion: Self.cloudSyncStorageVersion,
                            originDeviceType: localDeviceType
                        )
                    )
                }
                setCloudSyncStatus(
                    level: .synced,
                    title: "iCloud sync is working",
                    detail: cloudSyncSuccessDetail(
                        for: trigger,
                        fallbackDetail: subscriptionWarning
                    ),
                    markSuccessAt: Date(timeIntervalSince1970: mergedUpdatedAt)
                )
            } else {
                let timestamp = max(localUpdatedAt, Date().timeIntervalSince1970)
                cloudSyncLocalModifiedAt = timestamp
                try await AppCloudSyncService.shared.saveEnvelope(
                    CloudSyncEnvelope(
                        updatedAt: timestamp,
                        payload: localPayload,
                        storageVersion: Self.cloudSyncStorageVersion,
                        originDeviceType: localDeviceType
                    )
                )
                setCloudSyncStatus(
                    level: .synced,
                    title: "iCloud sync is working",
                    detail: cloudSyncSuccessDetail(
                        for: trigger,
                        fallbackDetail: subscriptionWarning
                    ),
                    markSuccessAt: Date(timeIntervalSince1970: timestamp)
                )
            }
        } catch {
            updateCloudSyncStatusAfterFailure(error)
        }
    }

    @MainActor
    func applyCloudSyncPayload(_ payload: CloudSyncPayload, updatedAt: Double) {
        isApplyingCloudSync = true

        hasCompletedOnboarding = payload.hasCompletedOnboarding
        storedDeficitCalories = payload.deficitCalories
        useWeekendDeficit = payload.useWeekendDeficit
        storedWeekendDeficitCalories = payload.weekendDeficitCalories
        goalTypeRaw = payload.goalTypeRaw
        storedSurplusCalories = payload.surplusCalories
        if let fixedGoalCalories = payload.fixedGoalCalories {
            storedFixedGoalCalories = fixedGoalCalories
        }
        storedDailyGoalTypeArchiveData = payload.dailyGoalTypeArchiveData
        legacyStoredProteinGoal = payload.proteinGoal
        storedEntriesData = payload.mealEntriesData
        storedTrackedNutrientsData = payload.trackedNutrientsData
        storedNutrientGoalsData = payload.nutrientGoalsData
        lastCentralDayIdentifier = payload.lastCentralDayIdentifier
        selectedAppIconChoiceRaw = payload.selectedAppIconChoiceRaw
        storedDailyEntryArchiveData = payload.dailyEntryArchiveData
        storedDailyCalorieGoalArchiveData = payload.dailyCalorieGoalArchiveData
        storedDailyBurnedCalorieArchiveData = payload.dailyBurnedCalorieArchiveData
        storedDailyExerciseArchiveData = payload.dailyExerciseArchiveData
        storedVenueMenusData = payload.venueMenusData
        storedVenueMenuSignaturesData = payload.venueMenuSignaturesData
        storedQuickAddFoodsData = payload.quickAddFoodsData
        useAIBaseServings = payload.useAIBaseServings
        storedCalibrationStateData = payload.calibrationStateData ?? ""
        storedHealthWeighInsData = payload.healthWeighInsData ?? ""
        storedSyncedHealthProfileData = payload.syncedHealthProfileData ?? ""
        storedSyncedTodayWorkoutsData = payload.syncedTodayWorkoutsData ?? ""
        storedSyncedHealthSourceDeviceTypeRaw = payload.syncedHealthSourceDeviceTypeRaw ?? ""
        cloudSyncLocalModifiedAt = updatedAt

        loadTrackingPreferences()
        loadDailyEntryArchive()
        loadCalibrationState()
        if goalType == .fixed, calibrationState.isEnabled {
            calibrationState.isEnabled = false
            saveCalibrationState()
        }
        loadHealthWeighIns()
        loadQuickAddFoods()
        loadCloudSyncedHealthState()
        loadVenueMenus()
        selectedMenuType = menuService.currentMenuType()
        applyCentralTimeTransitions(forceMenuReload: false)
        syncInputFieldsToTrackedNutrients()
        AppIconManager.apply(selectedAppIconChoice)
        syncCurrentDayGoalArchive()
        persistStateSnapshot()

        isApplyingCloudSync = false
    }

    func loadCloudSyncedHealthState() {
        if
            !storedSyncedHealthProfileData.isEmpty,
            let data = storedSyncedHealthProfileData.data(using: .utf8),
            let decoded = try? JSONDecoder().decode(HealthKitService.SyncedProfile.self, from: data)
        {
            cloudSyncedHealthProfile = decoded
        } else {
            cloudSyncedHealthProfile = nil
        }

        if
            !storedSyncedTodayWorkoutsData.isEmpty,
            let data = storedSyncedTodayWorkoutsData.data(using: .utf8),
            let decoded = try? JSONDecoder().decode([ExerciseEntry].self, from: data)
        {
            cloudSyncedTodayWorkouts = decoded
        } else {
            cloudSyncedTodayWorkouts = []
        }
    }

    var selectedAppIconChoice: AppIconChoice {
        AppIconChoice(rawValue: selectedAppIconChoiceRaw) ?? .standard
    }

    var cloudSyncPayload: CloudSyncPayload {
        let liveProfileData: String? = {
            guard currentCloudOriginDeviceType == .iphone, let profile = healthKitService.profile else {
                return storedSyncedHealthProfileData.isEmpty ? nil : storedSyncedHealthProfileData
            }
            guard let data = try? JSONEncoder().encode(profile) else { return nil }
            return String(decoding: data, as: UTF8.self)
        }()

        let liveWorkoutData: String? = {
            guard currentCloudOriginDeviceType == .iphone else {
                return storedSyncedTodayWorkoutsData.isEmpty ? nil : storedSyncedTodayWorkoutsData
            }
            guard let data = try? JSONEncoder().encode(healthKitService.todayWorkouts) else { return nil }
            return String(decoding: data, as: UTF8.self)
        }()

        return CloudSyncPayload(
            hasCompletedOnboarding: hasCompletedOnboarding,
            deficitCalories: storedDeficitCalories,
            useWeekendDeficit: useWeekendDeficit,
            weekendDeficitCalories: storedWeekendDeficitCalories,
            goalTypeRaw: goalTypeRaw,
            surplusCalories: storedSurplusCalories,
            fixedGoalCalories: storedFixedGoalCalories,
            dailyGoalTypeArchiveData: storedDailyGoalTypeArchiveData,
            proteinGoal: legacyStoredProteinGoal,
            mealEntriesData: storedEntriesData,
            trackedNutrientsData: storedTrackedNutrientsData,
            nutrientGoalsData: storedNutrientGoalsData,
            lastCentralDayIdentifier: lastCentralDayIdentifier,
            selectedAppIconChoiceRaw: selectedAppIconChoiceRaw,
            dailyEntryArchiveData: storedDailyEntryArchiveData,
            dailyCalorieGoalArchiveData: storedDailyCalorieGoalArchiveData,
            dailyBurnedCalorieArchiveData: storedDailyBurnedCalorieArchiveData,
            dailyExerciseArchiveData: storedDailyExerciseArchiveData,
            venueMenusData: storedVenueMenusData,
            venueMenuSignaturesData: storedVenueMenuSignaturesData,
            quickAddFoodsData: storedQuickAddFoodsData,
            useAIBaseServings: useAIBaseServings,
            calibrationStateData: storedCalibrationStateData,
            healthWeighInsData: storedHealthWeighInsData,
            syncedHealthProfileData: liveProfileData,
            syncedTodayWorkoutsData: liveWorkoutData,
            syncedHealthSourceDeviceTypeRaw: currentCloudOriginDeviceType == .iphone
                ? CloudSyncOriginDeviceType.iphone.rawValue
                : (storedSyncedHealthSourceDeviceTypeRaw.isEmpty ? nil : storedSyncedHealthSourceDeviceTypeRaw)
        )
    }

    var currentCloudOriginDeviceType: CloudSyncOriginDeviceType {
        switch UIDevice.current.userInterfaceIdiom {
        case .phone:
            return .iphone
        case .pad:
            return .ipad
        case .mac:
            return .mac
        default:
            return .unknown
        }
    }

    var cloudSyncStatusTint: Color {
        switch cloudSyncStatusLevel {
        case .checking, .uploading:
            return AppTheme.info
        case .synced:
            return AppTheme.success
        case .warning:
            return AppTheme.warning
        case .error:
            return AppTheme.danger
        }
    }

    var cloudSyncLastSuccessText: String {
        guard let cloudSyncLastSuccessAt else { return "No successful iCloud sync yet." }
        return "Last successful sync: \(cloudSyncLastSuccessAt.formatted(date: .abbreviated, time: .shortened))"
    }


}
