// Calorie Tracker 2026

import SwiftUI

extension ContentView {

    func openAddDestination(_ destination: AddDestination) {
        dismissKeyboard()
        if selectedAddDestination == .pccMenu, destination != .pccMenu {
            clearMenuSelection()
        }
        if destination != .aiPhoto {
            clearAITextMealState()
        }
        selectedAddDestination = destination
        isAddDestinationPickerPresented = false
        withAnimation(.none) {
            selectedTab = .add
        }

        switch destination {
        case .aiPhoto:
            aiFoodPhotoErrorMessage = nil
            aiTextErrorMessage = nil
        case .pccMenu:
            let shouldLoadMenu = prepareMenuDestination(for: .fourWinds)
            if shouldLoadMenu {
                Task {
                    await loadMenuFromFirebase(for: selectedMenuVenue)
                }
            }
        case .usdaSearch:
            usdaSearchError = nil
            hasCompletedUSDASearch = false
        case .barcode:
            hasScannedBarcodeInCurrentSheet = false
            barcodeLookupError = nil
        case .quickAdd, .manualEntry:
            break
        }
    }

    func handleWidgetDeepLink(_ url: URL) {
        guard url.scheme?.lowercased() == "calorietracker" else { return }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        guard components.host?.lowercased() == "open" else { return }
        let destination = components.queryItems?.first(where: { $0.name == "dest" })?.value?.lowercased()

        switch destination {
        case "pcc-menu":
            openAddDestination(.pccMenu)
        case "barcode":
            openAddDestination(.barcode)
        case "ai":
            openAddDestination(.aiPhoto)
        default:
            selectedTab = .today
        }
    }

    func openBarcodeScannerFromPicker() {
        openAddDestination(.barcode)
        hasScannedBarcodeInCurrentSheet = false
        barcodeLookupError = nil
    }

    func clearAITextMealState() {
        aiMealTextInput = ""
        aiTextMealResults = []
        aiTextErrorMessage = nil
        isAITextLoading = false
        clearAITextPlateState()
    }

    func clearMenuSelection() {
        selectedMenuItemQuantitiesByVenue = [:]
        selectedMenuItemMultipliersByVenue = [:]
        selectedMenuType = menuService.currentMenuType()
    }

    @MainActor
    func handleScannedBarcode(_ barcode: String) async {
        guard !isBarcodeLookupInFlight else { return }

        hasScannedBarcodeInCurrentSheet = true
        isBarcodeLookupInFlight = true
        barcodeLookupError = nil

        do {
            let product = try await openFoodFactsService.fetchProduct(for: barcode)
            isBarcodeLookupInFlight = false
            selectedFoodReviewMultiplier = 1.0
            DispatchQueue.main.async {
                openFoodReview(for: product)
            }
            Haptics.notification(.success)
        } catch {
            isBarcodeLookupInFlight = false
            hasScannedBarcodeInCurrentSheet = false
            barcodeLookupError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            showBarcodeErrorToast(barcodeLookupError ?? "Barcode lookup failed.")
            Haptics.notification(.warning)
        }
    }

    enum USDASearchTrigger {
        case automatic
        case manual
    }

    @MainActor
    func scheduleUSDASearch(query: String? = nil, trigger: USDASearchTrigger) async {
        let resolvedQuery = (query ?? usdaSearchText).trimmingCharacters(in: .whitespacesAndNewlines)
        guard resolvedQuery.count >= 2 else {
            latestFoodSearchRequestID += 1
            usdaSearchTask?.cancel()
            foodSearchResults = []
            isUSDASearchLoading = false
            usdaSearchError = nil
            hasCompletedUSDASearch = false
            return
        }

        latestFoodSearchRequestID += 1
        let requestID = latestFoodSearchRequestID
        usdaSearchTask?.cancel()
        usdaSearchTask = Task {
            await runUSDASearch(query: resolvedQuery, requestID: requestID, trigger: trigger)
        }
    }

    @MainActor
    func runUSDASearch(query: String, requestID: Int, trigger: USDASearchTrigger) async {
        isUSDASearchLoading = true
        usdaSearchError = nil

        do {
            let results = try await searchFoodsAcrossSources(query: query)
            guard requestID == latestFoodSearchRequestID else { return }
            foodSearchResults = results
            hasCompletedUSDASearch = true
            Haptics.selection()
        } catch {
            guard requestID == latestFoodSearchRequestID else { return }
            if isCancellationError(error) {
                isUSDASearchLoading = false
                return
            }

            foodSearchResults = []
            hasCompletedUSDASearch = true
            if case USDAFoodError.noResults = error {
                usdaSearchError = nil
            } else if trigger == .automatic, case USDAFoodError.networkFailure = error {
                // Avoid transient connectivity flashes while typing quickly.
                usdaSearchError = nil
            } else {
                usdaSearchError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                Haptics.notification(.warning)
            }
        }

        if requestID == latestFoodSearchRequestID {
            isUSDASearchLoading = false
        }
    }

    func searchFoodsAcrossSources(query: String) async throws -> [FoodSearchResult] {
        let merged = mergeAndRankSearchResults(
            usda: try await searchUSDAResults(query: query),
            query: query
        )
        if merged.isEmpty {
            throw USDAFoodError.noResults
        }
        return merged
    }

    func searchUSDAResults(query: String) async throws -> [USDAFoodSearchResult] {
        if disableUSDASearchForDebug {
            return []
        }
        return try await usdaFoodService.searchFoods(query: query)
    }

    func mergeAndRankSearchResults(
        usda: [USDAFoodSearchResult],
        query: String
    ) -> [FoodSearchResult] {
        let combined = usda.map(mapUSDAResult)
        var bestByKey: [String: (FoodSearchResult, Int)] = [:]

        for result in combined {
            let score = searchRelevanceScore(for: result, query: query)
            guard isSearchResultRelevant(result, query: query, score: score) else {
                continue
            }
            let key = normalizedSearchKey(name: result.name, brand: result.brand)
            if let existing = bestByKey[key], existing.1 >= score {
                continue
            }
            bestByKey[key] = (result, score)
        }

        return bestByKey.values
            .sorted {
                if $0.1 == $1.1 {
                    return $0.0.name.localizedCaseInsensitiveCompare($1.0.name) == .orderedAscending
                }
                return $0.1 > $1.1
            }
            .map(\.0)
            .prefix(25)
            .map { $0 }
    }

    func mapUSDAResult(_ result: USDAFoodSearchResult) -> FoodSearchResult {
        FoodSearchResult(
            id: "usda-\(result.fdcId)",
            source: .usda,
            name: formattedFoodTitle(result.name),
            brand: result.brand,
            calories: result.calories,
            nutrientValues: result.nutrientValues,
            servingAmount: result.servingAmount,
            servingUnit: result.servingUnit,
            servingDescription: result.servingDescription
        )
    }

    func formattedFoodTitle(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return name }
        return trimmed.lowercased().localizedCapitalized
    }

    func searchRelevanceScore(for result: FoodSearchResult, query: String) -> Int {
        let normalizedQuery = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let name = result.name.lowercased()
        let brand = (result.brand ?? "").lowercased()
        let searchable = "\(name) \(brand)"
        let searchWords = splitSearchWords(searchable)
        let tokens = normalizedQuery.split(whereSeparator: \.isWhitespace).map(String.init)

        var score = 0
        if name == normalizedQuery { score += 140 }
        if name.hasPrefix(normalizedQuery) { score += 90 }
        if name.contains(normalizedQuery) { score += normalizedQuery.count >= 4 ? 60 : 28 }
        if searchWords.contains(where: { $0.hasPrefix(normalizedQuery) }) { score += 36 }
        if !brand.isEmpty, brand.contains(normalizedQuery) { score += 24 }

        for token in tokens {
            if name.contains(token) { score += token.count >= 4 ? 22 : 10 }
            if !brand.isEmpty, brand.contains(token) { score += token.count >= 4 ? 10 : 4 }
            if searchWords.contains(where: { $0.hasPrefix(token) }) { score += 16 }
        }

        if result.calories > 0 { score += 8 }
        if (result.nutrientValues["g_protein"] ?? 0) > 0 { score += 6 }
        return score
    }

    func isSearchResultRelevant(_ result: FoodSearchResult, query: String, score: Int) -> Bool {
        let normalizedQuery = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalizedQuery.isEmpty else { return false }

        let name = result.name.lowercased()
        let brand = (result.brand ?? "").lowercased()
        let searchable = "\(name) \(brand)"
        let searchWords = splitSearchWords(searchable)
        if searchWords.contains(where: { $0.hasPrefix(normalizedQuery) }) {
            return true
        }
        if normalizedQuery.count >= 4 && searchable.contains(normalizedQuery) {
            return true
        }

        let tokens = normalizedQuery.split(whereSeparator: \.isWhitespace).map(String.init)
        let longTokens = tokens.filter { $0.count >= 3 }
        let matchedLongTokenCount = longTokens.filter { token in
            searchWords.contains(where: { $0.hasPrefix(token) })
            || (token.count >= 4 && searchable.contains(token))
        }.count

        switch result.source {
        case .usda:
            if longTokens.count <= 1 {
                return matchedLongTokenCount >= 1 && score >= 28
            }
            let requiredLongMatches = min(2, longTokens.count)
            return matchedLongTokenCount >= requiredLongMatches && score >= 34
        case .openFoodFacts:
            return matchedLongTokenCount >= 1 && score >= 20
        }
    }

    func splitSearchWords(_ text: String) -> [String] {
        text
            .components(separatedBy: .alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    func isCancellationError(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        if let urlError = error as? URLError, urlError.code == .cancelled {
            return true
        }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }

    func normalizedSearchKey(name: String, brand: String?) -> String {
        let normalizedName = name
            .lowercased()
            .components(separatedBy: .alphanumerics.inverted)
            .joined()
        let normalizedBrand = (brand ?? "")
            .lowercased()
            .components(separatedBy: .alphanumerics.inverted)
            .joined()
        return "\(normalizedName)|\(normalizedBrand)"
    }

}
