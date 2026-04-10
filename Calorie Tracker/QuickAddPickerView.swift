import SwiftUI
import UIKit

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
    @State private var selectedMultiplierValue = 1.0
    @State private var selectedServingBaselineAmount = 1.0
    @State private var servingSliderBaselineByItemId: [UUID: Double] = [:]
    @State private var servingSliderValueByItemId: [UUID: Double] = [:]
    @State private var selectedServingAmountText = ""
    @State private var isUpdatingServingTextFromSlider = false
    @State private var isServingKeyboardVisible = false
    @FocusState private var isServingAmountFieldFocused: Bool

    private let minMultiplier = 0.25
    private let maxMultiplier = 1.75
    private let multiplierStep = 0.25

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

    private var selectedServingEffectiveMultiplier: Double {
        guard let item = servingSheetContext?.item else { return 1.0 }
        let baseAmount = convertedServingAmount(item.servingAmount, unit: item.servingUnit)
        guard baseAmount > 0 else { return 1.0 }
        let selectedAmount = roundToServingSelectorIncrement(selectedServingBaselineAmount * selectedMultiplierValue)
        return max(selectedAmount / baseAmount, 0)
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
            servingSheet(item: context.item)
        }
    }

    private var scrollContent: some View {
        ScrollView {
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
            .padding(.top, showsStandaloneChrome ? 18 : 12)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
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

        return HStack(alignment: .top, spacing: 12) {
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

    private func servingSheet(item: QuickAddFood) -> some View {
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
                            countServingControl(for: item)
                        } else {
                            VStack(alignment: .leading, spacing: 14) {
                                let minServingAmount = formattedServingAmount(selectedServingBaselineAmount * minMultiplier)
                                let maxServingAmount = formattedServingAmount(selectedServingBaselineAmount * maxMultiplier)
                                let minServingUnit = inflectedUnit(displayServingUnit(for: item.servingUnit), quantity: selectedServingBaselineAmount * minMultiplier)
                                let maxServingUnit = inflectedUnit(displayServingUnit(for: item.servingUnit), quantity: selectedServingBaselineAmount * maxMultiplier)
                                HStack {
                                    Text("\(minServingAmount) \(minServingUnit)")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(textSecondary)
                                    Spacer()
                                    Text("\(maxServingAmount) \(maxServingUnit)")
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

                        ServingNutrientGridCard(
                            title: "Nutrition Info",
                            calories: item.calories,
                            nutrientValues: item.nutrientValues,
                            multiplier: selectedServingEffectiveMultiplier,
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
                    applySelectedServingMultiplier()
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
                    Button {
                        servingSheetContext = nil
                    } label: {
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
                syncSelectedServingAmountText()
            }
            .onDisappear {
                isServingKeyboardVisible = false
            }
            .onChange(of: selectedMultiplierValue) { _, _ in
                if !isServingAmountFieldFocused {
                    syncSelectedServingAmountText()
                }
            }
            .onChange(of: selectedServingBaselineAmount) { _, _ in
                if !isServingAmountFieldFocused {
                    syncSelectedServingAmountText()
                }
            }
            .onChange(of: selectedServingAmountText) { _, newValue in
                if isCountBased(item: item) {
                    applyTypedCountServingIfPossible(newValue)
                } else {
                    applyTypedServingAmountIfPossible(text: newValue)
                }
            }
            .interactiveDismissDisabled(isServingKeyboardVisible)
        }
    }

    private func countServingControl(for item: QuickAddFood) -> some View {
        let quantity = max(roundToServingSelectorIncrement(selectedServingBaselineAmount * selectedMultiplierValue), 0.25)
        let unit = displayCountUnit(for: item, quantity: quantity)
        return VStack(alignment: .leading, spacing: 10) {
            Text("Quantity")
                .font(.caption.weight(.semibold))
                .foregroundStyle(textSecondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)

            HStack(spacing: 18) {
                Button {
                    setSelectedCountQuantity(nextDecrementCountQuantity(from: quantity))
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
                    setSelectedCountQuantity(nextIncrementCountQuantity(from: quantity))
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
        let baseAmount = convertedServingAmount(item.servingAmount, unit: item.servingUnit)
        if let savedBaseline = servingSliderBaselineByItemId[item.id],
           let savedSlider = servingSliderValueByItemId[item.id] {
            selectedServingBaselineAmount = max(roundToServingSelectorIncrement(savedBaseline), 0)
            selectedMultiplierValue = min(max(savedSlider, minMultiplier), maxMultiplier)
        } else {
            let absoluteMultiplier = multiplier(for: item.id)
            selectedServingBaselineAmount = max(roundToServingSelectorIncrement(baseAmount * absoluteMultiplier), 0)
            selectedMultiplierValue = 1.0
        }
        syncSelectedServingAmountText()
        dismissKeyboard()
        servingSheetContext = nil
        Haptics.impact(.light)
        DispatchQueue.main.async {
            servingSheetContext = ServingSheetContext(item: item)
        }
    }

    private func applySelectedServingMultiplier() {
        guard let item = servingSheetContext?.item else { return }
        let baseAmount = convertedServingAmount(item.servingAmount, unit: item.servingUnit)
        let selectedAmount = roundToServingSelectorIncrement(selectedServingBaselineAmount * selectedMultiplierValue)
        let effectiveMultiplier: Double
        if baseAmount > 0 {
            effectiveMultiplier = max(selectedAmount / baseAmount, 0)
        } else {
            effectiveMultiplier = 1.0
        }
        selectedServingMultiplierByID[item.id] = effectiveMultiplier
        servingSliderBaselineByItemId[item.id] = max(roundToServingSelectorIncrement(selectedServingBaselineAmount), 0)
        servingSliderValueByItemId[item.id] = min(max(selectedMultiplierValue, minMultiplier), maxMultiplier)
        if quantity(for: item.id) == 0 {
            selectedQuantitiesByID[item.id] = 1
        }
        Haptics.notification(.success)
        servingSheetContext = nil
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func syncSelectedServingAmountText() {
        let amount = formattedServingAmount(selectedServingBaselineAmount * selectedMultiplierValue)
        if selectedServingAmountText != amount {
            isUpdatingServingTextFromSlider = true
            selectedServingAmountText = amount
        }
    }

    private func applyTypedServingAmountIfPossible(text: String) {
        if isUpdatingServingTextFromSlider {
            isUpdatingServingTextFromSlider = false
            return
        }
        guard let typedAmount = parsedDecimalAmount(text), typedAmount >= 0 else { return }
        let roundedTypedAmount = roundToServingSelectorIncrement(typedAmount)
        let currentAmount = roundToServingSelectorIncrement(selectedServingBaselineAmount * selectedMultiplierValue)
        if abs(roundedTypedAmount - currentAmount) > 0.0005 {
            selectedServingBaselineAmount = roundedTypedAmount
            selectedMultiplierValue = 1.0
        }
    }

    private func setSelectedCountQuantity(_ quantity: Double) {
        let clamped = min(max(roundToServingSelectorIncrement(quantity), 0.25), 99)
        selectedServingBaselineAmount = clamped
        selectedMultiplierValue = 1.0
        let amount = formattedServingAmount(clamped)
        if selectedServingAmountText != amount {
            isUpdatingServingTextFromSlider = true
            selectedServingAmountText = amount
        }
    }

    private func nextDecrementCountQuantity(from quantity: Double) -> Double {
        let normalized = min(max(roundToServingSelectorIncrement(quantity), 0.25), 99)
        if normalized > 1 {
            return max(1, normalized - 1)
        }
        return max(0.25, normalized - 0.25)
    }

    private func nextIncrementCountQuantity(from quantity: Double) -> Double {
        let normalized = min(max(roundToServingSelectorIncrement(quantity), 0.25), 99)
        if normalized < 1 {
            return min(1, normalized + 0.25)
        }
        return min(99, normalized + 1)
    }

    private func applyTypedCountServingIfPossible(_ text: String) {
        if isUpdatingServingTextFromSlider {
            isUpdatingServingTextFromSlider = false
            return
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        guard let parsed = Double(normalized), parsed >= 0.25 else { return }
        let rounded = roundToServingSelectorIncrement(parsed)
        let currentAmount = roundToServingSelectorIncrement(selectedServingBaselineAmount * selectedMultiplierValue)
        if abs(rounded - currentAmount) > 0.0005 {
            setSelectedCountQuantity(rounded)
        }
    }

    private func parsedDecimalAmount(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
    }

    private func formattedServingAmount(_ amount: Double) -> String {
        formatServingSelectorAmount(amount)
    }

    private func formattedDisplayServingWithUnit(_ amount: Double, unit: String) -> String {
        let convertedAmount = convertedServingAmount(amount, unit: unit)
        let formattedAmount = formattedServingAmount(convertedAmount)
        let unitText = inflectedUnit(displayServingUnit(for: unit), quantity: convertedAmount)
        return "\(formattedAmount) \(unitText)"
    }

    private func displayServingUnit(for unit: String) -> String {
        if isGramUnit(unit) {
            return "g"
        }
        return unit
    }

    private func inflectedTextFieldUnit(for unit: String, amountText: String) -> String {
        let displayUnit = displayServingUnit(for: unit)
        guard let amount = parsedDecimalAmount(amountText) else { return displayUnit }
        return inflectedUnit(displayUnit, quantity: amount)
    }

    private func inflectedUnit(_ unit: String, quantity: Double) -> String {
        inflectServingUnitToken(unit, quantity: quantity)
    }

    private func isGramUnit(_ unit: String) -> Bool {
        let normalized = unit.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "g" || normalized == "gram" || normalized == "grams" || normalized == "grms"
    }

    private func convertedServingAmount(_ amount: Double, unit: String) -> Double {
        amount
    }

    private func isCountBased(item: QuickAddFood) -> Bool {
        let unit = item.servingUnit.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if unit.contains("cup")
            || unit.contains("oz")
            || unit == "g" || unit == "gram" || unit == "grams" || unit == "grms"
            || unit.contains("tbsp") || unit.contains("tablespoon")
            || unit.contains("tsp") || unit.contains("teaspoon")
            || unit == "ml" || unit == "l" || unit == "lb" || unit == "lbs" {
            return false
        }

        if [
            "piece", "pieces",
            "slice", "slices",
            "nugget", "nuggets",
            "sandwich", "sandwiches",
            "burger", "burgers",
            "taco", "tacos",
            "burrito", "burritos",
            "wrap", "wraps",
            "quesadilla", "quesadillas"
        ].contains(unit) { return true }

        if name.contains("nugget") { return true }
        if name.contains("quesadilla") { return true }
        if name.contains("cookie") || name.contains("chips") || name.hasSuffix(" chip") { return true }
        if name.contains("sandwich") || name.contains("burger") || name.contains("burrito") || name.contains("taco") || name.contains("wrap") {
            return true
        }

        let ambiguousUnits: Set<String> = ["", "serving", "servings", "each", "ea", "item", "items", "portion", "portions"]
        if !ambiguousUnits.contains(unit) {
            let letters = CharacterSet.letters
            let unitChars = CharacterSet(charactersIn: unit)
            let looksLikeSingleWordUnit = !unit.contains(" ") && !unit.isEmpty && letters.isSuperset(of: unitChars)
            if looksLikeSingleWordUnit {
                return true
            }
        }
        return false
    }

    private func displayCountUnit(for item: QuickAddFood, quantity: Double) -> String {
        inflectCountUnitToken(item.servingUnit, quantity: quantity)
    }

    private func pruneUnavailableSelections() {
        let availableIDs = Set(quickAddFoods.map(\.id))
        selectedQuantitiesByID = selectedQuantitiesByID.filter { availableIDs.contains($0.key) && $0.value > 0 }
        selectedServingMultiplierByID = selectedServingMultiplierByID.filter { availableIDs.contains($0.key) && $0.value > 0 }
        servingSliderBaselineByItemId = servingSliderBaselineByItemId.filter { availableIDs.contains($0.key) }
        servingSliderValueByItemId = servingSliderValueByItemId.filter { availableIDs.contains($0.key) }
    }
}
