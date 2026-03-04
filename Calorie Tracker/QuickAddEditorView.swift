import SwiftUI
import UIKit

struct QuickAddEditorView: View {
    let item: QuickAddFood?
    let trackedNutrientKeys: [String]
    let surfacePrimary: Color
    let surfaceSecondary: Color
    let textPrimary: Color
    let textSecondary: Color
    let accent: Color
    let onSave: (QuickAddFood) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var nameText: String
    @State private var caloriesText: String
    @State private var nutrientTexts: [String: String]
    @State private var preservedHiddenNutrients: [String: Int]
    @State private var selectedMenuVenue: DiningVenue = .fourWinds
    @State private var importedMenu: NutrisliceMenu = .empty
    @State private var isMenuLoading = false
    @State private var menuLoadError: String?
    @State private var isMenuImportPresented = false
    @State private var isBarcodeScannerPresented = false
    @State private var hasScannedBarcodeInCurrentSheet = false
    @State private var isBarcodeLookupInFlight = false
    @State private var barcodeLookupError: String?
    @State private var isUSDASearchPresented = false
    @State private var usdaSearchText = ""
    @State private var usdaSearchResults: [USDAFoodSearchResult] = []
    @State private var isUSDASearchLoading = false
    @State private var usdaSearchError: String?
    @State private var usdaSearchDebounceTask: Task<Void, Never>?

    // Shared PCC menu storage (same as main app)
    @AppStorage("venueMenusData") private var storedVenueMenusData: String = ""
    @AppStorage("venueMenuSignaturesData") private var storedVenueMenuSignaturesData: String = ""

    private let menuService = NutrisliceMenuService()
    private let openFoodFactsService = OpenFoodFactsService()
    private let usdaFoodService = USDAFoodService()

    init(
        item: QuickAddFood?,
        trackedNutrientKeys: [String],
        surfacePrimary: Color,
        surfaceSecondary: Color,
        textPrimary: Color,
        textSecondary: Color,
        accent: Color,
        onSave: @escaping (QuickAddFood) -> Void
    ) {
        self.item = item
        self.trackedNutrientKeys = trackedNutrientKeys
        self.surfacePrimary = surfacePrimary
        self.surfaceSecondary = surfaceSecondary
        self.textPrimary = textPrimary
        self.textSecondary = textSecondary
        self.accent = accent
        self.onSave = onSave
        _nameText = State(initialValue: item?.name ?? "")
        _caloriesText = State(initialValue: item.map { $0.calories == 0 ? "" : "\($0.calories)" } ?? "")
        let editableNutrients = QuickAddEditorView.editableNutrientDefinitions(for: item, trackedNutrientKeys: trackedNutrientKeys)
        _nutrientTexts = State(initialValue: editableNutrients.reduce(into: [:]) { partialResult, nutrient in
            let value = item?.nutrientValues[nutrient.key] ?? 0
            partialResult[nutrient.key] = value == 0 ? "" : "\(value)"
        })
        let editableKeys = Set(editableNutrients.map(\.key))
        _preservedHiddenNutrients = State(initialValue: (item?.nutrientValues ?? [:]).filter { !editableKeys.contains($0.key) })
    }

    private var editableNutrients: [NutrientDefinition] {
        Self.editableNutrientDefinitions(for: item, trackedNutrientKeys: trackedNutrientKeys)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: AppTheme.sheetBackgroundGradient,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack {
                            Button {
                                dismiss()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "chevron.left")
                                        .font(.caption.weight(.bold))
                                    Text("Cancel")
                                        .font(.subheadline.weight(.semibold))
                                }
                                .foregroundStyle(textPrimary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(surfacePrimary.opacity(0.94))
                                )
                                .overlay(
                                    Capsule(style: .continuous)
                                        .stroke(textSecondary.opacity(0.14), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                            Spacer()
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(item == nil ? "New Quick Add" : "Edit Quick Add")
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .foregroundStyle(textPrimary)
                            Text("Save a reusable food for one-tap adding.")
                                .font(.subheadline)
                                .foregroundStyle(textSecondary)
                        }

                        HStack(spacing: 10) {
                            Button {
                                barcodeLookupError = nil
                                hasScannedBarcodeInCurrentSheet = false
                                isBarcodeScannerPresented = true
                                Haptics.impact(.light)
                            } label: {
                                Label("Scan Barcode", systemImage: "barcode.viewfinder")
                                    .font(.caption.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                            }
                            .buttonStyle(.bordered)
                            .tint(Color.white.opacity(0.26))
                            .disabled(isBarcodeLookupInFlight)

                            Button {
                                usdaSearchError = nil
                                usdaSearchResults = []
                                usdaSearchText = ""
                                isUSDASearchPresented = true
                                Haptics.impact(.light)
                            } label: {
                                Label("Search Food", systemImage: "magnifyingglass")
                                    .font(.caption.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                            }
                            .buttonStyle(.bordered)
                            .tint(Color.white.opacity(0.26))
                        }

                        HStack(spacing: 10) {
                            ForEach(DiningVenue.allCases) { venue in
                                Button {
                                    Haptics.impact(.light)
                                    Task {
                                        await loadPCCMenu(for: venue)
                                    }
                                } label: {
                                    Text(venue.title)
                                        .font(.caption.weight(.semibold))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.82)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                }
                                .buttonStyle(.bordered)
                                .tint(accent)
                            }
                        }

                        VStack(alignment: .leading, spacing: 14) {
                            labeledField("Food name") {
                                TextField("Food name", text: $nameText)
                                    .inputStyle(surface: surfaceSecondary, text: textPrimary, secondary: textSecondary)
                            }

                            if editableNutrients.isEmpty {
                                labeledField("Calories") {
                                    TextField("Calories", text: $caloriesText)
                                        .keyboardType(.numberPad)
                                        .inputStyle(surface: surfaceSecondary, text: textPrimary, secondary: textSecondary)
                                }
                            } else if editableNutrients.count.isMultiple(of: 2) {
                                labeledField("Calories") {
                                    TextField("Calories", text: $caloriesText)
                                        .keyboardType(.numberPad)
                                        .inputStyle(surface: surfaceSecondary, text: textPrimary, secondary: textSecondary)
                                }

                                Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                                    ForEach(Array(stride(from: 0, to: editableNutrients.count, by: 2)), id: \.self) { startIndex in
                                        GridRow {
                                            quickAddNutrientGridCell(at: startIndex)
                                            quickAddNutrientGridCell(at: startIndex + 1)
                                        }
                                    }
                                }
                            } else {
                                Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                                    GridRow {
                                        labeledField("Calories") {
                                            TextField("Calories", text: $caloriesText)
                                                .keyboardType(.numberPad)
                                                .inputStyle(surface: surfaceSecondary, text: textPrimary, secondary: textSecondary)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        quickAddNutrientGridCell(at: 0)
                                    }
                                    ForEach(Array(stride(from: 1, to: editableNutrients.count, by: 2)), id: \.self) { startIndex in
                                        GridRow {
                                            quickAddNutrientGridCell(at: startIndex)
                                            quickAddNutrientGridCell(at: startIndex + 1)
                                        }
                                    }
                                }
                            }

                            if let errorText = validationError {
                                Text(errorText)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }

                            if let usdaSearchError {
                                Text(usdaSearchError)
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }

                            if let menuLoadError {
                                Text(menuLoadError)
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                        .padding(18)
                        .cardStyle(surface: surfacePrimary, stroke: textSecondary.opacity(0.15))
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                    .padding(.bottom, 120)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    save()
                } label: {
                    Text("Save Quick Add")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
                .disabled(!canSave)
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 12)
                .background(
                    ZStack {
                        Rectangle().fill(.ultraThinMaterial)
                        LinearGradient(
                            colors: [surfacePrimary.opacity(0.24), surfacePrimary.opacity(0.96)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                    .ignoresSafeArea(edges: .bottom)
                )
            }
            .sheet(isPresented: $isMenuImportPresented) {
                QuickAddMenuImportView(
                    menu: $importedMenu,
                    sourceTitle: selectedMenuVenue.title,
                    mealTitle: menuService.currentMenuType().title,
                    isLoading: $isMenuLoading,
                    errorMessage: $menuLoadError,
                    surfacePrimary: surfacePrimary,
                    surfaceSecondary: surfaceSecondary,
                    textPrimary: textPrimary,
                    textSecondary: textSecondary,
                    accent: accent,
                    onRetry: {
                        await loadPCCMenu(for: selectedMenuVenue)
                    },
                    onSelect: { item in
                        applyImportedFood(name: item.name, calories: item.calories, nutrientValues: item.nutrientValues)
                        isMenuImportPresented = false
                    }
                )
            }
            .sheet(isPresented: $isBarcodeScannerPresented, onDismiss: {
                hasScannedBarcodeInCurrentSheet = false
            }) {
                quickAddBarcodeScannerSheet
            }
            .sheet(isPresented: $isUSDASearchPresented) {
                quickAddUSDASearchSheet
            }
        }
    }

    private func quickAddNutrientGridCell(at index: Int) -> some View {
        let nutrient = editableNutrients[index]
        return labeledField("\(nutrient.name) (\(nutrient.unit))", spacing: 8) {
            TextField("\(nutrient.name) (\(nutrient.unit))", text: nutrientBinding(for: nutrient.key))
                .keyboardType(.numberPad)
                .inputStyle(surface: surfaceSecondary, text: textPrimary, secondary: textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var parsedCalories: Int? {
        parseInput(caloriesText)
    }

    private var parsedNutrients: [String: Int]? {
        var result: [String: Int] = [:]
        for nutrient in editableNutrients {
            guard let parsed = parseInput(nutrientTexts[nutrient.key] ?? "") else {
                return nil
            }
            result[nutrient.key] = parsed
        }
        return result
    }

    private var canSave: Bool {
        guard parsedCalories != nil, let nutrients = parsedNutrients else { return false }
        return (parsedCalories ?? 0) + nutrients.values.reduce(0, +) > 0 &&
            !nameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var validationError: String? {
        let hasAnyText = !nameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !caloriesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            nutrientTexts.values.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        guard hasAnyText else { return nil }
        if nameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Enter a food name."
        }
        guard parsedCalories != nil, parsedNutrients != nil else {
            return "Use non-negative whole numbers."
        }
        return canSave ? nil : "Enter calories or nutrients above 0."
    }

    private func nutrientBinding(for key: String) -> Binding<String> {
        Binding(
            get: { nutrientTexts[key] ?? "" },
            set: { nutrientTexts[key] = $0 }
        )
    }

    private func labeledField<Content: View>(_ title: String, spacing: CGFloat = 6, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: spacing) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(textSecondary)
            content()
        }
    }

    private func parseInput(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return 0 }
        guard let value = Int(trimmed), value >= 0 else { return nil }
        return value
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func save() {
        guard let calories = parsedCalories, let nutrients = parsedNutrients else { return }
        let mergedNutrients = preservedHiddenNutrients.merging(nutrients) { _, new in new }
        let saved = QuickAddFood(
            id: item?.id ?? UUID(),
            name: nameText,
            calories: calories,
            nutrientValues: mergedNutrients,
            createdAt: item?.createdAt ?? Date()
        )
        onSave(saved)
        dismiss()
    }

    @MainActor
    private func loadPCCMenu(for venue: DiningVenue) async {
        selectedMenuVenue = venue
        isMenuLoading = true
        menuLoadError = nil
        isMenuImportPresented = true
        // Decode existing shared menus and signatures
        var menus = decodedVenueMenus()
        var signatures = decodedVenueMenuSignatures()
        let currentSignature = menuService.currentMenuSignature(for: venue)

        if let cached = menus[venue],
           let lastSignature = signatures[venue],
           lastSignature == currentSignature,
           !cached.lines.isEmpty {
            // Use cached menu for this venue
            importedMenu = cached
            isMenuLoading = false
            return
        }

        func performFetch() async throws {
            let menu = try await menuService.fetchTodayMenu(for: venue)
            importedMenu = menu
            menus[venue] = menu
            signatures[venue] = currentSignature
            encodeVenueMenus(menus, signatures: signatures)
        }

        do {
            try await performFetch()
        } catch {
            // If Nutrislice reports "no menu available" but we have no cache yet,
            // retry once before surfacing the error – this avoids the "first tap
            // shows no menu, second tap works" glitch.
            if let nutrisliceError = error as? NutrisliceMenuError,
               case .noMenuAvailable = nutrisliceError,
               (menus[venue]?.lines.isEmpty ?? true) {
                do {
                    try await Task.sleep(nanoseconds: 300_000_000) // 0.3s backoff
                    try await performFetch()
                    isMenuLoading = false
                    return
                } catch {
                    importedMenu = menus[venue] ?? .empty
                    menuLoadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }
            } else {
                importedMenu = menus[venue] ?? .empty
                menuLoadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }

        isMenuLoading = false
    }

    @MainActor
    private func handleScannedBarcode(_ barcode: String) async {
        guard !isBarcodeLookupInFlight else { return }

        hasScannedBarcodeInCurrentSheet = true
        isBarcodeLookupInFlight = true
        barcodeLookupError = nil

        do {
            let product = try await openFoodFactsService.fetchProduct(for: barcode)
            applyImportedFood(name: product.name, calories: product.calories, nutrientValues: product.nutrientValues)
            isBarcodeLookupInFlight = false
            hasScannedBarcodeInCurrentSheet = false
            isBarcodeScannerPresented = false
            Haptics.notification(.success)
        } catch {
            isBarcodeLookupInFlight = false
            hasScannedBarcodeInCurrentSheet = false
            barcodeLookupError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            Haptics.notification(.warning)
        }
    }

    // MARK: - Shared PCC menu storage helpers

    private func decodedVenueMenus() -> [DiningVenue: NutrisliceMenu] {
        guard
            !storedVenueMenusData.isEmpty,
            let data = storedVenueMenusData.data(using: .utf8),
            let decoded = try? JSONDecoder().decode([DiningVenue: NutrisliceMenu].self, from: data)
        else {
            return [:]
        }
        return decoded
    }

    private func decodedVenueMenuSignatures() -> [DiningVenue: String] {
        guard
            !storedVenueMenuSignaturesData.isEmpty,
            let data = storedVenueMenuSignaturesData.data(using: .utf8),
            let decoded = try? JSONDecoder().decode([DiningVenue: String].self, from: data)
        else {
            return [:]
        }
        return decoded
    }

    private func encodeVenueMenus(_ menus: [DiningVenue: NutrisliceMenu], signatures: [DiningVenue: String]) {
        if let data = try? JSONEncoder().encode(menus) {
            storedVenueMenusData = String(decoding: data, as: UTF8.self)
        }
        if let data = try? JSONEncoder().encode(signatures) {
            storedVenueMenuSignaturesData = String(decoding: data, as: UTF8.self)
        }
    }

    @MainActor
    private func performUSDASearch() async {
        guard !isUSDASearchLoading else { return }

        isUSDASearchLoading = true
        usdaSearchError = nil

        do {
            usdaSearchResults = try await usdaFoodService.searchFoods(query: usdaSearchText)
            Haptics.selection()
        } catch {
            usdaSearchResults = []
            usdaSearchError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            Haptics.notification(.warning)
        }

        isUSDASearchLoading = false
    }

    private func applyImportedFood(name: String, calories: Int, nutrientValues: [String: Int]) {
        nameText = MealEntry.normalizedName(name)
        caloriesText = calories > 0 ? "\(calories)" : ""
        let editableKeys = Set(editableNutrients.map(\.key))
        preservedHiddenNutrients = nutrientValues.filter { !editableKeys.contains($0.key) }
        for nutrient in editableNutrients {
            let value = nutrientValues[nutrient.key] ?? 0
            nutrientTexts[nutrient.key] = value > 0 ? "\(value)" : ""
        }
        Haptics.notification(.success)
    }

    static func editableNutrientDefinitions(for item: QuickAddFood?, trackedNutrientKeys: [String]) -> [NutrientDefinition] {
        let tracked = Set(trackedNutrientKeys.map { $0.lowercased() })
        let stored = Set(
            (item?.nutrientValues ?? [:]).compactMap { key, value in
                let normalized = key.lowercased()
                return value > 0 ? normalized : nil
            }
        )
        let keys = tracked.union(stored)
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

    private var quickAddBarcodeScannerSheet: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: AppTheme.sheetBackgroundGradient,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                BarcodeScannerView(
                    onScan: { code in
                        Task {
                            await handleScannedBarcode(code)
                        }
                    },
                    didScan: hasScannedBarcodeInCurrentSheet
                )
                .ignoresSafeArea()

                if isBarcodeLookupInFlight {
                    VStack(spacing: 14) {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(1.15)
                        Text("Looking up nutrition data...")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 18)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.black.opacity(0.70))
                    )
                }

                VStack {
                    Spacer()

                    if let barcodeLookupError {
                        quickAddBarcodeErrorToast(message: barcodeLookupError)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 24)
                .allowsHitTesting(false)
            }
            .navigationTitle("Scan Barcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        isBarcodeScannerPresented = false
                    }
                    .foregroundStyle(.white)
                }
            }
        }
    }

    private func quickAddBarcodeErrorToast(message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(Color.orange)
            Text(message)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(textPrimary)
                .lineLimit(2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Capsule(style: .continuous)
                .fill(surfacePrimary.opacity(0.98))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(textSecondary.opacity(0.16), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.2), radius: 18, y: 8)
        .padding(.bottom, 124)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var quickAddUSDASearchSheet: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: AppTheme.sheetBackgroundGradient,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack {
                            Button {
                                isUSDASearchPresented = false
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "chevron.left")
                                        .font(.caption.weight(.bold))
                                    Text("Close")
                                        .font(.subheadline.weight(.semibold))
                                }
                                .foregroundStyle(textPrimary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(surfacePrimary.opacity(0.94))
                                )
                                .overlay(
                                    Capsule(style: .continuous)
                                        .stroke(textSecondary.opacity(0.14), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                            Spacer()
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Search Food")
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .foregroundStyle(textPrimary)
                            Text("Search USDA FoodData Central")
                                .font(.subheadline)
                                .foregroundStyle(textSecondary)
                        }

                        HStack(spacing: 10) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(textSecondary)
                            TextField("Search foods", text: $usdaSearchText)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .submitLabel(.search)
                                .onSubmit {
                                    Task {
                                        await performUSDASearch()
                                    }
                                }
                                .foregroundStyle(textPrimary)
                            if !usdaSearchText.isEmpty {
                                Button {
                                    usdaSearchText = ""
                                    usdaSearchResults = []
                                    usdaSearchError = nil
                                    usdaSearchDebounceTask?.cancel()
                                    usdaSearchDebounceTask = nil
                                    Haptics.selection()
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(textSecondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .cardStyle(surface: surfacePrimary.opacity(0.95), stroke: textSecondary.opacity(0.15))

                        Button {
                            Task {
                                await performUSDASearch()
                            }
                        } label: {
                            if isUSDASearchLoading {
                                ProgressView()
                                    .tint(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                            } else {
                                Text("Search")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(accent)
                        .disabled(isUSDASearchLoading)

                        if let usdaSearchError {
                            Text(usdaSearchError)
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }

                        LazyVStack(spacing: 12) {
                            ForEach(usdaSearchResults) { result in
                                Button {
                                    applyImportedFood(name: result.name, calories: result.calories, nutrientValues: result.nutrientValues)
                                    isUSDASearchPresented = false
                                } label: {
                                    HStack(alignment: .top, spacing: 12) {
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(result.name)
                                                .font(.headline.weight(.semibold))
                                                .foregroundStyle(textPrimary)
                                            Text("\(result.calories) cal")
                                                .font(.caption)
                                                .foregroundStyle(textSecondary)
                                        }
                                        Spacer()
                                    }
                                    .padding(16)
                                    .background(
                                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                            .fill(surfacePrimary.opacity(0.95))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                            .stroke(textSecondary.opacity(0.12), lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                    .padding(.bottom, 32)
                }
            }
        }
        .onChange(of: usdaSearchText) { _, newValue in
            usdaSearchDebounceTask?.cancel()
            let query = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else {
                usdaSearchResults = []
                usdaSearchError = nil
                return
            }
            usdaSearchDebounceTask = Task {
                try? await Task.sleep(nanoseconds: 400_000_000)
                guard !Task.isCancelled else { return }
                await performUSDASearch()
            }
        }
    }
}
