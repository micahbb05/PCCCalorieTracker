import SwiftUI

struct QuickAddPickerView: View {
    private struct ServingSheetContext: Identifiable {
        let id = UUID()
        let item: QuickAddFood
    }

    let quickAddFoods: [QuickAddFood]
    let surfacePrimary: Color
    let surfaceSecondary: Color
    let textPrimary: Color
    let textSecondary: Color
    let accent: Color
    let trackedNutrientKeys: [String]
    let onAddSelected: ([(item: QuickAddFood, quantity: Int, multiplier: Double)]) -> Void
    let onManage: (() -> Void)?
    let onClose: (() -> Void)?
    let showsStandaloneChrome: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var searchText = ""
    @State private var selectedQuantitiesByID: [UUID: Int] = [:]
    @State private var selectedServingMultiplierByID: [UUID: Double] = [:]

    @State private var servingSheetContext: ServingSheetContext?
    @State private var servingSliderBaselineByItemId: [UUID: Double] = [:]
    @State private var servingSliderValueByItemId: [UUID: Double] = [:]

    private var filteredFoods: [QuickAddFood] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return quickAddFoods }
        return quickAddFoods.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }

    private var selectedCount: Int {
        selectedQuantitiesByID.values.reduce(0, +)
    }

    private var isSelectionActionEnabled: Bool {
        selectedCount > 0
    }

    private var selectedFoodsAndQuantities: [(item: QuickAddFood, quantity: Int, multiplier: Double)] {
        quickAddFoods.compactMap { item in
            let quantity = selectedQuantitiesByID[item.id] ?? 0
            guard quantity > 0 else { return nil }
            return (item, quantity, multiplier(for: item.id))
        }
    }

    private var backgroundTop: Color {
        colorScheme == .dark ? Color(red: 0.059, green: 0.051, blue: 0.039) : Color(red: 0.97, green: 0.95, blue: 0.92)
    }

    private var backgroundBottom: Color {
        colorScheme == .dark ? Color(red: 0.078, green: 0.063, blue: 0.039) : Color(red: 0.93, green: 0.90, blue: 0.86)
    }

    var body: some View {
        Group {
            if showsStandaloneChrome {
                NavigationStack {
                    ZStack {
                        LinearGradient(
                            colors: AppTheme.sheetBackgroundGradient,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .ignoresSafeArea()

                        scrollContent
                    }
                }
            } else {
                scrollContent
            }
        }
        .sheet(item: $servingSheetContext, onDismiss: {
            servingSheetContext = nil
        }) { context in
            QuickAddServingSheetView(
                item: context.item,
                initialBaseline: servingSliderBaselineByItemId[context.item.id],
                initialSlider: servingSliderValueByItemId[context.item.id],
                initialMultiplier: selectedServingMultiplierByID[context.item.id] ?? 1.0,
                trackedNutrientKeys: trackedNutrientKeys,
                surfacePrimary: surfacePrimary,
                surfaceSecondary: surfaceSecondary,
                textPrimary: textPrimary,
                textSecondary: textSecondary,
                accent: accent
            ) { effectiveMultiplier, baseline, sliderValue in
                applyServingSelection(
                    for: context.item.id,
                    effectiveMultiplier: effectiveMultiplier,
                    baseline: baseline,
                    sliderValue: sliderValue
                )
            } onDismiss: {
                servingSheetContext = nil
            }
        }
    }

    /// Title, caption, actions, and search stay fixed; only the food list scrolls.
    private var scrollContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                if showsStandaloneChrome {
                    HStack {
                        Button {
                            if let onClose {
                                onClose()
                            } else {
                                dismiss()
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "chevron.left")
                                    .font(.caption.weight(.bold))
                                Text(onClose == nil ? "Close" : "Back")
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
                }
                headerRow

                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(textSecondary)
                    TextField("Search quick add foods", text: $searchText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .foregroundStyle(textPrimary)
                    Button {
                        guard !searchText.isEmpty else { return }
                        searchText = ""
                        Haptics.selection()
                    } label: {
                        Label("Clear search", systemImage: "xmark.circle.fill")
                            .labelStyle(.iconOnly)
                            .foregroundStyle(textSecondary)
                            .opacity(searchText.isEmpty ? 0.35 : 1)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .disabled(searchText.isEmpty)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .cardStyle(surface: surfacePrimary.opacity(0.95), stroke: textSecondary.opacity(0.18))
            }
            .padding(.horizontal, 16)
            .padding(.top, showsStandaloneChrome ? 18 : 12)
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(backgroundTop)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if filteredFoods.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(quickAddFoods.isEmpty ? "No quick add foods yet." : "No quick add foods match your search.")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(textPrimary)
                            Text(quickAddFoods.isEmpty ? "Tap settings to create your first quick add food." : "Try a broader search term.")
                                .font(.subheadline)
                                .foregroundStyle(textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(18)
                        .cardStyle(surface: surfacePrimary.opacity(0.95), stroke: textSecondary.opacity(0.18))
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(filteredFoods) { item in
                                quickAddItemRow(item)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: quickAddFoods) { _, _ in
            pruneUnavailableSelections()
        }
    }

    private var compactHeaderActions: some View {
        HStack(spacing: 10) {
            if let onManage {
                Button {
                    onManage()
                    Haptics.impact(.light)
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(textPrimary)
                        .frame(width: 40, height: 40)
                        .background(
                            Circle()
                                .fill(surfaceSecondary.opacity(0.98))
                        )
                        .overlay(
                            Circle()
                                .stroke(textSecondary.opacity(0.18), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }

            compactAddSelectedButton
        }
    }

    private var headerRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 14) {
                Text("Quick Add")
                    .font(.system(size: 32, weight: .bold, design: .default))
                    .foregroundStyle(textPrimary)

                Spacer(minLength: 8)

                compactHeaderActions
                    .padding(.top, 2)
            }

            Text("Add one of your saved foods.")
                .font(.subheadline)
                .foregroundStyle(textSecondary)
        }
    }

    private var compactAddSelectedButton: some View {
        Button {
            guard selectedCount > 0 else {
                Haptics.notification(.warning)
                return
            }
            Haptics.impact(.medium)
            onAddSelected(selectedFoodsAndQuantities)
            let selectedIDs = Set(selectedFoodsAndQuantities.map { $0.item.id })
            selectedQuantitiesByID.removeAll()
            for id in selectedIDs {
                selectedServingMultiplierByID.removeValue(forKey: id)
                servingSliderBaselineByItemId.removeValue(forKey: id)
                servingSliderValueByItemId.removeValue(forKey: id)
            }
        } label: {
            HStack(spacing: 8) {
                Text("Add")
                    .font(.subheadline.weight(.semibold))

                Text("\(selectedCount)")
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous)
                            .fill(.white.opacity(0.14))
                    )
            }
            .foregroundStyle(isSelectionActionEnabled ? .white : textSecondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelectionActionEnabled ? accent : surfaceSecondary.opacity(0.98))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(
                        isSelectionActionEnabled ? Color.clear : textSecondary.opacity(0.18),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func quickAddItemRow(_ item: QuickAddFood) -> some View {
        let currentMultiplier = multiplier(for: item.id)
        let displayedCalories = Int((Double(item.calories) * currentMultiplier).rounded())
        let displayedProtein = Int((Double(item.nutrientValues["g_protein"] ?? 0) * currentMultiplier).rounded())

        return HStack(alignment: .center, spacing: 12) {
            FoodLogIconView(token: FoodIconMLMapper.icon(for: item.name), accent: accent, size: 30)
                .frame(width: 36, height: 36, alignment: .center)

            VStack(alignment: .leading, spacing: 6) {
                Text(item.name)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(textPrimary)
                HStack(spacing: 6) {
                    Text("\(displayedCalories) cal • \(displayedProtein)g protein")
                    if abs(currentMultiplier - 1.0) > 0.001 {
                        Text(formattedDisplayServingWithUnit(item.servingAmount * currentMultiplier, unit: item.servingUnit))
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.cyan)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(.cyan.opacity(0.14))
                            )
                    }
                }
                .font(.caption)
                .foregroundStyle(textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                openServingSheet(for: item)
            }

            Spacer()

            HStack(spacing: 10) {
                Button {
                    decrement(item.id)
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white.opacity(quantity(for: item.id) > 0 ? 0.92 : 0.35))
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(Color.white.opacity(quantity(for: item.id) > 0 ? 0.10 : 0.05))
                        )
                }
                .buttonStyle(.plain)
                .disabled(quantity(for: item.id) == 0)

                Text("\(quantity(for: item.id))")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .frame(minWidth: 28)
                    .foregroundStyle(textPrimary)

                Button {
                    increment(item.id)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white.opacity(0.96))
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(accent)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )
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

    private func quantity(for id: UUID) -> Int {
        max(selectedQuantitiesByID[id] ?? 0, 0)
    }

    private func multiplier(for id: UUID) -> Double {
        selectedServingMultiplierByID[id] ?? 1.0
    }

    private func increment(_ id: UUID) {
        selectedQuantitiesByID[id] = min(quantity(for: id) + 1, 99)
        if selectedServingMultiplierByID[id] == nil {
            selectedServingMultiplierByID[id] = 1.0
        }
        Haptics.selection()
    }

    private func decrement(_ id: UUID) {
        let next = quantity(for: id) - 1
        if next <= 0 {
            selectedQuantitiesByID.removeValue(forKey: id)
            selectedServingMultiplierByID.removeValue(forKey: id)
            servingSliderBaselineByItemId.removeValue(forKey: id)
            servingSliderValueByItemId.removeValue(forKey: id)
        } else {
            selectedQuantitiesByID[id] = next
        }
        Haptics.selection()
    }

    private func openServingSheet(for item: QuickAddFood) {
        dismissKeyboard()
        servingSheetContext = nil
        Haptics.impact(.light)
        DispatchQueue.main.async {
            servingSheetContext = ServingSheetContext(item: item)
        }
    }

    private func applyServingSelection(
        for id: UUID,
        effectiveMultiplier: Double,
        baseline: Double,
        sliderValue: Double
    ) {
        // Close first so the dismissal animation is not competing with heavy list re-render work.
        servingSheetContext = nil
        DispatchQueue.main.async {
            selectedServingMultiplierByID[id] = effectiveMultiplier
            servingSliderBaselineByItemId[id] = baseline
            servingSliderValueByItemId[id] = sliderValue
            if selectedQuantitiesByID[id] == nil || selectedQuantitiesByID[id] == 0 {
                selectedQuantitiesByID[id] = 1
            }
        }
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func formattedDisplayServingWithUnit(_ amount: Double, unit: String) -> String {
        let formattedAmount = formatServingSelectorAmount(amount)
        let displayUnit = quickAddIsGramUnit(unit) ? "g" : unit
        let unitText = inflectServingUnitToken(displayUnit, quantity: amount)
        return "\(formattedAmount) \(unitText)"
    }

    private func quickAddIsGramUnit(_ unit: String) -> Bool {
        let n = unit.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return n == "g" || n == "gram" || n == "grams" || n == "grms"
    }

    private func pruneUnavailableSelections() {
        let availableIDs = Set(quickAddFoods.map(\.id))
        selectedQuantitiesByID = selectedQuantitiesByID.filter { availableIDs.contains($0.key) && $0.value > 0 }
        selectedServingMultiplierByID = selectedServingMultiplierByID.filter { availableIDs.contains($0.key) && $0.value > 0 }
        servingSliderBaselineByItemId = servingSliderBaselineByItemId.filter { availableIDs.contains($0.key) }
        servingSliderValueByItemId = servingSliderValueByItemId.filter { availableIDs.contains($0.key) }
    }
}

// MARK: - Serving sheet (isolated so its state doesn't re-render the picker list)

struct QuickAddServingSheetView: View {
    let item: QuickAddFood
    let initialBaseline: Double?
    let initialSlider: Double?
    let initialMultiplier: Double
    let trackedNutrientKeys: [String]
    let surfacePrimary: Color
    let surfaceSecondary: Color
    let textPrimary: Color
    let textSecondary: Color
    let accent: Color
    let onConfirm: (_ effectiveMultiplier: Double, _ baseline: Double, _ sliderValue: Double) -> Void
    let onDismiss: () -> Void

    private let minMultiplier = 0.25
    private let maxMultiplier = 1.75
    private let multiplierStep = 0.25

    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedMultiplierValue = 1.0
    @State private var selectedServingBaselineAmount = 1.0
    @State private var selectedServingAmountText = ""
    @State private var isUpdatingServingTextFromSlider = false
    @State private var isServingKeyboardVisible = false
    @FocusState private var isServingAmountFieldFocused: Bool

    private var backgroundTop: Color {
        colorScheme == .dark ? Color(red: 0.059, green: 0.051, blue: 0.039) : Color(red: 0.97, green: 0.95, blue: 0.92)
    }

    private var backgroundBottom: Color {
        colorScheme == .dark ? Color(red: 0.078, green: 0.063, blue: 0.039) : Color(red: 0.93, green: 0.90, blue: 0.86)
    }

    private var effectiveMultiplier: Double {
        let baseAmount = item.servingAmount
        guard baseAmount > 0 else { return 1.0 }
        let selectedAmount = roundToServingSelectorIncrement(selectedServingBaselineAmount * selectedMultiplierValue)
        return max(selectedAmount / baseAmount, 0)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [backgroundTop, backgroundBottom],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Adjust Serving")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(accent)

                            Text(item.name)
                                .font(.system(size: 28, weight: .bold, design: .default))
                                .foregroundStyle(textPrimary)
                                .lineLimit(3)
                                .fixedSize(horizontal: false, vertical: true)

                            Text("Base serve: \(formattedDisplayServingWithUnit(item.servingAmount, unit: item.servingUnit))")
                                .font(.subheadline)
                                .foregroundStyle(textSecondary)
                        }

                        if isCountBased(item: item) {
                            countServingControl
                        } else {
                            sliderServingControl
                        }

                        ServingNutrientGridCard(
                            title: "Nutrition Info",
                            calories: item.calories,
                            nutrientValues: item.nutrientValues,
                            multiplier: effectiveMultiplier,
                            trackedNutrientKeys: trackedNutrientKeys,
                            displayedNutrientKeys: nil,
                            surface: surfacePrimary.opacity(0.95),
                            stroke: textSecondary.opacity(0.18),
                            titleColor: textPrimary,
                            labelColor: textSecondary,
                            valueColor: textPrimary
                        )
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 120)
                }
                .scrollBounceBehavior(.always)
                .scrollDismissesKeyboard(.interactively)
                .scrollIndicators(.hidden)
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    confirmServing()
                } label: {
                    Text("Set Serving Size")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
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
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { onDismiss() } label: {
                        Image(systemName: "chevron.left")
                    }
                    .foregroundStyle(textPrimary)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
                let endFrame = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect) ?? .zero
                let visibleHeight = max(0, UIScreen.main.bounds.maxY - endFrame.minY)
                isServingKeyboardVisible = visibleHeight > 20
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                isServingKeyboardVisible = false
            }
            .onAppear {
                isServingKeyboardVisible = false
                isServingAmountFieldFocused = false
                initializeState()
            }
            .onDisappear {
                isServingKeyboardVisible = false
            }
            .onChange(of: selectedMultiplierValue) { _, _ in
                if !isServingAmountFieldFocused { syncAmountText() }
            }
            .onChange(of: selectedServingBaselineAmount) { _, _ in
                if !isServingAmountFieldFocused { syncAmountText() }
            }
            .onChange(of: selectedServingAmountText) { _, newValue in
                if isCountBased(item: item) {
                    applyTypedCountServing(newValue)
                } else {
                    applyTypedServing(text: newValue)
                }
            }
            .interactiveDismissDisabled(isServingKeyboardVisible)
        }
    }

    private var sliderServingControl: some View {
        VStack(alignment: .leading, spacing: 14) {
            let minAmt = formattedServingAmount(selectedServingBaselineAmount * minMultiplier)
            let maxAmt = formattedServingAmount(selectedServingBaselineAmount * maxMultiplier)
            let displayUnit = isGramUnit(item.servingUnit) ? "g" : item.servingUnit
            let minUnit = inflectServingUnitToken(displayUnit, quantity: selectedServingBaselineAmount * minMultiplier)
            let maxUnit = inflectServingUnitToken(displayUnit, quantity: selectedServingBaselineAmount * maxMultiplier)
            HStack {
                Text("\(minAmt) \(minUnit)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(textSecondary)
                Spacer()
                Text("\(maxAmt) \(maxUnit)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(textSecondary)
            }

            HorizontalServeSlider(
                value: $selectedMultiplierValue,
                range: minMultiplier...maxMultiplier,
                step: multiplierStep
            ) {
                Haptics.selection()
            }
            .frame(height: 52)

            VStack(alignment: .leading, spacing: 8) {
                Text("Serve")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(textSecondary)

                TextField("", text: $selectedServingAmountText)
                    .keyboardType(.decimalPad)
                    .focused($isServingAmountFieldFocused)
                    .padding(.trailing, 52)
                    .inputStyle(surface: surfaceSecondary, text: textPrimary, secondary: textSecondary)
                    .overlay(alignment: .trailing) {
                        Text(inflectedTextFieldUnit(for: item.servingUnit, amountText: selectedServingAmountText))
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(textSecondary)
                            .padding(.trailing, 14)
                            .allowsHitTesting(false)
                    }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(surfacePrimary.opacity(0.94))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(textSecondary.opacity(0.12), lineWidth: 1)
            )
        }
    }

    private var countServingControl: some View {
        let quantity = max(roundToServingSelectorIncrement(selectedServingBaselineAmount * selectedMultiplierValue), 0.25)
        let unit = inflectCountUnitToken(item.servingUnit, quantity: quantity)
        return VStack(alignment: .leading, spacing: 10) {
            Text("Quantity")
                .font(.caption.weight(.semibold))
                .foregroundStyle(textSecondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)

            HStack(spacing: 18) {
                Button {
                    setCountQuantity(nextDecrementCount(from: quantity))
                    Haptics.selection()
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.title2)
                }
                .foregroundStyle(quantity > 0.25 ? accent : textSecondary.opacity(0.5))
                .disabled(quantity <= 0.25)

                TextField("", text: $selectedServingAmountText)
                    .font(.headline.weight(.semibold))
                    .keyboardType(.decimalPad)
                    .focused($isServingAmountFieldFocused)
                    .multilineTextAlignment(.leading)
                    .frame(width: 102)
                    .padding(.leading, 10)
                    .padding(.vertical, 8)
                    .padding(.trailing, 56)
                    .foregroundStyle(textPrimary)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(surfacePrimary.opacity(0.95))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(textSecondary.opacity(0.18), lineWidth: 1)
                    )
                    .overlay(alignment: .trailing) {
                        Text(unit)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(textSecondary)
                            .padding(.trailing, 10)
                            .allowsHitTesting(false)
                    }

                Button {
                    setCountQuantity(nextIncrementCount(from: quantity))
                    Haptics.selection()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                }
                .foregroundStyle(accent)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(surfacePrimary.opacity(0.94))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(textSecondary.opacity(0.12), lineWidth: 1)
        )
    }

    private func initializeState() {
        let baseAmount = item.servingAmount
        if let savedBaseline = initialBaseline, let savedSlider = initialSlider {
            selectedServingBaselineAmount = max(roundToServingSelectorIncrement(savedBaseline), 0)
            selectedMultiplierValue = min(max(savedSlider, minMultiplier), maxMultiplier)
        } else {
            selectedServingBaselineAmount = max(roundToServingSelectorIncrement(baseAmount * initialMultiplier), 0)
            selectedMultiplierValue = 1.0
        }
        syncAmountText()
    }

    private func confirmServing() {
        let baseAmount = item.servingAmount
        let selectedAmount = roundToServingSelectorIncrement(selectedServingBaselineAmount * selectedMultiplierValue)
        let mult = baseAmount > 0 ? max(selectedAmount / baseAmount, 0) : 1.0
        let baseline = max(roundToServingSelectorIncrement(selectedServingBaselineAmount), 0)
        let slider = min(max(selectedMultiplierValue, minMultiplier), maxMultiplier)
        Haptics.notification(.success)
        onConfirm(mult, baseline, slider)
    }

    private func syncAmountText() {
        let amount = formattedServingAmount(selectedServingBaselineAmount * selectedMultiplierValue)
        if selectedServingAmountText != amount {
            isUpdatingServingTextFromSlider = true
            selectedServingAmountText = amount
        }
    }

    private func applyTypedServing(text: String) {
        if isUpdatingServingTextFromSlider { isUpdatingServingTextFromSlider = false; return }
        guard let typedAmount = parsedAmount(text), typedAmount >= 0 else { return }
        let rounded = roundToServingSelectorIncrement(typedAmount)
        let current = roundToServingSelectorIncrement(selectedServingBaselineAmount * selectedMultiplierValue)
        if abs(rounded - current) > 0.0005 {
            selectedServingBaselineAmount = rounded
            selectedMultiplierValue = 1.0
        }
    }

    private func applyTypedCountServing(_ text: String) {
        if isUpdatingServingTextFromSlider { isUpdatingServingTextFromSlider = false; return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        guard let parsed = Double(normalized), parsed >= 0.25 else { return }
        let rounded = roundToServingSelectorIncrement(parsed)
        let current = roundToServingSelectorIncrement(selectedServingBaselineAmount * selectedMultiplierValue)
        if abs(rounded - current) > 0.0005 { setCountQuantity(rounded) }
    }

    private func setCountQuantity(_ quantity: Double) {
        let clamped = min(max(roundToServingSelectorIncrement(quantity), 0.25), 99)
        selectedServingBaselineAmount = clamped
        selectedMultiplierValue = 1.0
        let amount = formattedServingAmount(clamped)
        if selectedServingAmountText != amount {
            isUpdatingServingTextFromSlider = true
            selectedServingAmountText = amount
        }
    }

    private func nextDecrementCount(from quantity: Double) -> Double {
        let n = min(max(roundToServingSelectorIncrement(quantity), 0.25), 99)
        return n > 1 ? max(1, n - 1) : max(0.25, n - 0.25)
    }

    private func nextIncrementCount(from quantity: Double) -> Double {
        let n = min(max(roundToServingSelectorIncrement(quantity), 0.25), 99)
        return n < 1 ? min(1, n + 0.25) : min(99, n + 1)
    }

    private func parsedAmount(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Double(trimmed.replacingOccurrences(of: ",", with: "."))
    }

    private func formattedServingAmount(_ amount: Double) -> String {
        formatServingSelectorAmount(amount)
    }

    private func formattedDisplayServingWithUnit(_ amount: Double, unit: String) -> String {
        let displayUnit = isGramUnit(unit) ? "g" : unit
        let unitText = inflectServingUnitToken(displayUnit, quantity: amount)
        return "\(formatServingSelectorAmount(amount)) \(unitText)"
    }

    private func inflectedTextFieldUnit(for unit: String, amountText: String) -> String {
        let displayUnit = isGramUnit(unit) ? "g" : unit
        guard let amount = parsedAmount(amountText) else { return displayUnit }
        return inflectServingUnitToken(displayUnit, quantity: amount)
    }

    private func isGramUnit(_ unit: String) -> Bool {
        let n = unit.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return n == "g" || n == "gram" || n == "grams" || n == "grms"
    }

    private func isCountBased(item: QuickAddFood) -> Bool {
        let unit = item.servingUnit.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if unit.contains("cup") || unit.contains("oz")
            || unit == "g" || unit == "gram" || unit == "grams" || unit == "grms"
            || unit.contains("tbsp") || unit.contains("tablespoon")
            || unit.contains("tsp") || unit.contains("teaspoon")
            || unit == "ml" || unit == "l" || unit == "lb" || unit == "lbs" {
            return false
        }

        if ["piece", "pieces", "slice", "slices", "nugget", "nuggets",
            "sandwich", "sandwiches", "burger", "burgers", "taco", "tacos",
            "burrito", "burritos", "wrap", "wraps",
            "quesadilla", "quesadillas"].contains(unit) { return true }

        if name.contains("nugget") || name.contains("quesadilla") { return true }
        if name.contains("cookie") || name.contains("chips") || name.hasSuffix(" chip") { return true }
        if name.contains("sandwich") || name.contains("burger") || name.contains("burrito")
            || name.contains("taco") || name.contains("wrap") { return true }

        let ambiguous: Set<String> = ["", "serving", "servings", "each", "ea", "item", "items", "portion", "portions"]
        if !ambiguous.contains(unit) {
            let letters = CharacterSet.letters
            let unitChars = CharacterSet(charactersIn: unit)
            if !unit.contains(" ") && !unit.isEmpty && letters.isSuperset(of: unitChars) { return true }
        }
        return false
    }
}
