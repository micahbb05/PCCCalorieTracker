import SwiftUI

/// List-first plate result UI: tap an item to open the serving adjuster.
struct PlateEstimateResultView: View {
    let items: [MenuItem]
    @Binding var ozByItemId: [String: Double]
    let baseOzByItemId: [String: Double]
    let trackedNutrientKeys: [String]
    let mealGroup: MealGroup
    let onConfirm: ([(MenuItem, oz: Double, baseOz: Double)]) -> Void
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    @State private var selectedAdjustItem: MenuItem?
    @State private var adjusterBaselineAmount: Double = 1.0
    @State private var adjusterMultiplier: Double = 1.0
    @State private var adjusterBaselineByItemId: [String: Double] = [:]
    @State private var adjusterSliderValueByItemId: [String: Double] = [:]
    @State private var adjusterAmountText: String = ""
    @State private var adjusterQuantity: Double = 1
    @State private var adjusterCountText: String = "1"
    @State private var adjusterQuantityByItemId: [String: Double] = [:]
    @State private var preparedAdjusterItemId: String?
    @State private var isUpdatingAdjusterTextFromSlider = false
    @State private var isAdjusterKeyboardVisible = false
    @FocusState private var isAdjusterAmountFieldFocused: Bool

    @AppStorage("appThemeStyle") private var appThemeStyleRaw: String = AppThemeStyle.ember.rawValue

    private var isBlueprint: Bool { appThemeStyleRaw == AppThemeStyle.blueprint.rawValue }

    private var surfacePrimary: Color {
        colorScheme == .dark
            ? (isBlueprint ? Color(red: 0.13, green: 0.15, blue: 0.20) : Color(red: 0.140, green: 0.118, blue: 0.094))
            : Color.white
    }
    private var textPrimary: Color {
        colorScheme == .dark
            ? (isBlueprint ? Color(red: 0.95, green: 0.96, blue: 0.98) : Color(red: 0.961, green: 0.941, blue: 0.902))
            : (isBlueprint ? Color(red: 0.10, green: 0.11, blue: 0.14) : Color(red: 0.12, green: 0.10, blue: 0.08))
    }
    private var textSecondary: Color {
        colorScheme == .dark
            ? (isBlueprint ? Color(red: 0.78, green: 0.81, blue: 0.86) : Color(red: 0.62, green: 0.60, blue: 0.58))
            : (isBlueprint ? Color(red: 0.45, green: 0.47, blue: 0.52) : Color(red: 0.45, green: 0.42, blue: 0.38))
    }
    private var accent: Color { AppTheme.accent }

    private var itemsOnPlate: [MenuItem] {
        items.filter { (ozByItemId[$0.id] ?? 0) > 0 }
    }

    private var totalNutritionFacts: (calories: Int, nutrientValues: [String: Int]) {
        var caloriesTotal = 0.0
        var nutrientTotals: [String: Double] = [:]

        for item in itemsOnPlate {
            let currentOz = max(ozByItemId[item.id] ?? 0, 0)
            let baseOz = baseOzByItemId[item.id] ?? item.servingOzForPortions
            let multiplier: Double
            if item.isCountBased {
                let baseCount = max(item.servingAmount, 1)
                multiplier = currentOz / baseCount
            } else {
                multiplier = baseOz > 0 ? (currentOz / baseOz) : 1.0
            }
            let safeMultiplier = max(multiplier, 0)
            caloriesTotal += Double(item.calories) * safeMultiplier

            for (key, value) in item.nutrientValues {
                nutrientTotals[key, default: 0] += Double(value) * safeMultiplier
            }
        }

        let roundedNutrients = nutrientTotals.reduce(into: [String: Int]()) { partialResult, entry in
            partialResult[entry.key] = Int(entry.value.rounded())
        }
        return (Int(caloriesTotal.rounded()), roundedNutrients)
    }

    var body: some View {
        let hasLoggableItems = !itemsOnPlate.isEmpty
        let gradientBg = LinearGradient(
            colors: [
                colorScheme == .dark ? Color(red: 0.059, green: 0.051, blue: 0.039) : Color(red: 0.97, green: 0.95, blue: 0.92),
                colorScheme == .dark ? Color(red: 0.078, green: 0.063, blue: 0.039) : Color(red: 0.93, green: 0.90, blue: 0.86)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        NavigationStack {
            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: 12) {
                    Button("Cancel") { onDismiss() }
                        .font(.body.weight(.medium))
                        .foregroundStyle(accent)

                    Spacer(minLength: 0)

                    Button {
                        let pairs = itemsOnPlate.map { item -> (MenuItem, oz: Double, baseOz: Double) in
                            let oz = ozByItemId[item.id] ?? 0
                            let baseOz = baseOzByItemId[item.id] ?? item.servingOzForPortions
                            return (item, oz, baseOz)
                        }
                        onConfirm(pairs)
                    } label: {
                        Text("Add to log")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(hasLoggableItems ? .white : .white.opacity(0.6))
                            .frame(minWidth: 100)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(hasLoggableItems ? accent : accent.opacity(0.5))
                            .clipShape(Capsule(style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(!hasLoggableItems)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 12)

                Text("What's on your plate")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)

                List {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(textSecondary)
                        Text("AI portions are estimates - please double-check before logging.")
                            .font(.caption)
                            .foregroundStyle(textSecondary)
                            .multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(textSecondary.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(textSecondary.opacity(0.18), lineWidth: 0.5)
                    )
                    .padding(.top, 6)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)

                    if itemsOnPlate.isEmpty {
                        Text("No foods were detected on the plate.")
                            .font(.subheadline)
                            .foregroundStyle(textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(surfacePrimary.opacity(0.92))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(textSecondary.opacity(0.14), lineWidth: 1)
                            )
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 0, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    } else {
                        ForEach(itemsOnPlate) { item in
                            PlateSwipeDeleteRow(
                                item: item,
                                portionSummary: itemPortionSummary(item),
                                caloriesAtPortion: itemNutritionAtCurrentPortion(item).calories,
                                proteinAtPortion: itemNutritionAtCurrentPortion(item).protein,
                                calorieSource: item.calorieSource,
                                textPrimary: textPrimary,
                                textSecondary: textSecondary,
                                surfacePrimary: surfacePrimary
                            ) {
                                prepareServingAdjuster(for: item)
                                selectedAdjustItem = item
                            }
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        }
                        .onDelete(perform: deleteItemsFromPlate)

                        let totals = totalNutritionFacts
                        let availableTotalNutrientKeys = Set(totals.nutrientValues.keys.map { $0.lowercased() })
                        let displayedTotalNutrientKeys = trackedNutrientKeys.filter {
                            availableTotalNutrientKeys.contains($0.lowercased())
                        }
                        ServingNutrientGridCard(
                            title: "Total Nutrition Info",
                            calories: totals.calories,
                            nutrientValues: totals.nutrientValues,
                            multiplier: 1.0,
                            trackedNutrientKeys: trackedNutrientKeys,
                            displayedNutrientKeys: displayedTotalNutrientKeys,
                            surface: surfacePrimary.opacity(0.95),
                            stroke: textSecondary.opacity(0.18),
                            titleColor: textPrimary,
                            labelColor: textSecondary,
                            valueColor: textPrimary
                        )
                        .padding(.top, 4)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 10, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.hidden)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(gradientBg.ignoresSafeArea())
            .navigationBarHidden(true)
            .sheet(item: $selectedAdjustItem, onDismiss: {
                isAdjusterAmountFieldFocused = false
                preparedAdjusterItemId = nil
            }) { item in
                servingAdjusterSheet(item: item)
            }
        }
    }

    private func removeItemFromPlate(_ item: MenuItem) {
        var updated = ozByItemId
        updated[item.id] = 0
        ozByItemId = updated
        adjusterQuantityByItemId[item.id] = nil
        adjusterBaselineByItemId[item.id] = nil
        adjusterSliderValueByItemId[item.id] = nil
        if selectedAdjustItem?.id == item.id {
            selectedAdjustItem = nil
        }
    }

    private func deleteItemsFromPlate(at offsets: IndexSet) {
        for index in offsets {
            guard itemsOnPlate.indices.contains(index) else { continue }
            removeItemFromPlate(itemsOnPlate[index])
        }
    }

    private func servingAdjusterSheet(item: MenuItem) -> some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [
                        colorScheme == .dark ? Color(red: 0.07, green: 0.08, blue: 0.12) : Color(red: 0.95, green: 0.97, blue: 0.99),
                        colorScheme == .dark ? Color(red: 0.10, green: 0.11, blue: 0.17) : Color(red: 0.91, green: 0.94, blue: 0.98)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        servingAdjusterHeader(for: item)
                        servingAdjusterControls(for: item)

                        let nutrition = draftNutritionAtCurrentPortion(item)
                        ServingNutrientGridCard(
                            title: "Nutrition Info",
                            calories: item.calories,
                            nutrientValues: item.nutrientValues,
                            multiplier: nutrition.multiplier,
                            trackedNutrientKeys: trackedNutrientKeys,
                            displayedNutrientKeys: nil,
                            showNAForMissingNutrients: true,
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
                    applyAdjusterSliderChange(for: item)
                    selectedAdjustItem = nil
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
                        Rectangle()
                            .fill(.ultraThinMaterial)
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
                        selectedAdjustItem = nil
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .foregroundStyle(textPrimary)
                }
            }
            .onAppear {
                isAdjusterKeyboardVisible = false
                isAdjusterAmountFieldFocused = false
                prepareServingAdjuster(for: item)
            }
            .onDisappear {
                isAdjusterKeyboardVisible = false
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
                let endFrame = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect) ?? .zero
                let visibleHeight = max(0, UIScreen.main.bounds.maxY - endFrame.minY)
                isAdjusterKeyboardVisible = visibleHeight > 20
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                isAdjusterKeyboardVisible = false
            }
            .onChange(of: adjusterMultiplier) { _, _ in
                if !isAdjusterAmountFieldFocused {
                    syncAdjusterAmountTextFromSlider()
                }
            }
            .onChange(of: adjusterBaselineAmount) { _, _ in
                if !isAdjusterAmountFieldFocused {
                    syncAdjusterAmountTextFromSlider()
                }
            }
            .onChange(of: adjusterAmountText) { _, newValue in
                applyTypedAdjusterAmountIfPossible(newValue)
            }
            .interactiveDismissDisabled(isAdjusterKeyboardVisible)
        }
    }

    private func servingAdjusterHeader(for item: MenuItem) -> some View {
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
    }

    private func servingAdjusterControls(for item: MenuItem) -> some View {
        if item.isCountBased {
            return AnyView(servingAdjusterQuantityControl(for: item))
        }

        let minMultiplier = 0.25
        let maxMultiplier = 1.75
        let sliderStep = 0.25
        let minServingAmount = formattedServingAmount(adjusterBaselineAmount * minMultiplier)
        let maxServingAmount = formattedServingAmount(adjusterBaselineAmount * maxMultiplier)
        let minServingUnit = inflectedUnit(displayServingUnit(for: item.servingUnit), quantity: adjusterBaselineAmount * minMultiplier)
        let maxServingUnit = inflectedUnit(displayServingUnit(for: item.servingUnit), quantity: adjusterBaselineAmount * maxMultiplier)

        return AnyView(
            VStack(alignment: .leading, spacing: 14) {
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
                    value: $adjusterMultiplier,
                    range: minMultiplier...maxMultiplier,
                    step: sliderStep
                ) {
                    Haptics.selection()
                }
                .frame(height: 52)

                servingAdjusterSingleInput(for: item)
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
        )
    }

    private func servingAdjusterQuantityControl(for item: MenuItem) -> some View {
        let unit = displayCountUnit(for: item, quantity: adjusterQuantity)
        return VStack(alignment: .leading, spacing: 10) {
            Text("Quantity")
                .font(.caption.weight(.semibold))
                .foregroundStyle(textSecondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)

            HStack(spacing: 18) {
                Button {
                    setAdjusterQuantity(nextDecrementQuantity(from: adjusterQuantity))
                    Haptics.selection()
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.title2)
                }
                .foregroundStyle(adjusterQuantity > 0.25 ? accent : textSecondary.opacity(0.5))
                .disabled(adjusterQuantity <= 0.25)

                TextField("", text: $adjusterCountText)
                    .font(.headline.weight(.semibold))
                    .keyboardType(.decimalPad)
                    .focused($isAdjusterAmountFieldFocused)
                    .onChange(of: adjusterCountText) { _, newValue in
                        applyTypedCountIfPossible(newValue, for: item)
                    }
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
                    setAdjusterQuantity(nextIncrementQuantity(from: adjusterQuantity))
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

    private func servingAdjusterSingleInput(for item: MenuItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Serve")
                .font(.caption.weight(.semibold))
                .foregroundStyle(textSecondary)

            TextField("", text: $adjusterAmountText)
                .keyboardType(.decimalPad)
                .focused($isAdjusterAmountFieldFocused)
                .padding(.trailing, 52)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .foregroundStyle(textPrimary)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(surfacePrimary.opacity(0.95))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(textSecondary.opacity(0.18), lineWidth: 1)
                )
                .overlay(alignment: .trailing) {
                    Text(inflectedTextFieldUnit(for: item.servingUnit, amountText: adjusterAmountText))
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(textSecondary)
                        .padding(.trailing, 14)
                        .allowsHitTesting(false)
                }
        }
    }

    private func prepareServingAdjuster(for item: MenuItem) {
        let currentStoredAmount = max(ozByItemId[item.id] ?? 0, 0.01)
        if item.isCountBased {
            let quantity = max(0.25, adjusterQuantityByItemId[item.id] ?? roundToServingSelectorIncrement(currentStoredAmount))
            adjusterQuantity = quantity
            adjusterCountText = formattedServingAmount(quantity)
            adjusterBaselineAmount = 1.0
            adjusterMultiplier = 1.0
            adjusterAmountText = "1"
            adjusterQuantityByItemId[item.id] = quantity
        } else {
            let currentDisplayAmount = roundToServingSelectorIncrement(storedOzToDisplayAmount(currentStoredAmount, for: item))
            adjusterQuantity = 1.0
            if let savedBaseline = adjusterBaselineByItemId[item.id],
               let savedSliderValue = adjusterSliderValueByItemId[item.id] {
                adjusterBaselineAmount = max(roundToServingSelectorIncrement(savedBaseline), 0)
                adjusterMultiplier = min(max(savedSliderValue, 0.25), 1.75)
            } else {
                adjusterBaselineAmount = max(currentDisplayAmount, 0)
                adjusterMultiplier = 1.0
            }
            syncAdjusterAmountTextFromSlider()
        }
        preparedAdjusterItemId = item.id
    }

    private func syncAdjusterAmountTextFromSlider() {
        let amount = formattedServingAmount(currentAdjusterAmount())
        if adjusterAmountText != amount {
            isUpdatingAdjusterTextFromSlider = true
            adjusterAmountText = amount
        }
    }

    private func applyTypedAdjusterAmountIfPossible(_ text: String) {
        if isUpdatingAdjusterTextFromSlider {
            isUpdatingAdjusterTextFromSlider = false
            return
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        guard let parsed = Double(normalized), parsed >= 0 else { return }
        setAdjusterAmount(parsed)
    }

    private func setAdjusterAmount(_ amount: Double) {
        let clampedAmount = max(roundToServingSelectorIncrement(amount), 0)
        let currentAmount = roundToServingSelectorIncrement(currentAdjusterAmount())
        if abs(clampedAmount - currentAmount) <= 0.0005 { return }
        adjusterBaselineAmount = clampedAmount
        adjusterMultiplier = 1.0
    }

    private func setAdjusterQuantity(_ quantity: Double, syncText: Bool = true) {
        let clamped = min(max(roundToServingSelectorIncrement(quantity), 0.25), 99)
        adjusterQuantity = clamped
        if syncText {
            adjusterCountText = formattedServingAmount(clamped)
        }
    }

    private func nextDecrementQuantity(from quantity: Double) -> Double {
        let normalized = min(max(roundToServingSelectorIncrement(quantity), 0.25), 99)
        if normalized > 1 {
            return max(1, normalized - 1)
        }
        return max(0.25, normalized - 0.25)
    }

    private func nextIncrementQuantity(from quantity: Double) -> Double {
        let normalized = min(max(roundToServingSelectorIncrement(quantity), 0.25), 99)
        if normalized < 1 {
            return min(1, normalized + 0.25)
        }
        return min(99, normalized + 1)
    }

    private func applyTypedCountIfPossible(_ text: String, for item: MenuItem) {
        guard item.isCountBased else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        guard let parsed = Double(normalized), parsed >= 0.25 else { return }
        setAdjusterQuantity(parsed, syncText: false)
    }

    private func currentAdjusterTotalAmount(for item: MenuItem) -> Double {
        guard preparedAdjusterItemId == item.id else {
            return max(ozByItemId[item.id] ?? 0, 0)
        }
        if item.isCountBased {
            return adjusterQuantity
        }
        let displayAmount = max(roundToServingSelectorIncrement(currentAdjusterAmount()), 0)
        return displayAmountToStoredOz(displayAmount, for: item)
    }

    private func applyAdjusterSliderChange(for item: MenuItem) {
        let updatedAmount = currentAdjusterTotalAmount(for: item)
        var updated = ozByItemId
        updated[item.id] = updatedAmount
        ozByItemId = updated
        if item.isCountBased {
            adjusterQuantityByItemId[item.id] = adjusterQuantity
        } else {
            adjusterBaselineByItemId[item.id] = max(roundToServingSelectorIncrement(adjusterBaselineAmount), 0)
            adjusterSliderValueByItemId[item.id] = min(max(adjusterMultiplier, 0.25), 1.75)
        }
    }

    private func currentAdjusterAmount() -> Double {
        adjusterBaselineAmount * adjusterMultiplier
    }

    private func itemPortionSummary(_ item: MenuItem) -> String {
        let currentOz = max(ozByItemId[item.id] ?? 0, 0)
        if item.isCountBased {
            let quantity = max(0.25, adjusterQuantityByItemId[item.id] ?? roundToServingSelectorIncrement(currentOz))
            let unit = displayCountUnit(for: item, quantity: quantity)
            return "\(formattedServingAmount(quantity)) \(unit)"
        }
        let displayAmount = max(storedOzToDisplayAmount(currentOz, for: item), 0)
        let formattedAmount = formattedServingAmount(displayAmount)
        let unitText = inflectedUnit(displayServingUnit(for: item.servingUnit), quantity: displayAmount)
        return "\(formattedAmount) \(unitText)"
    }

    private func itemNutritionAtCurrentPortion(_ item: MenuItem) -> (calories: Int, protein: Int, multiplier: Double) {
        let currentOz = max(ozByItemId[item.id] ?? 0, 0)
        let baseOz = baseOzByItemId[item.id] ?? item.servingOzForPortions
        let multiplier: Double
        if item.isCountBased {
            let baseCount = max(item.servingAmount, 1)
            multiplier = currentOz / baseCount
        } else {
            multiplier = baseOz > 0 ? (currentOz / baseOz) : 1.0
        }
        let calories = Int((Double(item.calories) * multiplier).rounded())
        let protein = Int((Double(item.nutrientValues["g_protein"] ?? 0) * multiplier).rounded())
        return (max(0, calories), max(0, protein), max(0, multiplier))
    }

    private func draftNutritionAtCurrentPortion(_ item: MenuItem) -> (calories: Int, protein: Int, multiplier: Double) {
        let currentAmount = max(currentAdjusterTotalAmount(for: item), 0)
        let baseOz = baseOzByItemId[item.id] ?? item.servingOzForPortions
        let multiplier: Double
        if item.isCountBased {
            let baseCount = max(item.servingAmount, 1)
            multiplier = currentAmount / baseCount
        } else {
            multiplier = baseOz > 0 ? (currentAmount / baseOz) : 1.0
        }
        let calories = Int((Double(item.calories) * multiplier).rounded())
        let protein = Int((Double(item.nutrientValues["g_protein"] ?? 0) * multiplier).rounded())
        return (max(0, calories), max(0, protein), max(0, multiplier))
    }

    private func formattedServingAmount(_ amount: Double) -> String {
        formatServingSelectorAmount(amount)
    }

    private func formattedDisplayServingAmount(_ amount: Double, unit: String) -> String {
        formattedServingAmount(convertedServingAmount(amount, unit: unit))
    }

    private func formattedDisplayServingWithUnit(_ amount: Double, unit: String) -> String {
        let convertedAmount = convertedServingAmount(amount, unit: unit)
        let formattedAmount = formattedServingAmount(convertedAmount)
        let unitText = inflectedUnit(displayServingUnit(for: unit), quantity: convertedAmount)
        return "\(formattedAmount) \(unitText)"
    }

    private func displayServingUnit(for unit: String) -> String {
        let trimmed = unit.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "servings" }
        if isGramUnit(trimmed) { return "g" }
        return trimmed
    }

    private func inflectedTextFieldUnit(for unit: String, amountText: String) -> String {
        let displayUnit = displayServingUnit(for: unit)
        guard let amount = parsedDecimalAmount(amountText) else { return displayUnit }
        return inflectedUnit(displayUnit, quantity: amount)
    }

    private func inflectedUnit(_ unit: String, quantity: Double) -> String {
        inflectServingUnitToken(unit, quantity: quantity)
    }

    private func parsedDecimalAmount(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
    }

    private func convertedServingAmount(_ amount: Double, unit: String) -> Double {
        return amount
    }

    private func isGramUnit(_ unit: String) -> Bool {
        let normalizedUnit = unit.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalizedUnit == "g" || normalizedUnit == "gram" || normalizedUnit == "grams" || normalizedUnit == "grms"
    }

    private func baseDisplayServingAmount(for item: MenuItem) -> Double {
        max(convertedServingAmount(item.servingAmount, unit: item.servingUnit), 0)
    }

    private func storedOzToDisplayAmount(_ oz: Double, for item: MenuItem) -> Double {
        guard !item.isCountBased else { return oz }
        let baseOz = baseOzByItemId[item.id] ?? item.servingOzForPortions
        let baseDisplay = baseDisplayServingAmount(for: item)
        guard baseOz > 0, baseDisplay > 0 else { return oz }
        return (oz / baseOz) * baseDisplay
    }

    private func displayAmountToStoredOz(_ amount: Double, for item: MenuItem) -> Double {
        guard !item.isCountBased else { return amount }
        let baseOz = baseOzByItemId[item.id] ?? item.servingOzForPortions
        let baseDisplay = baseDisplayServingAmount(for: item)
        guard baseOz > 0, baseDisplay > 0 else { return amount }
        return (amount / baseDisplay) * baseOz
    }

    private func displayCountUnit(for item: MenuItem, quantity: Double) -> String {
        inflectCountUnitToken(item.servingUnit, quantity: quantity)
    }

}

private struct PlateSwipeDeleteRow: View {
    let item: MenuItem
    let portionSummary: String
    let caloriesAtPortion: Int
    let proteinAtPortion: Int
    let calorieSource: MenuItem.CalorieSource?
    let textPrimary: Color
    let textSecondary: Color
    let surfacePrimary: Color
    let onOpen: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(textPrimary)
                    .multilineTextAlignment(.leading)

                Text(portionSummary)
                    .font(.caption)
                    .foregroundStyle(textSecondary)

                Text("\(caloriesAtPortion) cal • \(proteinAtPortion)g protein")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(textSecondary.opacity(0.95))
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                if let calorieSource {
                    Text(calorieSource == .web ? "Source: web" : "Source: estimated")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(calorieSource == .web ? Color.green : Color.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule(style: .continuous)
                                .fill((calorieSource == .web ? Color.green : Color.orange).opacity(0.16))
                        )
                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(textSecondary.opacity(0.85))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(surfacePrimary.opacity(0.95))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(textSecondary.opacity(0.18), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
    }
}
