import SwiftUI
import UIKit

struct QuickAddEditorView: View {
    let item: QuickAddFood?
    let trackedNutrientKeys: [String]
    let storedVenueMenus: [DiningVenue: [NutrisliceMenuService.MenuType: NutrisliceMenu]]
    let surfacePrimary: Color
    let surfaceSecondary: Color
    let textPrimary: Color
    let textSecondary: Color
    let accent: Color
    let onSave: (QuickAddFood) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var nameText: String
    @State private var caloriesText: String
    @State private var servingAmountText: String
    @State private var servingUnitText: String
    @State private var nutrientTexts: [String: String]
    @State private var preservedHiddenNutrients: [String: Int]
    @State private var hasImportedServingBaseline: Bool
    @State private var isKeyboardVisible = false
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
    @State private var hasCompletedUSDASearch = false
    @State private var latestFoodSearchRequestID = 0
    @State private var usdaSearchDebounceTask: Task<Void, Never>?
    @State private var usdaSearchTask: Task<Void, Never>?
    @State private var isUSDASearchKeyboardVisible = false

    private let menuService = NutrisliceMenuService()
    private let openFoodFactsService = OpenFoodFactsService()
    private let usdaFoodService = USDAFoodService()

    init(
        item: QuickAddFood?,
        trackedNutrientKeys: [String],
        storedVenueMenus: [DiningVenue: [NutrisliceMenuService.MenuType: NutrisliceMenu]],
        surfacePrimary: Color,
        surfaceSecondary: Color,
        textPrimary: Color,
        textSecondary: Color,
        accent: Color,
        onSave: @escaping (QuickAddFood) -> Void
    ) {
        self.item = item
        self.trackedNutrientKeys = trackedNutrientKeys
        self.storedVenueMenus = storedVenueMenus
        self.surfacePrimary = surfacePrimary
        self.surfaceSecondary = surfaceSecondary
        self.textPrimary = textPrimary
        self.textSecondary = textSecondary
        self.accent = accent
        self.onSave = onSave
        _nameText = State(initialValue: item?.name ?? "")
        _caloriesText = State(initialValue: item.map { $0.calories == 0 ? "" : "\($0.calories)" } ?? "")
        _servingAmountText = State(initialValue: formatServingSelectorAmount(item?.servingAmount ?? 1))
        _servingUnitText = State(initialValue: item?.servingUnit ?? "serving")
        let editableNutrients = QuickAddEditorView.editableNutrientDefinitions(for: item, trackedNutrientKeys: trackedNutrientKeys)
        _nutrientTexts = State(initialValue: editableNutrients.reduce(into: [:]) { partialResult, nutrient in
            let value = item?.nutrientValues[nutrient.key] ?? 0
            partialResult[nutrient.key] = value == 0 ? "" : "\(value)"
        })
        let editableKeys = Set(editableNutrients.map(\.key))
        _preservedHiddenNutrients = State(initialValue: (item?.nutrientValues ?? [:]).filter { !editableKeys.contains($0.key) })
        _hasImportedServingBaseline = State(initialValue: item != nil)
    }

    private var editableNutrients: [NutrientDefinition] {
        Self.editableNutrientDefinitions(for: item, trackedNutrientKeys: trackedNutrientKeys)
    }

    private var isCreatingNewQuickAdd: Bool {
        item == nil
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
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                            }
                            .buttonStyle(
                                QuickAddGhostCapsuleButtonStyle(
                                    surface: surfacePrimary,
                                    text: textPrimary,
                                    stroke: textSecondary
                                )
                            )
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

                        if isCreatingNewQuickAdd {
                            HStack(spacing: 10) {
                                Button {
                                    barcodeLookupError = nil
                                    hasScannedBarcodeInCurrentSheet = false
                                    isBarcodeScannerPresented = true
                                    Haptics.impact(.light)
                                } label: {
                                    Label("Scan Barcode", systemImage: "barcode.viewfinder")
                                        .font(.subheadline.weight(.semibold))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                }
                                .buttonStyle(
                                    QuickAddSecondaryActionButtonStyle(
                                        surface: surfacePrimary,
                                        text: textPrimary,
                                        stroke: textSecondary
                                    )
                                )
                                .disabled(isBarcodeLookupInFlight)

                                Button {
                                    usdaSearchError = nil
                                    usdaSearchResults = []
                                    hasCompletedUSDASearch = false
                                    latestFoodSearchRequestID += 1
                                    usdaSearchText = ""
                                    isUSDASearchLoading = false
                                    usdaSearchDebounceTask?.cancel()
                                    usdaSearchTask?.cancel()
                                    usdaSearchDebounceTask = nil
                                    usdaSearchTask = nil
                                    isUSDASearchPresented = true
                                    Haptics.impact(.light)
                                } label: {
                                    Label("Search Food", systemImage: "magnifyingglass")
                                        .font(.subheadline.weight(.semibold))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                }
                                .buttonStyle(
                                    QuickAddSecondaryActionButtonStyle(
                                        surface: surfacePrimary,
                                        text: textPrimary,
                                        stroke: textSecondary
                                    )
                                )
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
                                    .buttonStyle(
                                        QuickAddVenueChipButtonStyle(
                                            isSelected: selectedMenuVenue == venue,
                                            accent: accent
                                        )
                                    )
                                }
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
                                if shouldPersistImportedServingBaseline {
                                    servingFields
                                }
                            } else if editableNutrients.count.isMultiple(of: 2) {
                                labeledField("Calories") {
                                    TextField("Calories", text: $caloriesText)
                                        .keyboardType(.numberPad)
                                        .inputStyle(surface: surfaceSecondary, text: textPrimary, secondary: textSecondary)
                                }
                                if shouldPersistImportedServingBaseline {
                                    servingFields
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
                                if shouldPersistImportedServingBaseline {
                                    servingFields
                                }
                            }

                            if let errorText = validationError {
                                Text(errorText)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }

                            if let usdaSearchError, isCreatingNewQuickAdd {
                                Text(usdaSearchError)
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }

                            if let menuLoadError, isCreatingNewQuickAdd {
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
                .scrollDismissesKeyboard(.interactively)
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
                .buttonStyle(QuickAddPrimaryButtonStyle(accent: accent))
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
            .interactiveDismissDisabled(isKeyboardVisible)
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
                let endFrame = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect) ?? .zero
                let keyboardHeight = max(0, UIScreen.main.bounds.height - endFrame.origin.y)
                isKeyboardVisible = keyboardHeight > 0
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                isKeyboardVisible = false
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
                        applyImportedFood(
                            name: item.name,
                            calories: item.calories,
                            nutrientValues: item.nutrientValues,
                            servingAmount: item.servingAmount,
                            servingUnit: item.servingUnit
                        )
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

    private var parsedServingAmount: Double? {
        parseServingAmount(servingAmountText)
    }

    private var parsedServingUnit: String? {
        let trimmed = servingUnitText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.isEmpty ? nil : trimmed
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
        guard
            parsedCalories != nil,
            let nutrients = parsedNutrients
        else { return false }
        if shouldPersistImportedServingBaseline &&
            (parsedServingAmount == nil || parsedServingUnit == nil) {
            return false
        }
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
        if shouldPersistImportedServingBaseline &&
            (parsedServingAmount == nil || parsedServingUnit == nil) {
            return "Enter a valid base serving size and unit."
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

    private func parseServingAmount(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return 1 }
        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value > 0 else { return nil }
        return value
    }

    private var shouldPersistImportedServingBaseline: Bool {
        !isCreatingNewQuickAdd || hasImportedServingBaseline
    }

    @MainActor
    private func loadPCCMenu(for venue: DiningVenue) async {
        selectedMenuVenue = venue
        isMenuLoading = true
        menuLoadError = nil
        isMenuImportPresented = true

        let preferredMenuType = menuService.currentMenuType()
        let cachedMenusByType = storedVenueMenus[venue] ?? [:]

        if let preferredMenu = cachedMenusByType[preferredMenuType], !preferredMenu.lines.isEmpty {
            importedMenu = preferredMenu
        } else if let fallbackMenu = menuService
            .allMenuTypes
            .lazy
            .compactMap({ cachedMenusByType[$0] })
            .first(where: { !$0.lines.isEmpty }) {
            importedMenu = fallbackMenu
        } else {
            importedMenu = .empty
            menuLoadError = "No stored PCC menu is available yet for \(venue.title). Open the PCC Menu tab once to cache it."
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
            applyImportedFood(
                name: product.name,
                calories: product.calories,
                nutrientValues: product.nutrientValues,
                servingAmount: product.servingAmount,
                servingUnit: product.servingUnit
            )
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

    private enum USDASearchTrigger {
        case automatic
        case manual
    }

    @MainActor
    private func scheduleUSDASearch(query: String? = nil, trigger: USDASearchTrigger) async {
        let resolvedQuery = (query ?? usdaSearchText).trimmingCharacters(in: .whitespacesAndNewlines)
        guard resolvedQuery.count >= 2 else {
            latestFoodSearchRequestID += 1
            usdaSearchTask?.cancel()
            usdaSearchResults = []
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
    private func runUSDASearch(query: String, requestID: Int, trigger: USDASearchTrigger) async {
        isUSDASearchLoading = true
        usdaSearchError = nil

        do {
            let results = try await usdaFoodService.searchFoods(query: query)
            guard requestID == latestFoodSearchRequestID else { return }
            usdaSearchResults = results
            hasCompletedUSDASearch = true
            Haptics.selection()
        } catch {
            guard requestID == latestFoodSearchRequestID else { return }
            if isCancellationError(error) {
                isUSDASearchLoading = false
                return
            }

            usdaSearchResults = []
            hasCompletedUSDASearch = true
            if case USDAFoodError.noResults = error {
                usdaSearchError = nil
            } else if trigger == .automatic, case USDAFoodError.networkFailure = error {
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

    private func isCancellationError(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        if let urlError = error as? URLError, urlError.code == .cancelled {
            return true
        }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == URLError.cancelled.rawValue
    }

    private func applyImportedFood(
        name: String,
        calories: Int,
        nutrientValues: [String: Int],
        servingAmount: Double? = nil,
        servingUnit: String? = nil
    ) {
        nameText = MealEntry.normalizedName(name)
        caloriesText = calories > 0 ? "\(calories)" : ""
        let editableKeys = Set(editableNutrients.map(\.key))
        preservedHiddenNutrients = nutrientValues.filter { !editableKeys.contains($0.key) }
        for nutrient in editableNutrients {
            let value = nutrientValues[nutrient.key] ?? 0
            nutrientTexts[nutrient.key] = value > 0 ? "\(value)" : ""
        }
        if let servingAmount, servingAmount > 0 {
            let normalizedServingUnit = (servingUnit ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            if !normalizedServingUnit.isEmpty {
                servingAmountText = formatServingSelectorAmount(servingAmount)
                servingUnitText = normalizedServingUnit
                hasImportedServingBaseline = true
            }
        }
        Haptics.notification(.success)
    }

    private func formattedUSDAFoodTitle(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return name }
        return trimmed.lowercased().localizedCapitalized
    }

    private func save() {
        guard
            let calories = parsedCalories,
            let nutrients = parsedNutrients
        else { return }
        let servingAmount: Double
        let servingUnit: String
        if shouldPersistImportedServingBaseline {
            guard
                let parsedServingAmount,
                let parsedServingUnit
            else { return }
            servingAmount = parsedServingAmount
            servingUnit = parsedServingUnit
        } else {
            servingAmount = 1
            servingUnit = "serving"
        }
        let mergedNutrients = preservedHiddenNutrients.merging(nutrients) { _, new in new }
        let saved = QuickAddFood(
            id: item?.id ?? UUID(),
            name: nameText,
            calories: calories,
            nutrientValues: mergedNutrients,
            servingAmount: servingAmount,
            servingUnit: servingUnit,
            createdAt: item?.createdAt ?? Date()
        )
        onSave(saved)
        dismiss()
    }

    private var servingFields: some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                labeledField("Base serving amount", spacing: 8) {
                    TextField("1", text: $servingAmountText)
                        .keyboardType(.decimalPad)
                        .inputStyle(surface: surfaceSecondary, text: textPrimary, secondary: textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                labeledField("Base serving unit", spacing: 8) {
                    TextField("serving", text: $servingUnitText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .inputStyle(surface: surfaceSecondary, text: textPrimary, secondary: textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
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
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                            }
                            .buttonStyle(
                                QuickAddGhostCapsuleButtonStyle(
                                    surface: surfacePrimary,
                                    text: textPrimary,
                                    stroke: textSecondary
                                )
                            )
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
                                    Task { @MainActor in
                                        await scheduleUSDASearch(trigger: .manual)
                                    }
                                }
                                .foregroundStyle(textPrimary)
                            Button {
                                guard !usdaSearchText.isEmpty else { return }
                                latestFoodSearchRequestID += 1
                                usdaSearchText = ""
                                usdaSearchResults = []
                                isUSDASearchLoading = false
                                usdaSearchError = nil
                                hasCompletedUSDASearch = false
                                usdaSearchDebounceTask?.cancel()
                                usdaSearchTask?.cancel()
                                usdaSearchDebounceTask = nil
                                usdaSearchTask = nil
                                Haptics.selection()
                            } label: {
                                Label("Clear search", systemImage: "xmark.circle.fill")
                                    .labelStyle(.iconOnly)
                                    .foregroundStyle(textSecondary)
                                    .opacity(usdaSearchText.isEmpty ? 0.35 : 1)
                                    .frame(width: 24, height: 24)
                            }
                            .buttonStyle(.plain)
                            .disabled(usdaSearchText.isEmpty)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .cardStyle(surface: surfacePrimary.opacity(0.95), stroke: textSecondary.opacity(0.15))

                        if let usdaSearchError {
                            Text(usdaSearchError)
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }

                        if isUSDASearchLoading {
                            HStack(spacing: 10) {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .tint(accent)
                                Text("Searching USDA foods...")
                                    .font(.subheadline)
                                    .foregroundStyle(textSecondary)
                            }
                            .padding(.vertical, 4)
                            .accessibilityIdentifier("quickAdd.usdaSearch.loading")
                        } else if !usdaSearchResults.isEmpty {
                            LazyVStack(spacing: 12) {
                                ForEach(usdaSearchResults) { result in
                                    Button {
                                        let formattedName = formattedUSDAFoodTitle(result.name)
                                        applyImportedFood(
                                            name: formattedName,
                                            calories: result.calories,
                                            nutrientValues: result.nutrientValues,
                                            servingAmount: result.servingAmount,
                                            servingUnit: result.servingUnit
                                        )
                                        isUSDASearchPresented = false
                                    } label: {
                                        HStack(alignment: .top, spacing: 12) {
                                            VStack(alignment: .leading, spacing: 6) {
                                                Text(formattedUSDAFoodTitle(result.name))
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
                        } else if !usdaSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isUSDASearchLoading && usdaSearchError == nil {
                            Text(hasCompletedUSDASearch ? "No results found. Try a broader search term." : "Type to see matching foods.")
                                .font(.subheadline)
                                .foregroundStyle(textSecondary)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                    .padding(.bottom, 32)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
            let endFrame = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect) ?? .zero
            let visibleHeight = max(0, UIScreen.main.bounds.maxY - endFrame.minY)
            isUSDASearchKeyboardVisible = visibleHeight > 20
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isUSDASearchKeyboardVisible = false
        }
        .onDisappear {
            isUSDASearchKeyboardVisible = false
            usdaSearchDebounceTask?.cancel()
            usdaSearchTask?.cancel()
        }
        .interactiveDismissDisabled(isUSDASearchKeyboardVisible)
        .onChange(of: usdaSearchText) { _, newValue in
            usdaSearchDebounceTask?.cancel()
            let query = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard query.count >= 2 else {
                latestFoodSearchRequestID += 1
                usdaSearchTask?.cancel()
                usdaSearchResults = []
                isUSDASearchLoading = false
                usdaSearchError = nil
                hasCompletedUSDASearch = false
                return
            }
            usdaSearchDebounceTask = Task {
                try? await Task.sleep(nanoseconds: 550_000_000)
                guard !Task.isCancelled else { return }
                await scheduleUSDASearch(query: query, trigger: .automatic)
            }
        }
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
}

private struct QuickAddGhostCapsuleButtonStyle: ButtonStyle {
    let surface: Color
    let text: Color
    let stroke: Color

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isEnabled ? text : text.opacity(0.48))
            .frame(minHeight: 44)
            .background(
                Capsule(style: .continuous)
                    .fill(surface.opacity(configuration.isPressed ? 0.86 : 0.94))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(stroke.opacity(isEnabled ? 0.22 : 0.12), lineWidth: 1)
            )
            .shadow(
                color: .black.opacity(configuration.isPressed ? 0.08 : 0.16),
                radius: configuration.isPressed ? 6 : 10,
                y: 4
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct QuickAddSecondaryActionButtonStyle: ButtonStyle {
    let surface: Color
    let text: Color
    let stroke: Color

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isEnabled ? text : text.opacity(0.42))
            .frame(minHeight: 46)
            .background(
                Capsule(style: .continuous)
                    .fill(surface.opacity(configuration.isPressed ? 0.84 : 0.92))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(stroke.opacity(isEnabled ? 0.26 : 0.12), lineWidth: 1)
            )
            .shadow(
                color: .black.opacity(configuration.isPressed ? 0.10 : 0.18),
                radius: configuration.isPressed ? 6 : 12,
                y: 5
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct QuickAddVenueChipButtonStyle: ButtonStyle {
    let isSelected: Bool
    let accent: Color

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let fill = isSelected
            ? accent.opacity(configuration.isPressed ? 0.76 : 0.88)
            : Color.white.opacity(configuration.isPressed ? 0.13 : 0.10)
        let border = isSelected
            ? accent.opacity(isEnabled ? 0.95 : 0.45)
            : Color.white.opacity(isEnabled ? 0.24 : 0.12)

        return configuration.label
            .foregroundStyle(
                isEnabled
                    ? (isSelected ? Color.white : accent)
                    : Color.white.opacity(0.45)
            )
            .frame(minHeight: 44)
            .background(
                Capsule(style: .continuous)
                    .fill(fill)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(border, lineWidth: isSelected ? 1.2 : 1)
            )
            .shadow(
                color: .black.opacity(configuration.isPressed ? 0.05 : (isSelected ? 0.20 : 0.12)),
                radius: isSelected ? 10 : 6,
                y: isSelected ? 5 : 3
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct QuickAddPrimaryButtonStyle: ButtonStyle {
    let accent: Color

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white.opacity(isEnabled ? 1 : 0.62))
            .frame(minHeight: 50)
            .background(
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: primaryColors(pressed: configuration.isPressed),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(isEnabled ? 0.14 : 0.08), lineWidth: 1)
            )
            .shadow(
                color: accent.opacity(isEnabled ? (configuration.isPressed ? 0.28 : 0.40) : 0.0),
                radius: configuration.isPressed ? 10 : 18,
                y: configuration.isPressed ? 4 : 8
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private func primaryColors(pressed: Bool) -> [Color] {
        guard isEnabled else {
            return [Color.white.opacity(0.18), Color.white.opacity(0.14)]
        }
        let top = accent.opacity(pressed ? 0.80 : 0.95)
        let bottom = accent.opacity(pressed ? 0.70 : 0.84)
        return [top, bottom]
    }
}
