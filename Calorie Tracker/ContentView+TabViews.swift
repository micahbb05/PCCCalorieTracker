// Calorie Tracker 2026

import SwiftUI

extension ContentView {

    var todayTabView: some View {
        VStack(alignment: .leading, spacing: 0) {
            tabHeader(title: "Today", subtitle: "Calories, nutrients, and today's log")
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 6)

            List {
                calorieHeroSection
                if !activeNutrients.isEmpty {
                    progressSection
                }
                foodLogSections
                exerciseLogSection
                mealDistributionSection
                todayResetSection
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .scrollIndicators(.hidden)
        }
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 110)
        }
    }

    var historyTabView: some View {
        VStack(alignment: .leading, spacing: 0) {
            tabHeader(title: "History", subtitle: "Calendar, calorie trends, and stats")
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 6)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(Array(historyCards.enumerated()), id: \.offset) { _, card in
                        card
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 140)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private var historyCards: [AnyView] {
        [
            AnyView(historyCalendarCard),
            AnyView(historyGraphCard),
            AnyView(netCalorieHistoryCard),
            AnyView(historyMealDistributionCard),
            AnyView(weightChangeComparisonButton),
            AnyView(weeklyInsightButton)
        ]
    }

    @ViewBuilder
    var addTabView: some View {
        switch selectedAddDestination {
        case .aiPhoto:
            aiPhotoTabView
        case .manualEntry:
            manualEntryTabView
        case .pccMenu:
            pccMenuTabView
        case .usdaSearch:
            usdaSearchTabView
        case .barcode:
            barcodeTabView
        case .quickAdd:
            quickAddTabView
        }
    }

    var aiPhotoTabView: some View {
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 0) {
                addWorkspaceHeader(
                    title: AddDestination.aiPhoto.title,
                    subtitle: AddDestination.aiPhoto.subtitle
                )

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        aiPhotoCaptureCard
                        aiModeOrDivider
                        aiTextMealCard
                            .id("aiTextMealCard")
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, aiModeBottomPadding)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
            }
            .onChange(of: aiMealTextFocused) { _, isFocused in
                guard isFocused else { return }
                scheduleAITextCardScroll(using: proxy)
            }
            .onChange(of: keyboardHeight) { _, newHeight in
                guard aiMealTextFocused, newHeight > 0 else { return }
                scheduleAITextCardScroll(using: proxy)
            }
            .overlay {
                if isAIFoodPhotoLoading || isAITextLoading {
                    ZStack {
                        Color.black.opacity(0.28)
                            .ignoresSafeArea()

                        VStack(spacing: 14) {
                            ProgressView()
                                .scaleEffect(1.15)
                                .tint(.white)
                            Text(isAITextLoading ? "Analyzing text…" : "Analyzing photo…")
                                .font(.headline.weight(.medium))
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 28)
                        .padding(.vertical, 24)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(Color.black.opacity(0.72))
                        )
                    }
                }
            }
            .alert("AI analysis failed", isPresented: Binding(
                get: { aiFoodPhotoErrorMessage != nil || aiTextErrorMessage != nil },
                set: {
                    if !$0 {
                        aiFoodPhotoErrorMessage = nil
                        aiTextErrorMessage = nil
                    }
                }
            )) {
                Button("OK", role: .cancel) {
                    aiFoodPhotoErrorMessage = nil
                    aiTextErrorMessage = nil
                }
            } message: {
                Text(aiFoodPhotoErrorMessage ?? aiTextErrorMessage ?? "Unknown error")
            }
        }
    }

    func scheduleAITextCardScroll(using proxy: ScrollViewProxy) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            withAnimation(.easeInOut(duration: 0.2)) {
                proxy.scrollTo("aiTextMealCard", anchor: .top)
            }
        }
    }

    var manualEntryTabView: some View {
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 0) {
                addWorkspaceHeader(
                    title: AddDestination.manualEntry.title,
                    subtitle: AddDestination.manualEntry.subtitle
                )

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        manualEntryFormCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, manualEntryBottomPadding)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
            }
            .onChange(of: focusedField) { _, newValue in
                guard newValue != nil else { return }
                scheduleManualEntryScroll(for: newValue, using: proxy)
            }
            .onChange(of: keyboardHeight) { _, newHeight in
                guard newHeight > 0, focusedField != nil else { return }
                scheduleManualEntryScroll(for: focusedField, using: proxy)
            }
        }
    }

    var pccMenuTabView: some View {
        pccMenuPage
    }

    var usdaSearchTabView: some View {
        VStack(alignment: .leading, spacing: 0) {
            addWorkspaceHeader(
                title: AddDestination.usdaSearch.title,
                subtitle: AddDestination.usdaSearch.subtitle
            )
            usdaSearchPageContent
        }
        .safeAreaInset(edge: .bottom) {
            Color.clear
                .frame(height: Self.embeddedMenuBottomClearance)
        }
        .onChange(of: usdaSearchText) { _, newValue in
            usdaSearchDebounceTask?.cancel()
            let query = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard query.count >= 2 else {
                latestFoodSearchRequestID += 1
                usdaSearchTask?.cancel()
                foodSearchResults = []
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

    var quickAddTabView: some View {
        VStack(alignment: .leading, spacing: 0) {
            QuickAddPickerView(
                quickAddFoods: quickAddFoods,
                surfacePrimary: surfacePrimary,
                surfaceSecondary: surfaceSecondary,
                textPrimary: textPrimary,
                textSecondary: textSecondary,
                accent: accent,
                trackedNutrientKeys: trackedNutrientKeys,
                onAddSelected: { selections in
                    addQuickAddFoods(selections, dismissPickerAfterAdd: false)
                },
                onManage: {
                    presentQuickAddManagerFromPicker()
                },
                onClose: nil,
                showsStandaloneChrome: false
            )
        }
        .safeAreaInset(edge: .bottom) {
            Color.clear
                .frame(height: Self.embeddedMenuBottomClearance)
        }
    }

    var barcodeTabView: some View {
        VStack(alignment: .leading, spacing: 0) {
            addWorkspaceHeader(
                title: AddDestination.barcode.title,
                subtitle: AddDestination.barcode.subtitle
            )

            ZStack {
                BarcodeScannerView(
                    onScan: { code in
                        Task {
                            await handleScannedBarcode(code)
                        }
                    },
                    didScan: hasScannedBarcodeInCurrentSheet
                )
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

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

                    if barcodeErrorToastMessage != nil {
                        barcodeErrorToastView
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 24)
                .allowsHitTesting(false)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(textSecondary.opacity(0.16), lineWidth: 1)
            )
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .safeAreaInset(edge: .bottom) {
            Color.clear
                .frame(height: Self.embeddedMenuBottomClearance)
        }
    }

    func addWorkspaceHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            tabHeader(title: title, subtitle: subtitle)
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 6)
    }

    var manualEntryFormCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Food name")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(textPrimary)

                TextField("e.g. Grilled chicken", text: $entryNameText)
                    .focused($focusedField, equals: .name)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .calories }
                    .inputStyle(surface: surfaceSecondary, text: textPrimary, secondary: textSecondary)
                    .id(manualEntryScrollID(for: .name))
            }

            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                ForEach(Array(manualEntryGridRows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        manualEntryGridCell(row[0])
                            .gridCellColumns(row.count == 1 ? 2 : 1)
                        if row.count > 1 {
                            manualEntryGridCell(row[1])
                        } else {
                            EmptyView()
                        }
                    }
                }
            }

            if let entryError {
                Text(entryError)
                    .font(.caption)
                    .foregroundStyle(Color.red)
            }

            addEntryButton
                .id("addEntryButton")
        }
        .padding(18)
        .cardStyle(surface: surfacePrimary, stroke: textSecondary.opacity(0.18))
        .id("addManualEntryCard")
    }

    func pageHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 32, weight: .bold, design: .default))
                .foregroundStyle(textPrimary)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(textSecondary)
        }
        .padding(.top, 8)
        .listRowInsets(EdgeInsets(top: 6, leading: 4, bottom: 10, trailing: 4))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    func tabHeader(title: String, subtitle: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 32, weight: .bold, design: .default))
                .foregroundStyle(textPrimary)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(textSecondary)
            }
        }
    }


}
