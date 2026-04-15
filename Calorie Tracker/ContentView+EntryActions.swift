// Calorie Tracker 2026

import SwiftUI

extension ContentView {

    func addReviewedFood(_ item: FoodReviewItem) {
        let multiplier = selectedFoodReviewEffectiveMultiplier
        let signature = foodReviewSliderSignature(for: item)
        let quantity = max(1, selectedFoodReviewQuantity)
        let editedName = MealEntry.normalizedName(foodReviewNameText)
        let selectedServingAmount = max(
            roundToServingSelectorIncrement(selectedFoodReviewBaselineAmount * selectedFoodReviewMultiplier),
            0.01
        )
        var scaledNutrients: [String: Int] = [:]
        for (key, value) in item.nutrientValues {
            scaledNutrients[key] = Int((Double(value) * multiplier).rounded())
        }

        let now = Date()
        let resolvedMealGroup = mealGroup(for: now, source: item.entrySource)
        let scaledCalories = Int((Double(item.calories) * multiplier).rounded())
        let selectedCount = inferredLoggedItemCount(from: selectedServingAmount)
        let shouldStoreAsCountedSingleEntry = item.isCountBased && quantity == 1 && selectedCount > 1
        let newEntries: [MealEntry]
        if shouldStoreAsCountedSingleEntry {
            newEntries = [
                MealEntry(
                    id: UUID(),
                    name: editedName,
                    calories: scaledCalories,
                    nutrientValues: scaledNutrients,
                    loggedCount: selectedCount,
                    createdAt: now,
                    mealGroup: resolvedMealGroup
                )
            ]
        } else {
            newEntries = (0..<quantity).map { _ in
                MealEntry(
                    id: UUID(),
                    name: editedName,
                    calories: scaledCalories,
                    nutrientValues: scaledNutrients,
                    createdAt: now,
                    mealGroup: resolvedMealGroup
                )
            }
        }

        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            entries.append(contentsOf: newEntries)
        }

        if let quickAddID = item.quickAddID {
            markQuickAddFoodsRecentlyUsed(ids: [quickAddID])
        }

        foodReviewItem = nil
        foodReviewNameText = ""
        if case .quickAdd = item.entrySource {
            // Quick Add serving edits in review are one-off for this add.
        } else {
            foodReviewSliderBaselineBySignature[signature] = max(roundToServingSelectorIncrement(selectedFoodReviewBaselineAmount), 0)
            foodReviewSliderValueBySignature[signature] = min(max(selectedFoodReviewMultiplier, 0.25), 1.75)
        }
        selectedFoodReviewMultiplier = 1.0
        selectedFoodReviewBaselineAmount = 1.0
        selectedFoodReviewAmountText = ""
        selectedFoodReviewQuantity = 1
        barcodeLookupError = nil
        usdaSearchError = nil
        showAddConfirmation()
    }

    func deleteEntry(_ entry: MealEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else {
            return
        }

        withAnimation(.easeInOut(duration: 0.2)) {
            _ = entries.remove(at: index)
        }
        Haptics.selection()
    }

    func deleteEntries(_ entriesToDelete: [MealEntry]) {
        let idsToDelete = Set(entriesToDelete.map(\.id))
        guard !idsToDelete.isEmpty else { return }

        withAnimation(.easeInOut(duration: 0.2)) {
            entries.removeAll { idsToDelete.contains($0.id) }
        }
        Haptics.selection()
    }

    func deleteExercise(_ entry: ExerciseEntry) {
        guard let index = exercises.firstIndex(where: { $0.id == entry.id }) else {
            return
        }

        withAnimation(.easeInOut(duration: 0.2)) {
            _ = exercises.remove(at: index)
        }
        Haptics.selection()
    }

    func updateEntry(_ updatedEntry: MealEntry) {
        guard let index = entries.firstIndex(where: { $0.id == updatedEntry.id }) else {
            return
        }

        withAnimation(.easeInOut(duration: 0.2)) {
            entries[index] = updatedEntry
        }
        editingEntry = nil
        Haptics.notification(.success)
    }

    func resetTodayLog() {
        withAnimation(.easeInOut(duration: 0.2)) {
            entries.removeAll()
            exercises.removeAll()
        }
        Haptics.notification(.warning)
    }

    func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    func parseInputValue(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return 0
        }

        guard let parsed = Int(trimmed), parsed >= 0 else {
            return nil
        }

        return parsed
    }

    func entryValue(for key: String, in entry: MealEntry) -> Int {
        if key == "g_protein" {
            return entry.nutrientValues[key] ?? entry.protein
        }
        return entry.nutrientValues[key] ?? 0
    }

    func entryValue(for key: String, in entry: FoodLogDisplayEntry) -> Int {
        entry.nutrientValues[key] ?? 0
    }

    func totalNutrient(for key: String) -> Int {
        entries.reduce(0) { $0 + entryValue(for: key, in: $1) }
    }

    func editableNutrients(for entry: MealEntry) -> [NutrientDefinition] {
        let keys = Set(activeNutrients.map(\.key))
        return keys
            .map { NutrientCatalog.definition(for: $0) }
            .sorted { lhs, rhs in
                let lhsRank = NutrientCatalog.preferredOrder.firstIndex(of: lhs.key) ?? Int.max
                let rhsRank = NutrientCatalog.preferredOrder.firstIndex(of: rhs.key) ?? Int.max
                if lhsRank != rhsRank {
                    return lhsRank < rhsRank
                }
                return lhs.name < rhs.name
            }
    }

    func goalForNutrient(_ key: String) -> Int {
        max(nutrientGoals[key] ?? NutrientCatalog.definition(for: key).defaultGoal, 1)
    }

    func sanitizeStoredGoals() {
        if storedDeficitCalories < 0 {
            storedDeficitCalories = 0
        }
        if storedSurplusCalories < 0 {
            storedSurplusCalories = 0
        }
        if storedFixedGoalCalories < 1 {
            storedFixedGoalCalories = 1
        }
        if storedFixedGoalCalories > 6000 {
            storedFixedGoalCalories = 6000
        }
        if storedManualBMRCalories < 800 {
            storedManualBMRCalories = 800
        }
        if storedManualBMRCalories > 4000 {
            storedManualBMRCalories = 4000
        }
        if GoalType(rawValue: goalTypeRaw) == nil {
            goalTypeRaw = GoalType.deficit.rawValue
        }
        if BMRSource(rawValue: bmrSourceRaw) == nil {
            bmrSourceRaw = BMRSource.automatic.rawValue
        }
    }

    func normalizeTrackingState() {
        let valid = trackedNutrientKeys
            .map { $0.lowercased() }
            .filter { !$0.isEmpty && !NutrientCatalog.nonTrackableKeys.contains($0) }
            .filter { !excludedNutrientKeys.contains($0) }
        trackedNutrientKeys = Array(NSOrderedSet(array: valid)) as? [String] ?? valid

        for key in trackedNutrientKeys {
            if nutrientGoals[key] == nil {
                let defaultGoal = key == "g_protein" ? max(legacyStoredProteinGoal, 1) : NutrientCatalog.definition(for: key).defaultGoal
                nutrientGoals[key] = defaultGoal
            }
        }
    }

    func loadTrackingPreferences() {
        if let data = storedTrackedNutrientsData.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            trackedNutrientKeys = decoded
        }

        if let data = storedNutrientGoalsData.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String: Int].self, from: data) {
            nutrientGoals = decoded
        }

        normalizeTrackingState()
        saveTrackingPreferences()
    }

    func saveTrackingPreferences() {
        if let trackedData = try? JSONEncoder().encode(trackedNutrientKeys) {
            storedTrackedNutrientsData = String(decoding: trackedData, as: UTF8.self)
        }
        if let goalsData = try? JSONEncoder().encode(nutrientGoals) {
            storedNutrientGoalsData = String(decoding: goalsData, as: UTF8.self)
        }
        persistStateSnapshot()
    }

    func syncInputFieldsToTrackedNutrients() {
        var next: [String: String] = [:]
        for nutrient in activeNutrients {
            next[nutrient.key] = nutrientInputTexts[nutrient.key] ?? ""
        }
        nutrientInputTexts = next
    }



    func historySummary(for identifier: String) -> HistoryDaySummary {
        let dayEntries = entries(forDayIdentifier: identifier)
        let total = dayEntries.reduce(0) { $0 + $1.calories }
        let date = date(fromCentralDayIdentifier: identifier) ?? currentCentralDate()
        let goal = calorieGoalForDay(identifier)
        let burned = burnedCaloriesForDay(identifier)
        let dayGoalType = goalTypeForDay(identifier)

        let goalMet: Bool
        if dayGoalType == .surplus {
            goalMet = total > 0 && total >= burned && total <= goal
        } else if dayGoalType == .fixed {
            goalMet = total > 0 && total <= goal
        } else {
            goalMet = total > 0 && total <= goal
        }

        return HistoryDaySummary(
            dayIdentifier: identifier,
            date: date,
            totalCalories: total,
            entryCount: dayEntries.count,
            goalMet: goalMet
        )
    }

    func dayIdentifiers(forLast dayCount: Int) -> [String] {
        let today = centralCalendar.startOfDay(for: Date())
        // Use completed days only: last `dayCount` days, excluding today
        return (0..<dayCount).compactMap { offset in
            centralCalendar.date(byAdding: .day, value: -(dayCount - offset), to: today)
                .map { centralDayIdentifier(for: $0) }
        }
    }

    func netCalorieColor(_ net: Int) -> Color {
        let targetNetGoal = weightedAverageNetGoalAmount()
        switch goalType {
        case .deficit:
            if net >= 0 {
                return .red
            }
            let deficit = -net
            if deficit >= Int((Double(targetNetGoal) * 0.85).rounded()) {
                return .green
            } else {
                return .yellow
            }
        case .surplus:
            if net < 0 {
                return .red
            }
            if net <= targetNetGoal {
                return .green
            } else {
                return .red
            }
        case .fixed:
            if net <= 0 {
                return .green
            }
            return .yellow
        }
    }

    private func weightedAverageNetGoalAmount() -> Int {
        let weekdayGoal: Int
        switch goalType {
        case .deficit:
            weekdayGoal = deficitCalories
        case .surplus:
            weekdayGoal = surplusCalories
        case .fixed:
            weekdayGoal = 0
        }

        guard goalType != .fixed, useWeekendDeficit else {
            return weekdayGoal
        }

        let weekendGoal = weekendDeficitCalories
        let weightedAverage = ((Double(weekdayGoal) * 5.0) + (Double(weekendGoal) * 2.0)) / 7.0
        return Int(weightedAverage.rounded())
    }

    func netSign(_ net: Int) -> String {
        if net > 0 { return "+" }
        if net < 0 { return "-" }
        return ""
    }

    func interpolateColor(from: UIColor, to: UIColor, progress: Double) -> Color {
        let clamped = max(0, min(progress, 1))

        var r1: CGFloat = 0
        var g1: CGFloat = 0
        var b1: CGFloat = 0
        var a1: CGFloat = 0
        var r2: CGFloat = 0
        var g2: CGFloat = 0
        var b2: CGFloat = 0
        var a2: CGFloat = 0

        from.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        to.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)

        return Color(
            red: Double(r1 + (r2 - r1) * clamped),
            green: Double(g1 + (g2 - g1) * clamped),
            blue: Double(b1 + (b2 - b1) * clamped),
            opacity: Double(a1 + (a2 - a1) * clamped)
        )
    }

    func presentFoodReview(_ item: FoodReviewItem, initialMultiplier: Double = 1.0) {
        let baseAmount = convertedServingAmount(item.servingAmount, unit: item.servingUnit)
        let signature = foodReviewSliderSignature(for: item)
        if case .quickAdd = item.entrySource {
            selectedFoodReviewBaselineAmount = max(roundToServingSelectorIncrement(baseAmount * initialMultiplier), 0)
            selectedFoodReviewMultiplier = 1.0
        } else if let savedBaseline = foodReviewSliderBaselineBySignature[signature],
                  let savedSliderValue = foodReviewSliderValueBySignature[signature] {
            selectedFoodReviewBaselineAmount = max(roundToServingSelectorIncrement(savedBaseline), 0)
            selectedFoodReviewMultiplier = min(max(savedSliderValue, 0.25), 1.75)
        } else {
            selectedFoodReviewBaselineAmount = max(roundToServingSelectorIncrement(baseAmount * initialMultiplier), 0)
            selectedFoodReviewMultiplier = 1.0
        }
        selectedFoodReviewAmountText = formattedServingAmount(selectedFoodReviewBaselineAmount * selectedFoodReviewMultiplier)
        selectedFoodReviewQuantity = 1
        foodReviewNameText = item.name
        foodReviewItem = item
    }

    func foodReviewSliderSignature(for item: FoodReviewItem) -> String {
        let normalizedName = MealEntry.normalizedName(item.name).lowercased()
        let normalizedSubtitle = MealEntry.normalizedName(item.subtitle ?? "").lowercased()
        let unit = item.servingUnit.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let sourceKey: String
        switch item.entrySource {
        case .manual:
            sourceKey = "manual"
        case .quickAdd:
            sourceKey = "quickAdd"
        case .barcode:
            sourceKey = "barcode"
        case .usda:
            sourceKey = "usda"
        case .aiFoodPhoto:
            sourceKey = "aiFoodPhoto"
        case .aiNutritionLabel:
            sourceKey = "aiNutritionLabel"
        case .aiText:
            sourceKey = "aiText"
        case .pccMenu(let menuType):
            sourceKey = "pccMenu:\(menuType.rawValue)"
        }
        let roundedServing = roundToServingSelectorIncrement(convertedServingAmount(item.servingAmount, unit: item.servingUnit))
        let servingKey = String(format: "%.4f", roundedServing)
        return "\(sourceKey)|\(normalizedName)|\(normalizedSubtitle)|\(servingKey)|\(unit)"
    }

    func syncFoodReviewAmountText() {
        let amount = formattedServingAmount(selectedFoodReviewBaselineAmount * selectedFoodReviewMultiplier)
        if selectedFoodReviewAmountText != amount {
            isUpdatingFoodReviewTextFromSlider = true
            selectedFoodReviewAmountText = amount
        }
    }

    func applyTypedFoodReviewAmountIfPossible(text: String) {
        if isUpdatingFoodReviewTextFromSlider {
            isUpdatingFoodReviewTextFromSlider = false
            return
        }
        guard let typedAmount = parsedDecimalAmount(text), typedAmount >= 0 else { return }
        let roundedTypedAmount = roundToServingSelectorIncrement(typedAmount)
        let currentAmount = roundToServingSelectorIncrement(selectedFoodReviewBaselineAmount * selectedFoodReviewMultiplier)
        if abs(roundedTypedAmount - currentAmount) > 0.0005 {
            selectedFoodReviewBaselineAmount = roundedTypedAmount
            selectedFoodReviewMultiplier = 1.0
        }
    }

    func parsedDecimalAmount(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
    }

    func openFoodReview(for product: OpenFoodFactsProduct) {
        presentFoodReview(
            FoodReviewItem(
            name: product.name,
            subtitle: product.brand,
            calories: product.calories,
            nutrientValues: product.nutrientValues,
            servingAmount: product.servingAmount,
            servingUnit: product.servingUnit,
            entrySource: .barcode,
            displayedNutrientKeys: nil
        )
        )
    }

    func openFoodReview(for result: USDAFoodSearchResult) {
        isUSDASearchPresented = false
        dismissKeyboard()
        DispatchQueue.main.async {
            presentFoodReview(
                FoodReviewItem(
                name: result.name,
                subtitle: result.brand,
                calories: result.calories,
                nutrientValues: result.nutrientValues,
                servingAmount: result.servingAmount,
                servingUnit: result.servingUnit,
                entrySource: .usda,
                displayedNutrientKeys: nil
            )
            )
        }
    }

    func openFoodReview(for result: FoodSearchResult) {
        isUSDASearchPresented = false
        dismissKeyboard()
        let source: EntrySource
        switch result.source {
        case .usda:
            source = .usda
        case .openFoodFacts:
            source = .barcode
        }
        DispatchQueue.main.async {
            presentFoodReview(
                FoodReviewItem(
                    name: result.name,
                    subtitle: result.brand,
                    calories: result.calories,
                    nutrientValues: result.nutrientValues,
                    servingAmount: result.servingAmount,
                    servingUnit: result.servingUnit,
                    entrySource: source,
                    displayedNutrientKeys: nil
                )
            )
        }
    }

    func openFoodReview(for item: AITextMealAnalysisResult.Item) {
        let normalizedCountServing = normalizedCountServingForAIItem(
            name: item.name,
            servingAmount: item.servingAmount,
            servingUnit: item.servingUnit,
            servingItemsCount: item.servingItemsCount,
            estimatedServings: item.estimatedServings,
            estimatedItemCount: item.estimatedItemCount
        )
        let cleanedNutrients = NutrientCatalog.acceptedImportedNutrientValues(item.nutrients)
        let calories = max(item.calories, cleanedNutrients["calories"] ?? 0)
        let protein = max(item.protein, cleanedNutrients["g_protein"] ?? 0)
        var nutrientValues = cleanedNutrients
        nutrientValues.removeValue(forKey: "calories")
        if protein > 0, nutrientValues["g_protein"] == nil {
            nutrientValues["g_protein"] = protein
        }

        let subtitlePrefix = item.sourceType == "real" ? "AI web match" : "AI estimate"
        let subtitle = [subtitlePrefix, item.brand].compactMap { $0 }.joined(separator: " • ")

        presentFoodReview(
            FoodReviewItem(
                name: item.name,
                subtitle: subtitle,
                calories: calories,
                nutrientValues: nutrientValues,
                servingAmount: normalizedCountServing.servingAmount,
                servingUnit: normalizedCountServing.servingUnit,
                entrySource: .aiText,
                displayedNutrientKeys: nil
            ),
            initialMultiplier: {
                let estimatedServings = normalizedEstimatedServingsForCountItems(
                    name: item.name,
                    servingAmount: normalizedCountServing.servingAmount,
                    servingUnit: normalizedCountServing.servingUnit,
                    estimatedServings: normalizedCountServing.estimatedServings
                )
                if let consumedCount = normalizedCountServing.consumedItemCount {
                    return max(consumedCount / max(normalizedCountServing.servingAmount, 1), 0.01)
                }
                return estimatedServings
            }()
        )
    }

    func mealGroup(for date: Date, source: EntrySource) -> MealGroup {
        switch source {
        case let .pccMenu(menuType):
            return mealGroup(for: menuType)
        case .manual, .quickAdd, .barcode, .usda, .aiFoodPhoto, .aiNutritionLabel, .aiText:
            return genericMealGroup(for: date)
        }
    }

    func mealGroup(for menuType: NutrisliceMenuService.MenuType) -> MealGroup {
        switch menuType {
        case .breakfast:
            return .breakfast
        case .lunch:
            return .lunch
        case .dinner:
            return .dinner
        }
    }

    func genericMealGroup(for date: Date) -> MealGroup {
        let components = centralCalendar.dateComponents([.hour, .minute], from: date)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        let totalMinutes = hour * 60 + minute

        if totalMinutes >= 240 && totalMinutes < 645 {
            return .breakfast
        }
        if totalMinutes >= 645 && totalMinutes < 840 {
            return .lunch
        }
        if totalMinutes >= 840 && totalMinutes < 1005 {
            return .snack
        }
        if totalMinutes >= 1005 && totalMinutes < 1200 {
            return .dinner
        }
        return .snack
    }

    func loadQuickAddFoods() {
        guard
            !storedQuickAddFoodsData.isEmpty,
            let data = storedQuickAddFoodsData.data(using: .utf8),
            let decoded = try? JSONDecoder().decode([QuickAddFood].self, from: data)
        else {
            quickAddFoods = []
            return
        }

        quickAddFoods = decoded
    }

    func saveQuickAddFoods() {
        guard let data = try? JSONEncoder().encode(quickAddFoods) else {
            return
        }
        storedQuickAddFoodsData = String(decoding: data, as: UTF8.self)
        persistStateSnapshot()
    }

    func presentQuickAddManagerFromPicker() {
        if isQuickAddPickerPresented {
            isQuickAddPickerPresented = false
            DispatchQueue.main.async {
                isQuickAddManagerPresented = true
            }
        } else {
            isQuickAddManagerPresented = true
        }
    }

    func addQuickAddFood(_ item: QuickAddFood) {
        let reviewItem = FoodReviewItem(
            name: item.name,
            subtitle: "Quick Add",
            calories: item.calories,
            nutrientValues: item.nutrientValues,
            servingAmount: item.servingAmount,
            servingUnit: item.servingUnit,
            entrySource: .quickAdd,
            displayedNutrientKeys: nil,
            quickAddID: item.id
        )

        if isQuickAddPickerPresented {
            isQuickAddPickerPresented = false
            DispatchQueue.main.async {
                presentFoodReview(reviewItem)
            }
        } else {
            presentFoodReview(reviewItem)
        }
    }

    func addQuickAddFoods(
        _ selections: [(item: QuickAddFood, quantity: Int, multiplier: Double)],
        dismissPickerAfterAdd: Bool
    ) {
        let now = Date()
        let mealGrp = genericMealGroup(for: now)
        var newEntries: [MealEntry] = []

        for (item, quantity, multiplier) in selections {
            guard quantity > 0 else { continue }
            let normalizedName = MealEntry.normalizedName(item.name)
            let itemEntries = (0..<quantity).map { _ in
                MealEntry(
                    id: UUID(),
                    name: normalizedName,
                    calories: Int((Double(item.calories) * multiplier).rounded()),
                    nutrientValues: item.nutrientValues.mapValues { Int((Double($0) * multiplier).rounded()) },
                    createdAt: now,
                    mealGroup: mealGrp
                )
            }
            newEntries.append(contentsOf: itemEntries)
        }

        guard !newEntries.isEmpty else { return }

        if dismissPickerAfterAdd && isQuickAddPickerPresented {
            isQuickAddPickerPresented = false
        }

        let usedIDs = Set(
            selections
                .filter { $0.quantity > 0 }
                .map(\.item.id)
        )
        markQuickAddFoodsRecentlyUsed(ids: usedIDs)

        withAnimation(.easeInOut(duration: 0.25)) {
            entries.append(contentsOf: newEntries)
        }
        showAddConfirmation()
    }

    /// Saves the food from a review item directly to the quick add list.
    /// Uses the edited name from the review form, and the base serving size (not the user's current selection).
    func addItemToQuickAdd(from item: FoodReviewItem) {
        let now = Date()
        let resolvedName = foodReviewNameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? item.name
            : foodReviewNameText
        let newFood = QuickAddFood(
            id: UUID(),
            name: resolvedName,
            calories: item.calories,
            nutrientValues: item.nutrientValues,
            servingAmount: item.servingAmount,
            servingUnit: item.servingUnit,
            createdAt: now
        )
        quickAddFoods.append(newFood)
        saveQuickAddFoods()
        showQuickAddSaveConfirmation()
    }

    /// Saves a menu item directly to the quick add list.
    func addMenuItemToQuickAdd(_ item: QuickAddFood) {
        quickAddFoods.append(item)
        saveQuickAddFoods()
        showQuickAddSaveConfirmation()
    }

    @MainActor
    func showQuickAddSaveConfirmation() {
        quickAddSaveConfirmationTask?.cancel()
        Haptics.notification(.success)

        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            isQuickAddSaveConfirmationPresented = true
        }

        quickAddSaveConfirmationTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.35))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                isQuickAddSaveConfirmationPresented = false
            }
        }
    }

    /// Updates `lastUsedAt` on matching quick adds without changing their order.
    func markQuickAddFoodsRecentlyUsed(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        let now = Date()
        quickAddFoods = quickAddFoods.map { food in
            ids.contains(food.id) ? food.withLastUsedAt(now) : food
        }
    }

    @MainActor
    func showAddConfirmation() {
        addConfirmationTask?.cancel()
        barcodeErrorToastTask?.cancel()
        barcodeErrorToastMessage = nil
        Haptics.notification(.success)

        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            isAddConfirmationPresented = true
        }

        addConfirmationTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.35))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                isAddConfirmationPresented = false
            }
        }
    }

    @MainActor
    func showBarcodeErrorToast(_ message: String) {
        addConfirmationTask?.cancel()
        withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
            isAddConfirmationPresented = false
        }

        barcodeErrorToastTask?.cancel()
        barcodeErrorToastMessage = message

        barcodeErrorToastTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.35))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                barcodeErrorToastMessage = nil
            }
        }
    }

    func formattedServingAmount(_ amount: Double) -> String {
        formatServingSelectorAmount(amount)
    }

    func formattedDisplayServingAmount(_ amount: Double, unit: String) -> String {
        formattedServingAmount(convertedServingAmount(amount, unit: unit))
    }

    func formattedDisplayServingWithUnit(_ amount: Double, unit: String) -> String {
        let convertedAmount = convertedServingAmount(amount, unit: unit)
        let formattedAmount = formattedServingAmount(convertedAmount)
        let unitText = inflectedUnit(displayServingUnit(for: unit), quantity: convertedAmount)
        return "\(formattedAmount) \(unitText)"
    }

    func displayServingUnit(for unit: String) -> String {
        if isGramUnit(unit) {
            return "g"
        }
        return unit
    }

    func inflectedTextFieldUnit(for unit: String, amountText: String) -> String {
        let displayUnit = displayServingUnit(for: unit)
        guard let amount = parsedDecimalAmount(amountText) else { return displayUnit }
        return inflectedUnit(displayUnit, quantity: amount)
    }

    func inflectedUnit(_ unit: String, quantity: Double) -> String {
        inflectServingUnitToken(unit, quantity: quantity)
    }

    func convertedServingAmount(_ amount: Double, unit: String) -> Double {
        return amount
    }

    func isGramUnit(_ unit: String) -> Bool {
        let normalized = unit.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "g" || normalized == "gram" || normalized == "grams" || normalized == "grms"
    }

    var totalCalories: Int { entries.reduce(0) { $0 + $1.calories } }
    var rawCalorieProgress: Double { Double(totalCalories) / Double(max(calorieGoal, 1)) }
    var calorieProgress: Double { min(Double(totalCalories) / Double(calorieGoal), 1.0) }
    var caloriesLeft: Int { max(calorieGoal - totalCalories, 0) }

    var sortedEntries: [MealEntry] {
        entries.sorted { $0.createdAt > $1.createdAt }
    }

    var groupedTodayEntries: [(group: MealGroup, entries: [FoodLogDisplayEntry])] {
        MealGroup.logDisplayOrder.compactMap { group in
            let groupEntries = aggregatedFoodLogEntries(
                from: sortedEntries.filter { $0.mealGroup == group }
            )
            guard !groupEntries.isEmpty else { return nil }
            return (group, groupEntries)
        }
    }

    func aggregatedFoodLogEntries(from entries: [MealEntry]) -> [FoodLogDisplayEntry] {
        struct GroupedEntry {
            let key: String
            var entries: [MealEntry]
        }

        let grouped = entries.reduce(into: [GroupedEntry]()) { partialResult, entry in
            let key = foodLogAggregationKey(for: entry)
            if let index = partialResult.firstIndex(where: { $0.key == key }) {
                partialResult[index].entries.append(entry)
            } else {
                partialResult.append(GroupedEntry(key: key, entries: [entry]))
            }
        }

        return grouped.map { groupedEntry in
            let sortedGroupEntries = groupedEntry.entries.sorted { $0.createdAt > $1.createdAt }
            let totalCalories = sortedGroupEntries.reduce(0) { $0 + $1.calories }
            let totalNutrients = sortedGroupEntries.reduce(into: [String: Int]()) { partialResult, entry in
                for (key, value) in entry.nutrientValues {
                    partialResult[key, default: 0] += value
                }
            }

            return FoodLogDisplayEntry(
                entries: sortedGroupEntries,
                name: sortedGroupEntries.first?.name ?? "Unnamed food",
                calories: totalCalories,
                nutrientValues: totalNutrients,
                createdAt: sortedGroupEntries.first?.createdAt ?? .distantPast,
                servingCount: sortedGroupEntries.count,
                displayCount: sortedGroupEntries.reduce(0) { partialResult, entry in
                    partialResult + max(entry.loggedCount ?? 1, 1)
                }
            )
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    func foodLogAggregationKey(for entry: MealEntry) -> String {
        "\(entry.mealGroup.rawValue)|\(entry.name.lowercased())"
    }

    var mealDistributionData: [(group: MealGroup, calories: Int)] {
        MealGroup.logDisplayOrder.compactMap { group in
            let calories = entries
                .filter { $0.mealGroup == group }
                .reduce(0) { $0 + $1.calories }
            guard calories > 0 else { return nil }
            return (group, calories)
        }
    }

    func mealDistributionData(for dayIdentifier: String) -> [(group: MealGroup, calories: Int)] {
        let dayEntries = entries(forDayIdentifier: dayIdentifier)
        return MealGroup.logDisplayOrder.compactMap { group in
            let calories = dayEntries
                .filter { $0.mealGroup == group }
                .reduce(0) { $0 + $1.calories }
            guard calories > 0 else { return nil }
            return (group, calories)
        }
    }

    var historicalSortedEntries: [MealEntry] {
        entries(forDayIdentifier: selectedHistoryDayIdentifier).sorted { $0.createdAt > $1.createdAt }
    }

    var archivedDayIdentifiers: [String] {
        dailyEntryArchive.compactMap { key, value in
            value.isEmpty ? nil : key
        }
        .sorted()
    }

    var selectedHistorySummary: HistoryDaySummary {
        historySummary(for: selectedHistoryDayIdentifier)
    }

    var selectedFoodReviewEffectiveMultiplier: Double {
        guard let item = foodReviewItem else { return 1.0 }
        let selectedAmount = roundToServingSelectorIncrement(selectedFoodReviewBaselineAmount * selectedFoodReviewMultiplier)
        let baseAmount = convertedServingAmount(item.servingAmount, unit: item.servingUnit)
        guard baseAmount > 0 else { return 1.0 }
        return max(selectedAmount / baseAmount, 0)
    }

    var selectedFoodReviewTotalMultiplier: Double {
        selectedFoodReviewEffectiveMultiplier * Double(selectedFoodReviewQuantity)
    }


}
