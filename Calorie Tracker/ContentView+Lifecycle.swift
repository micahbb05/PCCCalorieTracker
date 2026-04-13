// Calorie Tracker 2026

import SwiftUI
import UIKit

extension ContentView {

    func handleOnAppear() {
        if isPCCMenuUITestMode {
            return
        }

        bootstrapPersistentStateStore()
        sanitizeStoredGoals()
        loadTrackingPreferences()
        loadDailyEntryArchive()
        loadCalibrationState()
        if goalType == .fixed, calibrationState.isEnabled {
            calibrationState.isEnabled = false
            saveCalibrationState()
        }
        loadHealthWeighIns()
        loadCloudSyncedHealthState()
        loadQuickAddFoods()
        loadVenueMenus()
        selectedMenuType = menuService.currentMenuType()
        Task(priority: .userInitiated) {
            await preloadMenuForNutrientDiscovery()
        }
        Task(priority: .utility) {
            await bootstrapCloudSync(trigger: .launch)
        }
        applyCentralTimeTransitions(forceMenuReload: false)
        syncInputFieldsToTrackedNutrients()
        AppIconManager.apply(selectedAppIconChoice)
        stepActivityService.refreshIfAuthorized()
        Task {
            await healthKitService.refreshIfPossible()
            await MainActor.run {
                scheduleCalibrationEvaluation()
            }
        }
        syncCurrentDayGoalArchive()
        scheduleCalibrationEvaluation()
        persistStateSnapshot()
        bootstrapSmartMealReminders()
        pushWatchSnapshot()
    }

    func pushWatchSnapshot() {
        WatchAppSyncService.shared.push(context: makeWatchSnapshotContext())
    }

    func makeWatchSnapshotContext() -> [String: Any] {
        let mealType = menuService.currentMenuType()
        let mealTitle = mealType.title

        var venueMenuItems: [String: [String]] = [:]
        for venue in DiningVenue.allCases {
            let items: [String]
            if venue.supportedMenuTypes.contains(mealType) {
                items = menu(for: venue, menuType: mealType)
                    .lines
                    .flatMap(\.items)
                    .map(\.name)
                    .prefix(20)
                    .map { $0 }
            } else {
                items = []
            }
            venueMenuItems[venue.rawValue] = items
        }

        let recentEntries = entries
            .sorted(by: { $0.createdAt > $1.createdAt })
            .prefix(12)
            .map { entry in
                [
                    "id": entry.id.uuidString,
                    "name": entry.name,
                    "calories": entry.calories,
                    "createdAt": entry.createdAt.timeIntervalSince1970
                ] as [String: Any]
            }

        let activityCalories = max(effectiveActivityCaloriesToday + exerciseCaloriesToday, 0)

        return [
            "goalCalories": calorieGoal,
            "activityCalories": activityCalories,
            "currentMealTitle": mealTitle,
            "goalTypeRaw": goalType.rawValue,
            "selectedAppIconChoiceRaw": selectedAppIconChoiceRaw,
            "venueMenuItems": venueMenuItems,
            "entries": recentEntries
        ]
    }

    var isPCCMenuUITestMode: Bool {
        UserDefaults.standard.bool(forKey: Self.pccMenuUITestLaunchArgument)
            || ProcessInfo.processInfo.arguments.contains("-\(Self.pccMenuUITestLaunchArgument)")
            || ProcessInfo.processInfo.arguments.contains(Self.pccMenuUITestLaunchArgument)
            || ProcessInfo.processInfo.environment[Self.pccMenuUITestLaunchArgument] == "1"
    }

    var uiTestPCCMenuRoot: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                colors: [backgroundTop, backgroundBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            MenuSheetView(
                menu: Self.pccMenuUITestFixture,
                venue: .fourWinds,
                sourceTitle: DiningVenue.fourWinds.title,
                mealTitle: "Dinner",
                selectedMenuType: .dinner,
                availableMenuTypes: [.lunch, .dinner],
                trackedNutrientKeys: trackedNutrientKeys,
                selectedItemQuantities: Binding(
                    get: {
                        selectedMenuItemQuantitiesByVenue[.fourWinds]?[.dinner]
                            ?? ["entree-1": 1]
                    },
                    set: { newValue in
                        var venueCache = selectedMenuItemQuantitiesByVenue[.fourWinds] ?? [:]
                        venueCache[.dinner] = newValue
                        selectedMenuItemQuantitiesByVenue[.fourWinds] = venueCache
                    }
                ),
                selectedItemMultipliers: Binding(
                    get: {
                        selectedMenuItemMultipliersByVenue[.fourWinds]?[.dinner]
                            ?? ["entree-1": 1.0]
                    },
                    set: { newValue in
                        var venueCache = selectedMenuItemMultipliersByVenue[.fourWinds] ?? [:]
                        venueCache[.dinner] = newValue
                        selectedMenuItemMultipliersByVenue[.fourWinds] = venueCache
                    }
                ),
                isLoading: false,
                errorMessage: nil,
                onRetry: {},
                onAddSelected: {},
                onPhotoPlate: nil,
                plateEstimateItems: $plateEstimateItems,
                plateEstimateOzByItemId: $plateEstimateOzByItemId,
                plateEstimateBaseOzByItemId: [:],
                mealGroup: .dinner,
                onPlateEstimateConfirm: { _ in },
                onPlateEstimateDismiss: {},
                onVenueChange: { _ in },
                onMenuTypeChange: { _ in },
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            topSafeAreaShield
            bottomTabBar
        }
        .onAppear {
            selectedTab = .add
        }
    }

    static var pccMenuUITestFixture: NutrisliceMenu {
        let entreeItems = (1...12).map { index in
            MenuItem(
                id: "entree-\(index)",
                name: index == 1 ? "Grilled Chicken Bowl" : "Entree Item \(index)",
                calories: 300 + index * 15,
                nutrientValues: [
                    "calories": 300 + index * 15,
                    "g_protein": 18 + index,
                    "g_carbs": 20 + index * 2,
                    "g_fat": 8 + index
                ],
                servingAmount: 6,
                servingUnit: "oz"
            )
        }

        let lineNames = [
            "Entrees",
            "Sides",
            "Vegetables",
            "Soups",
            "Salads",
            "Sandwiches",
            "Pizza",
            "Pasta",
            "Grill",
            "Rice Bowls",
            "Bakery",
            "Desserts"
        ]

        let lines = lineNames.enumerated().map { offset, lineName in
            let itemCount = lineName == "Entrees" ? entreeItems.count : 3
            let items = lineName == "Entrees"
                ? entreeItems
                : (1...itemCount).map { index in
                    MenuItem(
                        id: "\(lineName.lowercased().replacingOccurrences(of: " ", with: "-"))-\(index)",
                        name: lineName == "Sides" && index == 2 ? "Garlic Green Beans" : "\(lineName) Item \(index)",
                        calories: 90 + (offset * 20) + index * 10,
                        nutrientValues: [
                            "calories": 90 + (offset * 20) + index * 10,
                            "g_protein": 3 + offset + index,
                            "g_carbs": 10 + offset + index * 2,
                            "g_fat": 2 + offset + index
                        ],
                        servingAmount: 4,
                        servingUnit: "oz"
                    )
                }

            return MenuLine(
                id: lineName.lowercased().replacingOccurrences(of: " ", with: "-"),
                name: lineName,
                items: items
            )
        }

        return NutrisliceMenu(
            lines: lines,
            nutrientNullRateByKey: [:]
        )
    }

    func completeOnboarding() {
        sanitizeStoredGoals()
        normalizeTrackingState()
        saveTrackingPreferences()
        syncInputFieldsToTrackedNutrients()
        selectedTab = .today
        onboardingPage = OnboardingPage.welcome.rawValue
        hasRequestedHealthDuringOnboarding = false
        hasCompletedOnboarding = true
    }

    func skipOnboarding() {
        sanitizeStoredGoals()
        normalizeTrackingState()
        saveTrackingPreferences()
        syncInputFieldsToTrackedNutrients()
        selectedTab = .today
        onboardingPage = OnboardingPage.welcome.rawValue
        hasRequestedHealthDuringOnboarding = false
        hasCompletedOnboarding = true
    }

    func handleHealthProfileChange(_ newProfile: HealthKitService.SyncedProfile?) {
        syncCurrentDayGoalArchive()
        scheduleCalibrationEvaluation()
    }

    func requestUnifiedHealthAccessAndRefresh() async {
        await healthKitService.requestAccessAndRefresh()
        stepActivityService.refreshIfAuthorized()
        scheduleCalibrationEvaluation()
    }

    func handleScenePhaseChange(_ newPhase: ScenePhase) {
        guard newPhase == .active else { return }
        applyCentralTimeTransitions(forceMenuReload: false)
        stepActivityService.refreshIfAuthorized()
        Task {
            await healthKitService.refreshIfPossible()
            await MainActor.run {
                scheduleCalibrationEvaluation()
            }
        }
        Task(priority: .utility) {
            await bootstrapCloudSync(trigger: .foreground)
        }
        syncCurrentDayGoalArchive()
        syncHistorySelection(preferToday: true)
        scheduleCalibrationEvaluation()
        syncSmartMealReminders()
        Task {
            await preloadMenuForNutrientDiscovery()
        }
    }

    func handleClockTick() {
        applyCentralTimeTransitions(forceMenuReload: false)
        stepActivityService.refreshIfAuthorized()
        Task {
            await healthKitService.refreshIfPossible()
            await MainActor.run {
                scheduleCalibrationEvaluation()
            }
        }
        Task(priority: .utility) {
            await bootstrapCloudSync(trigger: .timer)
        }
        syncCurrentDayGoalArchive()
        scheduleCalibrationEvaluation()
        syncSmartMealReminders()
    }

    func bootstrapSmartMealReminders() {
        guard smartMealRemindersEnabled else {
            syncSmartMealReminders()
            return
        }

        SmartMealReminderService.shared.requestAuthorizationIfNeeded { granted in
            DispatchQueue.main.async {
                if !granted {
                    smartMealRemindersEnabled = false
                    return
                }
                syncSmartMealReminders()
            }
        }
    }

    func handleSmartMealRemindersPreferenceChange(_ isEnabled: Bool) {
        guard isEnabled else {
            syncSmartMealReminders()
            return
        }

        SmartMealReminderService.shared.requestAuthorizationIfNeeded { granted in
            DispatchQueue.main.async {
                if !granted {
                    smartMealRemindersEnabled = false
                    return
                }
                syncSmartMealReminders()
            }
        }
    }

    func syncSmartMealReminders() {
        SmartMealReminderService.shared.refreshReminders(
            enabled: smartMealRemindersEnabled,
            now: Date(),
            calendar: centralCalendar,
            dailyEntryArchive: dailyEntryArchive,
            todayDayIdentifier: todayDayIdentifier
        )
    }

    @ViewBuilder
    var activeTabContent: some View {
        Group {
            switch selectedTab {
            case .today:    todayTabView
            case .history:  historyTabView
            case .add:      addTabView
            case .profile:  profileTabView
            case .settings: settingsTabView
            }
        }
        .id(selectedTab)
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.18), value: selectedTab)
    }

    func updateKeyboardState(from notification: Notification) {
        let endFrame = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect) ?? .zero
        let duration = (notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.25
        let visibleHeight: CGFloat = {
            if notification.name == UIResponder.keyboardWillHideNotification {
                return 0
            }

            let screenBounds = UIScreen.main.bounds
            let overlapHeight = endFrame.intersection(screenBounds).height
            return max(0, overlapHeight)
        }()

        withAnimation(.easeOut(duration: duration)) {
            keyboardHeight = visibleHeight
            isKeyboardVisible = visibleHeight > 0
        }
    }
}
