// Calorie Tracker 2026

import SwiftUI

extension ContentView {

    var body: some View {
        NavigationStack {
            rootHost
        }
    }

    var rootHost: some View {
        rootLifecycleHost
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
                updateKeyboardState(from: notification)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { notification in
                updateKeyboardState(from: notification)
            }
            .onOpenURL { url in
                handleWidgetDeepLink(url)
            }
    }

    @ViewBuilder
    var rootConditionalContent: some View {
        if isPCCMenuUITestMode {
            uiTestPCCMenuRoot
        } else if hasCompletedOnboarding {
            rootShellModalHost
        } else {
            onboardingView
        }
    }

    var rootLifecycleHost: some View {
        rootStateSyncHost
            .onAppear(perform: handleOnAppear)
            .onChange(of: entries) { _, _ in
                syncCurrentEntriesToArchive()
                syncSmartMealReminders()
                pushWatchSnapshot()
            }
            .onChange(of: exercises) { _, _ in
                syncCurrentEntriesToArchive()
                syncCurrentDayGoalArchive()
                pushWatchSnapshot()
            }
            .onChange(of: healthKitService.todayWorkouts) { _, _ in
                syncCurrentDayGoalArchive()
                scheduleCalibrationEvaluation()
                pushWatchSnapshot()
            }
            .onChange(of: scenePhase) { _, newPhase in
                handleScenePhaseChange(newPhase)
                if newPhase == .active {
                    pushWatchSnapshot()
                }
            }
            .onReceive(clockTimer) { _ in
                handleClockTick()
                pushWatchSnapshot()
            }
    }

    var rootStateSyncHost: some View {
        rootPreferenceHost
            .onChange(of: healthKitService.profile) { _, newProfile in
                handleHealthProfileChange(newProfile)
            }
            .onChange(of: storedDeficitCalories) { _, _ in
                syncCurrentDayGoalArchive()
                persistStateSnapshot()
                pushWatchSnapshot()
            }
            .onChange(of: useWeekendDeficit) { _, _ in
                syncCurrentDayGoalArchive()
                persistStateSnapshot()
                pushWatchSnapshot()
            }
            .onChange(of: storedWeekendDeficitCalories) { _, _ in
                syncCurrentDayGoalArchive()
                persistStateSnapshot()
                pushWatchSnapshot()
            }
            .onChange(of: smartMealRemindersEnabled) { _, newValue in
                handleSmartMealRemindersPreferenceChange(newValue)
            }
            .onChange(of: goalTypeRaw) { oldValue, newValue in
                let previousGoalType = GoalType(rawValue: oldValue) ?? .deficit
                let newGoalType = GoalType(rawValue: newValue) ?? .deficit

                if newGoalType == .fixed {
                    calibrationWasEnabledBeforeFixed = calibrationState.isEnabled
                    if calibrationState.isEnabled {
                        calibrationState.isEnabled = false
                        saveCalibrationState()
                        calibrationEvaluationTask?.cancel()
                    }
                } else if previousGoalType == .fixed {
                    if calibrationWasEnabledBeforeFixed, !calibrationState.isEnabled {
                        calibrationState.isEnabled = true
                        saveCalibrationState()
                        scheduleCalibrationEvaluation(force: true)
                    }
                }

                syncCurrentDayGoalArchive()
                persistStateSnapshot()
                pushWatchSnapshot()
            }
            .onChange(of: storedSurplusCalories) { _, _ in
                syncCurrentDayGoalArchive()
                persistStateSnapshot()
                pushWatchSnapshot()
            }
            .onChange(of: storedFixedGoalCalories) { _, _ in
                syncCurrentDayGoalArchive()
                persistStateSnapshot()
                pushWatchSnapshot()
            }
            .onChange(of: storedManualBMRCalories) { _, _ in
                syncCurrentDayGoalArchive()
                persistStateSnapshot()
                pushWatchSnapshot()
            }
            .onChange(of: bmrSourceRaw) { _, _ in
                syncCurrentDayGoalArchive()
                persistStateSnapshot()
                pushWatchSnapshot()
            }
            .onChange(of: stepActivityService.todayStepCount) { _, _ in
                syncCurrentDayGoalArchive()
                pushWatchSnapshot()
            }
            .onChange(of: stepActivityService.todayDistanceMeters) { _, _ in
                syncCurrentDayGoalArchive()
                pushWatchSnapshot()
            }
    }

    var rootPreferenceHost: some View {
        rootConditionalContent
            .onChange(of: trackedNutrientKeys) { _, _ in
                normalizeTrackingState()
                saveTrackingPreferences()
                syncInputFieldsToTrackedNutrients()
            }
            .onChange(of: nutrientGoals) { _, _ in
                saveTrackingPreferences()
            }
            .onChange(of: quickAddFoods) { _, _ in
                saveQuickAddFoods()
            }
            .onChange(of: selectedAppIconChoiceRaw) { _, newValue in
                AppIconManager.apply(AppIconChoice(rawValue: newValue) ?? .standard)
                syncWidgetSnapshot()
                persistStateSnapshot()
            }
            .onChange(of: venueMenus) { _, _ in
                normalizeTrackingState()
                saveTrackingPreferences()
                syncInputFieldsToTrackedNutrients()
                pushWatchSnapshot()
            }
            .onChange(of: onboardingPage) { _, newPage in
                guard !hasCompletedOnboarding, newPage == OnboardingPage.nutrients.rawValue else { return }
                normalizeTrackingState()
                saveTrackingPreferences()
                syncInputFieldsToTrackedNutrients()
            }
            .onChange(of: cloudSyncPayload) { oldPayload, newPayload in
                handleCloudSyncPayloadChange(oldPayload: oldPayload, newPayload: newPayload)
                if !isApplyingCloudSync {
                    persistStateSnapshot()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .cloudKitAppStateDidChange)) { _ in
                Task(priority: .utility) {
                    await bootstrapCloudSync(trigger: .push)
                }
            }
    }

    var rootShellBase: some View {
        appChrome
            // Keep the floating tab bar fixed when keyboard appears.
            .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    var onboardingView: some View {
        OnboardingFlowView(
            currentPage: $onboardingPage,
            deficitCalories: $storedDeficitCalories,
            goalTypeRaw: $goalTypeRaw,
            surplusCalories: $storedSurplusCalories,
            fixedGoalCalories: $storedFixedGoalCalories,
            manualBMRCalories: $storedManualBMRCalories,
            bmrSourceRaw: $bmrSourceRaw,
            trackedNutrientKeys: $trackedNutrientKeys,
            nutrientGoals: $nutrientGoals,
            availableNutrients: availableNutrients,
            healthAuthorizationState: healthKitService.authorizationState,
            healthProfile: healthKitService.profile,
            hasRequestedHealthAccess: hasRequestedHealthDuringOnboarding,
            backgroundTop: backgroundTop,
            backgroundBottom: backgroundBottom,
            surfacePrimary: surfacePrimary,
            textPrimary: textPrimary,
            textSecondary: textSecondary,
            accent: accent,
            onRequestHealthAccess: {
                Task {
                    await requestUnifiedHealthAccessAndRefresh()
                    await MainActor.run {
                        hasRequestedHealthDuringOnboarding = true
                    }
                }
            },
            onSkip: skipOnboarding,
            onFinish: completeOnboarding
        )
    }

    var rootShellSheetHost: some View {
        rootShellBase
            .sheet(isPresented: $isMenuSheetPresented, onDismiss: clearMenuSelection) {
                menuSheet
            }
            .sheet(isPresented: $isUSDASearchPresented) {
                usdaSearchSheet
            }
            .sheet(item: $foodReviewItem, onDismiss: {
                foodReviewNameText = ""
                selectedFoodReviewBaselineAmount = 1.0
                selectedFoodReviewAmountText = ""
                foodReviewItem = nil
                hasScannedBarcodeInCurrentSheet = false
            }) { context in
                foodReviewSheet(item: context)
            }
            .sheet(isPresented: $isExpandedHistoryChartPresented) {
                expandedHistoryChartSheet
            }
            .sheet(isPresented: $isWeightChangeComparisonPresented) {
                weightChangeComparisonSheet
            }
            .sheet(item: $presentedHistoryDaySummary) { summary in
                historyDayDetailSheet(summary: summary)
            }
            .sheet(item: $editingEntry) { entry in
                editEntrySheet(entry: entry)
            }
            .sheet(item: $foodLogEntryPickerContext) { context in
                foodLogEntryPickerSheet(
                    initialContext: context,
                    context: $foodLogEntryPickerContext
                )
            }
            .fullScreenCover(item: $aiFoodPhotoRequestedPickerSource) { source in
                PlateImagePickerView(source: source, onPicked: { data in
                    aiFoodPhotoRequestedPickerSource = nil
                    analyzeAIFoodPhoto(data)
                }, onCancel: {
                    aiFoodPhotoRequestedPickerSource = nil
                })
            }
            .fullScreenCover(isPresented: Binding(
                get: { aiPhotoItems != nil },
                set: { if !$0 { clearAIPhotoMultiItemState() } }
            )) {
                if let items = aiPhotoItems {
                    PlateEstimateResultView(
                        items: items,
                        ozByItemId: $aiPhotoOzByItemId,
                        baseOzByItemId: aiPhotoBaseOzByItemId,
                        trackedNutrientKeys: trackedNutrientKeys,
                        mealGroup: genericMealGroup(for: Date()),
                        onConfirm: { pairs in
                            addAIPhotoItemsWithPortions(pairs)
                            clearAIPhotoMultiItemState()
                        },
                        onDismiss: {
                            clearAIPhotoMultiItemState()
                        }
                    )
                }
            }
            .fullScreenCover(isPresented: Binding(
                get: { aiTextPlateItems != nil },
                set: { if !$0 { clearAITextPlateState() } }
            )) {
                if let items = aiTextPlateItems {
                    PlateEstimateResultView(
                        items: items,
                        ozByItemId: $aiTextOzByItemId,
                        baseOzByItemId: aiTextBaseOzByItemId,
                        trackedNutrientKeys: trackedNutrientKeys,
                        mealGroup: genericMealGroup(for: Date()),
                        onConfirm: { pairs in
                            addAITextItemsWithPortions(pairs)
                            clearAITextPlateState()
                            clearAITextMealState()
                        },
                        onDismiss: {
                            clearAITextPlateState()
                        }
                    )
                }
            }
    }

    var rootShellModalHost: some View {
        rootShellSheetHost
            .sheet(isPresented: $isQuickAddManagerPresented) {
                quickAddManagerSheet
            }
            .sheet(isPresented: $isQuickAddPickerPresented) {
                quickAddPickerSheet
            }
            .sheet(isPresented: $isAddExerciseSheetPresented) {
                AddExerciseSheet(
                    weightPounds: resolvedBMRProfile?.weightPounds ?? 170,
                    surfacePrimary: surfacePrimary,
                    surfaceSecondary: surfaceSecondary,
                    textPrimary: textPrimary,
                    textSecondary: textSecondary,
                    accent: accent,
                    onAdd: { draft in
                        let reclassifiedWalkingCalories: Int
                        if draft.exerciseType == .running {
                            let walkingEquivalent = ExerciseCalorieService.walkingEquivalentCalories(
                                type: draft.exerciseType,
                                durationMinutes: draft.durationMinutes,
                                distanceMiles: draft.distanceMiles,
                                weightPounds: resolvedBMRProfile?.weightPounds ?? 170
                            )
                            let availableWalkingCalories = max(activityCaloriesToday - reclassifiedWalkingCaloriesToday, 0)
                            reclassifiedWalkingCalories = min(walkingEquivalent, availableWalkingCalories)
                        } else {
                            reclassifiedWalkingCalories = 0
                        }

                        let entry = ExerciseEntry(
                            id: UUID(),
                            exerciseType: draft.exerciseType,
                            customName: draft.customName,
                            durationMinutes: draft.durationMinutes,
                            distanceMiles: draft.distanceMiles,
                            calories: draft.calories,
                            reclassifiedWalkingCalories: reclassifiedWalkingCalories,
                            createdAt: Date()
                        )
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                            exercises.append(entry)
                        }
                    }
                )
            }
            .sheet(isPresented: $isAddDestinationPickerPresented) {
                addDestinationPickerSheet
            }
            .sheet(isPresented: $isResetConfirmationPresented) {
                resetTodaySheet
            }
    }

    var addDestinationPickerSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Add Food")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(textPrimary)
            }

            VStack(spacing: 12) {
                Button {
                    openAddDestination(.pccMenu)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: AddDestination.pccMenu.iconName)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(accent)
                        Text(AddDestination.pccMenu.title)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(textPrimary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(surfaceSecondary.opacity(0.95))
                    )
                }
                .buttonStyle(.plain)

                Button {
                    openAddDestination(.manualEntry)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: AddDestination.manualEntry.iconName)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(accent)
                        Text(AddDestination.manualEntry.title)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(textPrimary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(surfaceSecondary.opacity(0.95))
                    )
                }
                .buttonStyle(.plain)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    addDestinationSquareButton(title: "Search Foods", icon: "magnifyingglass") {
                        openAddDestination(.usdaSearch)
                    }

                    addDestinationSquareButton(title: "Scan Barcode", icon: "barcode.viewfinder") {
                        openBarcodeScannerFromPicker()
                    }

                    addDestinationSquareButton(title: "Smart Log", icon: "sparkles") {
                        openAddDestination(.aiPhoto)
                    }

                    addDestinationSquareButton(title: "Quick add", icon: "bolt.fill") {
                        openAddDestination(.quickAdd)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 28)
        .padding(.bottom, 16)
        .presentationDetents([.height(428)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(32)
        .presentationBackground(surfacePrimary)
    }

    func addDestinationSquareButton(
        title: String,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(accent)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(textPrimary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .center)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(surfaceSecondary.opacity(0.95))
            )
        }
        .buttonStyle(.plain)
    }

    var resetTodaySheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Reset today?")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(textPrimary)

                Text("This will remove all food and exercise entries logged today.")
                    .font(.subheadline)
                    .foregroundStyle(textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 12) {
                Button(role: .destructive) {
                    isResetConfirmationPresented = false
                    resetTodayLog()
                } label: {
                    Text("Reset Today")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(Color.red)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    isResetConfirmationPresented = false
                } label: {
                    Text("Cancel")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(surfaceSecondary.opacity(0.95))
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 20)
        .presentationDetents([.height(240)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(32)
        .presentationBackground(surfacePrimary)
    }

    var appChrome: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                colors: [backgroundTop, backgroundBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            activeTabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            topSafeAreaShield

            feedbackToast

            bottomTabBar

            embeddedMenuAIPopupOverlay
        }
        .animation(.easeInOut(duration: 0.18), value: isEmbeddedMenuAIPopupPresented)
    }

    var topSafeAreaShield: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [backgroundTop.opacity(0.98), backgroundTop.opacity(0.92)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: proxy.safeAreaInsets.top + 12)

                Spacer()
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }

    var feedbackToast: some View {
        VStack {
            Spacer()

            if let barcodeErrorToastMessage, selectedAddDestination != .barcode {
                barcodeErrorToastView
            } else if isAddConfirmationPresented {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(accent)
                    Text("Added")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(textPrimary)
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
        .allowsHitTesting(false)
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: isAddConfirmationPresented)
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: barcodeErrorToastMessage)
    }

    var barcodeErrorToastView: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(Color.orange)
            Text(barcodeErrorToastMessage ?? "Barcode lookup failed.")
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

    var embeddedMenuAIPopupOverlay: some View {
        ZStack {
            Color.black
                .opacity(isEmbeddedMenuAIPopupPresented ? 0.28 : 0)
                .ignoresSafeArea()
                .onTapGesture {
                    guard isEmbeddedMenuAIPopupPresented else { return }
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isEmbeddedMenuAIPopupPresented = false
                    }
                }

            embeddedMenuAIPopupCard
                .opacity(isEmbeddedMenuAIPopupPresented ? 1 : 0)
        }
        .allowsHitTesting(isEmbeddedMenuAIPopupPresented)
    }

    var embeddedMenuAIPopupCard: some View {
        VStack {
            Spacer()

            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("AI portion estimation")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(textPrimary)
                    Text("Add a plate photo from camera or library.")
                        .font(.body)
                        .foregroundStyle(textSecondary)
                }

                VStack(spacing: 12) {
                    embeddedMenuAIPopupButton(title: "Use camera") {
                        embeddedMenuRequestedAIPickerSource = .camera
                        withAnimation(.easeInOut(duration: 0.18)) {
                            isEmbeddedMenuAIPopupPresented = false
                        }
                    }

                    embeddedMenuAIPopupButton(title: "Choose from library") {
                        embeddedMenuRequestedAIPickerSource = .photoLibrary
                        withAnimation(.easeInOut(duration: 0.18)) {
                            isEmbeddedMenuAIPopupPresented = false
                        }
                    }
                }
            }
            .padding(22)
            .frame(maxWidth: 340)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(surfacePrimary.opacity(0.98))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(textSecondary.opacity(0.14), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.22), radius: 24, y: 10)
            .padding(.horizontal, 24)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    func embeddedMenuAIPopupButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    Capsule(style: .continuous)
                        .fill(surfaceSecondary.opacity(0.96))
                )
        }
        .buttonStyle(.plain)
    }

    var menuSheet: some View {
        menuPage(onClose: nil, bottomOverlayClearance: 0)
            .fullScreenCover(isPresented: $isPlateEstimateLoading) {
                ZStack {
                    Color.black.opacity(0.7)
                        .ignoresSafeArea()
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.2)
                            .tint(.white)
                        Text("Estimating portions…")
                            .font(.headline.weight(.medium))
                            .foregroundStyle(.white)
                    }
                }
                .interactiveDismissDisabled()
            }
            .alert("Portion estimate failed", isPresented: Binding(get: { plateEstimateErrorMessage != nil }, set: { if !$0 { plateEstimateErrorMessage = nil } })) {
                Button("OK", role: .cancel) {
                    plateEstimateErrorMessage = nil
                }
            } message: {
                Text(plateEstimateErrorMessage ?? "Unknown error")
            }
    }

    func menuPage(
        onClose: (() -> Void)?,
        bottomOverlayClearance: CGFloat,
        onRequestExternalAIPopup: (() -> Void)? = nil,
        requestedExternalAIPickerSource: PlateImagePickerView.Source? = nil,
        clearRequestedExternalAIPickerSource: @escaping () -> Void = {}
    ) -> some View {
        MenuSheetView(
            menu: currentMenu,
            venue: selectedMenuVenue,
            sourceTitle: selectedMenuVenue.title,
            mealTitle: selectedMenuType.title,
            selectedMenuType: selectedMenuType,
            availableMenuTypes: availableMenuTypesForSelectedVenue,
            trackedNutrientKeys: trackedNutrientKeys,
            selectedItemQuantities: Binding(
                get: { menuQuantities(for: selectedMenuVenue, menuType: selectedMenuType) },
                set: { newValue in
                    setMenuQuantities(newValue, for: selectedMenuVenue, menuType: selectedMenuType)
                }
            ),
            selectedItemMultipliers: Binding(
                get: { menuMultipliers(for: selectedMenuVenue, menuType: selectedMenuType) },
                set: { newValue in
                    setMenuMultipliers(newValue, for: selectedMenuVenue, menuType: selectedMenuType)
                }
            ),
            isLoading: isMenuLoading,
            errorMessage: currentMenuError,
            onRetry: {
                await loadMenuFromFirebase()
            },
            onAddSelected: {
                addSelectedMenuItems()
            },
            onPhotoPlate: { items, imageData in
                handlePhotoPlate(items: items, imageData: imageData)
            },
            plateEstimateItems: $plateEstimateItems,
            plateEstimateOzByItemId: $plateEstimateOzByItemId,
            plateEstimateBaseOzByItemId: plateEstimateBaseOzByItemId,
            mealGroup: mealGroup(for: selectedMenuType),
            onPlateEstimateConfirm: { pairs in
                addMenuItemsWithPortions(pairs)
                plateEstimateItems = nil
                plateEstimateOzByItemId = [:]
                plateEstimateBaseOzByItemId = [:]
                isMenuSheetPresented = false
                clearMenuSelection()
            },
            onPlateEstimateDismiss: {
                plateEstimateItems = nil
                plateEstimateOzByItemId = [:]
                plateEstimateBaseOzByItemId = [:]
            },
            onVenueChange: { newVenue in
                switchMenuToVenue(newVenue)
            },
            onMenuTypeChange: { newMenuType in
                switchMenuToMealType(newMenuType)
            },
            onClose: onClose,
            bottomOverlayClearance: bottomOverlayClearance,
            onRequestExternalAIPopup: onRequestExternalAIPopup,
            requestedExternalAIPickerSource: requestedExternalAIPickerSource,
            clearRequestedExternalAIPickerSource: clearRequestedExternalAIPickerSource
        )
    }

    var pccMenuPage: some View {
        menuPage(
            onClose: nil,
            bottomOverlayClearance: 0,
            onRequestExternalAIPopup: {
                isEmbeddedMenuAIPopupPresented = true
            },
            requestedExternalAIPickerSource: embeddedMenuRequestedAIPickerSource,
            clearRequestedExternalAIPickerSource: {
                embeddedMenuRequestedAIPickerSource = nil
            }
        )
        .safeAreaInset(edge: .bottom) {
            Color.clear
                .frame(height: Self.embeddedMenuBottomClearance)
        }
        .fullScreenCover(isPresented: $isPlateEstimateLoading) {
            ZStack {
                Color.black.opacity(0.7)
                    .ignoresSafeArea()
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)
                        .tint(.white)
                    Text("Estimating portions…")
                        .font(.headline.weight(.medium))
                        .foregroundStyle(.white)
                }
            }
            .interactiveDismissDisabled()
        }
        .alert("Portion estimate failed", isPresented: Binding(get: { plateEstimateErrorMessage != nil }, set: { if !$0 { plateEstimateErrorMessage = nil } })) {
            Button("OK", role: .cancel) {
                plateEstimateErrorMessage = nil
            }
        } message: {
            Text(plateEstimateErrorMessage ?? "Unknown error")
        }
    }

    var quickAddManagerSheet: some View {
        QuickAddManagerView(
            quickAddFoods: $quickAddFoods,
            trackedNutrientKeys: trackedNutrientKeys,
            storedVenueMenus: venueMenus,
            surfacePrimary: surfacePrimary,
            surfaceSecondary: surfaceSecondary,
            textPrimary: textPrimary,
            textSecondary: textSecondary,
            accent: accent
        )
    }

    var quickAddPickerSheet: some View {
        QuickAddPickerView(
            quickAddFoods: quickAddFoods,
            surfacePrimary: surfacePrimary,
            surfaceSecondary: surfaceSecondary,
            textPrimary: textPrimary,
            textSecondary: textSecondary,
            accent: accent,
            trackedNutrientKeys: trackedNutrientKeys,
            onAddSelected: { selections in
                addQuickAddFoods(selections, dismissPickerAfterAdd: true)
            },
            onManage: {
                presentQuickAddManagerFromPicker()
            },
            onClose: nil,
            showsStandaloneChrome: true
        )
    }

    func editEntrySheet(entry: MealEntry) -> some View {
        EditMealEntrySheet(
            entry: entry,
            editableNutrients: editableNutrients(for: entry),
            initialMealGroup: entry.mealGroup,
            surfacePrimary: surfacePrimary,
            surfaceSecondary: surfaceSecondary,
            textPrimary: textPrimary,
            textSecondary: textSecondary,
            accent: accent,
            onSave: { updatedEntry in
                updateEntry(updatedEntry)
            }
        )
    }

    func foodLogEntryPickerSheet(initialContext: FoodLogEntryPickerContext, context: Binding<FoodLogEntryPickerContext?>) -> some View {
        let resolvedContext = context.wrappedValue ?? initialContext
        let pickerTitle = resolvedContext.title
        let pickerEntries = resolvedContext.entries

        return NavigationStack {
            List {
                Section {
                    ForEach(pickerEntries.sorted { $0.createdAt > $1.createdAt }) { entry in
                        Button {
                            foodLogEntryPickerContext = nil
                            DispatchQueue.main.async {
                                editingEntry = entry
                            }
                        } label: {
                            HStack(alignment: .center, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(entry.name)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(textPrimary)
                                    Text(entry.createdAt.formatted(date: .omitted, time: .shortened))
                                        .font(.caption)
                                        .foregroundStyle(textSecondary)
                                }

                                Spacer()

                                Text("\(entry.calories) cal")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(textSecondary)
                                    .monospacedDigit()
                            }
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(surfacePrimary)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                deleteEntry(entry)
                                let remainingEntries = pickerEntries.filter { $0.id != entry.id }
                                if remainingEntries.isEmpty {
                                    foodLogEntryPickerContext = nil
                                } else {
                                    context.wrappedValue?.entries = remainingEntries
                                }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    Text("Choose an entry to edit")
                        .foregroundStyle(textSecondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(surfaceSecondary.ignoresSafeArea())
            .navigationTitle(pickerTitle)
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.height(280), .large])
        .presentationDragIndicator(.visible)
    }


    var bottomTabBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            tabBarButton(for: .today)
            tabBarButton(for: .history)
            tabBarButton(for: .add, isCenter: true)
            tabBarButton(for: .profile)
            tabBarButton(for: .settings)
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 14)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(surfacePrimary.opacity(0.94))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(textSecondary.opacity(0.18), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.24), radius: 24, x: 0, y: 10)
                .ignoresSafeArea(edges: .bottom)
        )
        .overlay(alignment: .top) {
            Color.clear
                .frame(height: 1)
                .accessibilityIdentifier("app.bottomTabBar.topEdge")
        }
    }

    func tabBarButton(for tab: AppTab, isCenter: Bool = false) -> some View {
        let isSelected = selectedTab == tab

        return Button {
            if tab == .add {
                dismissKeyboard()
                isAddDestinationPickerPresented = true
            } else {
                if selectedTab == .add, selectedAddDestination == .pccMenu {
                    clearMenuSelection()
                }
                clearAITextMealState()
                withAnimation(.none) {
                    selectedTab = tab
                }
            }
            Haptics.selection()
        } label: {
            VStack(spacing: isCenter ? 0 : 6) {
                if isCenter {
                    Image(systemName: tab.iconName)
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 72, height: 72)
                        .background(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .fill(accent)
                                .shadow(color: isSelected ? accent.opacity(0.38) : .clear, radius: 18, x: 0, y: 10)
                        )
                        .offset(y: 4)
                } else {
                    Image(systemName: tab.iconName)
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(isSelected ? accent : textSecondary)

                    Text(tab.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isSelected ? accent : textSecondary)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        // Prevent implicit fade/transition on selection color changes.
        .transaction { txn in
            txn.animation = nil
        }
    }


}
