// Calorie Tracker 2026

import SwiftUI
import UIKit

extension ContentView {

    func presentMenu(for venue: DiningVenue) {
        let shouldLoadMenu = prepareMenuDestination(for: venue)
        isMenuSheetPresented = true

        if shouldLoadMenu {
            Task {
                await loadMenuFromFirebase(for: selectedMenuVenue)
            }
        }
    }

    @discardableResult
    func prepareMenuDestination(for venue: DiningVenue) -> Bool {
        let initialMenuType = menuService.currentMenuType()
        let resolvedVenue = preferredMenuVenue(startingFrom: venue, menuType: initialMenuType)
        let resolvedMenuType = preferredMenuType(startingFrom: initialMenuType, for: resolvedVenue)
        selectedMenuVenue = resolvedVenue
        selectedMenuType = resolvedMenuType
        let signature = menuService.currentMenuSignature(for: resolvedVenue, menuType: resolvedMenuType)
        let shouldLoadMenu = menu(for: resolvedVenue, menuType: resolvedMenuType).lines.isEmpty
            || menuSignature(for: resolvedVenue, menuType: resolvedMenuType) != signature
            || menuLoadErrorsByVenue[resolvedVenue]?[resolvedMenuType] != nil

        if menuSignature(for: resolvedVenue, menuType: resolvedMenuType) != signature {
            setMenu(.empty, for: resolvedVenue, menuType: resolvedMenuType)
            setMenuError(nil, for: resolvedVenue, menuType: resolvedMenuType)
        }

        isMenuLoading = shouldLoadMenu
        return shouldLoadMenu
    }

    func switchMenuToVenue(_ venue: DiningVenue) {
        guard venue != selectedMenuVenue else { return }
        selectedMenuVenue = venue
        let currentMenuType = menuService.currentMenuType()
        let resolvedMenuType = preferredMenuType(startingFrom: currentMenuType, for: venue)
        selectedMenuType = resolvedMenuType
        let signature = menuService.currentMenuSignature(for: venue, menuType: resolvedMenuType)
        let shouldLoadMenu = menu(for: venue, menuType: resolvedMenuType).lines.isEmpty
            || menuSignature(for: venue, menuType: resolvedMenuType) != signature
            || menuLoadErrorsByVenue[venue]?[resolvedMenuType] != nil

        if menuSignature(for: venue, menuType: resolvedMenuType) != signature {
            setMenu(.empty, for: venue, menuType: resolvedMenuType)
            setMenuError(nil, for: venue, menuType: resolvedMenuType)
        }

        isMenuLoading = shouldLoadMenu

        if shouldLoadMenu {
            Task {
                await loadMenuFromFirebase(for: venue, menuType: resolvedMenuType)
            }
        }
    }

    func switchMenuToMealType(_ menuType: NutrisliceMenuService.MenuType) {
        let resolvedVenue = preferredMenuVenue(startingFrom: selectedMenuVenue, menuType: menuType)
        let resolvedMenuType = preferredMenuType(startingFrom: menuType, for: resolvedVenue)
        selectedMenuVenue = resolvedVenue
        selectedMenuType = resolvedMenuType

        let signature = menuService.currentMenuSignature(for: resolvedVenue, menuType: resolvedMenuType)
        let shouldLoadMenu = menu(for: resolvedVenue, menuType: resolvedMenuType).lines.isEmpty
            || menuSignature(for: resolvedVenue, menuType: resolvedMenuType) != signature
            || menuLoadErrorsByVenue[resolvedVenue]?[resolvedMenuType] != nil

        if menuSignature(for: resolvedVenue, menuType: resolvedMenuType) != signature {
            setMenu(.empty, for: resolvedVenue, menuType: resolvedMenuType)
            setMenuError(nil, for: resolvedVenue, menuType: resolvedMenuType)
        }

        isMenuLoading = shouldLoadMenu

        if shouldLoadMenu {
            Task {
                await loadMenuFromFirebase(for: resolvedVenue, menuType: resolvedMenuType)
            }
        }
    }

    @MainActor
    func loadMenuFromFirebase(
        for venue: DiningVenue? = nil,
        menuType: NutrisliceMenuService.MenuType? = nil,
        showLoadingIndicator: Bool = true
    ) async {
        let venue = venue ?? selectedMenuVenue
        let menuType = menuType ?? selectedMenuType
        let shouldDriveLoadingIndicator = showLoadingIndicator && venue == selectedMenuVenue && menuType == selectedMenuType
        if shouldDriveLoadingIndicator {
            isMenuLoading = true
        }
        setMenuError(nil, for: venue, menuType: menuType)
        do {
            let menu = try await menuService.fetchTodayMenu(for: venue, menuType: menuType)
            setMenu(menu, for: venue, menuType: menuType)
            setMenuSignature(menuService.currentMenuSignature(for: venue, menuType: menuType), for: venue, menuType: menuType)
            setMenuQuantities([:], for: venue, menuType: menuType)
            setMenuMultipliers([:], for: venue, menuType: menuType)
            saveVenueMenus()
        } catch {
            if let nutrisliceError = error as? NutrisliceMenuError {
                switch nutrisliceError {
                case .noMenuAvailable, .unavailableAtThisTime:
                    setMenu(.empty, for: venue, menuType: menuType)
                    setMenuError(nil, for: venue, menuType: menuType)
                default:
                    setMenuError(nutrisliceError.errorDescription ?? nutrisliceError.localizedDescription, for: venue, menuType: menuType)
                    setMenu(.empty, for: venue, menuType: menuType)
                }
            } else {
                setMenuError((error as? LocalizedError)?.errorDescription ?? error.localizedDescription, for: venue, menuType: menuType)
                setMenu(.empty, for: venue, menuType: menuType)
            }
            setMenu(.empty, for: venue, menuType: menuType)
            setMenuQuantities([:], for: venue, menuType: menuType)
            setMenuMultipliers([:], for: venue, menuType: menuType)
        }
        saveVenueMenus()
        if shouldDriveLoadingIndicator {
            isMenuLoading = false
        }
    }

    @MainActor
    func preloadMenuForNutrientDiscovery() async {
        let combos = DiningVenue.allCases.flatMap { venue in
            menuService.allMenuTypes
                .filter { venue.supportedMenuTypes.contains($0) }
                .map { (venue, $0) }
        }

        for (venue, menuType) in combos {
            let currentSignature = menuService.currentMenuSignature(for: venue, menuType: menuType)
            let existingMenu = menu(for: venue, menuType: menuType)
            let lastSignature = menuSignature(for: venue, menuType: menuType)
            guard existingMenu.lines.isEmpty || lastSignature != currentSignature else {
                continue
            }

            await loadMenuFromFirebase(for: venue, menuType: menuType, showLoadingIndicator: false)
        }
    }

    func applyCentralTimeTransitions(forceMenuReload: Bool) {
        let currentCentralDay = menuService.currentCentralDayIdentifier()

        if lastCentralDayIdentifier.isEmpty {
            lastCentralDayIdentifier = currentCentralDay
            if dailyEntryArchive[currentCentralDay] == nil {
                dailyEntryArchive[currentCentralDay] = normalizedEntries(entries)
            }
            dailyExerciseArchive[currentCentralDay] = exercises
            dailyCalorieGoalArchive[currentCentralDay] = CalibrationEngine.floorAgainstArchive(
                calorieGoal,
                archivedValue: dailyCalorieGoalArchive[currentCentralDay]
            )
            dailyBurnedCalorieArchive[currentCentralDay] = CalibrationEngine.floorAgainstArchive(
                burnedCaloriesToday,
                archivedValue: dailyBurnedCalorieArchive[currentCentralDay]
            )
            dailyGoalTypeArchive[currentCentralDay] = goalType.rawValue
            saveDailyEntryArchive()
            saveDailyExerciseArchive()
            saveDailyCalorieGoalArchive()
            saveDailyBurnedCalorieArchive()
            saveDailyGoalTypeArchive()
        }

        if lastCentralDayIdentifier != currentCentralDay {
            // When the app crosses midnight while running, `entries` and `exercises` still contain
            // the previous day's data and should be archived under `lastCentralDayIdentifier`.
            // On a cold start the next day, however, we load today's (empty) entries before
            // calling this method. In that case we *must not* overwrite a non-empty archive
            // for the previous day with an empty array.
            let existingLastEntries = dailyEntryArchive[lastCentralDayIdentifier] ?? []
            if !(entries.isEmpty && !existingLastEntries.isEmpty) {
                dailyEntryArchive[lastCentralDayIdentifier] = normalizedEntries(entries)
            }

            let existingLastExercises = dailyExerciseArchive[lastCentralDayIdentifier] ?? []
            if !(exercises.isEmpty && !existingLastExercises.isEmpty) {
                dailyExerciseArchive[lastCentralDayIdentifier] = exercises
            }

            dailyCalorieGoalArchive[lastCentralDayIdentifier] = calorieGoalForDay(lastCentralDayIdentifier)
            dailyBurnedCalorieArchive[lastCentralDayIdentifier] = burnedCaloriesForDay(lastCentralDayIdentifier)
            dailyGoalTypeArchive[lastCentralDayIdentifier] = goalType.rawValue
            lastCentralDayIdentifier = currentCentralDay
            entries = entries(forDayIdentifier: currentCentralDay)
            exercises = exercises(forDayIdentifier: currentCentralDay)
            if dailyEntryArchive[currentCentralDay] == nil {
                dailyEntryArchive[currentCentralDay] = []
            }
            if dailyExerciseArchive[currentCentralDay] == nil {
                dailyExerciseArchive[currentCentralDay] = []
            }
            dailyCalorieGoalArchive[currentCentralDay] = CalibrationEngine.floorAgainstArchive(
                calorieGoal,
                archivedValue: dailyCalorieGoalArchive[currentCentralDay]
            )
            dailyBurnedCalorieArchive[currentCentralDay] = CalibrationEngine.floorAgainstArchive(
                burnedCaloriesToday,
                archivedValue: dailyBurnedCalorieArchive[currentCentralDay]
            )
            dailyGoalTypeArchive[currentCentralDay] = goalType.rawValue
            saveEntries()
            saveDailyEntryArchive()
            saveDailyExerciseArchive()
            saveDailyCalorieGoalArchive()
            saveDailyBurnedCalorieArchive()
            saveDailyGoalTypeArchive()
            selectedMenuItemQuantitiesByVenue = [:]
            selectedMenuItemMultipliersByVenue = [:]
            venueMenus = [:]
            lastLoadedMenuSignatureByVenue = [:]
            menuLoadErrorsByVenue = [:]
            selectedMenuType = menuService.currentMenuType()
            saveVenueMenus()
            syncHistorySelection(preferToday: true)
            // Push a zeroed snapshot immediately so the widget doesn't carry
            // yesterday's stale consumed/burned values into the new day.
            syncWidgetSnapshot(force: true)
        }

        if forceMenuReload {
            venueMenus = [:]
            lastLoadedMenuSignatureByVenue = [:]
            menuLoadErrorsByVenue = [:]
            saveVenueMenus()
            Task {
                await preloadMenuForNutrientDiscovery()
            }
        }
    }

    func addSelectedMenuItems() {
        var itemByID: [String: MenuItem] = [:]
        for item in currentMenu.lines.flatMap(\.items) {
            if itemByID[item.id] == nil {
                itemByID[item.id] = item
            }
        }

        var expandedSelections: [MealEntry] = []
        let now = Date()

        let quantities = menuQuantities(for: selectedMenuVenue, menuType: selectedMenuType)
        let multipliers = menuMultipliers(for: selectedMenuVenue, menuType: selectedMenuType)
        for (id, quantity) in quantities {
            guard let item = itemByID[id], quantity > 0 else { continue }
            let multiplier = multipliers[id] ?? 1.0
            var scaledNutrients: [String: Int] = [:]
            for (key, value) in item.nutrientValues {
                scaledNutrients[key] = Int((Double(value) * multiplier).rounded())
            }
            let scaledCalories = scaledNutrients["calories"] ?? Int((Double(item.calories) * multiplier).rounded())

            for _ in 0..<quantity {
                expandedSelections.append(
                    MealEntry(
                        id: UUID(),
                        name: item.name,
                        calories: scaledCalories,
                        nutrientValues: scaledNutrients,
                        createdAt: now,
                        mealGroup: mealGroup(for: selectedMenuType)
                    )
                )
            }
        }

        guard !expandedSelections.isEmpty else {
            Haptics.notification(.warning)
            return
        }

        withAnimation(.easeInOut(duration: 0.25)) {
            entries.append(contentsOf: expandedSelections)
        }
        Haptics.notification(.success)

        setMenuQuantities([:], for: selectedMenuVenue, menuType: selectedMenuType)
        setMenuMultipliers([:], for: selectedMenuVenue, menuType: selectedMenuType)
        isMenuSheetPresented = false
        showAddConfirmation()
    }

    func handlePhotoPlate(items: [MenuItem], imageData: Data) {
        isPlateEstimateLoading = true
        plateEstimateErrorMessage = nil
        Task {
            do {
                let service = GeminiPlateEstimateService()
                let result = try await service.estimatePortions(imageData: imageData, items: items)
                let ozByName = result.ozByName
                let countByName = result.countByName
                let baseOzByName = result.baseOzByName
                await MainActor.run {
                    var ozById: [String: Double] = [:]
                    var baseOzById: [String: Double] = [:]
                    for item in items {
                        let unit = item.servingUnit.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                        let ambiguousUnit = unit.isEmpty || unit == "serving" || unit == "servings" || unit == "each" || unit == "ea" || unit == "item"
                        // Missing or zero = not on plate. Count-based items use quantity; others use oz.
                        if item.isCountBased {
                            ozById[item.id] = Double(countByName[item.name] ?? 0)
                        } else {
                            ozById[item.id] = ozByName[item.name] ?? 0
                            // Only let Gemini override base serving when:
                            // 1) The user has enabled AI base servings in Settings, and
                            // 2) The menu unit is ambiguous ("1 each", "1 serving", etc).
                            // For explicit weights/volumes like cups/oz/g, or when the toggle is off,
                            // keep the Nutrislice base serving instead of Gemini's.
                            if useAIBaseServings, ambiguousUnit, let base = baseOzByName[item.name] {
                                baseOzById[item.id] = base
                            }
                        }
                    }
                    plateEstimateItems = items
                    plateEstimateOzByItemId = ozById
                    plateEstimateBaseOzByItemId = baseOzById
                    isPlateEstimateLoading = false
                }
            } catch {
                await MainActor.run {
                    plateEstimateErrorMessage = error.localizedDescription
                    isPlateEstimateLoading = false
                }
            }
        }
    }

    func analyzeAIFoodPhoto(_ imageData: Data) {
        isAIFoodPhotoLoading = true
        aiFoodPhotoErrorMessage = nil
        let backgroundTaskID = beginAIBackgroundTask(named: "AI Food Photo Analysis")

        Task {
            defer {
                Task { @MainActor in
                    endAIBackgroundTask(backgroundTaskID)
                }
            }
            do {
                let service = AIFoodPhotoService()
                let result = try await service.analyze(imageData: imageData)
                await MainActor.run {
                    handleAIFoodPhotoResult(result)
                    isAIFoodPhotoLoading = false
                }
            } catch {
                await MainActor.run {
                    aiFoodPhotoErrorMessage = error.localizedDescription
                    isAIFoodPhotoLoading = false
                }
            }
        }
    }

    func analyzeAITextMeal() {
        let mealText = aiMealTextInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !mealText.isEmpty else {
            aiTextErrorMessage = "Enter what you ate."
            return
        }

        dismissKeyboard()
        isAITextLoading = true
        aiTextErrorMessage = nil
        aiTextMealResults = []
        let backgroundTaskID = beginAIBackgroundTask(named: "AI Text Meal Analysis")

        Task {
            defer {
                Task { @MainActor in
                    endAIBackgroundTask(backgroundTaskID)
                }
            }
            do {
                let result = try await aiTextMealService.analyze(mealText: mealText)
                await MainActor.run {
                    isAITextLoading = false
                    if result.items.isEmpty {
                        aiTextErrorMessage = "AI could not find any foods from that text."
                    } else {
                        aiTextMealResults = result.items
                        presentAITextPlateResults()
                        Haptics.selection()
                    }
                }
            } catch {
                await MainActor.run {
                    isAITextLoading = false
                    aiTextErrorMessage = error.localizedDescription
                }
            }
        }
    }

    @MainActor
    func beginAIBackgroundTask(named name: String) -> UIBackgroundTaskIdentifier {
        UIApplication.shared.beginBackgroundTask(withName: name, expirationHandler: nil)
    }

    @MainActor
    func endAIBackgroundTask(_ identifier: UIBackgroundTaskIdentifier) {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
    }

    func isAmbiguousAIServingUnit(_ unit: String) -> Bool {
        let normalized = unit.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty
            || normalized == "serving"
            || normalized == "servings"
            || normalized == "each"
            || normalized == "ea"
            || normalized == "item"
            || normalized == "items"
            || normalized == "portion"
            || normalized == "portions"
    }

    func isLikelyCountServingUnit(name: String, unit: String) -> Bool {
        let normalizedUnit = unit.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let countUnits: Set<String> = [
            "piece", "pieces",
            "slice", "slices",
            "nugget", "nuggets",
            "sandwich", "sandwiches",
            "burger", "burgers",
            "taco", "tacos",
            "burrito", "burritos",
            "wrap", "wraps",
            "quesadilla", "quesadillas",
            "cookie", "cookies",
            "chip", "chips"
        ]
        if countUnits.contains(normalizedUnit) { return true }
        return normalizedName.contains("nugget")
            || normalizedName.contains("quesadilla")
            || normalizedName.contains("sandwich")
            || normalizedName.contains("burger")
            || normalizedName.contains("taco")
            || normalizedName.contains("burrito")
            || normalizedName.contains("wrap")
            || normalizedName.contains("cookie")
            || normalizedName.contains("chips")
            || normalizedName.hasSuffix(" chip")
    }

    struct AICountServingNormalization {
        let servingAmount: Double
        let servingUnit: String
        let estimatedServings: Double
        let consumedItemCount: Double?
    }

    func inferredCountUnitFromName(_ name: String) -> String? {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalizedName.contains("nugget") { return "nuggets" }
        if normalizedName.contains("quesadilla") { return "quesadillas" }
        if normalizedName.contains("sandwich") { return "sandwiches" }
        if normalizedName.contains("burger") { return "burgers" }
        if normalizedName.contains("taco") { return "tacos" }
        if normalizedName.contains("burrito") { return "burritos" }
        if normalizedName.contains("wrap") { return "wraps" }
        if normalizedName.contains("slice") { return "slices" }
        if normalizedName.contains("cookie") { return "cookies" }
        if normalizedName.contains("chip") || normalizedName.contains("chips") { return "chips" }
        return nil
    }

    func normalizedCountServingForAIItem(
        name: String,
        servingAmount: Double,
        servingUnit: String,
        servingItemsCount: Double?,
        estimatedServings: Double,
        estimatedItemCount: Double?
    ) -> AICountServingNormalization {
        let safeServingAmount = max(servingAmount, 1)
        let safeEstimatedServings = max(min(estimatedServings, 100), 0.01)
        let safeServingItemsCount = (servingItemsCount ?? 0) > 0 ? servingItemsCount : nil
        let safeEstimatedItemCount = (estimatedItemCount ?? 0) > 0 ? estimatedItemCount : nil
        let likelyCountBased = isLikelyCountServingUnit(name: name, unit: servingUnit)

        guard likelyCountBased else {
            return AICountServingNormalization(
                servingAmount: safeServingAmount,
                servingUnit: servingUnit,
                estimatedServings: safeEstimatedServings,
                consumedItemCount: nil
            )
        }

        var normalizedServingAmount = safeServingItemsCount ?? safeServingAmount
        var normalizedServingUnit = servingUnit
        if isAmbiguousAIServingUnit(normalizedServingUnit), let inferredUnit = inferredCountUnitFromName(name) {
            normalizedServingUnit = inferredUnit
        }

        let consumedCount: Double
        if let explicitConsumedCount = safeEstimatedItemCount {
            consumedCount = explicitConsumedCount
        } else {
            consumedCount = max(normalizedServingAmount * safeEstimatedServings, 0.01)
        }

        if normalizedServingAmount <= 0 {
            normalizedServingAmount = 1
        }

        return AICountServingNormalization(
            servingAmount: normalizedServingAmount,
            servingUnit: normalizedServingUnit,
            estimatedServings: safeEstimatedServings,
            consumedItemCount: consumedCount
        )
    }

    func normalizedEstimatedServingsForCountItems(
        name: String,
        servingAmount: Double,
        servingUnit: String,
        estimatedServings: Double
    ) -> Double {
        let safeEstimated = max(min(estimatedServings, 100), 0.01)
        let safeServingAmount = max(servingAmount, 1)
        guard safeServingAmount > 1 else { return safeEstimated }
        guard isLikelyCountServingUnit(name: name, unit: servingUnit) else { return safeEstimated }

        // Guard against AI returning total piece count (e.g. 5 nuggets) as servings.
        let roundedEstimate = safeEstimated.rounded()
        let looksIntegerCount = abs(safeEstimated - roundedEstimate) <= 0.05
        if looksIntegerCount && safeEstimated + 0.05 >= safeServingAmount {
            return max(safeEstimated / safeServingAmount, 0.01)
        }
        return safeEstimated
    }

    func presentAITextPlateResults() {
        guard !aiTextMealResults.isEmpty else { return }

        let normalizedItems = aiTextMealResults.map {
            normalizedCountServingForAIItem(
                name: $0.name,
                servingAmount: $0.servingAmount,
                servingUnit: $0.servingUnit,
                servingItemsCount: $0.servingItemsCount,
                estimatedServings: $0.estimatedServings,
                estimatedItemCount: $0.estimatedItemCount
            )
        }

        let menuItems = zip(aiTextMealResults.enumerated(), normalizedItems).map { pair -> MenuItem in
            let (indexedItem, normalized) = pair
            let (index, item) = indexedItem
            let cleanedNutrients = NutrientCatalog.acceptedImportedNutrientValues(item.nutrients)
            let calories = max(item.calories, cleanedNutrients["calories"] ?? 0)
            let protein = max(item.protein, cleanedNutrients["g_protein"] ?? 0)
            var nutrientValues = cleanedNutrients
            nutrientValues.removeValue(forKey: "calories")
            if protein > 0, nutrientValues["g_protein"] == nil {
                nutrientValues["g_protein"] = protein
            }
            return MenuItem(
                id: "ai-text-\(index)-\(UUID().uuidString)",
                name: item.name,
                calories: calories,
                nutrientValues: nutrientValues,
                servingAmount: normalized.servingAmount,
                servingUnit: normalized.servingUnit,
                calorieSource: item.sourceType == "real" ? .web : .estimated
            )
        }

        var ozById: [String: Double] = [:]
        var baseOzById: [String: Double] = [:]
        for ((menuItem, aiItem), normalized) in zip(zip(menuItems, aiTextMealResults), normalizedItems) {
            let estimatedServings = normalizedEstimatedServingsForCountItems(
                name: aiItem.name,
                servingAmount: normalized.servingAmount,
                servingUnit: normalized.servingUnit,
                estimatedServings: normalized.estimatedServings
            )
            if menuItem.isCountBased {
                let consumedCount = normalized.consumedItemCount ?? max(normalized.servingAmount * estimatedServings, 0.01)
                ozById[menuItem.id] = max(consumedCount, 0.25)
            } else if isAmbiguousAIServingUnit(menuItem.servingUnit) {
                // For ambiguous AI units (serving/each/item), treat estimatedServings as direct serving count.
                baseOzById[menuItem.id] = 1.0
                ozById[menuItem.id] = max(estimatedServings, 0.01)
            } else {
                let baseOz = menuItem.servingOzForPortions
                baseOzById[menuItem.id] = baseOz
                ozById[menuItem.id] = max(baseOz * estimatedServings, 0.01)
            }
        }

        aiTextPlateItems = menuItems
        aiTextOzByItemId = ozById
        aiTextBaseOzByItemId = baseOzById
    }

    @MainActor
    func handleAIFoodPhotoResult(_ result: AIFoodPhotoAnalysisResult) {
        func makeAIPhotoMenuItem(
            _ item: AIFoodPhotoAnalysisResult.Item,
            normalized: AICountServingNormalization,
            index: Int
        ) -> MenuItem {
            let cleanedNutrients = NutrientCatalog.acceptedImportedNutrientValues(item.nutrients)
            let calories = max(item.calories, cleanedNutrients["calories"] ?? 0)
            let protein = max(item.protein, cleanedNutrients["g_protein"] ?? 0)
            var nutrientValues = cleanedNutrients
            nutrientValues.removeValue(forKey: "calories")
            if protein > 0, nutrientValues["g_protein"] == nil {
                nutrientValues["g_protein"] = protein
            }
            return MenuItem(
                id: "ai-photo-\(index)-\(UUID().uuidString)",
                name: item.name,
                calories: calories,
                nutrientValues: nutrientValues,
                servingAmount: normalized.servingAmount,
                servingUnit: normalized.servingUnit,
                calorieSource: item.sourceType == .real ? .web : .estimated
            )
        }

        switch result.mode {
        case .foodPhoto:
            guard let firstItem = result.items.first else {
                aiFoodPhotoErrorMessage = "AI did not find any foods."
                return
            }

            if result.items.count == 1 {
                let normalized = normalizedCountServingForAIItem(
                    name: firstItem.name,
                    servingAmount: firstItem.servingAmount,
                    servingUnit: firstItem.servingUnit,
                    servingItemsCount: firstItem.servingItemsCount,
                    estimatedServings: firstItem.estimatedServings,
                    estimatedItemCount: firstItem.estimatedItemCount
                )
                let menuItem = makeAIPhotoMenuItem(firstItem, normalized: normalized, index: 0)

                aiPhotoOzByItemId = [:]
                aiPhotoBaseOzByItemId = [:]
                let estimatedServings = normalizedEstimatedServingsForCountItems(
                    name: firstItem.name,
                    servingAmount: normalized.servingAmount,
                    servingUnit: normalized.servingUnit,
                    estimatedServings: normalized.estimatedServings
                )
                if menuItem.isCountBased {
                    let consumedCount = normalized.consumedItemCount ?? max(normalized.servingAmount * estimatedServings, 0.01)
                    aiPhotoOzByItemId[menuItem.id] = max(consumedCount, 0.25)
                } else if isAmbiguousAIServingUnit(menuItem.servingUnit) {
                    aiPhotoBaseOzByItemId[menuItem.id] = 1.0
                    aiPhotoOzByItemId[menuItem.id] = max(estimatedServings, 0.01)
                } else {
                    let baseOz = menuItem.servingOzForPortions
                    aiPhotoBaseOzByItemId[menuItem.id] = baseOz
                    aiPhotoOzByItemId[menuItem.id] = max(baseOz * estimatedServings, 0.01)
                }
                aiPhotoItems = [menuItem]
                return
            }

            let normalizedItems = result.items.map {
                normalizedCountServingForAIItem(
                    name: $0.name,
                    servingAmount: $0.servingAmount,
                    servingUnit: $0.servingUnit,
                    servingItemsCount: $0.servingItemsCount,
                    estimatedServings: $0.estimatedServings,
                    estimatedItemCount: $0.estimatedItemCount
                )
            }

            let menuItems = zip(result.items.enumerated(), normalizedItems).map { pair in
                let (indexedItem, normalized) = pair
                let (index, item) = indexedItem
                return makeAIPhotoMenuItem(item, normalized: normalized, index: index)
            }

            var ozById: [String: Double] = [:]
            var baseOzById: [String: Double] = [:]
            for ((menuItem, aiItem), normalized) in zip(zip(menuItems, result.items), normalizedItems) {
                let estimatedServings = normalizedEstimatedServingsForCountItems(
                    name: aiItem.name,
                    servingAmount: normalized.servingAmount,
                    servingUnit: normalized.servingUnit,
                    estimatedServings: normalized.estimatedServings
                )
                if menuItem.isCountBased {
                    let consumedCount = normalized.consumedItemCount ?? max(normalized.servingAmount * estimatedServings, 0.01)
                    ozById[menuItem.id] = max(consumedCount, 0.25)
                } else if isAmbiguousAIServingUnit(menuItem.servingUnit) {
                    baseOzById[menuItem.id] = 1.0
                    ozById[menuItem.id] = max(estimatedServings, 0.01)
                } else {
                    let baseOz = menuItem.servingOzForPortions
                    baseOzById[menuItem.id] = baseOz
                    ozById[menuItem.id] = max(baseOz * estimatedServings, 0.01)
                }
            }

            aiPhotoItems = menuItems
            aiPhotoOzByItemId = ozById
            aiPhotoBaseOzByItemId = baseOzById

        case .nutritionLabel:
            guard let item = result.items.first else {
                aiFoodPhotoErrorMessage = "AI could not read the nutrition label."
                return
            }

            let nutrientValues = NutrientCatalog.acceptedImportedNutrientValues(item.nutrients)
            let displayedKeys = trackedNutrientKeys
                .map { $0.lowercased() }
                .filter { nutrientValues[$0] != nil }
            presentFoodReview(
                FoodReviewItem(
                    name: item.name,
                    subtitle: "AI nutrition label scan",
                    calories: item.calories,
                    nutrientValues: nutrientValues,
                    servingAmount: item.servingAmount,
                    servingUnit: item.servingUnit,
                    entrySource: .aiNutritionLabel,
                    displayedNutrientKeys: displayedKeys
                ),
                initialMultiplier: 1.0
            )
        }
    }

    func clearAIPhotoMultiItemState() {
        aiPhotoItems = nil
        aiPhotoOzByItemId = [:]
        aiPhotoBaseOzByItemId = [:]
    }

    func clearAITextPlateState() {
        aiTextPlateItems = nil
        aiTextOzByItemId = [:]
        aiTextBaseOzByItemId = [:]
    }

    func addAIPhotoItemsWithPortions(_ pairs: [(item: MenuItem, oz: Double, baseOz: Double)]) {
        let now = Date()
        let mealGrp = genericMealGroup(for: now)
        let newEntries = pairs.map { pair -> MealEntry in
            let multiplier: Double
            if pair.item.isCountBased {
                let baseCount = max(pair.item.servingAmount, 1)
                multiplier = pair.oz / baseCount
            } else {
                multiplier = pair.baseOz > 0 ? (pair.oz / pair.baseOz) : 1.0
            }
            let scaledNutrients = pair.item.nutrientValues.mapValues { Int((Double($0) * multiplier).rounded()) }
            let scaledCalories = Int((Double(pair.item.calories) * multiplier).rounded())
            let loggedCount = pair.item.isCountBased ? inferredLoggedItemCount(from: pair.oz) : 1
            return MealEntry(
                id: UUID(),
                name: pair.item.name,
                calories: scaledCalories,
                nutrientValues: scaledNutrients,
                loggedCount: loggedCount > 1 ? loggedCount : nil,
                createdAt: now,
                mealGroup: mealGrp
            )
        }

        guard !newEntries.isEmpty else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            entries.append(contentsOf: newEntries)
        }
        showAddConfirmation()
    }

    func addAITextItemsWithPortions(_ pairs: [(item: MenuItem, oz: Double, baseOz: Double)]) {
        let now = Date()
        let mealGrp = genericMealGroup(for: now)
        let newEntries = pairs.map { pair -> MealEntry in
            let multiplier: Double
            if pair.item.isCountBased {
                let baseCount = max(pair.item.servingAmount, 1)
                multiplier = pair.oz / baseCount
            } else {
                multiplier = pair.baseOz > 0 ? (pair.oz / pair.baseOz) : 1.0
            }

            let scaledNutrients = pair.item.nutrientValues.mapValues { Int((Double($0) * multiplier).rounded()) }
            let scaledCalories = Int((Double(pair.item.calories) * multiplier).rounded())
            let loggedCount = pair.item.isCountBased ? inferredLoggedItemCount(from: pair.oz) : 1
            return MealEntry(
                id: UUID(),
                name: MealEntry.normalizedName(pair.item.name),
                calories: scaledCalories,
                nutrientValues: scaledNutrients,
                loggedCount: loggedCount > 1 ? loggedCount : nil,
                createdAt: now,
                mealGroup: mealGrp
            )
        }

        guard !newEntries.isEmpty else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            entries.append(contentsOf: newEntries)
        }
        Haptics.notification(.success)
        showAddConfirmation()
    }

    func addMenuItemsWithPortions(_ pairs: [(item: MenuItem, oz: Double, baseOz: Double)]) {
        let now = Date()
        let mealGrp = mealGroup(for: selectedMenuType)
        var expandedSelections: [MealEntry] = []
        for (item, oz, baseOz) in pairs {
            let multiplier: Double
            if item.isCountBased {
                let baseCount = max(item.servingAmount, 1)
                multiplier = oz / baseCount
            } else {
                multiplier = baseOz > 0 ? (oz / baseOz) : 1.0
            }
            var scaledNutrients: [String: Int] = [:]
            for (key, value) in item.nutrientValues {
                scaledNutrients[key] = Int((Double(value) * multiplier).rounded())
            }
            let scaledCalories = Int((Double(item.calories) * multiplier).rounded())
            let loggedCount = item.isCountBased ? inferredLoggedItemCount(from: oz) : 1
            expandedSelections.append(
                MealEntry(
                    id: UUID(),
                    name: item.name,
                    calories: scaledCalories,
                    nutrientValues: scaledNutrients,
                    loggedCount: loggedCount > 1 ? loggedCount : nil,
                    createdAt: now,
                    mealGroup: mealGrp
                )
            )
        }
        guard !expandedSelections.isEmpty else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            entries.append(contentsOf: expandedSelections)
        }
        showAddConfirmation()
    }

    func preferredMenuType(
        startingFrom menuType: NutrisliceMenuService.MenuType,
        for venue: DiningVenue
    ) -> NutrisliceMenuService.MenuType {
        if venue.supportedMenuTypes.contains(menuType) {
            return menuType
        }

        return menuService.allMenuTypes.first(where: { venue.supportedMenuTypes.contains($0) }) ?? .lunch
    }

    func preferredMenuVenue(
        startingFrom venue: DiningVenue,
        menuType: NutrisliceMenuService.MenuType
    ) -> DiningVenue {
        if venue.supportedMenuTypes.contains(menuType) {
            return venue
        }

        if menuType == .breakfast {
            return .varsity
        }

        return DiningVenue.allCases.first(where: { $0.supportedMenuTypes.contains(menuType) }) ?? venue
    }


}
