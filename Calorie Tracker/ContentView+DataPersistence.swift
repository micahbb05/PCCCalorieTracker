// Calorie Tracker 2026

import SwiftUI
import WidgetKit

extension ContentView {

    func loadCalibrationState() {
        guard
            !storedCalibrationStateData.isEmpty,
            let data = storedCalibrationStateData.data(using: .utf8),
            let decoded = try? JSONDecoder().decode(CalibrationState.self, from: data)
        else {
            calibrationState = .default
            return
        }
        calibrationState = decoded
    }

    func saveCalibrationState() {
        guard let data = try? JSONEncoder().encode(calibrationState) else { return }
        storedCalibrationStateData = String(decoding: data, as: UTF8.self)
        persistStateSnapshot()
    }

    func loadHealthWeighIns() {
        guard
            !storedHealthWeighInsData.isEmpty,
            let data = storedHealthWeighInsData.data(using: .utf8),
            let decoded = try? JSONDecoder().decode([HealthWeighInDay].self, from: data)
        else {
            healthWeighIns = []
            return
        }
        healthWeighIns = decoded
    }

    func saveHealthWeighIns() {
        guard let data = try? JSONEncoder().encode(healthWeighIns) else { return }
        storedHealthWeighInsData = String(decoding: data, as: UTF8.self)
        persistStateSnapshot()
    }

    func refreshWeightChangeComparisonIfNeeded() async {
        guard !isRefreshingWeightChangeComparison else { return }
        guard healthKitService.authorizationState == .connected else { return }

        isRefreshingWeightChangeComparison = true
        defer { isRefreshingWeightChangeComparison = false }

        let reducedWeights = await healthKitService.fetchReducedBodyMassHistory(days: NetHistoryRange.twoYears.dayCount)
        guard !reducedWeights.isEmpty else { return }

        healthWeighIns = reducedWeights
        saveHealthWeighIns()
    }

    func loadDailyEntryArchive() {
        if !storedDailyEntryArchiveData.isEmpty,
           let data = storedDailyEntryArchiveData.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String: [MealEntry]].self, from: data) {
            dailyEntryArchive = decoded.mapValues { normalizedEntries($0) }
        } else {
            dailyEntryArchive = migrateLegacyEntriesIfNeeded()
        }

        displayedHistoryMonth = monthStart(for: Date())
        loadDailyExerciseArchive()
        entries = entries(forDayIdentifier: todayDayIdentifier)
        exercises = exercises(forDayIdentifier: todayDayIdentifier)
        loadDailyCalorieGoalArchive()
        loadDailyBurnedCalorieArchive()
        loadDailyGoalTypeArchive()
        syncCurrentDayGoalArchive()
        syncHistorySelection(preferToday: true)
        saveDailyEntryArchive()
    }

    func saveEntries() {
        guard let data = try? JSONEncoder().encode(entries) else {
            return
        }

        storedEntriesData = String(decoding: data, as: UTF8.self)
        persistStateSnapshot()
    }

    func saveDailyEntryArchive() {
        guard let data = try? JSONEncoder().encode(dailyEntryArchive) else {
            return
        }
        storedDailyEntryArchiveData = String(decoding: data, as: UTF8.self)
        persistStateSnapshot()
    }

    func loadDailyCalorieGoalArchive() {
        guard
            !storedDailyCalorieGoalArchiveData.isEmpty,
            let data = storedDailyCalorieGoalArchiveData.data(using: .utf8),
            let decoded = try? JSONDecoder().decode([String: Int].self, from: data)
        else {
            dailyCalorieGoalArchive = [:]
            return
        }

        dailyCalorieGoalArchive = decoded
    }

    func saveDailyCalorieGoalArchive() {
        guard let data = try? JSONEncoder().encode(dailyCalorieGoalArchive) else {
            return
        }
        storedDailyCalorieGoalArchiveData = String(decoding: data, as: UTF8.self)
        persistStateSnapshot()
    }

    func loadDailyBurnedCalorieArchive() {
        guard
            !storedDailyBurnedCalorieArchiveData.isEmpty,
            let data = storedDailyBurnedCalorieArchiveData.data(using: .utf8),
            let decoded = try? JSONDecoder().decode([String: Int].self, from: data)
        else {
            dailyBurnedCalorieArchive = [:]
            return
        }

        dailyBurnedCalorieArchive = decoded
    }

    func saveDailyBurnedCalorieArchive() {
        guard let data = try? JSONEncoder().encode(dailyBurnedCalorieArchive) else {
            return
        }
        storedDailyBurnedCalorieArchiveData = String(decoding: data, as: UTF8.self)
        persistStateSnapshot()
    }

    func loadDailyExerciseArchive() {
        guard
            !storedDailyExerciseArchiveData.isEmpty,
            let data = storedDailyExerciseArchiveData.data(using: .utf8),
            let decoded = try? JSONDecoder().decode([String: [ExerciseEntry]].self, from: data)
        else {
            dailyExerciseArchive = [:]
            return
        }
        dailyExerciseArchive = decoded
    }

    func saveDailyExerciseArchive() {
        guard let data = try? JSONEncoder().encode(dailyExerciseArchive) else {
            return
        }
        storedDailyExerciseArchiveData = String(decoding: data, as: UTF8.self)
        persistStateSnapshot()
    }

    func loadDailyGoalTypeArchive() {
        guard
            !storedDailyGoalTypeArchiveData.isEmpty,
            let data = storedDailyGoalTypeArchiveData.data(using: .utf8),
            let decoded = try? JSONDecoder().decode([String: String].self, from: data)
        else {
            dailyGoalTypeArchive = [:]
            return
        }
        dailyGoalTypeArchive = decoded
    }

    func saveDailyGoalTypeArchive() {
        guard let data = try? JSONEncoder().encode(dailyGoalTypeArchive) else {
            return
        }
        storedDailyGoalTypeArchiveData = String(decoding: data, as: UTF8.self)
        persistStateSnapshot()
    }

    func syncCurrentEntriesToArchive() {
        dailyEntryArchive[todayDayIdentifier] = normalizedEntries(entries)
        dailyExerciseArchive[todayDayIdentifier] = exercises
        saveEntries()
        saveDailyEntryArchive()
        saveDailyExerciseArchive()
        syncWidgetSnapshot()
        syncHistorySelection()
    }

    func migrateLegacyEntriesIfNeeded() -> [String: [MealEntry]] {
        guard
            !storedEntriesData.isEmpty,
            let data = storedEntriesData.data(using: .utf8),
            let decoded = try? JSONDecoder().decode([MealEntry].self, from: data)
        else {
            return [:]
        }

        let normalized = normalizedEntries(decoded)
        guard !normalized.isEmpty else {
            return [:]
        }

        return [todayDayIdentifier: normalized]
    }

    func normalizedEntries(_ entries: [MealEntry]) -> [MealEntry] {
        entries.map {
            MealEntry(
                id: $0.id,
                name: MealEntry.normalizedName($0.name),
                calories: $0.calories,
                nutrientValues: $0.nutrientValues,
                loggedCount: $0.loggedCount,
                createdAt: $0.createdAt,
                mealGroup: $0.mealGroup
            )
        }
    }

    func inferredLoggedItemCount(from amount: Double) -> Int {
        let rounded = Int(amount.rounded())
        guard rounded > 1 else { return 1 }
        guard abs(amount - Double(rounded)) <= 0.05 else { return 1 }
        return rounded
    }

    func entries(forDayIdentifier identifier: String) -> [MealEntry] {
        dailyEntryArchive[identifier] ?? []
    }

    func exercises(forDayIdentifier identifier: String) -> [ExerciseEntry] {
        dailyExerciseArchive[identifier] ?? []
    }

    func currentCentralDate() -> Date {
        Date()
    }

    func centralDayIdentifier(for date: Date) -> String {
        let startOfDay = centralCalendar.startOfDay(for: date)
        let components = centralCalendar.dateComponents([.year, .month, .day], from: startOfDay)
        let year = components.year ?? 0
        let month = components.month ?? 1
        let day = components.day ?? 1
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    func date(fromCentralDayIdentifier identifier: String) -> Date? {
        let parts = identifier.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        let components = DateComponents(timeZone: centralCalendar.timeZone, year: parts[0], month: parts[1], day: parts[2])
        return centralCalendar.date(from: components)
    }

    func monthStart(for date: Date) -> Date {
        let start = centralCalendar.startOfDay(for: date)
        let components = centralCalendar.dateComponents([.year, .month], from: start)
        return centralCalendar.date(from: components) ?? start
    }

    func syncHistorySelection(preferToday: Bool = false) {
        let today = todayDayIdentifier
        if preferToday {
            selectedHistoryDayIdentifier = today
        } else if selectedHistoryDayIdentifier.isEmpty {
            selectedHistoryDayIdentifier = defaultHistorySelectionIdentifier()
        } else if dailyEntryArchive[selectedHistoryDayIdentifier] == nil && selectedHistoryDayIdentifier != today {
            selectedHistoryDayIdentifier = defaultHistorySelectionIdentifier()
        }

        if let selectedDate = date(fromCentralDayIdentifier: selectedHistoryDayIdentifier) {
            displayedHistoryMonth = monthStart(for: selectedDate)
        }
    }

    func defaultHistorySelectionIdentifier() -> String {
        let today = todayDayIdentifier
        if let latestPast = archivedDayIdentifiers.last(where: { $0 < today }) {
            return latestPast
        }
        return today
    }

    func dailyCalories(for identifier: String) -> Int {
        entries(forDayIdentifier: identifier).reduce(0) { $0 + $1.calories }
    }

    func calculatedBMR(for profile: BMRProfile) -> Int? {
        guard profile.isComplete else { return nil }

        let weightKg = Double(profile.weightPounds) * 0.45359237
        let totalInches = (profile.heightFeet * 12) + profile.heightInches
        let heightCm = Double(totalInches) * 2.54
        let sexConstant = profile.sex == .male ? 5.0 : -161.0
        let raw = (10.0 * weightKg) + (6.25 * heightCm) - (5.0 * Double(profile.age)) + sexConstant
        return max(Int(raw.rounded()), 800)
    }

    func nutrientTotals(for identifier: String) -> [String: Int] {
        entries(forDayIdentifier: identifier).reduce(into: [:]) { partialResult, entry in
            for (key, value) in entry.nutrientValues {
                partialResult[key, default: 0] += value
            }
        }
    }

    func calorieGoalForDay(_ identifier: String) -> Int {
        if identifier == todayDayIdentifier {
            return max(calorieGoal, 1)
        }
        if let archived = dailyCalorieGoalArchive[identifier] {
            return max(archived, 1)
        }

        let burned = burnedCaloriesForDay(identifier)
        let amount = deficitForDay(identifier)
        let dayGoalType = goalTypeForDay(identifier)
        if dayGoalType == .fixed {
            return max(fixedGoalCalories, 1)
        }
        if dayGoalType == .surplus {
            return max(burned + amount, 1)
        } else {
            return max(burned - amount, 1)
        }
    }

    func burnedCaloriesForDay(_ identifier: String) -> Int {
        if let archived = dailyBurnedCalorieArchive[identifier] {
            return max(archived, 1)
        }
        if identifier == todayDayIdentifier {
            return max(burnedCaloriesToday, 1)
        }
        if let archivedGoal = dailyCalorieGoalArchive[identifier] {
            // Older archived days only stored the intake goal. Fall back to that value as burned for compatibility.
            return max(archivedGoal, 1)
        }
        return max(manualBMRCalories, 1)
    }

    func syncCurrentDayGoalArchive() {
        guard hasResolvedInitialLiveCalorieInputsThisLaunch else { return }

        // Only write the archive when real activity has been detected: steps, a HealthKit
        // workout, or a manually-logged exercise. This single gate replaces all the
        // high-water-mark guards — zero-step HealthKit results never reach the archive,
        // so there is nothing to protect against afterward.
        let hasActivity = stepActivityService.todayStepCount > 0
            || !effectiveTodayHealthWorkouts.isEmpty
            || !exercises.isEmpty
        guard hasActivity else { return }

        dailyExerciseArchive[todayDayIdentifier] = exercises
        let freshBurned = burnedCaloriesToday
        let freshGoal = calorieGoal
        dailyCalorieGoalArchive[todayDayIdentifier] = freshGoal
        dailyBurnedCalorieArchive[todayDayIdentifier] = freshBurned
        dailyGoalTypeArchive[todayDayIdentifier] = goalType.rawValue
        activityDetectedDayIdentifier = todayDayIdentifier

        saveDailyExerciseArchive()
        saveDailyCalorieGoalArchive()
        saveDailyBurnedCalorieArchive()
        saveDailyGoalTypeArchive()

        // Cache for the background widget service so it has a reliable burned/goal
        // fallback when its own HealthKit queries return no activity.
        let calorieCacheComponents = centralCalendar.dateComponents([.year, .month, .day], from: centralCalendar.startOfDay(for: Date()))
        let calorieCacheDayID = String(format: "%04d-%02d-%02d", calorieCacheComponents.year ?? 0, calorieCacheComponents.month ?? 1, calorieCacheComponents.day ?? 1)
        let calorieModelCache = CachedCalorieModel(dayIdentifier: calorieCacheDayID, goal: freshGoal, burned: freshBurned)
        if let cacheData = try? JSONEncoder().encode(calorieModelCache) {
            UserDefaults.standard.set(String(decoding: cacheData, as: UTF8.self), forKey: "cachedTodayCalorieModel")
        }
        syncWidgetSnapshot()
    }

    func syncWidgetSnapshot(force: Bool = false) {
        // Don't push a BMR-only snapshot to the widget before any activity has been
        // detected for today. If activity has been detected the archive holds real
        // values and currentDailyCalorieModel already returns them, so the snapshot
        // will be correct even before HealthKit finishes its fresh load.
        // `force: true` bypasses this guard for new-day resets, where consumed = 0
        // is correct and we need to immediately clear yesterday's stale snapshot.
        if !force, !hasResolvedInitialLiveCalorieInputsThisLaunch, !activityDetectedToday {
            return
        }
        let safeGoal = max(calorieGoal, 1)
        let progress = min(max(Double(totalCalories) / Double(safeGoal), 0), 1)
        let nutrientSummaries = trackedNutrientKeys
            .filter { !NutrientCatalog.nonTrackableKeys.contains($0.lowercased()) }
            .prefix(3)
            .map { key -> WidgetCalorieSnapshot.TrackedNutrient in
                let definition = NutrientCatalog.definition(for: key)
                let total = max(totalNutrient(for: key), 0)
                let goal = max(goalForNutrient(key), 1)
                let nutrientProgress = min(max(Double(total) / Double(goal), 0), 9.99)
                return WidgetCalorieSnapshot.TrackedNutrient(
                    key: key,
                    name: definition.name,
                    unit: definition.unit,
                    total: total,
                    goal: goal,
                    progress: nutrientProgress
                )
            }
        let snapshot = WidgetCalorieSnapshot(
            updatedAt: Date(),
            consumedCalories: max(totalCalories, 0),
            goalCalories: safeGoal,
            burnedCalories: max(burnedCaloriesToday, 0),
            caloriesLeft: max(caloriesLeft, 0),
            progress: progress,
            goalTypeRaw: goalType.rawValue,
            selectedAppIconChoiceRaw: selectedAppIconChoiceRaw,
            trackedNutrients: Array(nutrientSummaries)
        )
        WidgetSnapshotStore.save(snapshot)
    }

    func menu(for venue: DiningVenue, menuType: NutrisliceMenuService.MenuType) -> NutrisliceMenu {
        venueMenus[venue]?[menuType] ?? .empty
    }

    func setMenu(_ menu: NutrisliceMenu, for venue: DiningVenue, menuType: NutrisliceMenuService.MenuType) {
        var venueCache = venueMenus[venue] ?? [:]
        venueCache[menuType] = menu
        venueMenus[venue] = venueCache
    }

    func menuSignature(for venue: DiningVenue, menuType: NutrisliceMenuService.MenuType) -> String? {
        lastLoadedMenuSignatureByVenue[venue]?[menuType]
    }

    func setMenuSignature(_ signature: String?, for venue: DiningVenue, menuType: NutrisliceMenuService.MenuType) {
        var venueCache = lastLoadedMenuSignatureByVenue[venue] ?? [:]
        venueCache[menuType] = signature
        lastLoadedMenuSignatureByVenue[venue] = venueCache
    }

    func setMenuError(_ error: String?, for venue: DiningVenue, menuType: NutrisliceMenuService.MenuType) {
        var venueCache = menuLoadErrorsByVenue[venue] ?? [:]
        if let error {
            venueCache[menuType] = error
        } else {
            venueCache.removeValue(forKey: menuType)
        }
        menuLoadErrorsByVenue[venue] = venueCache
    }

    func menuQuantities(for venue: DiningVenue, menuType: NutrisliceMenuService.MenuType) -> [String: Int] {
        selectedMenuItemQuantitiesByVenue[venue]?[menuType] ?? [:]
    }

    func setMenuQuantities(_ quantities: [String: Int], for venue: DiningVenue, menuType: NutrisliceMenuService.MenuType) {
        var venueCache = selectedMenuItemQuantitiesByVenue[venue] ?? [:]
        venueCache[menuType] = quantities
        selectedMenuItemQuantitiesByVenue[venue] = venueCache
    }

    func menuMultipliers(for venue: DiningVenue, menuType: NutrisliceMenuService.MenuType) -> [String: Double] {
        selectedMenuItemMultipliersByVenue[venue]?[menuType] ?? [:]
    }

    func setMenuMultipliers(_ multipliers: [String: Double], for venue: DiningVenue, menuType: NutrisliceMenuService.MenuType) {
        var venueCache = selectedMenuItemMultipliersByVenue[venue] ?? [:]
        venueCache[menuType] = multipliers
        selectedMenuItemMultipliersByVenue[venue] = venueCache
    }

    func loadVenueMenus() {
        if !storedVenueMenusData.isEmpty,
           let data = storedVenueMenusData.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(VenueMenuCache.self, from: data) {
            venueMenus = decoded
        } else {
            venueMenus = [:]
        }

        if !storedVenueMenuSignaturesData.isEmpty,
           let data = storedVenueMenuSignaturesData.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(VenueMenuSignatureCache.self, from: data) {
            lastLoadedMenuSignatureByVenue = decoded
        } else {
            lastLoadedMenuSignatureByVenue = [:]
        }
    }

    func saveVenueMenus() {
        if let data = try? JSONEncoder().encode(venueMenus) {
            storedVenueMenusData = String(decoding: data, as: UTF8.self)
        }
        if let data = try? JSONEncoder().encode(lastLoadedMenuSignatureByVenue) {
            storedVenueMenuSignaturesData = String(decoding: data, as: UTF8.self)
        }
        persistStateSnapshot()
    }

    var persistentStateSnapshot: PersistentAppStateSnapshot {
        PersistentAppStateSnapshot(
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
            calibrationStateData: storedCalibrationStateData,
            healthWeighInsData: storedHealthWeighInsData,
            cloudSyncLocalModifiedAt: cloudSyncLocalModifiedAt,
            useAIBaseServings: useAIBaseServings
        )
    }

    func applyPersistentStateSnapshot(_ snapshot: PersistentAppStateSnapshot) {
        hasCompletedOnboarding = snapshot.hasCompletedOnboarding
        storedDeficitCalories = snapshot.deficitCalories
        useWeekendDeficit = snapshot.useWeekendDeficit
        storedWeekendDeficitCalories = snapshot.weekendDeficitCalories
        goalTypeRaw = snapshot.goalTypeRaw
        storedSurplusCalories = snapshot.surplusCalories
        storedFixedGoalCalories = snapshot.fixedGoalCalories
        storedDailyGoalTypeArchiveData = snapshot.dailyGoalTypeArchiveData
        legacyStoredProteinGoal = snapshot.proteinGoal
        storedEntriesData = snapshot.mealEntriesData
        storedTrackedNutrientsData = snapshot.trackedNutrientsData
        storedNutrientGoalsData = snapshot.nutrientGoalsData
        lastCentralDayIdentifier = snapshot.lastCentralDayIdentifier
        selectedAppIconChoiceRaw = snapshot.selectedAppIconChoiceRaw
        storedDailyEntryArchiveData = snapshot.dailyEntryArchiveData
        storedDailyCalorieGoalArchiveData = snapshot.dailyCalorieGoalArchiveData
        storedDailyBurnedCalorieArchiveData = snapshot.dailyBurnedCalorieArchiveData
        storedDailyExerciseArchiveData = snapshot.dailyExerciseArchiveData
        storedVenueMenusData = snapshot.venueMenusData
        storedVenueMenuSignaturesData = snapshot.venueMenuSignaturesData
        storedQuickAddFoodsData = snapshot.quickAddFoodsData
        storedCalibrationStateData = snapshot.calibrationStateData
        storedHealthWeighInsData = snapshot.healthWeighInsData
        cloudSyncLocalModifiedAt = snapshot.cloudSyncLocalModifiedAt
        useAIBaseServings = snapshot.useAIBaseServings
    }

    func bootstrapPersistentStateStore() {
        let snapshot = PersistentAppStateStore.shared.bootstrapSnapshot(
            defaults: .standard,
            fallback: persistentStateSnapshot
        )
        applyPersistentStateSnapshot(snapshot)
    }

    func persistStateSnapshot() {
        PersistentAppStateStore.shared.saveSnapshot(persistentStateSnapshot)
    }

    var currentMenu: NutrisliceMenu {
        menu(for: selectedMenuVenue, menuType: selectedMenuType)
    }

    var currentMenuError: String? {
        menuLoadErrorsByVenue[selectedMenuVenue]?[selectedMenuType]
    }

    var availableMenuTypesForSelectedVenue: [NutrisliceMenuService.MenuType] {
        menuService.allMenuTypes.filter { selectedMenuVenue.supportedMenuTypes.contains($0) }
    }

    var excludedNutrientKeys: Set<String> {
        let threshold = 0.95
        let dynamic = Set<String>(currentMenu.nutrientNullRateByKey.compactMap { key, rate in
            let normalized = key.lowercased()
            guard normalized != "g_protein", normalized != "g_fiber", rate >= threshold else { return nil }
            return normalized
        })
        return dynamic.union(NutrientCatalog.defaultExcludedBecauseConsistentlyNull)
    }

    var availableNutrientKeys: [String] {
        var keys = Set<String>(NutrientCatalog.knownKeys)

        for line in currentMenu.lines {
            for item in line.items {
                for key in item.nutrientValues.keys where !NutrientCatalog.nonTrackableKeys.contains(key.lowercased()) {
                    keys.insert(key.lowercased())
                }
            }
        }

        for entry in entries {
            for key in entry.nutrientValues.keys where !NutrientCatalog.nonTrackableKeys.contains(key.lowercased()) {
                keys.insert(key.lowercased())
            }
        }

        for archivedEntries in dailyEntryArchive.values {
            for entry in archivedEntries {
                for key in entry.nutrientValues.keys where !NutrientCatalog.nonTrackableKeys.contains(key.lowercased()) {
                    keys.insert(key.lowercased())
                }
            }
        }

        for key in trackedNutrientKeys where !NutrientCatalog.nonTrackableKeys.contains(key.lowercased()) {
            keys.insert(key.lowercased())
        }

        keys.insert("g_protein")
        keys.subtract(excludedNutrientKeys)
        return keys.sorted { lhs, rhs in
            let lhsRank = NutrientCatalog.preferredOrder.firstIndex(of: lhs) ?? Int.max
            let rhsRank = NutrientCatalog.preferredOrder.firstIndex(of: rhs) ?? Int.max
            if lhsRank != rhsRank {
                return lhsRank < rhsRank
            }
            let lhsName = NutrientCatalog.definition(for: lhs).name
            let rhsName = NutrientCatalog.definition(for: rhs).name
            if lhsName != rhsName {
                return lhsName < rhsName
            }
            return lhs < rhs
        }
    }

    var availableNutrients: [NutrientDefinition] {
        availableNutrientKeys.map { NutrientCatalog.definition(for: $0) }
    }

    var activeNutrients: [NutrientDefinition] {
        return trackedNutrientKeys
            .map { $0.lowercased() }
            .filter { !NutrientCatalog.nonTrackableKeys.contains($0) }
            .filter { !excludedNutrientKeys.contains($0) }
            .map { NutrientCatalog.definition(for: $0) }
    }

    var manualEntryGridRows: [[ManualEntryGridField]] {
        guard !activeNutrients.isEmpty else {
            return [[.calories]]
        }

        if activeNutrients.count.isMultiple(of: 2) {
            var rows: [[ManualEntryGridField]] = [[.calories]]
            for startIndex in stride(from: 0, to: activeNutrients.count, by: 2) {
                rows.append([
                    .nutrient(activeNutrients[startIndex]),
                    .nutrient(activeNutrients[startIndex + 1])
                ])
            }
            return rows
        }

        var rows: [[ManualEntryGridField]] = [[.calories, .nutrient(activeNutrients[0])]]
        for startIndex in stride(from: 1, to: activeNutrients.count, by: 2) {
            if startIndex + 1 < activeNutrients.count {
                rows.append([
                    .nutrient(activeNutrients[startIndex]),
                    .nutrient(activeNutrients[startIndex + 1])
                ])
            } else {
                rows.append([.nutrient(activeNutrients[startIndex])])
            }
        }
        return rows
    }

    var primaryNutrient: NutrientDefinition {
        activeNutrients.first ?? NutrientCatalog.definition(for: "g_protein")
    }

    var isManualEntryEditing: Bool {
        focusedField != nil && isKeyboardVisible
    }

    var manualEntryBottomPadding: CGFloat {
        guard isManualEntryEditing else { return 140 }
        return max(124, keyboardHeight + 24)
    }

    var aiModeBottomPadding: CGFloat {
        guard isKeyboardVisible else { return 120 }
        return max(120, keyboardHeight + 32)
    }


}
