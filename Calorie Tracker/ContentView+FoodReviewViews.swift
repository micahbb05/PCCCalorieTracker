// Calorie Tracker 2026

import SwiftUI

extension ContentView {

    var usdaSearchSheet: some View {
        usdaSearchPage(onClose: {
            isUSDASearchPresented = false
            dismissKeyboard()
            Haptics.selection()
        })
    }

    func usdaSearchPage(onClose: (() -> Void)?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let onClose {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top, spacing: 14) {
                        Button {
                            onClose()
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(textPrimary)
                                .frame(width: 42, height: 42)
                                .background(
                                    Circle()
                                        .fill(surfacePrimary.opacity(0.94))
                                )
                                .overlay(
                                    Circle()
                                        .stroke(textSecondary.opacity(0.16), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Search Food")
                                .font(.system(size: 30, weight: .bold, design: .rounded))
                                .foregroundStyle(textPrimary)
                            Text("Search USDA FoodData Central")
                                .font(.subheadline)
                                .foregroundStyle(textSecondary)
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 24)
                    .padding(.bottom, 6)
                }
            }

            usdaSearchPageContent
        }
    }

    var usdaSearchPageContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
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
                        foodSearchResults = []
                        isUSDASearchLoading = false
                        usdaSearchError = nil
                        hasCompletedUSDASearch = false
                        usdaSearchDebounceTask?.cancel()
                        usdaSearchTask?.cancel()
                        usdaSearchDebounceTask = nil
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
                        .foregroundStyle(Color.orange)
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
                    .accessibilityIdentifier("usdaSearch.loading")
                } else if !foodSearchResults.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Results")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(textPrimary)

                        LazyVStack(spacing: 12) {
                            ForEach(foodSearchResults) { result in
                                foodSearchResultCard(result)
                            }
                        }
                    }
                } else if !usdaSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isUSDASearchLoading && usdaSearchError == nil {
                    Text(hasCompletedUSDASearch ? "No results found. Try a broader search term." : "Type to see matching foods.")
                        .font(.subheadline)
                        .foregroundStyle(textSecondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
    }

    func foodReviewSheet(item: FoodReviewItem) -> some View {
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

                            VStack(alignment: .leading, spacing: 6) {
                                if isFoodReviewNameEditable(for: item) {
                                    TextField("Food name", text: $foodReviewNameText)
                                        .font(.system(size: 28, weight: .bold, design: .rounded))
                                        .foregroundStyle(textPrimary)
                                        .submitLabel(.done)
                                        .focused($foodReviewFocusedField, equals: .name)
                                        .inputStyle(surface: surfacePrimary.opacity(0.94), text: textPrimary, secondary: textSecondary)
                                } else {
                                    Text(item.name)
                                        .font(.system(size: 28, weight: .bold, design: .rounded))
                                        .foregroundStyle(textPrimary)
                                        .lineLimit(2)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }

                            if let subtitle = item.subtitle {
                                Text(subtitle)
                                    .font(.subheadline)
                                    .foregroundStyle(textSecondary)
                                    .lineLimit(2)
                            }

                            Text("Base serve: \(formattedDisplayServingWithUnit(item.servingAmount, unit: item.servingUnit))")
                                .font(.subheadline)
                                .foregroundStyle(textSecondary)
                        }

                        VStack(alignment: .leading, spacing: 14) {
                            if item.isCountBased {
                                foodReviewCountBasedQuantityCard(for: item)
                            } else {
                                let minMultiplier = 0.25
                                let maxMultiplier = 1.75
                                let minServingAmount = formattedServingAmount(selectedFoodReviewBaselineAmount * minMultiplier)
                                let maxServingAmount = formattedServingAmount(selectedFoodReviewBaselineAmount * maxMultiplier)
                                let minServingUnit = inflectedUnit(displayServingUnit(for: item.servingUnit), quantity: selectedFoodReviewBaselineAmount * minMultiplier)
                                let maxServingUnit = inflectedUnit(displayServingUnit(for: item.servingUnit), quantity: selectedFoodReviewBaselineAmount * maxMultiplier)
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
                                    value: $selectedFoodReviewMultiplier,
                                    range: minMultiplier...maxMultiplier,
                                    step: 0.25
                                ) {
                                    Haptics.selection()
                                }
                                .frame(height: 52)

                                HStack(alignment: .top, spacing: 14) {
                                    foodReviewServingAmountCard(for: item)
                                    foodReviewQuantityCard
                                }
                            }
                        }

                        foodReviewNutrientCard(for: item)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 120)
                }
                .scrollDismissesKeyboard(.interactively)
                .scrollIndicators(.hidden)

            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    addReviewedFood(item)
                } label: {
                    Text("Add to Tracker")
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
                        foodReviewItem = nil
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .foregroundStyle(textPrimary)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
                let endFrame = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect) ?? .zero
                let visibleHeight = max(0, UIScreen.main.bounds.maxY - endFrame.minY)
                isFoodReviewKeyboardVisible = visibleHeight > 20
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                isFoodReviewKeyboardVisible = false
            }
            .onAppear {
                isFoodReviewKeyboardVisible = false
                syncFoodReviewAmountText()
            }
            .onDisappear {
                isFoodReviewKeyboardVisible = false
            }
            .onChange(of: selectedFoodReviewMultiplier) { _, _ in
                if foodReviewFocusedField != .amount {
                    syncFoodReviewAmountText()
                }
            }
            .onChange(of: selectedFoodReviewAmountText) { _, newValue in
                applyTypedFoodReviewAmountIfPossible(text: newValue)
            }
            .interactiveDismissDisabled(isFoodReviewKeyboardVisible)
        }
    }

    func isFoodReviewNameEditable(for item: FoodReviewItem) -> Bool {
        switch item.entrySource {
        case .quickAdd:
            return false
        case .manual, .barcode, .usda, .aiFoodPhoto, .aiNutritionLabel, .aiText, .pccMenu:
            return true
        }
    }

    func foodSearchResultCard(_ result: FoodSearchResult) -> some View {
        Button {
            openFoodReview(for: result)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text(result.name)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let brand = result.brand {
                    Text(brand)
                        .font(.caption)
                        .foregroundStyle(textSecondary)
                }

                Text("\(result.calories) cal • \(result.nutrientValues["g_protein"] ?? 0)g protein")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(textSecondary)

                Text(formattedDisplayServingWithUnit(result.servingAmount, unit: result.servingUnit))
                    .font(.caption2)
                    .foregroundStyle(textSecondary.opacity(0.9))
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle(surface: surfacePrimary.opacity(0.95), stroke: textSecondary.opacity(0.15))
        }
        .buttonStyle(.plain)
    }

    func foodReviewNutrientCard(for item: FoodReviewItem) -> some View {
        let showNAForMissingNutrients: Bool
        switch item.entrySource {
        case .aiFoodPhoto, .aiNutritionLabel, .aiText:
            showNAForMissingNutrients = true
        default:
            showNAForMissingNutrients = false
        }
        return ServingNutrientGridCard(
            title: "Nutrition Info",
            calories: item.calories,
            nutrientValues: item.nutrientValues,
            multiplier: selectedFoodReviewTotalMultiplier,
            trackedNutrientKeys: trackedNutrientKeys,
            displayedNutrientKeys: item.displayedNutrientKeys,
            showNAForMissingNutrients: showNAForMissingNutrients,
            surface: surfacePrimary.opacity(0.95),
            stroke: textSecondary.opacity(0.15),
            titleColor: textPrimary,
            labelColor: textSecondary,
            valueColor: textPrimary
        )
    }

    func reviewStatCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(textSecondary)
            Text(value)
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(textPrimary)
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

    var foodReviewQuantityCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Number of Servings")
                .font(.caption.weight(.semibold))
                .foregroundStyle(textSecondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)

            HStack(spacing: 14) {
                Button {
                    selectedFoodReviewQuantity = max(1, selectedFoodReviewQuantity - 1)
                    Haptics.selection()
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.title2)
                }
                .foregroundStyle(selectedFoodReviewQuantity > 1 ? accent : textSecondary.opacity(0.5))
                .disabled(selectedFoodReviewQuantity <= 1)

                Text("\(selectedFoodReviewQuantity)")
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                    .frame(minWidth: 30)
                    .foregroundStyle(textPrimary)

                Button {
                    selectedFoodReviewQuantity = min(99, selectedFoodReviewQuantity + 1)
                    Haptics.selection()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                }
                .foregroundStyle(accent)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(surfacePrimary.opacity(0.94))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(textSecondary.opacity(0.12), lineWidth: 1)
        )
    }

    func foodReviewServingAmountCard(for item: FoodReviewItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Serving Size")
                .font(.caption.weight(.semibold))
                .foregroundStyle(textSecondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)

            TextField("", text: $selectedFoodReviewAmountText)
                .font(.subheadline.weight(.semibold))
                .keyboardType(.decimalPad)
                .focused($foodReviewFocusedField, equals: .amount)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .padding(.trailing, 46)
                .foregroundStyle(textPrimary)
                .tint(textPrimary)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(surfaceSecondary)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(textSecondary.opacity(0.35), lineWidth: 1)
                )
                .overlay(alignment: .trailing) {
                    Text(inflectedTextFieldUnit(for: item.servingUnit, amountText: selectedFoodReviewAmountText))
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(textSecondary)
                        .padding(.trailing, 12)
                        .allowsHitTesting(false)
                }

        }
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(surfacePrimary.opacity(0.94))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(textSecondary.opacity(0.12), lineWidth: 1)
        )
    }

    func foodReviewCountBasedQuantityCard(for item: FoodReviewItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Quantity")
                .font(.caption.weight(.semibold))
                .foregroundStyle(textSecondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)

            HStack(spacing: 18) {
                let currentValue = parsedDecimalAmount(selectedFoodReviewAmountText) ?? roundToServingSelectorIncrement(selectedFoodReviewBaselineAmount * selectedFoodReviewMultiplier)
                Button {
                    let nextAmount = max(1.0, currentValue - 1.0)
                    selectedFoodReviewBaselineAmount = nextAmount
                    selectedFoodReviewMultiplier = 1.0
                    syncFoodReviewAmountText()
                    Haptics.selection()
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.title2)
                }
                .foregroundStyle(currentValue > 1.0 ? accent : textSecondary.opacity(0.5))
                .disabled(currentValue <= 1.0)

                TextField("", text: $selectedFoodReviewAmountText)
                    .font(.headline.weight(.semibold))
                    .keyboardType(.decimalPad)
                    .focused($foodReviewFocusedField, equals: .amount)
                    .multilineTextAlignment(.leading)
                    .frame(width: 102)
                    .padding(.leading, 10)
                    .padding(.vertical, 8)
                    .padding(.trailing, 56)
                    .foregroundStyle(textPrimary)
                    .tint(textPrimary)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(surfacePrimary.opacity(0.95))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(textSecondary.opacity(0.18), lineWidth: 1)
                    )
                    .overlay(alignment: .trailing) {
                        Text(inflectedTextFieldUnit(for: item.servingUnit, amountText: selectedFoodReviewAmountText))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(textSecondary)
                            .padding(.trailing, 10)
                            .allowsHitTesting(false)
                    }

                Button {
                    let currentValue = parsedDecimalAmount(selectedFoodReviewAmountText) ?? roundToServingSelectorIncrement(selectedFoodReviewBaselineAmount * selectedFoodReviewMultiplier)
                    let nextAmount = currentValue + 1.0
                    selectedFoodReviewBaselineAmount = nextAmount
                    selectedFoodReviewMultiplier = 1.0
                    syncFoodReviewAmountText()
                    Haptics.selection()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                }
                .foregroundStyle(accent)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .padding(10)
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
