import SwiftUI
import Charts
import UIKit
import Combine

private enum AppTab: String, CaseIterable, Identifiable {
    case today
    case history
    case add
    case profile
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "Today"
        case .history: return "History"
        case .add: return "Add Food"
        case .profile: return "Profile"
        case .settings: return "Settings"
        }
    }

    var label: String {
        switch self {
        case .today: return "Today"
        case .history: return "History"
        case .add: return "Add"
        case .profile: return "Profile"
        case .settings: return "Settings"
        }
    }

    var iconName: String {
        switch self {
        case .today: return "fork.knife"
        case .history: return "clock.arrow.circlepath"
        case .add: return "plus"
        case .profile: return "person"
        case .settings: return "gearshape"
        }
    }
}

struct ContentView: View {
    private struct FoodReviewItem: Identifiable {
        let id = UUID()
        let name: String
        let subtitle: String?
        let calories: Int
        let nutrientValues: [String: Int]
        let servingAmount: Double
        let servingUnit: String
        let entrySource: EntrySource
    }

    private struct HistoryDaySummary: Identifiable {
        let dayIdentifier: String
        let date: Date
        let totalCalories: Int
        let entryCount: Int
        let goalMet: Bool

        var id: String { dayIdentifier }
    }

    private struct CalorieGraphPoint: Identifiable {
        let dayIdentifier: String
        let date: Date
        let calories: Int
        let goal: Int
        let burned: Int

        var id: String { dayIdentifier }
    }

    private struct SegmentedCalorieLinePoint: Identifiable {
        let point: CalorieGraphPoint
        let segment: Int

        var id: String { "\(segment)-\(point.dayIdentifier)" }
    }

    private enum EntrySource {
        case manual
        case quickAdd
        case barcode
        case usda
        case pccMenu(NutrisliceMenuService.MenuType)
    }

    private enum HistoryChartRange: String, CaseIterable, Identifiable {
        case thirtyDays
        case sixMonths
        case oneYear
        case twoYears

        var id: String { rawValue }

        var title: String {
            switch self {
            case .thirtyDays: return "30 Days"
            case .sixMonths: return "6 Months"
            case .oneYear: return "1 Year"
            case .twoYears: return "2 Years"
            }
        }

        var dayCount: Int {
            switch self {
            case .thirtyDays: return 30
            case .sixMonths: return 182
            case .oneYear: return 365
            case .twoYears: return 730
            }
        }
    }

    private enum NetHistoryRange: String, CaseIterable, Identifiable {
        case sevenDays
        case thirtyDays
        case sixMonths
        case oneYear
        case twoYears

        var id: String { rawValue }

        var title: String {
            switch self {
            case .sevenDays: return "7 Days"
            case .thirtyDays: return "30 Days"
            case .sixMonths: return "6 Months"
            case .oneYear: return "1 Year"
            case .twoYears: return "2 Years"
            }
        }

        var dayCount: Int {
            switch self {
            case .sevenDays: return 7
            case .thirtyDays: return 30
            case .sixMonths: return 182
            case .oneYear: return 365
            case .twoYears: return 730
            }
        }
    }

    private struct DailyCalorieModel {
        let bmr: Int?
        let burned: Int
        let goal: Int
        let deficit: Int
        let usesBMR: Bool
    }

    private static let fallbackAverageBMR = 1800

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    @AppStorage("deficitCalories") private var storedDeficitCalories: Int = 500
    @AppStorage("useWeekendDeficit") private var useWeekendDeficit: Bool = false
    @AppStorage("weekendDeficitCalories") private var storedWeekendDeficitCalories: Int = 0
    @AppStorage("goalTypeRaw") private var goalTypeRaw: String = GoalType.deficit.rawValue
    @AppStorage("surplusCalories") private var storedSurplusCalories: Int = 300
    @AppStorage("dailyGoalTypeArchiveData") private var storedDailyGoalTypeArchiveData: String = ""

    private enum GoalType: String, CaseIterable {
        case deficit
        case surplus

        var title: String {
            switch self {
            case .deficit: return "Deficit"
            case .surplus: return "Surplus"
            }
        }

        var subtitle: String {
            switch self {
            case .deficit: return "Subtract from burned to lose weight"
            case .surplus: return "Add to burned to gain weight"
            }
        }
    }

    private var goalType: GoalType {
        GoalType(rawValue: goalTypeRaw) ?? .deficit
    }
    @AppStorage("proteinGoal") private var legacyStoredProteinGoal: Int = 150
    @AppStorage("mealEntriesData") private var storedEntriesData: String = ""
    @AppStorage("trackedNutrientsData") private var storedTrackedNutrientsData: String = ""
    @AppStorage("nutrientGoalsData") private var storedNutrientGoalsData: String = ""
    @AppStorage("lastCentralDayIdentifier") private var lastCentralDayIdentifier: String = ""
    @AppStorage("selectedAppIconChoice") private var selectedAppIconChoiceRaw: String = AppIconChoice.standard.rawValue
    @AppStorage("dailyEntryArchiveData") private var storedDailyEntryArchiveData: String = ""
    @AppStorage("dailyCalorieGoalArchiveData") private var storedDailyCalorieGoalArchiveData: String = ""
    @AppStorage("dailyBurnedCalorieArchiveData") private var storedDailyBurnedCalorieArchiveData: String = ""
    @AppStorage("dailyExerciseArchiveData") private var storedDailyExerciseArchiveData: String = ""
    @AppStorage("venueMenusData") private var storedVenueMenusData: String = ""
    @AppStorage("venueMenuSignaturesData") private var storedVenueMenuSignaturesData: String = ""
    @AppStorage("quickAddFoodsData") private var storedQuickAddFoodsData: String = ""
    /// When true, Gemini can override ambiguous base servings (e.g. \"1 each\" entrees) with its inferred base oz.
    /// When false, base servings always come from the menu's serving size.
    @AppStorage("useAIBaseServings") private var useAIBaseServings: Bool = true

    @State private var entries: [MealEntry] = []
    @State private var exercises: [ExerciseEntry] = []
    @State private var dailyEntryArchive: [String: [MealEntry]] = [:]
    @State private var dailyCalorieGoalArchive: [String: Int] = [:]
    @State private var dailyBurnedCalorieArchive: [String: Int] = [:]
    @State private var dailyExerciseArchive: [String: [ExerciseEntry]] = [:]
    @State private var dailyGoalTypeArchive: [String: String] = [:]
    @State private var quickAddFoods: [QuickAddFood] = []
    @State private var trackedNutrientKeys: [String] = ["g_protein"]
    @State private var nutrientGoals: [String: Int] = [:]
    @State private var entryNameText = ""
    @State private var entryCaloriesText = ""
    @State private var nutrientInputTexts: [String: String] = [:]

    @State private var isMenuSheetPresented = false
    @State private var isBarcodeScannerPresented = false
    @State private var isBarcodeLookupInFlight = false
    @State private var barcodeLookupError: String?
    @State private var hasScannedBarcodeInCurrentSheet = false
    @State private var isUSDASearchPresented = false
    @State private var usdaSearchText = ""
    @State private var usdaSearchResults: [USDAFoodSearchResult] = []
    @State private var isUSDASearchLoading = false
    @State private var usdaSearchError: String?
    @State private var usdaSearchDebounceTask: Task<Void, Never>?
    @State private var foodReviewItem: FoodReviewItem?
    @State private var selectedFoodReviewMultiplier = 1.0
    @State private var selectedTab: AppTab = .today
    @State private var selectedMenuVenue: DiningVenue = .fourWinds
    @State private var selectedHistoryDayIdentifier = ""
    @State private var displayedHistoryMonth = Date()
    @State private var presentedHistoryDaySummary: HistoryDaySummary?
    @State private var isExpandedHistoryChartPresented = false
    @State private var expandedHistoryChartRange: HistoryChartRange = .thirtyDays
    @State private var netHistoryRange: NetHistoryRange = .sevenDays
    @State private var historyDistributionRange: NetHistoryRange = .sevenDays
    @State private var editingEntry: MealEntry?
    @State private var isQuickAddManagerPresented = false
    @State private var isQuickAddPickerPresented = false
    @State private var onboardingPage = 0
    @State private var hasRequestedHealthDuringOnboarding = false

    @State private var venueMenus: [DiningVenue: NutrisliceMenu] = [:]
    @State private var selectedMenuItemQuantitiesByVenue: [DiningVenue: [String: Int]] = [:]
    @State private var selectedMenuItemMultipliersByVenue: [DiningVenue: [String: Double]] = [:]
    @State private var isMenuLoading = false
    @State private var menuLoadErrorsByVenue: [DiningVenue: String] = [:]
    @State private var lastLoadedMenuSignatureByVenue: [DiningVenue: String] = [:]
    @State private var isResetConfirmationPresented = false
    @State private var isKeyboardVisible = false
    @State private var keyboardHeight: CGFloat = 0
    @State private var isAddNutrientsExpanded = false
    @State private var isExerciseSectionCollapsed = false
    @State private var isAddExerciseSheetPresented = false
    @State private var plateEstimateItems: [MenuItem]?
    @State private var plateEstimateOzByItemId: [String: Double] = [:]
    @State private var plateEstimateBaseOzByItemId: [String: Double] = [:]
    @State private var isPlateEstimateLoading = false
    @State private var plateEstimateErrorMessage: String?

    @FocusState private var focusedField: Field?
    @StateObject private var stepActivityService = StepActivityService()
    @StateObject private var healthKitService = HealthKitService()

    private let menuService = NutrisliceMenuService()
    private let openFoodFactsService = OpenFoodFactsService()
    private let usdaFoodService = USDAFoodService()
    private let clockTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private enum Field: Hashable {
        case name
        case calories
        case nutrient(String)
    }

    private enum OnboardingPage: Int, CaseIterable {
        case welcome
        case health
        case deficit
        case nutrients
    }

    private var surfacePrimary: Color {
        colorScheme == .dark ? Color(red: 0.13, green: 0.15, blue: 0.20) : Color.white
    }

    private var surfaceSecondary: Color {
        colorScheme == .dark ? Color(red: 0.17, green: 0.19, blue: 0.25) : Color(red: 0.97, green: 0.98, blue: 1.00)
    }

    private var textPrimary: Color {
        colorScheme == .dark ? Color(red: 0.95, green: 0.96, blue: 0.98) : Color(red: 0.12, green: 0.14, blue: 0.18)
    }

    private var textSecondary: Color {
        colorScheme == .dark ? Color(red: 0.78, green: 0.81, blue: 0.86) : Color(red: 0.43, green: 0.47, blue: 0.54)
    }

    private var accent: Color { AppTheme.accent }

    private var backgroundTop: Color {
        colorScheme == .dark ? Color(red: 0.07, green: 0.08, blue: 0.12) : Color(red: 0.95, green: 0.97, blue: 0.99)
    }

    private var backgroundBottom: Color {
        colorScheme == .dark ? Color(red: 0.10, green: 0.11, blue: 0.17) : Color(red: 0.91, green: 0.94, blue: 0.98)
    }

    private var centralCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        return calendar
    }

    private var todayDayIdentifier: String {
        centralDayIdentifier(for: Date())
    }

    private var currentHistoryMonthTitle: String {
        displayedHistoryMonth.formatted(.dateTime.month(.wide).year())
    }

    private var historyMonthDays: [Date?] {
        guard
            let monthInterval = centralCalendar.dateInterval(of: .month, for: displayedHistoryMonth),
            let firstWeekInterval = centralCalendar.dateInterval(of: .weekOfMonth, for: monthInterval.start),
            let lastDayOfMonth = centralCalendar.date(byAdding: DateComponents(day: -1), to: monthInterval.end),
            let lastWeekInterval = centralCalendar.dateInterval(of: .weekOfMonth, for: lastDayOfMonth)
        else {
            return []
        }

        var days: [Date?] = []
        var cursor = firstWeekInterval.start
        while cursor < lastWeekInterval.end {
            if monthInterval.contains(cursor) {
                days.append(cursor)
            } else {
                days.append(nil)
            }

            guard let next = centralCalendar.date(byAdding: .day, value: 1, to: cursor) else {
                break
            }
            cursor = next
        }
        return days
    }

    private var deficitCalories: Int { min(max(storedDeficitCalories, 0), 2500) }
    private var surplusCalories: Int { min(max(storedSurplusCalories, 0), 2500) }
    private var weekendDeficitCalories: Int { min(max(storedWeekendDeficitCalories, 0), 2500) }

    private func goalTypeForDay(_ identifier: String) -> GoalType {
        if identifier == todayDayIdentifier {
            return goalType
        }
        if let raw = dailyGoalTypeArchive[identifier], let type = GoalType(rawValue: raw) {
            return type
        }
        return goalType
    }

    private func deficitForDay(_ identifier: String) -> Int {
        guard useWeekendDeficit else {
            return goalTypeForDay(identifier) == .surplus ? surplusCalories : deficitCalories
        }
        guard let date = date(fromCentralDayIdentifier: identifier) else {
            return goalTypeForDay(identifier) == .surplus ? surplusCalories : deficitCalories
        }
        let weekday = centralCalendar.component(.weekday, from: date)
        let isWeekend = (weekday == 1) || (weekday == 7)
        return isWeekend ? weekendDeficitCalories : (goalTypeForDay(identifier) == .surplus ? surplusCalories : deficitCalories)
    }
    private var resolvedBMRProfile: BMRProfile? { healthKitService.profile?.bmrProfile }
    private var activityCaloriesToday: Int {
        stepActivityService.estimatedCaloriesToday(profile: resolvedBMRProfile)
    }

    private var exerciseCaloriesToday: Int {
        let manual = exercises.reduce(0) { $0 + $1.calories }
        let health = healthKitService.todayWorkouts.reduce(0) { $0 + $1.calories }
        return manual + health
    }
    private var currentDailyCalorieModel: DailyCalorieModel {
        // Use archived goal/burned for today while HealthKit hasn't loaded, to avoid flash of fallback value
        if resolvedBMRProfile == nil,
           let archivedGoal = dailyCalorieGoalArchive[todayDayIdentifier],
           let archivedBurned = dailyBurnedCalorieArchive[todayDayIdentifier] {
            return DailyCalorieModel(
                bmr: nil,
                burned: archivedBurned,
                goal: archivedGoal,
                deficit: deficitForDay(todayDayIdentifier),
                usesBMR: false
            )
        }

        let bmr = resolvedBMRProfile.flatMap(calculatedBMR(for:)) ?? ContentView.fallbackAverageBMR
        let burned = max(bmr + activityCaloriesToday + exerciseCaloriesToday, 1)
        let dayGoalType = goalTypeForDay(todayDayIdentifier)
        let amount = deficitForDay(todayDayIdentifier)
        let goal: Int
        if dayGoalType == .surplus {
            goal = max(burned + amount, 1)
        } else {
            goal = max(burned - amount, 1)
        }
        return DailyCalorieModel(
            bmr: bmr,
            burned: burned,
            goal: goal,
            deficit: amount,
            usesBMR: resolvedBMRProfile != nil
        )
    }
    private var burnedCaloriesToday: Int { currentDailyCalorieModel.burned }
    private var calorieGoal: Int { currentDailyCalorieModel.goal }
    private var selectedAppIconChoice: AppIconChoice {
        AppIconChoice(rawValue: selectedAppIconChoiceRaw) ?? .standard
    }

    private var currentMenu: NutrisliceMenu {
        venueMenus[selectedMenuVenue] ?? .empty
    }

    private var currentMenuError: String? {
        menuLoadErrorsByVenue[selectedMenuVenue]
    }

    private var excludedNutrientKeys: Set<String> {
        let threshold = 0.95
        let dynamic = Set<String>(currentMenu.nutrientNullRateByKey.compactMap { key, rate in
            let normalized = key.lowercased()
            guard normalized != "g_protein", rate >= threshold else { return nil }
            return normalized
        })
        return dynamic.union(NutrientCatalog.defaultExcludedBecauseConsistentlyNull)
    }

    private var availableNutrientKeys: [String] {
        var keys = Set<String>(NutrientCatalog.knownKeys)

        for line in currentMenu.lines {
            for item in line.items {
                for key in item.nutrientValues.keys where !NutrientCatalog.nonTrackableKeys.contains(key.lowercased()) {
                    keys.insert(key.lowercased())
                }
            }
        }

        for entry in entries {
            for key in entry.nutrientValues.keys where !NutrientCatalog.nonTrackableKeys.contains(key.lowercased()) {
                keys.insert(key.lowercased())
            }
        }

        for archivedEntries in dailyEntryArchive.values {
            for entry in archivedEntries {
                for key in entry.nutrientValues.keys where !NutrientCatalog.nonTrackableKeys.contains(key.lowercased()) {
                    keys.insert(key.lowercased())
                }
            }
        }

        for key in trackedNutrientKeys where !NutrientCatalog.nonTrackableKeys.contains(key.lowercased()) {
            keys.insert(key.lowercased())
        }

        keys.insert("g_protein")
        keys.subtract(excludedNutrientKeys)
        return keys.sorted { lhs, rhs in
            let lhsRank = NutrientCatalog.preferredOrder.firstIndex(of: lhs) ?? Int.max
            let rhsRank = NutrientCatalog.preferredOrder.firstIndex(of: rhs) ?? Int.max
            if lhsRank != rhsRank {
                return lhsRank < rhsRank
            }
            let lhsName = NutrientCatalog.definition(for: lhs).name
            let rhsName = NutrientCatalog.definition(for: rhs).name
            if lhsName != rhsName {
                return lhsName < rhsName
            }
            return lhs < rhs
        }
    }

    private var availableNutrients: [NutrientDefinition] {
        availableNutrientKeys.map { NutrientCatalog.definition(for: $0) }
    }

    private var activeNutrients: [NutrientDefinition] {
        return trackedNutrientKeys
            .map { $0.lowercased() }
            .filter { !NutrientCatalog.nonTrackableKeys.contains($0) }
            .filter { !excludedNutrientKeys.contains($0) }
            .map { NutrientCatalog.definition(for: $0) }
    }

    private var primaryNutrient: NutrientDefinition {
        activeNutrients.first ?? NutrientCatalog.definition(for: "g_protein")
    }

    private var isManualEntryEditing: Bool {
        focusedField != nil && isKeyboardVisible
    }

    private var manualEntryBottomPadding: CGFloat {
        guard isManualEntryEditing else { return 140 }

        var padding: CGFloat = max(124, keyboardHeight + 24)
        if isAddNutrientsExpanded && activeNutrients.count > 1 {
            let nutrientRows = CGFloat((activeNutrients.count + 1) / 2)
            padding += nutrientRows * 190
        }
        return padding
    }

    private var collapsedManualEntryPageLift: CGFloat {
        guard isManualEntryEditing, !isAddNutrientsExpanded else { return 0 }
        return 0
    }

    private func loadVenueMenus() {
        if !storedVenueMenusData.isEmpty,
           let data = storedVenueMenusData.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([DiningVenue: NutrisliceMenu].self, from: data) {
            venueMenus = decoded
        } else {
            venueMenus = [:]
        }

        if !storedVenueMenuSignaturesData.isEmpty,
           let data = storedVenueMenuSignaturesData.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([DiningVenue: String].self, from: data) {
            lastLoadedMenuSignatureByVenue = decoded
        } else {
            lastLoadedMenuSignatureByVenue = [:]
        }
    }

    private func saveVenueMenus() {
        if let data = try? JSONEncoder().encode(venueMenus) {
            storedVenueMenusData = String(decoding: data, as: UTF8.self)
        }
        if let data = try? JSONEncoder().encode(lastLoadedMenuSignatureByVenue) {
            storedVenueMenuSignaturesData = String(decoding: data, as: UTF8.self)
        }
    }

    private var totalCalories: Int { entries.reduce(0) { $0 + $1.calories } }
    private var rawCalorieProgress: Double { Double(totalCalories) / Double(max(calorieGoal, 1)) }
    private var calorieProgress: Double { min(Double(totalCalories) / Double(calorieGoal), 1.0) }
    private var caloriesLeft: Int { max(calorieGoal - totalCalories, 0) }

    private var sortedEntries: [MealEntry] {
        entries.sorted { $0.createdAt > $1.createdAt }
    }

    private var groupedTodayEntries: [(group: MealGroup, entries: [MealEntry])] {
        MealGroup.logDisplayOrder.compactMap { group in
            let groupEntries = entries
                .filter { $0.mealGroup == group }
                .sorted { $0.createdAt > $1.createdAt }
            guard !groupEntries.isEmpty else { return nil }
            return (group, groupEntries)
        }
    }

    private var mealDistributionData: [(group: MealGroup, calories: Int)] {
        MealGroup.logDisplayOrder.compactMap { group in
            let calories = entries
                .filter { $0.mealGroup == group }
                .reduce(0) { $0 + $1.calories }
            guard calories > 0 else { return nil }
            return (group, calories)
        }
    }

    private func mealDistributionData(for dayIdentifier: String) -> [(group: MealGroup, calories: Int)] {
        let dayEntries = entries(forDayIdentifier: dayIdentifier)
        return MealGroup.logDisplayOrder.compactMap { group in
            let calories = dayEntries
                .filter { $0.mealGroup == group }
                .reduce(0) { $0 + $1.calories }
            guard calories > 0 else { return nil }
            return (group, calories)
        }
    }

    private var historicalSortedEntries: [MealEntry] {
        entries(forDayIdentifier: selectedHistoryDayIdentifier).sorted { $0.createdAt > $1.createdAt }
    }

    private var archivedDayIdentifiers: [String] {
        dailyEntryArchive.compactMap { key, value in
            value.isEmpty ? nil : key
        }
        .sorted()
    }

    private var selectedHistorySummary: HistoryDaySummary {
        historySummary(for: selectedHistoryDayIdentifier)
    }

    private var calorieGraphPoints: [CalorieGraphPoint] {
        graphPoints(dayCount: 7)
    }

    private var expandedCalorieGraphPoints: [CalorieGraphPoint] {
        graphPoints(for: expandedHistoryChartRange)
    }

    private func graphPoints(for range: HistoryChartRange) -> [CalorieGraphPoint] {
        graphPoints(dayCount: range.dayCount)
    }

    private func graphPoints(dayCount: Int) -> [CalorieGraphPoint] {
        let today = centralCalendar.startOfDay(for: Date())
        // Use completed days only: last `dayCount` days, excluding today
        return (0..<dayCount).compactMap { offset in
            guard let date = centralCalendar.date(byAdding: .day, value: -(dayCount - offset), to: today) else {
                return nil
            }
            let identifier = centralDayIdentifier(for: date)
            return CalorieGraphPoint(
                dayIdentifier: identifier,
                date: date,
                calories: dailyCalories(for: identifier),
                goal: calorieGoalForDay(identifier),
                burned: burnedCaloriesForDay(identifier)
            )
        }
    }

    private var historyStatistics: (average: Int, highest: CalorieGraphPoint?, goalHitCount: Int) {
        let points = calorieGraphPoints
        let nonZeroPoints = points.filter { $0.calories > 0 }
        let total = nonZeroPoints.reduce(0) { $0 + $1.calories }
        let highest = nonZeroPoints.max { $0.calories < $1.calories }
        let goalHits = points.reduce(0) { partialResult, point in
            partialResult + ((point.calories > 0 && point.calories <= point.goal) ? 1 : 0)
        }
        let average = nonZeroPoints.isEmpty ? 0 : Int((Double(total) / Double(nonZeroPoints.count)).rounded())
        return (average: average, highest: highest, goalHitCount: goalHits)
    }

    private var netCalorieSummary: (net: Int, hasData: Bool) {
        let identifiers = dayIdentifiers(forLast: netHistoryRange.dayCount)
            .filter { dailyCalories(for: $0) > 0 }
        guard !identifiers.isEmpty else {
            return (net: 0, hasData: false)
        }

        let dayCount = identifiers.count
        let totalConsumed = identifiers.reduce(0) { $0 + dailyCalories(for: $1) }
        let totalBurned = identifiers.reduce(0) { $0 + burnedCaloriesForDay($1) }
        let totalNet = totalConsumed - totalBurned
        let averageNet = Int((Double(totalNet) / Double(dayCount)).rounded())

        return (net: averageNet, hasData: true)
    }

    private var historyAverageMealDistribution: [(group: MealGroup, calories: Int)] {
        let identifiers = dayIdentifiers(forLast: historyDistributionRange.dayCount)
            .filter { dailyCalories(for: $0) > 0 }
        guard !identifiers.isEmpty else { return [] }

        return MealGroup.logDisplayOrder.compactMap { group in
            let totalGroupCalories = identifiers.reduce(0) { partialResult, identifier in
                let dayCalories = entries(forDayIdentifier: identifier)
                    .filter { $0.mealGroup == group }
                    .reduce(0) { $0 + $1.calories }
                return partialResult + dayCalories
            }
            let averageCalories = Int((Double(totalGroupCalories) / Double(identifiers.count)).rounded())
            guard averageCalories > 0 else { return nil }
            return (group, averageCalories)
        }
    }

    private var parsedEntryCalories: Int? { parseInputValue(entryCaloriesText) }

    private var parsedNutrientInputs: [String: Int]? {
        var result: [String: Int] = [:]
        for nutrient in activeNutrients {
            let text = nutrientInputTexts[nutrient.key] ?? ""
            guard let parsed = parseInputValue(text) else { return nil }
            result[nutrient.key] = parsed
        }
        return result
    }

    private var hasTypedManualNutritionInput: Bool {
        if !entryCaloriesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        return activeNutrients.contains {
            !(nutrientInputTexts[$0.key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private var entryError: String? {
        guard hasTypedManualNutritionInput else {
            return nil
        }

        guard parsedEntryCalories != nil, let nutrientMap = parsedNutrientInputs else {
            return "Use non-negative whole numbers."
        }

        let nutrientSum = nutrientMap.values.reduce(0, +)
        let calories = parsedEntryCalories ?? 0
        if calories + nutrientSum == 0 {
            return "Enter calories or a nutrient above 0."
        }

        return nil
    }

    private var canAddEntry: Bool {
        guard let calories = parsedEntryCalories, let nutrientMap = parsedNutrientInputs else {
            return false
        }
        return calories + nutrientMap.values.reduce(0, +) > 0
    }

    var body: some View {
        NavigationStack {
            rootHost
        }
    }

    private var rootHost: some View {
        rootLifecycleHost
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
                updateKeyboardState(from: notification)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { notification in
                updateKeyboardState(from: notification)
            }
    }

    @ViewBuilder
    private var rootConditionalContent: some View {
        if hasCompletedOnboarding {
            rootShellModalHost
        } else {
            onboardingView
        }
    }

    private var rootLifecycleHost: some View {
        rootStateSyncHost
            .onAppear(perform: handleOnAppear)
            .onChange(of: entries) { _, _ in
                syncCurrentEntriesToArchive()
            }
            .onChange(of: exercises) { _, _ in
                syncCurrentEntriesToArchive()
                syncCurrentDayGoalArchive()
            }
            .onChange(of: healthKitService.todayWorkouts) { _, _ in
                syncCurrentDayGoalArchive()
            }
            .onChange(of: scenePhase) { _, newPhase in
                handleScenePhaseChange(newPhase)
            }
            .onReceive(clockTimer) { _ in
                handleClockTick()
            }
    }

    private var rootStateSyncHost: some View {
        rootPreferenceHost
            .onChange(of: healthKitService.profile) { _, newProfile in
                handleHealthProfileChange(newProfile)
            }
            .onChange(of: storedDeficitCalories) { _, _ in
                syncCurrentDayGoalArchive()
            }
            .onChange(of: useWeekendDeficit) { _, _ in
                syncCurrentDayGoalArchive()
            }
            .onChange(of: storedWeekendDeficitCalories) { _, _ in
                syncCurrentDayGoalArchive()
            }
            .onChange(of: goalTypeRaw) { _, _ in
                syncCurrentDayGoalArchive()
            }
            .onChange(of: storedSurplusCalories) { _, _ in
                syncCurrentDayGoalArchive()
            }
            .onChange(of: stepActivityService.todayStepCount) { _, _ in
                syncCurrentDayGoalArchive()
            }
            .onChange(of: stepActivityService.todayDistanceMeters) { _, _ in
                syncCurrentDayGoalArchive()
            }
    }

    private var rootPreferenceHost: some View {
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
            }
            .onChange(of: venueMenus) { _, _ in
                normalizeTrackingState()
                saveTrackingPreferences()
                syncInputFieldsToTrackedNutrients()
            }
            .onChange(of: onboardingPage) { _, newPage in
                guard !hasCompletedOnboarding, newPage == OnboardingPage.nutrients.rawValue else { return }
                normalizeTrackingState()
                saveTrackingPreferences()
                syncInputFieldsToTrackedNutrients()
            }
    }

    private var rootShellBase: some View {
        appChrome
            // Keep the floating tab bar fixed when keyboard appears.
            .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    private var onboardingView: some View {
        OnboardingFlowView(
            currentPage: $onboardingPage,
            deficitCalories: $storedDeficitCalories,
            goalTypeRaw: $goalTypeRaw,
            surplusCalories: $storedSurplusCalories,
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
                hasRequestedHealthDuringOnboarding = true
                Task {
                    await healthKitService.requestAccessAndRefresh()
                }
            },
            onSkip: skipOnboarding,
            onFinish: completeOnboarding
        )
    }

    private var rootShellSheetHost: some View {
        rootShellBase
            .sheet(isPresented: $isMenuSheetPresented, onDismiss: clearMenuSelection) {
                menuSheet
            }
            .sheet(isPresented: $isBarcodeScannerPresented, onDismiss: {
                hasScannedBarcodeInCurrentSheet = false
            }) {
                barcodeScannerSheet
            }
            .sheet(isPresented: $isUSDASearchPresented) {
                usdaSearchSheet
            }
            .sheet(item: $foodReviewItem, onDismiss: {
                foodReviewItem = nil
            }) { context in
                foodReviewSheet(item: context)
            }
            .sheet(isPresented: $isExpandedHistoryChartPresented) {
                expandedHistoryChartSheet
            }
            .sheet(item: $presentedHistoryDaySummary) { summary in
                historyDayDetailSheet(summary: summary)
            }
            .sheet(item: $editingEntry) { entry in
                editEntrySheet(entry: entry)
            }
    }

    private var rootShellModalHost: some View {
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
                    onAdd: { entry in
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                            exercises.append(entry)
                        }
                    }
                )
            }
            .sheet(isPresented: $isResetConfirmationPresented) {
                resetTodaySheet
            }
    }

    private var resetTodaySheet: some View {
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

    private var appChrome: some View {
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

            bottomTabBar
        }
    }

    private var topSafeAreaShield: some View {
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

    private var menuSheet: some View {
        MenuSheetView(
            menu: currentMenu,
            venue: selectedMenuVenue,
            sourceTitle: selectedMenuVenue.title,
            mealTitle: menuService.currentMenuType().title,
            selectedItemQuantities: Binding(
                get: { selectedMenuItemQuantitiesByVenue[selectedMenuVenue] ?? [:] },
                set: { newValue in
                    var updated = selectedMenuItemQuantitiesByVenue
                    updated[selectedMenuVenue] = newValue
                    selectedMenuItemQuantitiesByVenue = updated
                }
            ),
            selectedItemMultipliers: Binding(
                get: { selectedMenuItemMultipliersByVenue[selectedMenuVenue] ?? [:] },
                set: { newValue in
                    var updated = selectedMenuItemMultipliersByVenue
                    updated[selectedMenuVenue] = newValue
                    selectedMenuItemMultipliersByVenue = updated
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
            mealGroup: mealGroup(for: menuService.currentMenuType(now: Date())),
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
            }
        )
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

    private var quickAddManagerSheet: some View {
        QuickAddManagerView(
            quickAddFoods: $quickAddFoods,
            trackedNutrientKeys: trackedNutrientKeys,
            surfacePrimary: surfacePrimary,
            surfaceSecondary: surfaceSecondary,
            textPrimary: textPrimary,
            textSecondary: textSecondary,
            accent: accent
        )
    }

    private var quickAddPickerSheet: some View {
        QuickAddPickerView(
            quickAddFoods: quickAddFoods,
            surfacePrimary: surfacePrimary,
            surfaceSecondary: surfaceSecondary,
            textPrimary: textPrimary,
            textSecondary: textSecondary,
            accent: accent,
            onSelect: { item in
                addQuickAddFood(item)
            }
        )
    }

    private func editEntrySheet(entry: MealEntry) -> some View {
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

    private func handleOnAppear() {
        sanitizeStoredGoals()
        loadTrackingPreferences()
        loadDailyEntryArchive()
        loadQuickAddFoods()
        loadVenueMenus()
        applyCentralTimeTransitions(forceMenuReload: false)
        syncInputFieldsToTrackedNutrients()
        AppIconManager.apply(selectedAppIconChoice)
        stepActivityService.requestAccessAndRefresh()
        Task {
            await healthKitService.refreshIfPossible()
        }
        syncCurrentDayGoalArchive()
        Task {
            await preloadMenuForNutrientDiscovery()
        }
    }

    private func completeOnboarding() {
        sanitizeStoredGoals()
        normalizeTrackingState()
        saveTrackingPreferences()
        syncInputFieldsToTrackedNutrients()
        selectedTab = .today
        onboardingPage = OnboardingPage.welcome.rawValue
        hasRequestedHealthDuringOnboarding = false
        hasCompletedOnboarding = true
    }

    private func skipOnboarding() {
        sanitizeStoredGoals()
        normalizeTrackingState()
        saveTrackingPreferences()
        syncInputFieldsToTrackedNutrients()
        selectedTab = .today
        onboardingPage = OnboardingPage.welcome.rawValue
        hasRequestedHealthDuringOnboarding = false
        hasCompletedOnboarding = true
    }

    private func handleHealthProfileChange(_ newProfile: HealthKitService.SyncedProfile?) {
        syncCurrentDayGoalArchive()
    }

    private func handleScenePhaseChange(_ newPhase: ScenePhase) {
        guard newPhase == .active else { return }
        applyCentralTimeTransitions(forceMenuReload: false)
        stepActivityService.refreshIfAuthorized()
        Task {
            await healthKitService.refreshIfPossible()
        }
        syncCurrentDayGoalArchive()
        syncHistorySelection(preferToday: true)
        Task {
            await preloadMenuForNutrientDiscovery()
        }
    }

    private func handleClockTick() {
        applyCentralTimeTransitions(forceMenuReload: false)
        stepActivityService.refreshIfAuthorized()
        Task {
            await healthKitService.refreshIfPossible()
        }
        syncCurrentDayGoalArchive()
    }

    @ViewBuilder
    private var activeTabContent: some View {
        switch selectedTab {
        case .today:
            todayTabView
        case .history:
            historyTabView
        case .add:
            addTabView
        case .profile:
            profileTabView
        case .settings:
            settingsTabView
        }
    }

    private func updateKeyboardState(from notification: Notification) {
        let endFrame = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect) ?? .zero
        let duration = (notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.25
        let visibleHeight = max(0, endFrame.height)

        withAnimation(.easeOut(duration: duration)) {
            keyboardHeight = visibleHeight
            isKeyboardVisible = visibleHeight > 0
        }
    }

    private var bottomTabBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            tabBarButton(for: .today)
            tabBarButton(for: .history)
            tabBarButton(for: .add, isCenter: true)
            tabBarButton(for: .profile)
            tabBarButton(for: .settings)
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 22)
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
    }

    private func tabBarButton(for tab: AppTab, isCenter: Bool = false) -> some View {
        let isSelected = selectedTab == tab

        return Button {
            withAnimation(.none) {
                selectedTab = tab
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

    private var todayTabView: some View {
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

    private var historyTabView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                tabHeader(title: "History", subtitle: "Calendar, calorie trends, and stats")
                historyCalendarCard
                historyGraphCard
                historyStatisticsCard
                netCalorieHistoryCard
                historyMealDistributionCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 140)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
    }

    private var addTabView: some View {
        ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        tabHeader(title: "Add Food")
                            .padding(.bottom, 8)

                    Button {
                        presentMenu(for: .fourWinds)
                    } label: {
                        Label("PCC Menu", systemImage: "fork.knife")
                            .font(.subheadline.weight(.semibold))
                            .imageScale(.medium)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.bordered)
                    .tint(accent)

                    HStack(spacing: 10) {
                        Button {
                            usdaSearchError = nil
                            usdaSearchResults = []
                            usdaSearchText = ""
                            isUSDASearchPresented = true
                            Haptics.impact(.light)
                        } label: {
                            Label("Search", systemImage: "magnifyingglass")
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.bordered)
                        .tint(textSecondary)

                        Button {
                            barcodeLookupError = nil
                            hasScannedBarcodeInCurrentSheet = false
                            isBarcodeScannerPresented = true
                            Haptics.impact(.light)
                        } label: {
                            Label(isBarcodeLookupInFlight ? "Looking Up..." : "Barcode", systemImage: "barcode.viewfinder")
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.bordered)
                        .tint(textSecondary)
                        .disabled(isBarcodeLookupInFlight)

                        Button {
                            isQuickAddPickerPresented = true
                            Haptics.impact(.light)
                        } label: {
                            Label("Quick Add", systemImage: "bolt.fill")
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.bordered)
                        .tint(textSecondary)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Manual entry")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(textSecondary)
                    }
                    .padding(.top, 4)

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

                        if activeNutrients.count == 1 {
                            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                                GridRow {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Calories")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(textPrimary)
                                        TextField("e.g. 250", text: $entryCaloriesText)
                                            .keyboardType(.numberPad)
                                            .focused($focusedField, equals: .calories)
                                            .inputStyle(surface: surfaceSecondary, text: textPrimary, secondary: textSecondary)
                                            .id(manualEntryScrollID(for: .calories))
                                    }
                                    nutrientFieldCell(activeNutrients[0])
                                }
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Calories")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(textPrimary)

                                TextField("e.g. 250", text: $entryCaloriesText)
                                    .keyboardType(.numberPad)
                                    .focused($focusedField, equals: .calories)
                                    .inputStyle(surface: surfaceSecondary, text: textPrimary, secondary: textSecondary)
                                    .id(manualEntryScrollID(for: .calories))
                            }

                            if activeNutrients.count > 1 {
                                DisclosureGroup(isExpanded: $isAddNutrientsExpanded) {
                                    Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                                        ForEach(Array(stride(from: 0, to: activeNutrients.count, by: 2)), id: \.self) { startIndex in
                                            GridRow {
                                                if startIndex + 1 < activeNutrients.count {
                                                    nutrientFieldCell(activeNutrients[startIndex])
                                                    nutrientFieldCell(activeNutrients[startIndex + 1])
                                                } else {
                                                    nutrientFieldCell(activeNutrients[startIndex])
                                                        .gridCellColumns(2)
                                                }
                                            }
                                        }
                                    }
                                    .padding(.top, 12)
                                } label: {
                                    Text("Add nutrients")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(textPrimary)
                                }
                                .tint(textPrimary)
                            }
                        }

                        if let entryError {
                            Text(entryError)
                                .font(.caption)
                                .foregroundStyle(Color.red)
                        }

                        if let barcodeLookupError {
                            Text(barcodeLookupError)
                                .font(.caption)
                                .foregroundStyle(Color.orange)
                        }

                        addEntryButton
                            .id("addEntryButton")
                    }
                    .padding(18)
                    .cardStyle(surface: surfacePrimary, stroke: textSecondary.opacity(0.15))
                    .id("addManualEntryCard")
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, manualEntryBottomPadding)
                .offset(y: collapsedManualEntryPageLift)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
            .onChange(of: focusedField) { _, newValue in
                guard newValue != nil else { return }
                scheduleManualEntryScroll(for: newValue, using: proxy)
            }
            .onChange(of: keyboardHeight) { _, newHeight in
                guard newHeight > 0, focusedField != nil else { return }
                scheduleManualEntryScroll(for: focusedField, using: proxy)
            }
            .onChange(of: isAddNutrientsExpanded) { _, isExpanded in
                guard isExpanded, isKeyboardVisible, activeNutrients.count > 1 else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    let targetField: Field
                    if case .nutrient = focusedField {
                        targetField = focusedField ?? .nutrient(activeNutrients[0].key)
                    } else {
                        targetField = .nutrient(activeNutrients[0].key)
                    }
                    scrollManualEntryField(targetField, using: proxy)
                }
            }
        }
    }

    private var profileTabView: some View {
        VStack(alignment: .leading, spacing: 0) {
            tabHeader(title: "Profile", subtitle: "Health-based BMR, calorie goal, and nutrient targets")
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 6)

            List {
                Section {
                    ProfileGoalsView(
                        deficitCalories: $storedDeficitCalories,
                        goalTypeRaw: $goalTypeRaw,
                        surplusCalories: $storedSurplusCalories,
                        useWeekendDeficit: $useWeekendDeficit,
                        weekendDeficitCalories: $storedWeekendDeficitCalories,
                        trackedNutrientKeys: trackedNutrientKeys,
                        nutrientGoals: $nutrientGoals,
                        healthAuthorizationState: healthKitService.authorizationState,
                        healthProfile: healthKitService.profile,
                        bmrCalories: currentDailyCalorieModel.bmr,
                        burnedCaloriesToday: burnedCaloriesToday,
                        activeBurnedCaloriesToday: activityCaloriesToday + exerciseCaloriesToday,
                        isUsingAutomatedCalories: currentDailyCalorieModel.usesBMR,
                        onRequestHealthAccess: {
                            Task {
                                await healthKitService.requestAccessAndRefresh()
                            }
                        }
                    )
                }
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 4, trailing: 0))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                Section {
                    quickAddManagementCard
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 4, trailing: 0))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
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

    private var settingsTabView: some View {
        VStack(alignment: .leading, spacing: 0) {
            tabHeader(title: "Settings", subtitle: "Tracked nutrients and app appearance")
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 6)

            List {
                Section {
                    AppSettingsTabView(
                        trackedNutrientKeys: $trackedNutrientKeys,
                        availableNutrients: availableNutrients,
                        selectedAppIconChoiceRaw: $selectedAppIconChoiceRaw,
                        useAIBaseServings: $useAIBaseServings
                    )
                }
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 4, trailing: 0))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                Section {
                    Button {
                        hasCompletedOnboarding = false
                        Haptics.impact(.light)
                    } label: {
                        HStack {
                            Label("Replay Onboarding", systemImage: "arrow.counterclockwise")
                            Spacer()
                        }
                        .padding(18)
                    }
                    .buttonStyle(.plain)

                    Button {
                        if let url = URL(string: "https://calorie-tracker-364e3.web.app/privacy") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack {
                            Label("Privacy Policy", systemImage: "doc.text")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(18)
                    }
                    .buttonStyle(.plain)
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 4, trailing: 0))
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemBackground).opacity(0.55))
                )
                .listRowSeparator(.hidden)
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

    private func pageHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 32, weight: .bold, design: .rounded))
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

    private func tabHeader(title: String, subtitle: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(textPrimary)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(textSecondary)
            }
        }
    }

    private var todayHistorySummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Today")
                .font(.headline)
                .foregroundStyle(textPrimary)

            HStack(spacing: 16) {
                summaryMetric(title: "Calories", value: "\(totalCalories)")
                summaryMetric(title: "Items", value: "\(entries.count)")
            }
        }
        .padding(16)
        .cardStyle(surface: surfacePrimary, stroke: textSecondary.opacity(0.15))
        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private func summaryMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(textPrimary)
            Text(title)
                .font(.caption)
                .foregroundStyle(textSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var calorieHeroSection: some View {
        Section {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.03, green: 0.07, blue: 0.19),
                                Color(red: 0.05, green: 0.10, blue: 0.24)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Circle()
                    .fill(Color(red: 0.20, green: 0.23, blue: 0.48).opacity(0.38))
                    .frame(width: 230, height: 230)
                    .offset(x: 74, y: -26)

                VStack(alignment: .leading, spacing: 18) {
                    let caloriePalette = calorieBarPalette(consumed: totalCalories, goal: calorieGoal, burned: burnedCaloriesToday)
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(caloriesLeft)")
                                .font(.system(size: 56, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(.white)
                            Text("Calories Left")
                                .font(.system(size: 20, weight: .medium, design: .rounded))
                                .foregroundStyle(Color.white.opacity(0.70))
                        }

                        Spacer()

                        Image(systemName: "flame")
                            .font(.system(size: 34, weight: .regular))
                            .foregroundStyle(Color.orange)
                            .padding(.top, 10)
                    }

                    GeometryReader { proxy in
                        let fillWidth = proxy.size.width * calorieProgress
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.10))
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [caloriePalette.start, caloriePalette.end],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(fillWidth, calorieProgress > 0 ? 8 : 0))
                        }
                        .animation(.easeInOut(duration: 0.5), value: calorieProgress)
                    }
                    .frame(height: 20)

                    HStack {
                        Text("Consumed: \(totalCalories)")
                            .font(.system(size: 18, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Color.white.opacity(0.72))
                        Spacer()
                        Text("Goal: \(calorieGoal)")
                            .font(.system(size: 18, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Color.white.opacity(0.72))
                    }
                }
                .padding(24)
            }
            .frame(minHeight: 248)
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    private var progressSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 22) {
                Text(activeNutrients.count <= 3 ? "Daily Macros" : "Daily Goals")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(textPrimary)

                ForEach(activeNutrients) { nutrient in
                    let total = totalNutrient(for: nutrient.key)
                    let goal = goalForNutrient(nutrient.key)
                    let progress = min(Double(total) / Double(max(goal, 1)), 1.0)
                    let palette = paletteForNutrient(nutrient.key, progress: progress)
                    progressRow(
                        title: nutrient.name,
                        detail: "\(total)\(nutrient.unit) / \(goal)\(nutrient.unit)",
                        progress: progress,
                        start: palette.start,
                        end: palette.end
                    )
                }
            }
            .padding(20)
            .cardStyle(surface: surfacePrimary, stroke: textSecondary.opacity(0.15))
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    private var historyCalendarCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Button {
                    guard let previousMonth = centralCalendar.date(byAdding: .month, value: -1, to: displayedHistoryMonth) else { return }
                    displayedHistoryMonth = monthStart(for: previousMonth)
                    Haptics.selection()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(textPrimary)
                        .frame(width: 34, height: 34)
                        .background(
                            Circle()
                                .fill(surfaceSecondary.opacity(0.92))
                        )
                }
                .buttonStyle(.plain)

                Spacer()

                Text(currentHistoryMonthTitle)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(textPrimary)

                Spacer()

                Button {
                    guard let nextMonth = centralCalendar.date(byAdding: .month, value: 1, to: displayedHistoryMonth) else { return }
                    displayedHistoryMonth = monthStart(for: nextMonth)
                    Haptics.selection()
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(textPrimary)
                        .frame(width: 34, height: 34)
                        .background(
                            Circle()
                                .fill(surfaceSecondary.opacity(0.92))
                        )
                }
                .buttonStyle(.plain)
            }

            let weekdaySymbols = centralCalendar.veryShortStandaloneWeekdaySymbols
            HStack(spacing: 0) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(textSecondary)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 7), spacing: 12) {
                ForEach(Array(historyMonthDays.enumerated()), id: \.offset) { _, date in
                    historyCalendarDay(date)
                }
            }
        }
        .padding(18)
        .cardStyle(surface: surfacePrimary, stroke: textSecondary.opacity(0.15))
    }

    @ViewBuilder
    private func historyCalendarDay(_ date: Date?) -> some View {
        if let date {
            let identifier = centralDayIdentifier(for: date)
            let isSelected = identifier == selectedHistoryDayIdentifier
            let isToday = identifier == todayDayIdentifier
            let dayEntries = entries(forDayIdentifier: identifier)
            let hasEntries = !dayEntries.isEmpty
            let dayCalories = dayEntries.reduce(0) { $0 + $1.calories }
            let dayGoal = calorieGoalForDay(identifier)
            let dayBurned = burnedCaloriesForDay(identifier)
            let dayDotColor = historyBarColor(calories: dayCalories, goal: dayGoal, burned: dayBurned)

            Button {
                selectedHistoryDayIdentifier = identifier
                presentedHistoryDaySummary = historySummary(for: identifier)
                Haptics.selection()
            } label: {
                VStack(spacing: 4) {
                    Text("\(centralCalendar.component(.day, from: date))")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isSelected ? Color.white : textPrimary)

                    Circle()
                        .fill(hasEntries ? dayDotColor : Color.clear)
                        .frame(width: 5, height: 5)
                }
                .frame(maxWidth: .infinity, minHeight: 38)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            isSelected
                            ? accent
                            : (isToday ? surfaceSecondary.opacity(0.98) : Color.clear)
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(isToday && !isSelected ? accent.opacity(0.40) : .clear, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        } else {
            Color.clear
                .frame(maxWidth: .infinity, minHeight: 50)
        }
    }

    private func historyDayDetailSheet(summary: HistoryDaySummary) -> some View {
        let dayGoal = calorieGoalForDay(summary.dayIdentifier)
        let dayBurned = burnedCaloriesForDay(summary.dayIdentifier)
        let dayGoalType = goalTypeForDay(summary.dayIdentifier)
        let nutrientTotals = nutrientTotals(for: summary.dayIdentifier)
        let dayMealDistribution = mealDistributionData(for: summary.dayIdentifier)
        let calorieColor = historyBarColor(calories: summary.totalCalories, goal: dayGoal, burned: dayBurned)
        let rawProgress = Double(summary.totalCalories) / Double(max(dayGoal, 1))
        let barProgress = min(max(rawProgress, 0), 1)
        let statusText: String
        let statusColor: Color
        if summary.totalCalories == 0 {
            statusText = "No Intake"
            statusColor = textSecondary
        } else if summary.totalCalories < dayBurned {
            // Under burned = in deficit; adapted to that day's goal type
            if dayGoalType == .deficit && summary.totalCalories > dayGoal {
                statusText = "Above Goal"
                statusColor = Color.yellow
            } else {
                statusText = "In Deficit"
                statusColor = dayGoalType == .deficit ? Color.green : Color.yellow
            }
        } else if dayGoalType == .surplus && summary.totalCalories > dayBurned && summary.totalCalories <= dayGoal {
            statusText = "On Target"
            statusColor = Color.green
        } else if summary.totalCalories > dayGoal {
            statusText = "Over Burned"
            statusColor = Color.red
        } else {
            // totalCalories == dayBurned (at maintenance)
            statusText = dayGoalType == .surplus ? "Below Goal" : "Above Goal"
            statusColor = Color.yellow
        }

        return NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [backgroundTop, backgroundBottom],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                    Text(summary.date.formatted(.dateTime.month(.abbreviated).day().year()))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(textPrimary)

                        VStack(alignment: .leading, spacing: 16) {
                            calorieDetailBar(
                                calories: summary.totalCalories,
                                goal: dayGoal,
                                progress: barProgress,
                                color: calorieColor
                            )

                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                                historySummaryMetric(title: "Goal", value: "\(dayGoal)")
                                historySummaryMetric(title: "Burned", value: "\(dayBurned)")
                                historySummaryMetric(title: "Items", value: "\(summary.entryCount)")
                                historySummaryMetric(title: "Status", value: statusText, valueColor: statusColor)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(18)
                        .cardStyle(surface: surfacePrimary, stroke: textSecondary.opacity(0.15))

                        if !dayMealDistribution.isEmpty {
                            mealDistributionCard(dayMealDistribution)
                                .padding(18)
                                .cardStyle(surface: surfacePrimary, stroke: textSecondary.opacity(0.15))
                        }

                        VStack(alignment: .leading, spacing: 14) {
                            Text("Tracked Nutrients")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(textPrimary)

                            if activeNutrients.isEmpty {
                                Text("No tracked nutrients for this day.")
                                    .font(.subheadline)
                                    .foregroundStyle(textSecondary)
                            } else {
                                VStack(spacing: 12) {
                                    ForEach(activeNutrients, id: \.key) { nutrient in
                                        let total = nutrientTotals[nutrient.key] ?? 0
                                        nutrientDetailRow(
                                            nutrient: nutrient,
                                            total: total,
                                            goal: nutrientGoals[nutrient.key] ?? nutrient.defaultGoal
                                        )
                                    }
                                }
                            }
                        }
                        .padding(18)
                        .cardStyle(surface: surfacePrimary, stroke: textSecondary.opacity(0.15))

                        Spacer(minLength: 0)
                    }
                    .padding(20)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") {
                        presentedHistoryDaySummary = nil
                    }
                    .foregroundStyle(textPrimary)
                }
            }
        }
    }

    private func calorieDetailBar(calories: Int, goal: Int, progress: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(calories.formatted())")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(textPrimary)
                    Text("Calories")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(textSecondary)
                }

                Spacer(minLength: 16)

                Text("Goal \(goal.formatted())")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(textSecondary)
                    .monospacedDigit()
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(textSecondary.opacity(0.18))

                    Capsule(style: .continuous)
                        .fill(color)
                        .frame(width: max(12, proxy.size.width * progress))
                }
            }
            .frame(height: 14)
        }
    }

    private func nutrientDetailRow(nutrient: NutrientDefinition, total: Int, goal: Int) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(nutrient.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(textPrimary)
                Text("Goal \(goal.formatted()) \(nutrient.unit)")
                    .font(.caption)
                    .foregroundStyle(textSecondary)
            }
            Spacer()
            Text("\(total.formatted()) \(nutrient.unit)")
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(textPrimary)
        }
    }

    private func historySummaryMetric(title: String, value: String, valueColor: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(textSecondary)
            Text(value)
                .font(.headline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(valueColor ?? textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var historyGraphCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("7-Day Calorie Trends")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(textPrimary)
                Spacer()
                Button("See More") {
                    expandedHistoryChartRange = .thirtyDays
                    isExpandedHistoryChartPresented = true
                    Haptics.selection()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(accent)
            }

            calorieChart(points: calorieGraphPoints, labelMode: .weekday)
                .frame(height: 220)
        }
        .padding(18)
        .cardStyle(surface: surfacePrimary, stroke: textSecondary.opacity(0.15))
    }

    private var historyStatisticsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("7-Day Statistics")
                .font(.headline.weight(.semibold))
                .foregroundStyle(textPrimary)

            HStack(spacing: 12) {
                statTile(title: "Average", value: "\(historyStatistics.average)", detail: "cal/day")
                statTile(
                    title: "Highest",
                    value: "\(historyStatistics.highest?.calories ?? 0)",
                    detail: historyStatistics.highest?.date.formatted(.dateTime.month(.abbreviated).day()) ?? "No data"
                )
                statTile(title: "Goal Hits", value: "\(historyStatistics.goalHitCount)", detail: "last 7 days")
            }
        }
        .padding(18)
        .cardStyle(surface: surfacePrimary, stroke: textSecondary.opacity(0.15))
    }

    private var netCalorieHistoryCard: some View {
        let summary = netCalorieSummary
        let netColor = netCalorieColor(summary.net)

        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Net Average Intake")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(textPrimary)
                    Text("Average daily difference between consumed and burned.")
                        .font(.caption)
                        .foregroundStyle(textSecondary)
                }

                Spacer(minLength: 12)

                Menu {
                    ForEach(NetHistoryRange.allCases) { range in
                        Button(range.title) {
                            netHistoryRange = range
                            Haptics.selection()
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text(netHistoryRange.title)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.bold))
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(textPrimary)
                    .frame(width: 144)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        Capsule(style: .continuous)
                            .fill(surfaceSecondary.opacity(0.96))
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(textSecondary.opacity(0.16), lineWidth: 1)
                    )
                }
            }

            if summary.hasData {
                (
                    Text("\(netSign(summary.net))\(abs(summary.net).formatted())")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(netColor)
                    +
                    Text(" cal/day")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(textPrimary)
                )
            } else {
                Text("No logged days in this range.")
                    .font(.caption)
                    .foregroundStyle(textSecondary)
            }
        }
        .padding(18)
        .cardStyle(surface: surfacePrimary, stroke: textSecondary.opacity(0.15))
    }

    private var historyMealDistributionCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Average Meal Distribution")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(textPrimary)
                    Text("Estimated average daily calorie split by meal group.")
                        .font(.caption)
                        .foregroundStyle(textSecondary)
                }

                Spacer(minLength: 12)

                Menu {
                    ForEach(NetHistoryRange.allCases) { range in
                        Button(range.title) {
                            historyDistributionRange = range
                            Haptics.selection()
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text(historyDistributionRange.title)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.bold))
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(textPrimary)
                    .frame(width: 144)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        Capsule(style: .continuous)
                            .fill(surfaceSecondary.opacity(0.96))
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(textSecondary.opacity(0.16), lineWidth: 1)
                    )
                }
            }

            if historyAverageMealDistribution.isEmpty {
                Text("Log food to see estimated meal distribution over time.")
                    .font(.subheadline)
                    .foregroundStyle(textSecondary)
            } else {
                mealDistributionCard(historyAverageMealDistribution, valueSuffix: "cal")
            }
        }
        .padding(18)
        .cardStyle(surface: surfacePrimary, stroke: textSecondary.opacity(0.15))
    }

    private var expandedHistoryChartSheet: some View {
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
                        HStack {
                            Text("Calorie Trends")
                                .font(.system(size: 30, weight: .bold, design: .rounded))
                                .foregroundStyle(textPrimary)
                            Spacer()
                            Menu {
                                ForEach(HistoryChartRange.allCases) { range in
                                    Button(range.title) {
                                        expandedHistoryChartRange = range
                                        Haptics.selection()
                                    }
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Text(expandedHistoryChartRange.title)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Image(systemName: "chevron.down")
                                        .font(.caption.weight(.bold))
                                }
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(textPrimary)
                                .frame(width: 158)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(surfacePrimary.opacity(0.94))
                                )
                                .overlay(
                                    Capsule(style: .continuous)
                                        .stroke(textSecondary.opacity(0.16), lineWidth: 1)
                                )
                            }
                        }

                        Text("Line view shows the overall calorie trend across the selected range.")
                            .font(.subheadline)
                            .foregroundStyle(textSecondary)

                        calorieChart(
                            points: expandedCalorieGraphPoints,
                            labelMode: .adaptive,
                            style: .line
                        )
                        .frame(height: 320)
                        .padding(18)
                        .cardStyle(surface: surfacePrimary, stroke: textSecondary.opacity(0.15))
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 32)
                }
                .scrollIndicators(.hidden)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") {
                        isExpandedHistoryChartPresented = false
                    }
                    .foregroundStyle(textPrimary)
                }
            }
        }
    }

    private func statTile(title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(textSecondary)
            Text(value)
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(textPrimary)
            Text(detail)
                .font(.caption)
                .foregroundStyle(textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(surfaceSecondary.opacity(0.92))
        )
    }

    private enum ChartAxisLabelMode {
        case weekday
        case adaptive
    }

    private enum CalorieChartStyle {
        case bars
        case line
    }

    private func calorieChart(
        points: [CalorieGraphPoint],
        labelMode: ChartAxisLabelMode,
        style: CalorieChartStyle = .bars
    ) -> some View {
        let yAxisValues = chartYAxisValues(for: points)
        let segmentedLinePoints = segmentedLinePoints(for: points)

        return Chart {
            switch style {
            case .bars:
                ForEach(points) { point in
                    BarMark(
                        x: .value("Day", point.date, unit: .day),
                        y: .value("Calories", point.calories)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .foregroundStyle(historyBarColor(for: point))
                }

            case .line:
                ForEach(segmentedLinePoints) { segmentedPoint in
                    AreaMark(
                        x: .value("Day", segmentedPoint.point.date, unit: .day),
                        y: .value("Calories", segmentedPoint.point.calories),
                        series: .value("Segment", segmentedPoint.segment)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [accent.opacity(0.22), accent.opacity(0.03)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    LineMark(
                        x: .value("Day", segmentedPoint.point.date, unit: .day),
                        y: .value("Calories", segmentedPoint.point.calories),
                        series: .value("Segment", segmentedPoint.segment)
                    )
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(historyBarColor(for: segmentedPoint.point))
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: chartXAxisValues(for: points)) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        switch labelMode {
                        case .weekday:
                            Text(date.formatted(.dateTime.weekday(.narrow)))
                        case .adaptive:
                            Text(adaptiveChartLabel(for: date, totalPoints: points.count))
                        }
                    }
                }
                .foregroundStyle(textSecondary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: yAxisValues) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6))
                    .foregroundStyle(textSecondary.opacity(0.10))
                AxisValueLabel {
                    if let intValue = value.as(Int.self) {
                        Text(intValue.formatted())
                    }
                }
                .foregroundStyle(textSecondary)
            }
        }
    }

    private func chartXAxisValues(for points: [CalorieGraphPoint]) -> [Date] {
        guard !points.isEmpty else { return [] }
        guard points.count > 4 else { return points.map(\.date) }

        let targetMarks = min(4, points.count)
        let lastIndex = points.count - 1
        let step = max(1, lastIndex / max(targetMarks - 1, 1))
        var indices = Array(stride(from: 0, through: lastIndex, by: step))
        if indices.last != lastIndex {
            indices.append(lastIndex)
        }
        return indices.map { points[$0].date }
    }

    private func chartYAxisValues(for points: [CalorieGraphPoint]) -> [Int] {
        let maxValue = max(points.map(\.calories).max() ?? 0, points.map(\.goal).max() ?? 0, points.map(\.burned).max() ?? 0, 1)
        let roundedTop = max(500, ((maxValue + 499) / 500) * 500)
        let middle = roundedTop / 2
        return Array(Set([0, middle, roundedTop])).sorted()
    }

    private func segmentedLinePoints(for points: [CalorieGraphPoint]) -> [SegmentedCalorieLinePoint] {
        var segment = 0
        var result: [SegmentedCalorieLinePoint] = []

        for point in points {
            if point.calories <= 0 {
                segment += 1
                continue
            }

            result.append(SegmentedCalorieLinePoint(point: point, segment: segment))
        }

        return result
    }

    private func adaptiveChartLabel(for date: Date, totalPoints: Int) -> String {
        if totalPoints <= 30 {
            return date.formatted(.dateTime.month(.abbreviated).day())
        }
        return date.formatted(.dateTime.month(.abbreviated))
    }

    private func historyBarColor(for point: CalorieGraphPoint) -> Color {
        historyBarColor(calories: point.calories, goal: point.goal, burned: point.burned)
    }

    private func historyBarColor(calories: Int, goal: Int, burned: Int) -> Color {
        let safeGoal = max(goal, 1)
        let safeBurned = max(burned, 1)
        let isSurplus = safeGoal > safeBurned

        if isSurplus {
            if calories < safeBurned { return Color.yellow }
            if calories <= safeGoal { return Color.green }
            return Color.red
        } else {
            // Deficit: goal < burned. Green = at or below goal, yellow = between goal and burned, red = over burned
            if calories > safeBurned { return Color.red }
            if calories <= safeGoal { return Color.green }
            return Color.yellow
        }
    }

    private func progressRow(
        title: String,
        detail: String,
        progress: Double,
        start: Color,
        end: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(textPrimary)
                Spacer()
                Text(detail)
                    .font(.headline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(textSecondary)
            }

            GeometryReader { proxy in
                let fillWidth = proxy.size.width * progress
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(textSecondary.opacity(0.16))
                    Capsule()
                        .fill(LinearGradient(colors: [start, end], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(fillWidth, progress > 0 ? 7 : 0))
                }
                .animation(.easeInOut(duration: 0.5), value: progress)
            }
            .frame(height: 14)
        }
    }

    private func paletteForNutrient(_ key: String, progress: Double) -> (start: Color, end: Color) {
        switch key.lowercased() {
        case "g_protein":
            return (
                interpolateColor(from: UIColor.systemMint, to: UIColor.systemGreen, progress: progress),
                interpolateColor(from: UIColor.systemGreen, to: UIColor.systemTeal, progress: progress)
            )
        case "g_carbs":
            return (
                interpolateColor(from: UIColor.systemYellow, to: UIColor.systemOrange, progress: progress),
                interpolateColor(from: UIColor(red: 1.0, green: 0.84, blue: 0.20, alpha: 1.0), to: UIColor.systemYellow, progress: progress)
            )
        case "g_fat", "g_saturated_fat", "g_trans_fat":
            return (
                interpolateColor(from: UIColor.systemPink, to: UIColor.systemRed, progress: progress),
                interpolateColor(from: UIColor.systemPink.withAlphaComponent(0.85), to: UIColor.systemOrange, progress: progress)
            )
        case "g_sugar", "g_added_sugar":
            return (
                interpolateColor(from: UIColor.systemOrange, to: UIColor.systemRed, progress: progress),
                interpolateColor(from: UIColor.systemYellow, to: UIColor.systemOrange, progress: progress)
            )
        case "mg_sodium":
            return (
                interpolateColor(from: UIColor.systemBlue, to: UIColor.systemIndigo, progress: progress),
                interpolateColor(from: UIColor.systemCyan, to: UIColor.systemBlue, progress: progress)
            )
        case "mg_calcium":
            return (
                interpolateColor(from: UIColor.systemTeal, to: UIColor.systemBlue, progress: progress),
                interpolateColor(from: UIColor.systemMint, to: UIColor.systemTeal, progress: progress)
            )
        case "mg_iron":
            return (
                interpolateColor(from: UIColor.systemRed, to: UIColor(red: 0.58, green: 0.12, blue: 0.18, alpha: 1.0), progress: progress),
                interpolateColor(from: UIColor.systemOrange, to: UIColor.systemRed, progress: progress)
            )
        case "mg_vitamin_c":
            return (
                interpolateColor(from: UIColor.systemGreen, to: UIColor.systemTeal, progress: progress),
                interpolateColor(from: UIColor.systemMint, to: UIColor.systemGreen, progress: progress)
            )
        default:
            return (
                interpolateColor(from: UIColor.systemPurple, to: UIColor.systemBlue, progress: progress),
                interpolateColor(from: UIColor.systemIndigo, to: UIColor.systemPurple, progress: progress)
            )
        }
    }

    /// Vivid bar colors so the calorie state is obvious at a glance.
    private static let barGreen = Color(red: 0.22, green: 0.78, blue: 0.35)
    private static let barYellow = Color(red: 1.0, green: 0.76, blue: 0.12)
    private static let barRed = Color(red: 0.95, green: 0.26, blue: 0.21)

    private func calorieBarPalette(consumed: Int, goal: Int, burned: Int) -> (start: Color, end: Color) {
        let safeGoal = max(goal, 1)
        let safeBurned = max(burned, 1)
        let consumedValue = max(consumed, 0)
        let isSurplus = safeGoal > safeBurned

        if isSurplus {
            if consumedValue < safeBurned {
                return (Self.barYellow, Self.barYellow)
            }
            if consumedValue <= safeGoal {
                return (Self.barGreen, Self.barGreen)
            }
            return (Self.barRed, Self.barRed)
        }

        if safeBurned == safeGoal {
            if consumedValue <= safeGoal { return (Self.barGreen, Self.barGreen) }
            return (Self.barRed, Self.barRed)
        }

        if consumedValue <= safeGoal {
            return (Self.barGreen, Self.barGreen)
        }
        if consumedValue <= safeBurned {
            return (Self.barYellow, Self.barYellow)
        }
        return (Self.barRed, Self.barRed)
    }

    @ViewBuilder
    private var foodLogSections: some View {
        if groupedTodayEntries.isEmpty {
            Section {
                Text("No entries yet.")
                    .foregroundStyle(textSecondary)
                    .listRowBackground(surfacePrimary)
            } header: {
                Text("Today's Food Log")
                .foregroundStyle(textSecondary)
            }
        } else {
            ForEach(Array(groupedTodayEntries.enumerated()), id: \.element.group.id) { index, groupData in
                Section {
                    ForEach(groupData.entries) { entry in
                        logRow(entry)
                            .listRowBackground(surfacePrimary)
                            .contextMenu {
                                Button {
                                    editingEntry = entry
                                    Haptics.selection()
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }

                                Button(role: .destructive) {
                                    deleteEntry(entry)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    deleteEntry(entry)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                } header: {
                    VStack(alignment: .leading, spacing: index == 0 ? 18 : 12) {
                        if index == 0 {
                            Text("Today's Food Log")
                            .padding(.bottom, 2)
                        }
                        HStack(spacing: 12) {
                            Text(groupData.group.title)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(textSecondary.opacity(0.92))
                            Spacer()
                            Text("\(groupData.entries.reduce(0) { $0 + $1.calories }) cal")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(textSecondary.opacity(0.82))
                                .monospacedDigit()
                        }
                    }
                    .padding(.top, index == 0 ? 8 : 0)
                    .foregroundStyle(textSecondary)
                }
            }
        }
    }

    @ViewBuilder
    private var todayResetSection: some View {
        Section {
            Button(role: .destructive) {
                isResetConfirmationPresented = true
                Haptics.impact(.light)
            } label: {
                Text("Reset Today")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.red)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .listRowBackground(surfacePrimary)
        }
    }

    @ViewBuilder
    private var exerciseLogSection: some View {
        let allExercises = exercises + healthKitService.todayWorkouts
        let exerciseCalTotal = allExercises.reduce(0) { $0 + $1.calories }
        Section {
            if allExercises.isEmpty && activityCaloriesToday == 0 {
                Text("No exercise logged.")
                    .foregroundStyle(textSecondary)
                    .listRowBackground(surfacePrimary)
            } else {
                ForEach(allExercises.sorted(by: { $0.createdAt < $1.createdAt })) { entry in
                    exerciseLogRow(entry, isDeletable: exercises.contains(where: { $0.id == entry.id }))
                }
                if activityCaloriesToday > 0 {
                    HStack(spacing: 12) {
                        Image(systemName: "figure.walk")
                            .font(.body)
                            .foregroundStyle(accent)
                            .frame(width: 28, alignment: .center)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Walking")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(textPrimary)
                            Text("\(stepActivityService.todayStepCount.formatted()) steps")
                                .font(.caption)
                                .foregroundStyle(textSecondary)
                        }
                        Spacer()
                        Text("\(activityCaloriesToday) cal")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(accent)
                            .monospacedDigit()
                    }
                    .listRowBackground(surfacePrimary)
                }
            }

            Button {
                isAddExerciseSheetPresented = true
                Haptics.impact(.light)
            } label: {
                Label("Add Exercise", systemImage: "figure.run")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .listRowBackground(surfacePrimary)
        } header: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Text("Exercise")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(textSecondary.opacity(0.92))
                    Spacer()
                    Text("\(exerciseCalTotal + activityCaloriesToday) cal")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(textSecondary.opacity(0.82))
                        .monospacedDigit()
                }
            }
            .padding(.top, 8)
            .foregroundStyle(textSecondary)
        }
    }

    private func exerciseLogRow(_ entry: ExerciseEntry, isDeletable: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: entry.exerciseType.iconName)
                .font(.body)
                .foregroundStyle(accent)
                .frame(width: 28, alignment: .center)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.exerciseType.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(textPrimary)
                Text(entry.displayValue)
                    .font(.caption)
                    .foregroundStyle(textSecondary)
            }
            Spacer()
            Text("\(entry.calories) cal")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(accent)
                .monospacedDigit()
        }
        .listRowBackground(surfacePrimary)
        .contextMenu {
            if isDeletable {
                Button(role: .destructive) {
                    deleteExercise(entry)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if isDeletable {
                Button(role: .destructive) {
                    deleteExercise(entry)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    @ViewBuilder
    private var mealDistributionSection: some View {
        Section {
            if mealDistributionData.isEmpty {
                Text("Log food to see your calorie split by meal.")
                    .foregroundStyle(textSecondary)
                    .listRowBackground(surfacePrimary)
            } else {
                mealDistributionCard(mealDistributionData)
                .padding(.vertical, 8)
                .listRowBackground(surfacePrimary)
            }
        } header: {
            Text("Meal Distribution")
                .foregroundStyle(textSecondary)
        }
    }

    private func mealDistributionCard(_ distribution: [(group: MealGroup, calories: Int)], valueSuffix: String = "cal") -> some View {
        HStack(alignment: .center, spacing: 20) {
            MealDistributionRingView(
                segments: distribution.map { (group: $0.group, calories: $0.calories, color: color(for: $0.group)) }
            )
            .frame(width: 132, height: 132)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(distribution, id: \.group.id) { item in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(color(for: item.group))
                            .frame(width: 10, height: 10)

                        Text(item.group.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(textPrimary)

                        Spacer(minLength: 12)

                        Text("\(item.calories) \(valueSuffix)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(textSecondary)
                            .monospacedDigit()
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
            }
            .padding(.leading, 8)
        }
    }

    private func color(for mealGroup: MealGroup) -> Color {
        switch mealGroup {
        case .dinner:
            return Color(red: 1.0, green: 0.42, blue: 0.29)
        case .lunch:
            return Color(red: 0.99, green: 0.80, blue: 0.11)
        case .breakfast:
            return Color(red: 0.15, green: 0.83, blue: 0.55)
        case .snack:
            return Color(red: 0.23, green: 0.51, blue: 1.0)
        }
    }

    private func logRow(_ entry: MealEntry) -> some View {
        let nutrientSummary = activeNutrients.prefix(2).map {
            "\(entryValue(for: $0.key, in: entry))\($0.unit) \($0.name)"
        }.joined(separator: " • ")

        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(textPrimary)
                Text("\(entry.calories) cal" + (nutrientSummary.isEmpty ? "" : " • \(nutrientSummary)"))
                    .font(.caption)
                    .foregroundStyle(textSecondary)
                    .lineLimit(2)
            }

            Spacer()

            Text(entry.createdAt.formatted(date: .omitted, time: .shortened))
                .font(.caption)
                .foregroundStyle(textSecondary)
        }
        .padding(.vertical, 2)
    }

    private var quickAddManagementCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Add Foods")
                .font(.headline.weight(.semibold))
            Text("Save foods you log often for one-tap adding.")
                .font(.subheadline)
                .foregroundStyle(textSecondary)

            Button {
                isQuickAddManagerPresented = true
                Haptics.impact(.light)
            } label: {
                Text("Manage Quick Add Foods")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.bordered)
            .tint(accent)
        }
        .padding(18)
        .tint(Color(red: 0.20, green: 0.50, blue: 0.98))
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground).opacity(0.55))
        )
    }

    private func nutrientFieldBinding(for key: String) -> Binding<String> {
        Binding(
            get: { nutrientInputTexts[key] ?? "" },
            set: { nutrientInputTexts[key] = $0 }
        )
    }

    private var addEntryButton: some View {
        Button {
            addEntry()
        } label: {
            Text("Add Entry")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.borderedProminent)
        .tint(accent)
        .disabled(!canAddEntry)
    }

    private func examplePlaceholder(for nutrient: NutrientDefinition) -> String {
        let example = max(1, nutrient.defaultGoal / 6)
        return "e.g. \(example)"
    }

    private func manualEntryScrollID(for field: Field) -> String {
        switch field {
        case .name:
            return "manualEntryField_name"
        case .calories:
            return "manualEntryField_calories"
        case .nutrient(let key):
            return "manualEntryField_\(key)"
        }
    }

    private func scrollManualEntryField(_ field: Field?, using proxy: ScrollViewProxy) {
        guard let field else { return }
        if case .nutrient = field, activeNutrients.count > 1, !isAddNutrientsExpanded {
            isAddNutrientsExpanded = true
        }
        withAnimation(.easeOut(duration: 0.25)) {
            if isKeyboardVisible, !isAddNutrientsExpanded {
                let collapsedAnchorY = keyboardHeight > 340 ? 0.125 : 0.14
                proxy.scrollTo("addManualEntryCard", anchor: UnitPoint(x: 0.5, y: collapsedAnchorY))
                return
            }

            if case .nutrient(let key) = field,
               isKeyboardVisible,
               let nutrientIndex = activeNutrients.firstIndex(where: { $0.key == key }) {
                let lastRowIndex = (activeNutrients.count - 1) / 2
                let rowIndex = nutrientIndex / 2
                if rowIndex == lastRowIndex {
                    proxy.scrollTo("addEntryButton", anchor: UnitPoint(x: 0.5, y: 0.5))
                    return
                }

                proxy.scrollTo(manualEntryScrollID(for: field), anchor: UnitPoint(x: 0.5, y: 0.32))
                return
            }

            proxy.scrollTo(manualEntryScrollID(for: field), anchor: .center)
        }
    }

    private func scheduleManualEntryScroll(for field: Field?, using proxy: ScrollViewProxy) {
        let delays: [TimeInterval] = [0.08, 0.28]
        for delay in delays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard field == focusedField || field == nil else { return }
                scrollManualEntryField(focusedField ?? field, using: proxy)
            }
        }
    }

    @ViewBuilder
    private func nutrientFieldCell(_ nutrient: NutrientDefinition) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(nutrient.name) (\(nutrient.unit))")
                .font(.caption.weight(.semibold))
                .foregroundStyle(textPrimary)

            TextField(examplePlaceholder(for: nutrient), text: nutrientFieldBinding(for: nutrient.key))
                .keyboardType(.numberPad)
                .focused($focusedField, equals: .nutrient(nutrient.key))
                .inputStyle(surface: surfaceSecondary, text: textPrimary, secondary: textSecondary)
                .id(manualEntryScrollID(for: .nutrient(nutrient.key)))
        }
    }

    private func addEntry() {
        guard
            let calories = parsedEntryCalories,
            let nutrientMap = parsedNutrientInputs,
            calories + nutrientMap.values.reduce(0, +) > 0
        else {
            Haptics.notification(.warning)
            return
        }

        let newEntry = MealEntry(
            id: UUID(),
            name: entryNameText,
            calories: calories,
            nutrientValues: nutrientMap,
            createdAt: Date(),
            mealGroup: mealGroup(for: Date(), source: .manual)
        )

        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            entries.append(newEntry)
        }
        Haptics.impact(.medium)

        entryNameText = ""
        entryCaloriesText = ""
        barcodeLookupError = nil
        for nutrient in activeNutrients {
            nutrientInputTexts[nutrient.key] = ""
        }
        focusedField = nil
        dismissKeyboard()
    }

    private var barcodeScannerSheet: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [backgroundTop, backgroundBottom],
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

    private var usdaSearchSheet: some View {
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
                        HStack(alignment: .top, spacing: 14) {
                            Button {
                                isUSDASearchPresented = false
                                dismissKeyboard()
                                Haptics.selection()
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
                                .foregroundStyle(Color.orange)
                        }

                        if !usdaSearchResults.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Results")
                                    .font(.headline.weight(.semibold))
                                    .foregroundStyle(textPrimary)

                                LazyVStack(spacing: 12) {
                                    ForEach(usdaSearchResults) { result in
                                        usdaSearchResultCard(result)
                                    }
                                }
                            }
                        } else if !usdaSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isUSDASearchLoading && usdaSearchError == nil {
                            Text("Search to see matching foods.")
                                .font(.subheadline)
                                .foregroundStyle(textSecondary)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 24)
                    .padding(.bottom, 32)
                }
                .scrollIndicators(.hidden)
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

    private func foodReviewSheet(item: FoodReviewItem) -> some View {
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
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundStyle(textPrimary)
                                .lineLimit(3)
                                .fixedSize(horizontal: false, vertical: true)

                            if let subtitle = item.subtitle {
                                Text(subtitle)
                                    .font(.subheadline)
                                    .foregroundStyle(textSecondary)
                                    .lineLimit(2)
                            }

                            Text("Base serve: \(formattedDisplayServingAmount(item.servingAmount, unit: item.servingUnit)) \(displayServingUnit(for: item.servingUnit))")
                                .font(.subheadline)
                                .foregroundStyle(textSecondary)
                        }

                        HStack(alignment: .center, spacing: 22) {
                            VerticalServeSlider(
                                value: $selectedFoodReviewMultiplier,
                                range: 0.25...2.0,
                                step: 0.25
                            ) {
                                Haptics.selection()
                            }
                            .frame(width: 104, height: 336)

                            VStack(alignment: .leading, spacing: 14) {
                                reviewStatCard(
                                    title: "Serve",
                                    value: "\(formattedDisplayServingAmount(item.servingAmount * selectedFoodReviewMultiplier, unit: item.servingUnit)) \(displayServingUnit(for: item.servingUnit))"
                                )

                                reviewStatCard(
                                    title: "Multiplier",
                                    value: String(format: "%.2fx", selectedFoodReviewMultiplier)
                                )

                                Text("Move up for more, down for less")
                                    .font(.caption)
                                    .foregroundStyle(textSecondary)
                                    .padding(.top, 2)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        foodReviewNutrientCard(for: item)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 120)
                }
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
        }
    }

    private func usdaSearchResultCard(_ result: USDAFoodSearchResult) -> some View {
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

                Text("\(formattedDisplayServingAmount(result.servingAmount, unit: result.servingUnit)) \(displayServingUnit(for: result.servingUnit))")
                    .font(.caption2)
                    .foregroundStyle(textSecondary.opacity(0.9))
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle(surface: surfacePrimary.opacity(0.95), stroke: textSecondary.opacity(0.15))
        }
        .buttonStyle(.plain)
    }

    private func foodReviewNutrientCard(for item: FoodReviewItem) -> some View {
        let nutrients = reviewNutrients(for: item)

        return VStack(alignment: .leading, spacing: 14) {
            Text("Nutrient Information")
                .font(.headline.weight(.semibold))
                .foregroundStyle(textPrimary)

            if nutrients.isEmpty {
                reviewNutrientTile(
                    title: "Calories",
                    value: "\(scaledReviewCalories(item))"
                )
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    reviewNutrientTile(
                        title: "Calories",
                        value: "\(scaledReviewCalories(item))"
                    )

                    ForEach(nutrients, id: \.key) { nutrient in
                        reviewNutrientTile(
                            title: nutrient.definition.name,
                            value: "\(scaledReviewNutrientValue(for: nutrient.key, item: item)) \(nutrient.definition.unit)"
                        )
                    }
                }
            }
        }
        .padding(18)
        .cardStyle(surface: surfacePrimary.opacity(0.95), stroke: textSecondary.opacity(0.15))
    }

    private func reviewNutrientTile(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(textSecondary)
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(surfaceSecondary.opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(textSecondary.opacity(0.08), lineWidth: 1)
        )
    }

    private func reviewStatCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
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

    private func presentMenu(for venue: DiningVenue) {
        selectedMenuVenue = venue
        let signature = menuService.currentMenuSignature(for: venue)
        let shouldLoadMenu = (venueMenus[venue] ?? .empty).lines.isEmpty
            || lastLoadedMenuSignatureByVenue[venue] != signature
            || menuLoadErrorsByVenue[venue] != nil

        if lastLoadedMenuSignatureByVenue[venue] != signature {
            venueMenus[venue] = .empty
            menuLoadErrorsByVenue.removeValue(forKey: venue)
        }

        isMenuLoading = shouldLoadMenu
        isMenuSheetPresented = true

        if shouldLoadMenu {
            Task {
                await loadMenuFromFirebase(for: venue)
            }
        }
    }

    private func switchMenuToVenue(_ venue: DiningVenue) {
        guard venue != selectedMenuVenue else { return }
        selectedMenuVenue = venue
        let signature = menuService.currentMenuSignature(for: venue)
        let shouldLoadMenu = (venueMenus[venue] ?? .empty).lines.isEmpty
            || lastLoadedMenuSignatureByVenue[venue] != signature
            || menuLoadErrorsByVenue[venue] != nil

        if lastLoadedMenuSignatureByVenue[venue] != signature {
            venueMenus[venue] = .empty
            menuLoadErrorsByVenue.removeValue(forKey: venue)
        }

        isMenuLoading = shouldLoadMenu

        if shouldLoadMenu {
            Task {
                await loadMenuFromFirebase(for: venue)
            }
        }
    }

    @MainActor
    private func loadMenuFromFirebase(for venue: DiningVenue? = nil) async {
        let venue = venue ?? selectedMenuVenue
        isMenuLoading = true
        menuLoadErrorsByVenue.removeValue(forKey: venue)
        do {
            let menu = try await menuService.fetchTodayMenu(for: venue)
            venueMenus[venue] = menu
            lastLoadedMenuSignatureByVenue[venue] = menuService.currentMenuSignature(for: venue)
            var q = selectedMenuItemQuantitiesByVenue
            var m = selectedMenuItemMultipliersByVenue
            q[venue] = [:]
            m[venue] = [:]
            selectedMenuItemQuantitiesByVenue = q
            selectedMenuItemMultipliersByVenue = m
            saveVenueMenus()
        } catch {
            if let nutrisliceError = error as? NutrisliceMenuError,
               case .noMenuAvailable = nutrisliceError {
                // Treat "no menu" as a neutral state, not an error
                venueMenus[venue] = .empty
                menuLoadErrorsByVenue.removeValue(forKey: venue)
            } else {
                menuLoadErrorsByVenue[venue] = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                venueMenus[venue] = .empty
            }
            venueMenus[venue] = .empty
            var q = selectedMenuItemQuantitiesByVenue
            var m = selectedMenuItemMultipliersByVenue
            q[venue] = [:]
            m[venue] = [:]
            selectedMenuItemQuantitiesByVenue = q
            selectedMenuItemMultipliersByVenue = m
        }
        isMenuLoading = false
    }

    @MainActor
    private func preloadMenuForNutrientDiscovery() async {
        let currentSignature = menuService.currentMenuSignature(for: selectedMenuVenue)
        let existingMenu = currentMenu
        let lastSignature = lastLoadedMenuSignatureByVenue[selectedMenuVenue]
        guard existingMenu.lines.isEmpty || lastSignature != currentSignature else {
            return
        }
        do {
            let menu = try await menuService.fetchTodayMenu(for: selectedMenuVenue)
            venueMenus[selectedMenuVenue] = menu
            lastLoadedMenuSignatureByVenue[selectedMenuVenue] = currentSignature
            saveVenueMenus()
        } catch {
            // Keep this silent so startup does not show menu errors.
        }
    }

    private func applyCentralTimeTransitions(forceMenuReload: Bool) {
        let currentCentralDay = menuService.currentCentralDayIdentifier()

        if lastCentralDayIdentifier.isEmpty {
            lastCentralDayIdentifier = currentCentralDay
            if dailyEntryArchive[currentCentralDay] == nil {
                dailyEntryArchive[currentCentralDay] = normalizedEntries(entries)
            }
            dailyExerciseArchive[currentCentralDay] = exercises
            dailyCalorieGoalArchive[currentCentralDay] = calorieGoal
            dailyBurnedCalorieArchive[currentCentralDay] = burnedCaloriesToday
            dailyGoalTypeArchive[currentCentralDay] = goalType.rawValue
            saveDailyEntryArchive()
            saveDailyExerciseArchive()
            saveDailyCalorieGoalArchive()
            saveDailyBurnedCalorieArchive()
            saveDailyGoalTypeArchive()
        }

        if lastCentralDayIdentifier != currentCentralDay {
            // When the app crosses midnight while running, `entries` and `exercises` still contain
            // the previous day's data and should be archived under `lastCentralDayIdentifier`.
            // On a cold start the next day, however, we load today's (empty) entries before
            // calling this method. In that case we *must not* overwrite a non-empty archive
            // for the previous day with an empty array.
            let existingLastEntries = dailyEntryArchive[lastCentralDayIdentifier] ?? []
            if !(entries.isEmpty && !existingLastEntries.isEmpty) {
                dailyEntryArchive[lastCentralDayIdentifier] = normalizedEntries(entries)
            }

            let existingLastExercises = dailyExerciseArchive[lastCentralDayIdentifier] ?? []
            if !(exercises.isEmpty && !existingLastExercises.isEmpty) {
                dailyExerciseArchive[lastCentralDayIdentifier] = exercises
            }

            dailyCalorieGoalArchive[lastCentralDayIdentifier] = calorieGoalForDay(lastCentralDayIdentifier)
            dailyBurnedCalorieArchive[lastCentralDayIdentifier] = burnedCaloriesForDay(lastCentralDayIdentifier)
            dailyGoalTypeArchive[lastCentralDayIdentifier] = goalType.rawValue
            lastCentralDayIdentifier = currentCentralDay
            entries = entries(forDayIdentifier: currentCentralDay)
            exercises = exercises(forDayIdentifier: currentCentralDay)
            if dailyEntryArchive[currentCentralDay] == nil {
                dailyEntryArchive[currentCentralDay] = []
            }
            if dailyExerciseArchive[currentCentralDay] == nil {
                dailyExerciseArchive[currentCentralDay] = []
            }
            dailyCalorieGoalArchive[currentCentralDay] = calorieGoal
            dailyBurnedCalorieArchive[currentCentralDay] = burnedCaloriesToday
            dailyGoalTypeArchive[currentCentralDay] = goalType.rawValue
            saveEntries()
            saveDailyEntryArchive()
            saveDailyExerciseArchive()
            saveDailyCalorieGoalArchive()
            saveDailyBurnedCalorieArchive()
            saveDailyGoalTypeArchive()
            selectedMenuItemQuantitiesByVenue = [:]
            selectedMenuItemMultipliersByVenue = [:]
            venueMenus = [:]
            lastLoadedMenuSignatureByVenue = [:]
            menuLoadErrorsByVenue = [:]
            saveVenueMenus()
            syncHistorySelection(preferToday: true)
        }

        if forceMenuReload {
            venueMenus = [:]
            lastLoadedMenuSignatureByVenue = [:]
            saveVenueMenus()
            Task {
                await preloadMenuForNutrientDiscovery()
            }
        }
    }

    private func addSelectedMenuItems() {
        var itemByID: [String: MenuItem] = [:]
        for item in currentMenu.lines.flatMap(\.items) {
            if itemByID[item.id] == nil {
                itemByID[item.id] = item
            }
        }

        var expandedSelections: [MealEntry] = []
        let now = Date()

        let quantities = selectedMenuItemQuantitiesByVenue[selectedMenuVenue] ?? [:]
        let multipliers = selectedMenuItemMultipliersByVenue[selectedMenuVenue] ?? [:]
        for (id, quantity) in quantities {
            guard let item = itemByID[id], quantity > 0 else { continue }
            let multiplier = multipliers[id] ?? 1.0
            var scaledNutrients: [String: Int] = [:]
            for (key, value) in item.nutrientValues {
                scaledNutrients[key] = Int((Double(value) * multiplier).rounded())
            }
            let scaledCalories = scaledNutrients["calories"] ?? Int((Double(item.calories) * multiplier).rounded())

            for _ in 0..<quantity {
                expandedSelections.append(
                    MealEntry(
                        id: UUID(),
                        name: item.name,
                        calories: scaledCalories,
                        nutrientValues: scaledNutrients,
                        createdAt: now,
                        mealGroup: mealGroup(for: menuService.currentMenuType(now: now))
                    )
                )
            }
        }

        guard !expandedSelections.isEmpty else {
            Haptics.notification(.warning)
            return
        }

        withAnimation(.easeInOut(duration: 0.25)) {
            entries.append(contentsOf: expandedSelections)
        }
        Haptics.notification(.success)

        var q = selectedMenuItemQuantitiesByVenue
        var m = selectedMenuItemMultipliersByVenue
        q[selectedMenuVenue] = [:]
        m[selectedMenuVenue] = [:]
        selectedMenuItemQuantitiesByVenue = q
        selectedMenuItemMultipliersByVenue = m
        isMenuSheetPresented = false
        selectedTab = .today
    }

    private func handlePhotoPlate(items: [MenuItem], imageData: Data) {
        isPlateEstimateLoading = true
        plateEstimateErrorMessage = nil
        Task {
            do {
                let service = GeminiPlateEstimateService()
                let result = try await service.estimatePortions(imageData: imageData, items: items)
                let ozByName = result.ozByName
                let countByName = result.countByName
                let baseOzByName = result.baseOzByName
                await MainActor.run {
                    var ozById: [String: Double] = [:]
                    var baseOzById: [String: Double] = [:]
                    for item in items {
                        let unit = item.servingUnit.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                        let ambiguousUnit = unit.isEmpty || unit == "serving" || unit == "servings" || unit == "each" || unit == "ea" || unit == "item"
                        // Missing or zero = not on plate. Count-based items use quantity; others use oz.
                        if item.isCountBased {
                            ozById[item.id] = Double(countByName[item.name] ?? 0)
                        } else {
                            ozById[item.id] = ozByName[item.name] ?? 0
                            // Only let Gemini override base serving when:
                            // 1) The user has enabled AI base servings in Settings, and
                            // 2) The menu unit is ambiguous ("1 each", "1 serving", etc).
                            // For explicit weights/volumes like cups/oz/g, or when the toggle is off,
                            // keep the Nutrislice base serving instead of Gemini's.
                            if useAIBaseServings, ambiguousUnit, let base = baseOzByName[item.name] {
                                baseOzById[item.id] = base
                            }
                        }
                    }
                    plateEstimateItems = items
                    plateEstimateOzByItemId = ozById
                    plateEstimateBaseOzByItemId = baseOzById
                    isPlateEstimateLoading = false
                }
            } catch {
                await MainActor.run {
                    plateEstimateErrorMessage = error.localizedDescription
                    isPlateEstimateLoading = false
                }
            }
        }
    }

    private func addMenuItemsWithPortions(_ pairs: [(item: MenuItem, oz: Double, baseOz: Double)]) {
        let now = Date()
        let mealGrp = mealGroup(for: menuService.currentMenuType(now: now))
        var expandedSelections: [MealEntry] = []
        for (item, oz, baseOz) in pairs {
            let multiplier: Double = item.isCountBased ? oz : (baseOz > 0 ? (oz / baseOz) : 1.0)
            var scaledNutrients: [String: Int] = [:]
            for (key, value) in item.nutrientValues {
                scaledNutrients[key] = Int((Double(value) * multiplier).rounded())
            }
            let scaledCalories = Int((Double(item.calories) * multiplier).rounded())
            expandedSelections.append(
                MealEntry(
                    id: UUID(),
                    name: item.name,
                    calories: scaledCalories,
                    nutrientValues: scaledNutrients,
                    createdAt: now,
                    mealGroup: mealGrp
                )
            )
        }
        guard !expandedSelections.isEmpty else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            entries.append(contentsOf: expandedSelections)
        }
        Haptics.notification(.success)
        selectedTab = .today
    }

    private func clearMenuSelection() {
        selectedMenuItemQuantitiesByVenue = [:]
        selectedMenuItemMultipliersByVenue = [:]
    }

    @MainActor
    private func handleScannedBarcode(_ barcode: String) async {
        guard !isBarcodeLookupInFlight else { return }

        hasScannedBarcodeInCurrentSheet = true
        isBarcodeLookupInFlight = true
        barcodeLookupError = nil

        do {
            let product = try await openFoodFactsService.fetchProduct(for: barcode)
            isBarcodeLookupInFlight = false
            hasScannedBarcodeInCurrentSheet = false
            isBarcodeScannerPresented = false
            selectedFoodReviewMultiplier = 1.0
            DispatchQueue.main.async {
                openFoodReview(for: product)
            }
            Haptics.notification(.success)
        } catch {
            isBarcodeLookupInFlight = false
            hasScannedBarcodeInCurrentSheet = false
            barcodeLookupError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            Haptics.notification(.warning)
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

    private func addReviewedFood(_ item: FoodReviewItem) {
        let multiplier = selectedFoodReviewMultiplier
        var scaledNutrients: [String: Int] = [:]
        for (key, value) in item.nutrientValues {
            scaledNutrients[key] = Int((Double(value) * multiplier).rounded())
        }

        let newEntry = MealEntry(
            id: UUID(),
            name: item.name,
            calories: scaledReviewCalories(item),
            nutrientValues: scaledNutrients,
            createdAt: Date(),
            mealGroup: mealGroup(for: Date(), source: item.entrySource)
        )

        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            entries.append(newEntry)
        }

        foodReviewItem = nil
        selectedFoodReviewMultiplier = 1.0
        selectedTab = .today
        barcodeLookupError = nil
        usdaSearchError = nil
        Haptics.notification(.success)
    }

    private func deleteEntry(_ entry: MealEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else {
            return
        }

        withAnimation(.easeInOut(duration: 0.2)) {
            _ = entries.remove(at: index)
        }
        Haptics.selection()
    }

    private func deleteExercise(_ entry: ExerciseEntry) {
        guard let index = exercises.firstIndex(where: { $0.id == entry.id }) else {
            return
        }

        withAnimation(.easeInOut(duration: 0.2)) {
            _ = exercises.remove(at: index)
        }
        Haptics.selection()
    }

    private func updateEntry(_ updatedEntry: MealEntry) {
        guard let index = entries.firstIndex(where: { $0.id == updatedEntry.id }) else {
            return
        }

        withAnimation(.easeInOut(duration: 0.2)) {
            entries[index] = updatedEntry
        }
        editingEntry = nil
        Haptics.notification(.success)
    }

    private func resetTodayLog() {
        withAnimation(.easeInOut(duration: 0.2)) {
            entries.removeAll()
            exercises.removeAll()
        }
        Haptics.notification(.warning)
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func parseInputValue(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return 0
        }

        guard let parsed = Int(trimmed), parsed >= 0 else {
            return nil
        }

        return parsed
    }

    private func entryValue(for key: String, in entry: MealEntry) -> Int {
        if key == "g_protein" {
            return entry.nutrientValues[key] ?? entry.protein
        }
        return entry.nutrientValues[key] ?? 0
    }

    private func totalNutrient(for key: String) -> Int {
        entries.reduce(0) { $0 + entryValue(for: key, in: $1) }
    }

    private func editableNutrients(for entry: MealEntry) -> [NutrientDefinition] {
        let keys = Set(activeNutrients.map(\.key))
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

    private func goalForNutrient(_ key: String) -> Int {
        max(nutrientGoals[key] ?? NutrientCatalog.definition(for: key).defaultGoal, 1)
    }

    private func sanitizeStoredGoals() {
        if storedDeficitCalories < 0 {
            storedDeficitCalories = 0
        }
    }

    private func normalizeTrackingState() {
        let valid = trackedNutrientKeys
            .map { $0.lowercased() }
            .filter { !$0.isEmpty && !NutrientCatalog.nonTrackableKeys.contains($0) }
            .filter { !excludedNutrientKeys.contains($0) }
        trackedNutrientKeys = Array(NSOrderedSet(array: valid)) as? [String] ?? valid

        for key in trackedNutrientKeys {
            if nutrientGoals[key] == nil {
                let defaultGoal = key == "g_protein" ? max(legacyStoredProteinGoal, 1) : NutrientCatalog.definition(for: key).defaultGoal
                nutrientGoals[key] = defaultGoal
            }
        }
    }

    private func loadTrackingPreferences() {
        if let data = storedTrackedNutrientsData.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            trackedNutrientKeys = decoded
        }

        if let data = storedNutrientGoalsData.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String: Int].self, from: data) {
            nutrientGoals = decoded
        }

        normalizeTrackingState()
        saveTrackingPreferences()
    }

    private func saveTrackingPreferences() {
        if let trackedData = try? JSONEncoder().encode(trackedNutrientKeys) {
            storedTrackedNutrientsData = String(decoding: trackedData, as: UTF8.self)
        }
        if let goalsData = try? JSONEncoder().encode(nutrientGoals) {
            storedNutrientGoalsData = String(decoding: goalsData, as: UTF8.self)
        }
    }

    private func syncInputFieldsToTrackedNutrients() {
        var next: [String: String] = [:]
        for nutrient in activeNutrients {
            next[nutrient.key] = nutrientInputTexts[nutrient.key] ?? ""
        }
        nutrientInputTexts = next
    }

    private func loadDailyEntryArchive() {
        if !storedDailyEntryArchiveData.isEmpty,
           let data = storedDailyEntryArchiveData.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String: [MealEntry]].self, from: data) {
            dailyEntryArchive = decoded.mapValues { normalizedEntries($0) }
        } else {
            dailyEntryArchive = migrateLegacyEntriesIfNeeded()
        }

        displayedHistoryMonth = monthStart(for: Date())
        loadDailyExerciseArchive()
        entries = entries(forDayIdentifier: todayDayIdentifier)
        exercises = exercises(forDayIdentifier: todayDayIdentifier)
        loadDailyCalorieGoalArchive()
        loadDailyBurnedCalorieArchive()
        loadDailyGoalTypeArchive()
        syncCurrentDayGoalArchive()
        syncHistorySelection(preferToday: true)
        saveDailyEntryArchive()
    }

    private func saveEntries() {
        guard let data = try? JSONEncoder().encode(entries) else {
            return
        }

        storedEntriesData = String(decoding: data, as: UTF8.self)
    }

    private func saveDailyEntryArchive() {
        guard let data = try? JSONEncoder().encode(dailyEntryArchive) else {
            return
        }
        storedDailyEntryArchiveData = String(decoding: data, as: UTF8.self)
    }

    private func loadDailyCalorieGoalArchive() {
        guard
            !storedDailyCalorieGoalArchiveData.isEmpty,
            let data = storedDailyCalorieGoalArchiveData.data(using: .utf8),
            let decoded = try? JSONDecoder().decode([String: Int].self, from: data)
        else {
            dailyCalorieGoalArchive = [:]
            return
        }

        dailyCalorieGoalArchive = decoded
    }

    private func saveDailyCalorieGoalArchive() {
        guard let data = try? JSONEncoder().encode(dailyCalorieGoalArchive) else {
            return
        }
        storedDailyCalorieGoalArchiveData = String(decoding: data, as: UTF8.self)
    }

    private func loadDailyBurnedCalorieArchive() {
        guard
            !storedDailyBurnedCalorieArchiveData.isEmpty,
            let data = storedDailyBurnedCalorieArchiveData.data(using: .utf8),
            let decoded = try? JSONDecoder().decode([String: Int].self, from: data)
        else {
            dailyBurnedCalorieArchive = [:]
            return
        }

        dailyBurnedCalorieArchive = decoded
    }

    private func saveDailyBurnedCalorieArchive() {
        guard let data = try? JSONEncoder().encode(dailyBurnedCalorieArchive) else {
            return
        }
        storedDailyBurnedCalorieArchiveData = String(decoding: data, as: UTF8.self)
    }

    private func loadDailyExerciseArchive() {
        guard
            !storedDailyExerciseArchiveData.isEmpty,
            let data = storedDailyExerciseArchiveData.data(using: .utf8),
            let decoded = try? JSONDecoder().decode([String: [ExerciseEntry]].self, from: data)
        else {
            dailyExerciseArchive = [:]
            return
        }
        dailyExerciseArchive = decoded
    }

    private func saveDailyExerciseArchive() {
        guard let data = try? JSONEncoder().encode(dailyExerciseArchive) else {
            return
        }
        storedDailyExerciseArchiveData = String(decoding: data, as: UTF8.self)
    }

    private func loadDailyGoalTypeArchive() {
        guard
            !storedDailyGoalTypeArchiveData.isEmpty,
            let data = storedDailyGoalTypeArchiveData.data(using: .utf8),
            let decoded = try? JSONDecoder().decode([String: String].self, from: data)
        else {
            dailyGoalTypeArchive = [:]
            return
        }
        dailyGoalTypeArchive = decoded
    }

    private func saveDailyGoalTypeArchive() {
        guard let data = try? JSONEncoder().encode(dailyGoalTypeArchive) else {
            return
        }
        storedDailyGoalTypeArchiveData = String(decoding: data, as: UTF8.self)
    }

    private func syncCurrentEntriesToArchive() {
        dailyEntryArchive[todayDayIdentifier] = normalizedEntries(entries)
        dailyExerciseArchive[todayDayIdentifier] = exercises
        saveEntries()
        saveDailyEntryArchive()
        saveDailyExerciseArchive()
        syncHistorySelection()
    }

    private func migrateLegacyEntriesIfNeeded() -> [String: [MealEntry]] {
        guard
            !storedEntriesData.isEmpty,
            let data = storedEntriesData.data(using: .utf8),
            let decoded = try? JSONDecoder().decode([MealEntry].self, from: data)
        else {
            return [:]
        }

        let normalized = normalizedEntries(decoded)
        guard !normalized.isEmpty else {
            return [:]
        }

        return [todayDayIdentifier: normalized]
    }

    private func normalizedEntries(_ entries: [MealEntry]) -> [MealEntry] {
        entries.map {
            MealEntry(
                id: $0.id,
                name: MealEntry.normalizedName($0.name),
                calories: $0.calories,
                nutrientValues: $0.nutrientValues,
                createdAt: $0.createdAt,
                mealGroup: $0.mealGroup
            )
        }
    }

    private func entries(forDayIdentifier identifier: String) -> [MealEntry] {
        dailyEntryArchive[identifier] ?? []
    }

    private func exercises(forDayIdentifier identifier: String) -> [ExerciseEntry] {
        dailyExerciseArchive[identifier] ?? []
    }

    private func currentCentralDate() -> Date {
        Date()
    }

    private func centralDayIdentifier(for date: Date) -> String {
        let startOfDay = centralCalendar.startOfDay(for: date)
        let components = centralCalendar.dateComponents([.year, .month, .day], from: startOfDay)
        let year = components.year ?? 0
        let month = components.month ?? 1
        let day = components.day ?? 1
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    private func date(fromCentralDayIdentifier identifier: String) -> Date? {
        let parts = identifier.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        let components = DateComponents(timeZone: centralCalendar.timeZone, year: parts[0], month: parts[1], day: parts[2])
        return centralCalendar.date(from: components)
    }

    private func monthStart(for date: Date) -> Date {
        let start = centralCalendar.startOfDay(for: date)
        let components = centralCalendar.dateComponents([.year, .month], from: start)
        return centralCalendar.date(from: components) ?? start
    }

    private func syncHistorySelection(preferToday: Bool = false) {
        let today = todayDayIdentifier
        if preferToday {
            selectedHistoryDayIdentifier = today
        } else if selectedHistoryDayIdentifier.isEmpty {
            selectedHistoryDayIdentifier = defaultHistorySelectionIdentifier()
        } else if dailyEntryArchive[selectedHistoryDayIdentifier] == nil && selectedHistoryDayIdentifier != today {
            selectedHistoryDayIdentifier = defaultHistorySelectionIdentifier()
        }

        if let selectedDate = date(fromCentralDayIdentifier: selectedHistoryDayIdentifier) {
            displayedHistoryMonth = monthStart(for: selectedDate)
        }
    }

    private func defaultHistorySelectionIdentifier() -> String {
        let today = todayDayIdentifier
        if let latestPast = archivedDayIdentifiers.last(where: { $0 < today }) {
            return latestPast
        }
        return today
    }

    private func dailyCalories(for identifier: String) -> Int {
        entries(forDayIdentifier: identifier).reduce(0) { $0 + $1.calories }
    }

    private func calculatedBMR(for profile: BMRProfile) -> Int? {
        guard profile.isComplete else { return nil }

        let weightKg = Double(profile.weightPounds) * 0.45359237
        let totalInches = (profile.heightFeet * 12) + profile.heightInches
        let heightCm = Double(totalInches) * 2.54
        let sexConstant = profile.sex == .male ? 5.0 : -161.0
        let raw = (10.0 * weightKg) + (6.25 * heightCm) - (5.0 * Double(profile.age)) + sexConstant
        return max(Int(raw.rounded()), 800)
    }

    private func nutrientTotals(for identifier: String) -> [String: Int] {
        entries(forDayIdentifier: identifier).reduce(into: [:]) { partialResult, entry in
            for (key, value) in entry.nutrientValues {
                partialResult[key, default: 0] += value
            }
        }
    }

    private func calorieGoalForDay(_ identifier: String) -> Int {
        if identifier == todayDayIdentifier {
            return max(calorieGoal, 1)
        }
        if let archived = dailyCalorieGoalArchive[identifier] {
            return max(archived, 1)
        }

        let burned = burnedCaloriesForDay(identifier)
        let amount = deficitForDay(identifier)
        if goalTypeForDay(identifier) == .surplus {
            return max(burned + amount, 1)
        } else {
            return max(burned - amount, 1)
        }
    }

    private func burnedCaloriesForDay(_ identifier: String) -> Int {
        if let archived = dailyBurnedCalorieArchive[identifier] {
            return max(archived, 1)
        }
        if identifier == todayDayIdentifier {
            return max(burnedCaloriesToday, 1)
        }
        if let archivedGoal = dailyCalorieGoalArchive[identifier] {
            // Older archived days only stored the intake goal. Fall back to that value as burned for compatibility.
            return max(archivedGoal, 1)
        }
        return max(ContentView.fallbackAverageBMR, 1)
    }

    private func syncCurrentDayGoalArchive() {
        dailyExerciseArchive[todayDayIdentifier] = exercises
        dailyCalorieGoalArchive[todayDayIdentifier] = calorieGoal
        dailyBurnedCalorieArchive[todayDayIdentifier] = burnedCaloriesToday
        dailyGoalTypeArchive[todayDayIdentifier] = goalType.rawValue
        saveDailyExerciseArchive()
        saveDailyCalorieGoalArchive()
        saveDailyBurnedCalorieArchive()
        saveDailyGoalTypeArchive()
    }

    private func historySummary(for identifier: String) -> HistoryDaySummary {
        let dayEntries = entries(forDayIdentifier: identifier)
        let total = dayEntries.reduce(0) { $0 + $1.calories }
        let date = date(fromCentralDayIdentifier: identifier) ?? currentCentralDate()
        let goal = calorieGoalForDay(identifier)
        let burned = burnedCaloriesForDay(identifier)
        let dayGoalType = goalTypeForDay(identifier)

        let goalMet: Bool
        if dayGoalType == .surplus {
            goalMet = total > 0 && total >= burned && total <= goal
        } else {
            goalMet = total > 0 && total <= goal
        }

        return HistoryDaySummary(
            dayIdentifier: identifier,
            date: date,
            totalCalories: total,
            entryCount: dayEntries.count,
            goalMet: goalMet
        )
    }

    private func dayIdentifiers(forLast dayCount: Int) -> [String] {
        let today = centralCalendar.startOfDay(for: Date())
        // Use completed days only: last `dayCount` days, excluding today
        return (0..<dayCount).compactMap { offset in
            centralCalendar.date(byAdding: .day, value: -(dayCount - offset), to: today)
                .map { centralDayIdentifier(for: $0) }
        }
    }

    private func netCalorieColor(_ net: Int) -> Color {
        switch goalType {
        case .deficit:
            // Negative net = deficit, positive = surplus
            if net >= 0 {
                // At or above maintenance while aiming for a deficit
                return .red
            }
            let deficit = -net
            if deficit >= storedDeficitCalories {
                // At or beyond target deficit
                return .green
            } else {
                // In a deficit but smaller than target
                return .yellow
            }
        case .surplus:
            // Positive net = surplus, negative = unintended deficit
            if net < 0 {
                return .red
            }
            if net <= storedSurplusCalories {
                // Within target surplus range
                return .green
            } else {
                // Surplus larger than goal
                return .red
            }
        }
    }

    private func netSign(_ net: Int) -> String {
        if net > 0 { return "+" }
        if net < 0 { return "-" }
        return ""
    }

    private func interpolateColor(from: UIColor, to: UIColor, progress: Double) -> Color {
        let clamped = max(0, min(progress, 1))

        var r1: CGFloat = 0
        var g1: CGFloat = 0
        var b1: CGFloat = 0
        var a1: CGFloat = 0
        var r2: CGFloat = 0
        var g2: CGFloat = 0
        var b2: CGFloat = 0
        var a2: CGFloat = 0

        from.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        to.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)

        return Color(
            red: Double(r1 + (r2 - r1) * clamped),
            green: Double(g1 + (g2 - g1) * clamped),
            blue: Double(b1 + (b2 - b1) * clamped),
            opacity: Double(a1 + (a2 - a1) * clamped)
        )
    }

    private func openFoodReview(for product: OpenFoodFactsProduct) {
        selectedFoodReviewMultiplier = 1.0
        foodReviewItem = FoodReviewItem(
            name: product.name,
            subtitle: nil,
            calories: product.calories,
            nutrientValues: product.nutrientValues,
            servingAmount: product.servingAmount,
            servingUnit: product.servingUnit,
            entrySource: .barcode
        )
    }

    private func openFoodReview(for result: USDAFoodSearchResult) {
        selectedFoodReviewMultiplier = 1.0
        isUSDASearchPresented = false
        dismissKeyboard()
        DispatchQueue.main.async {
            foodReviewItem = FoodReviewItem(
                name: result.name,
                subtitle: result.brand,
                calories: result.calories,
                nutrientValues: result.nutrientValues,
                servingAmount: result.servingAmount,
                servingUnit: result.servingUnit,
                entrySource: .usda
            )
        }
    }

    private func mealGroup(for date: Date, source: EntrySource) -> MealGroup {
        switch source {
        case let .pccMenu(menuType):
            return mealGroup(for: menuType)
        case .manual, .quickAdd, .barcode, .usda:
            return genericMealGroup(for: date)
        }
    }

    private func mealGroup(for menuType: NutrisliceMenuService.MenuType) -> MealGroup {
        switch menuType {
        case .breakfast:
            return .breakfast
        case .lunch:
            return .lunch
        case .dinner:
            return .dinner
        }
    }

    private func genericMealGroup(for date: Date) -> MealGroup {
        let components = centralCalendar.dateComponents([.hour, .minute], from: date)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        let totalMinutes = hour * 60 + minute

        if totalMinutes >= 240 && totalMinutes < 645 {
            return .breakfast
        }
        if totalMinutes >= 645 && totalMinutes < 840 {
            return .lunch
        }
        if totalMinutes >= 840 && totalMinutes < 1005 {
            return .snack
        }
        if totalMinutes >= 1005 && totalMinutes < 1200 {
            return .dinner
        }
        return .snack
    }

    private func loadQuickAddFoods() {
        guard
            !storedQuickAddFoodsData.isEmpty,
            let data = storedQuickAddFoodsData.data(using: .utf8),
            let decoded = try? JSONDecoder().decode([QuickAddFood].self, from: data)
        else {
            quickAddFoods = []
            return
        }

        quickAddFoods = decoded.sorted { $0.createdAt > $1.createdAt }
    }

    private func saveQuickAddFoods() {
        guard let data = try? JSONEncoder().encode(quickAddFoods) else {
            return
        }
        storedQuickAddFoodsData = String(decoding: data, as: UTF8.self)
    }

    private func addQuickAddFood(_ item: QuickAddFood) {
        let now = Date()
        let newEntry = MealEntry(
            id: UUID(),
            name: item.name,
            calories: item.calories,
            nutrientValues: item.nutrientValues,
            createdAt: now,
            mealGroup: mealGroup(for: now, source: .quickAdd)
        )

        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            entries.append(newEntry)
        }

        isQuickAddPickerPresented = false
        selectedTab = .today
        Haptics.notification(.success)
    }

    private func scaledReviewCalories(_ item: FoodReviewItem) -> Int {
        Int((Double(item.calories) * selectedFoodReviewMultiplier).rounded())
    }

    private func scaledReviewNutrientValue(for key: String, item: FoodReviewItem) -> Int {
        Int((Double(item.nutrientValues[key] ?? 0) * selectedFoodReviewMultiplier).rounded())
    }

    private func reviewNutrients(for item: FoodReviewItem) -> [(key: String, definition: NutrientDefinition)] {
        item.nutrientValues.keys
            .sorted { lhs, rhs in
                let lhsRank = NutrientCatalog.preferredOrder.firstIndex(of: lhs) ?? Int.max
                let rhsRank = NutrientCatalog.preferredOrder.firstIndex(of: rhs) ?? Int.max
                if lhsRank != rhsRank {
                    return lhsRank < rhsRank
                }
                let lhsName = NutrientCatalog.definition(for: lhs).name
                let rhsName = NutrientCatalog.definition(for: rhs).name
                if lhsName != rhsName {
                    return lhsName < rhsName
                }
                return lhs < rhs
            }
            .filter { (item.nutrientValues[$0] ?? 0) > 0 }
            .prefix(5)
            .map { ($0, NutrientCatalog.definition(for: $0)) }
    }

    private func formattedServingAmount(_ amount: Double) -> String {
        if abs(amount.rounded() - amount) < 0.001 {
            return String(format: "%.0f", amount)
        }
        if abs((amount * 10).rounded() - (amount * 10)) < 0.001 {
            return String(format: "%.1f", amount)
        }
        return String(format: "%.2f", amount)
    }

    private func formattedDisplayServingAmount(_ amount: Double, unit: String) -> String {
        formattedServingAmount(convertedServingAmount(amount, unit: unit))
    }

    private func displayServingUnit(for unit: String) -> String {
        isGramUnit(unit) ? "oz" : unit
    }

    private func convertedServingAmount(_ amount: Double, unit: String) -> Double {
        if isGramUnit(unit) {
            return amount / 28.3495
        }
        return amount
    }

    private func isGramUnit(_ unit: String) -> Bool {
        let normalized = unit.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "g" || normalized == "gram" || normalized == "grams"
    }
}

#Preview {
    ContentView()
}
