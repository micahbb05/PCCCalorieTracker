import SwiftUI
import Charts
import UIKit
import Combine

enum MealGroup: String, Codable, CaseIterable, Identifiable {
    case breakfast
    case lunch
    case dinner
    case snack

    var id: String { rawValue }

    var title: String {
        switch self {
        case .breakfast:
            return "Breakfast"
        case .lunch:
            return "Lunch"
        case .dinner:
            return "Dinner"
        case .snack:
            return "Snack"
        }
    }

    var logSortRank: Int {
        switch self {
        case .dinner:
            return 0
        case .lunch:
            return 1
        case .breakfast:
            return 2
        case .snack:
            return 3
        }
    }

    static var logDisplayOrder: [MealGroup] {
        [.dinner, .lunch, .breakfast, .snack]
    }
}

enum BMRSex: String, Codable, CaseIterable, Identifiable {
    case male
    case female

    var id: String { rawValue }

    var title: String {
        switch self {
        case .male: return "Male"
        case .female: return "Female"
        }
    }
}

struct BMRProfile: Codable, Equatable {
    var age: Int
    var sex: BMRSex
    var heightFeet: Int
    var heightInches: Int
    var weightPounds: Int

    static let empty = BMRProfile(age: 0, sex: .male, heightFeet: 0, heightInches: 0, weightPounds: 0)

    var isComplete: Bool {
        age > 0 && heightFeet > 0 && heightInches >= 0 && heightInches < 12 && weightPounds > 0
    }
}

struct MealEntry: Identifiable, Codable, Equatable {
    let id: UUID
    let name: String
    let calories: Int
    let protein: Int
    let nutrientValues: [String: Int]
    let createdAt: Date
    let mealGroup: MealGroup

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case calories
        case protein
        case nutrientValues
        case createdAt
        case mealGroup
    }

    init(id: UUID, name: String, calories: Int, nutrientValues: [String: Int], createdAt: Date, mealGroup: MealGroup) {
        self.id = id
        self.name = MealEntry.normalizedName(name)
        self.calories = max(0, calories)
        self.nutrientValues = nutrientValues.mapValues { max(0, $0) }
        self.protein = self.nutrientValues["g_protein"] ?? 0
        self.createdAt = createdAt
        self.mealGroup = mealGroup
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        calories = max(0, try container.decode(Int.self, forKey: .calories))
        createdAt = try container.decode(Date.self, forKey: .createdAt)

        let decodedName = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        name = MealEntry.normalizedName(decodedName)

        var decodedNutrients = try container.decodeIfPresent([String: Int].self, forKey: .nutrientValues) ?? [:]
        let decodedProtein = max(0, try container.decodeIfPresent(Int.self, forKey: .protein) ?? 0)
        if decodedNutrients["g_protein"] == nil && decodedProtein > 0 {
            decodedNutrients["g_protein"] = decodedProtein
        }

        nutrientValues = decodedNutrients.mapValues { max(0, $0) }
        protein = nutrientValues["g_protein"] ?? decodedProtein
        mealGroup = try container.decodeIfPresent(MealGroup.self, forKey: .mealGroup)
            ?? MealEntry.inferredMealGroup(for: createdAt)
    }

    static func normalizedName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Unnamed food" : trimmed
    }

    private static func inferredMealGroup(for date: Date) -> MealGroup {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago") ?? .current
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        let totalMinutes = hour * 60 + minute

        if totalMinutes >= 240 && totalMinutes < 705 {
            return .breakfast
        }
        if totalMinutes >= 705 && totalMinutes < 840 {
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
}

struct QuickAddFood: Identifiable, Codable, Equatable {
    let id: UUID
    let name: String
    let calories: Int
    let nutrientValues: [String: Int]
    let createdAt: Date

    init(id: UUID, name: String, calories: Int, nutrientValues: [String: Int], createdAt: Date) {
        self.id = id
        self.name = MealEntry.normalizedName(name)
        self.calories = max(0, calories)
        self.nutrientValues = nutrientValues.mapValues { max(0, $0) }
        self.createdAt = createdAt
    }
}

struct NutrientDefinition: Identifiable, Hashable {
    let key: String
    let name: String
    let unit: String
    let defaultGoal: Int
    let minGoal: Int
    let maxGoal: Int
    let step: Int

    var id: String { key }
}

private enum AppIconChoice: String, CaseIterable, Identifiable {
    case standard
    case pink

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard:
            return "Standard"
        case .pink:
            return "Pink"
        }
    }

    var alternateIconName: String? {
        switch self {
        case .standard:
            return nil
        case .pink:
            return "AppIconPink"
        }
    }
}

private enum AppIconManager {
    static func apply(_ choice: AppIconChoice) {
        guard UIApplication.shared.supportsAlternateIcons else { return }
        let desired = choice.alternateIconName
        guard UIApplication.shared.alternateIconName != desired else { return }
        UIApplication.shared.setAlternateIconName(desired)
    }
}

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

private enum NutrientCatalog {
    private static let known: [String: NutrientDefinition] = [
        "g_protein": NutrientDefinition(key: "g_protein", name: "Protein", unit: "g", defaultGoal: 150, minGoal: 10, maxGoal: 400, step: 5),
        "g_carbs": NutrientDefinition(key: "g_carbs", name: "Carbs", unit: "g", defaultGoal: 250, minGoal: 10, maxGoal: 700, step: 5),
        "g_fat": NutrientDefinition(key: "g_fat", name: "Fat", unit: "g", defaultGoal: 70, minGoal: 10, maxGoal: 250, step: 5),
        "g_saturated_fat": NutrientDefinition(key: "g_saturated_fat", name: "Saturated Fat", unit: "g", defaultGoal: 20, minGoal: 0, maxGoal: 120, step: 1),
        "g_trans_fat": NutrientDefinition(key: "g_trans_fat", name: "Trans Fat", unit: "g", defaultGoal: 2, minGoal: 0, maxGoal: 30, step: 1),
        "g_fiber": NutrientDefinition(key: "g_fiber", name: "Fiber", unit: "g", defaultGoal: 30, minGoal: 0, maxGoal: 120, step: 1),
        "g_sugar": NutrientDefinition(key: "g_sugar", name: "Sugar", unit: "g", defaultGoal: 50, minGoal: 0, maxGoal: 250, step: 1),
        "g_added_sugar": NutrientDefinition(key: "g_added_sugar", name: "Added Sugar", unit: "g", defaultGoal: 30, minGoal: 0, maxGoal: 150, step: 1),
        "mg_sodium": NutrientDefinition(key: "mg_sodium", name: "Sodium", unit: "mg", defaultGoal: 2300, minGoal: 100, maxGoal: 8000, step: 50),
        "mg_cholesterol": NutrientDefinition(key: "mg_cholesterol", name: "Cholesterol", unit: "mg", defaultGoal: 300, minGoal: 0, maxGoal: 2000, step: 10),
        "mg_potassium": NutrientDefinition(key: "mg_potassium", name: "Potassium", unit: "mg", defaultGoal: 3500, minGoal: 100, maxGoal: 10000, step: 50),
        "mg_calcium": NutrientDefinition(key: "mg_calcium", name: "Calcium", unit: "mg", defaultGoal: 1000, minGoal: 100, maxGoal: 5000, step: 25),
        "mg_iron": NutrientDefinition(key: "mg_iron", name: "Iron", unit: "mg", defaultGoal: 18, minGoal: 0, maxGoal: 200, step: 1),
        "mg_vitamin_c": NutrientDefinition(key: "mg_vitamin_c", name: "Vitamin C", unit: "mg", defaultGoal: 90, minGoal: 0, maxGoal: 2000, step: 5),
        "iu_vitamin_a": NutrientDefinition(key: "iu_vitamin_a", name: "Vitamin A", unit: "IU", defaultGoal: 3000, minGoal: 0, maxGoal: 12000, step: 100),
        "mcg_vitamin_a": NutrientDefinition(key: "mcg_vitamin_a", name: "Vitamin A", unit: "mcg", defaultGoal: 900, minGoal: 0, maxGoal: 5000, step: 25),
        "mcg_vitamin_d": NutrientDefinition(key: "mcg_vitamin_d", name: "Vitamin D", unit: "mcg", defaultGoal: 20, minGoal: 0, maxGoal: 200, step: 1)
    ]

    static let preferredOrder: [String] = [
        "g_protein", "g_carbs", "g_fat", "g_fiber", "g_sugar", "mg_sodium"
    ]
    static let nonTrackableKeys: Set<String> = ["calories", "re_vitamin_a"]
    static let defaultExcludedBecauseConsistentlyNull: Set<String> = [
        "g_fiber",
        "mg_potassium",
        "g_added_sugar",
        "g_trans_fat",
        "mg_vitamin_c",
        "iu_vitamin_a",
        "mcg_vitamin_a",
        "mcg_vitamin_d",
        "mg_vitamin_d",
        "re_vitamin_a"
    ]

    static var knownKeys: [String] {
        Array(known.keys)
    }

    static func definition(for key: String) -> NutrientDefinition {
        let normalizedKey = key.lowercased()
        if let knownDefinition = known[normalizedKey] {
            return knownDefinition
        }

        let parts = normalizedKey.split(separator: "_")
        let unitToken = parts.first.map(String.init) ?? "g"
        let remainder = parts.dropFirst().map(String.init).joined(separator: "_")
        let name = prettyName(from: remainder.isEmpty ? normalizedKey : remainder)
        let unit = prettyUnit(unitToken)
        let range = rangeFor(unitToken: unitToken)
        return NutrientDefinition(
            key: normalizedKey,
            name: name,
            unit: unit,
            defaultGoal: range.defaultGoal,
            minGoal: range.minGoal,
            maxGoal: range.maxGoal,
            step: range.step
        )
    }

    private static func prettyName(from raw: String) -> String {
        raw.split(separator: "_")
            .map { token in
                let word = String(token)
                if word.count <= 3 {
                    return word.uppercased()
                }
                return word.prefix(1).uppercased() + word.dropFirst()
            }
            .joined(separator: " ")
    }

    private static func prettyUnit(_ token: String) -> String {
        switch token {
        case "iu":
            return "IU"
        case "mcg":
            return "mcg"
        case "mg":
            return "mg"
        case "g":
            return "g"
        default:
            return token.uppercased()
        }
    }

    private static func rangeFor(unitToken: String) -> (defaultGoal: Int, minGoal: Int, maxGoal: Int, step: Int) {
        switch unitToken {
        case "mg":
            return (100, 0, 10000, 10)
        case "mcg":
            return (100, 0, 100000, 10)
        case "iu":
            return (1000, 0, 50000, 100)
        default:
            return (50, 0, 1000, 1)
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
    @AppStorage("proteinGoal") private var legacyStoredProteinGoal: Int = 150
    @AppStorage("mealEntriesData") private var storedEntriesData: String = ""
    @AppStorage("trackedNutrientsData") private var storedTrackedNutrientsData: String = ""
    @AppStorage("nutrientGoalsData") private var storedNutrientGoalsData: String = ""
    @AppStorage("lastCentralDayIdentifier") private var lastCentralDayIdentifier: String = ""
    @AppStorage("selectedAppIconChoice") private var selectedAppIconChoiceRaw: String = AppIconChoice.standard.rawValue
    @AppStorage("dailyEntryArchiveData") private var storedDailyEntryArchiveData: String = ""
    @AppStorage("dailyCalorieGoalArchiveData") private var storedDailyCalorieGoalArchiveData: String = ""
    @AppStorage("dailyBurnedCalorieArchiveData") private var storedDailyBurnedCalorieArchiveData: String = ""
    @AppStorage("quickAddFoodsData") private var storedQuickAddFoodsData: String = ""

    @State private var entries: [MealEntry] = []
    @State private var dailyEntryArchive: [String: [MealEntry]] = [:]
    @State private var dailyCalorieGoalArchive: [String: Int] = [:]
    @State private var dailyBurnedCalorieArchive: [String: Int] = [:]
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

    @State private var firebaseMenu: NutrisliceMenu = .empty
    @State private var selectedMenuItemQuantities: [String: Int] = [:]
    @State private var selectedMenuItemMultipliers: [String: Double] = [:]
    @State private var isMenuLoading = false
    @State private var menuLoadError: String?
    @State private var lastLoadedMenuSignature = ""
    @State private var isResetConfirmationPresented = false
    @State private var isKeyboardVisible = false
    @State private var keyboardHeight: CGFloat = 0
    @State private var collapsedMealGroups: Set<MealGroup> = []

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

    private enum ScrollTarget: String {
        case addManualEntryCard
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

    private var accent: Color {
        Color(red: 0.20, green: 0.50, blue: 0.98)
    }

    private var backgroundTop: Color {
        colorScheme == .dark ? Color(red: 0.07, green: 0.08, blue: 0.12) : Color(red: 0.95, green: 0.97, blue: 0.99)
    }

    private var backgroundBottom: Color {
        colorScheme == .dark ? Color(red: 0.10, green: 0.11, blue: 0.17) : Color(red: 0.91, green: 0.94, blue: 0.98)
    }

    private var centralCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago") ?? .current
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
    private var weekendDeficitCalories: Int { min(max(storedWeekendDeficitCalories, 0), 2500) }

    private func deficitForDay(_ identifier: String) -> Int {
        guard useWeekendDeficit else { return deficitCalories }
        guard let date = date(fromCentralDayIdentifier: identifier) else { return deficitCalories }
        let weekday = centralCalendar.component(.weekday, from: date)
        let isWeekend = (weekday == 1) || (weekday == 7)
        return isWeekend ? weekendDeficitCalories : deficitCalories
    }
    private var resolvedBMRProfile: BMRProfile? { healthKitService.profile?.bmrProfile }
    private var activityCaloriesToday: Int {
        stepActivityService.estimatedCaloriesToday(profile: resolvedBMRProfile)
    }
    private var currentDailyCalorieModel: DailyCalorieModel {
        let bmr = resolvedBMRProfile.flatMap(calculatedBMR(for:)) ?? ContentView.fallbackAverageBMR

        let burned = max(bmr + activityCaloriesToday, 1)
        let deficit = deficitForDay(todayDayIdentifier)
        let goal = max(burned - deficit, 1)
        return DailyCalorieModel(
            bmr: bmr,
            burned: burned,
            goal: goal,
            deficit: deficit,
            usesBMR: resolvedBMRProfile != nil
        )
    }
    private var burnedCaloriesToday: Int { currentDailyCalorieModel.burned }
    private var calorieGoal: Int { currentDailyCalorieModel.goal }
    private var selectedAppIconChoice: AppIconChoice {
        AppIconChoice(rawValue: selectedAppIconChoiceRaw) ?? .standard
    }

    private var excludedNutrientKeys: Set<String> {
        let threshold = 0.95
        let dynamic = Set<String>(firebaseMenu.nutrientNullRateByKey.compactMap { key, rate in
            let normalized = key.lowercased()
            guard normalized != "g_protein", rate >= threshold else { return nil }
            return normalized
        })
        return dynamic.union(NutrientCatalog.defaultExcludedBecauseConsistentlyNull)
    }

    private var availableNutrientKeys: [String] {
        var keys = Set<String>(NutrientCatalog.knownKeys)

        for line in firebaseMenu.lines {
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
        trackedNutrientKeys
            .map { $0.lowercased() }
            .filter { !NutrientCatalog.nonTrackableKeys.contains($0) }
            .filter { !excludedNutrientKeys.contains($0) }
            .map { NutrientCatalog.definition(for: $0) }
    }

    private var primaryNutrient: NutrientDefinition {
        activeNutrients.first ?? NutrientCatalog.definition(for: "g_protein")
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
        return (0..<dayCount).compactMap { offset in
            guard let date = centralCalendar.date(byAdding: .day, value: -((dayCount - 1) - offset), to: today) else {
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

    private var netCalorieSummary: (net: Int, consumed: Int, burned: Int) {
        let identifiers = dayIdentifiers(forLast: netHistoryRange.dayCount)
            .filter { dailyCalories(for: $0) > 0 }
        let consumed = identifiers.reduce(0) { $0 + dailyCalories(for: $1) }
        let burned = identifiers.reduce(0) { $0 + burnedCaloriesForDay($1) }
        return (net: consumed - burned, consumed: consumed, burned: burned)
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

    private var addTabKeyboardLift: CGFloat {
        guard selectedTab == .add, isKeyboardVisible else { return 0 }
        return min(250, max(0, keyboardHeight - 150))
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
            .confirmationDialog(
                "Reset today's log?",
                isPresented: $isResetConfirmationPresented,
                titleVisibility: .visible
            ) {
                Button("Reset Today", role: .destructive) {
                    resetTodayLog()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will remove all of today's logged foods and reset your totals to zero.")
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
            .onChange(of: firebaseMenu) { _, _ in
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
            .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    private var onboardingView: some View {
        OnboardingFlowView(
            currentPage: $onboardingPage,
            deficitCalories: $storedDeficitCalories,
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
            menu: firebaseMenu,
            venue: selectedMenuVenue,
            sourceTitle: selectedMenuVenue.title,
            mealTitle: menuService.currentMenuType().title,
            selectedItemQuantities: $selectedMenuItemQuantities,
            selectedItemMultipliers: $selectedMenuItemMultipliers,
            isLoading: isMenuLoading,
            errorMessage: menuLoadError,
            onRetry: {
                await loadMenuFromFirebase()
            },
            onAddSelected: {
                addSelectedMenuItems()
            }
        )
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
        let screenHeight = UIScreen.main.bounds.height
        let endFrame = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect) ?? .zero
        let duration = (notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.25
        let visibleHeight = max(0, screenHeight - endFrame.minY)

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
            selectedTab = tab
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
                                .shadow(color: accent.opacity(0.38), radius: 18, x: 0, y: 10)
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
    }

    private var todayTabView: some View {
        List {
            pageHeader(title: "Today", subtitle: "Calories, nutrients, and today's log")
            calorieHeroSection
            progressSection
            foodLogSections
            mealDistributionSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 110)
        }
    }

    private var historyTabView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                tabHeader(title: "History", subtitle: "Calendar, calorie trends, and stats")
                historyGraphCard
                historyCalendarCard
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
                    HStack(alignment: .top, spacing: 16) {
                        tabHeader(title: "Add Food", subtitle: "Search, scan, or add manually")

                        Spacer()

                        Button {
                            isQuickAddPickerPresented = true
                            Haptics.impact(.light)
                        } label: {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .background(
                                    Circle()
                                        .fill(accent)
                                )
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 2)
                    }

                    HStack(spacing: 10) {
                        Button {
                            barcodeLookupError = nil
                            hasScannedBarcodeInCurrentSheet = false
                            isBarcodeScannerPresented = true
                            Haptics.impact(.light)
                        } label: {
                            Label(isBarcodeLookupInFlight ? "Looking Up..." : "Scan Barcode", systemImage: "barcode.viewfinder")
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
                                presentMenu(for: venue)
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
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Food name")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(textPrimary)

                            TextField("Food name", text: $entryNameText)
                                .focused($focusedField, equals: .name)
                                .submitLabel(.next)
                                .onSubmit { focusedField = .calories }
                                .inputStyle(surface: surfaceSecondary, text: textPrimary, secondary: textSecondary)
                        }

                        if shouldExpandCaloriesField {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Calories")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(textPrimary)

                                TextField("Calories", text: $entryCaloriesText)
                                    .keyboardType(.numberPad)
                                    .focused($focusedField, equals: .calories)
                                    .inputStyle(surface: surfaceSecondary, text: textPrimary, secondary: textSecondary)
                            }

                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                                ForEach(activeNutrients) { nutrient in
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("\(nutrient.name) (\(nutrient.unit))")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(textPrimary)

                                        TextField("\(nutrient.name) (\(nutrient.unit))", text: nutrientFieldBinding(for: nutrient.key))
                                            .keyboardType(.numberPad)
                                            .focused($focusedField, equals: .nutrient(nutrient.key))
                                            .inputStyle(surface: surfaceSecondary, text: textPrimary, secondary: textSecondary)
                                    }
                                }
                            }
                        } else {
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Calories")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(textPrimary)

                                    TextField("Calories", text: $entryCaloriesText)
                                        .keyboardType(.numberPad)
                                        .focused($focusedField, equals: .calories)
                                        .inputStyle(surface: surfaceSecondary, text: textPrimary, secondary: textSecondary)
                                }

                                ForEach(Array(activeNutrients.enumerated()), id: \.element.id) { index, nutrient in
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("\(nutrient.name) (\(nutrient.unit))")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(textPrimary)

                                        TextField("\(nutrient.name) (\(nutrient.unit))", text: nutrientFieldBinding(for: nutrient.key))
                                            .keyboardType(.numberPad)
                                            .focused($focusedField, equals: .nutrient(nutrient.key))
                                            .inputStyle(surface: surfaceSecondary, text: textPrimary, secondary: textSecondary)
                                    }
                                    .gridCellColumns(shouldExpandLastNutrientField(at: index) ? 2 : 1)
                                }
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
                    .padding(18)
                    .cardStyle(surface: surfacePrimary, stroke: textSecondary.opacity(0.15))
                    .id(ScrollTarget.addManualEntryCard.rawValue)
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, isKeyboardVisible ? max(96, keyboardHeight - 140) : 140)
                .offset(y: -addTabKeyboardLift)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: isKeyboardVisible) { _, visible in
                guard visible, selectedTab == .add else { return }
                withAnimation(.easeInOut(duration: 0.22)) {
                    proxy.scrollTo(ScrollTarget.addManualEntryCard.rawValue, anchor: .bottom)
                }
            }
            .onChange(of: focusedField) { _, newField in
                guard newField != nil, selectedTab == .add else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        proxy.scrollTo(ScrollTarget.addManualEntryCard.rawValue, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var profileTabView: some View {
        List {
            pageHeader(title: "Profile", subtitle: "Health-based BMR, calorie goal, and nutrient targets")

            Section {
                ProfileGoalsView(
                    deficitCalories: $storedDeficitCalories,
                    useWeekendDeficit: $useWeekendDeficit,
                    weekendDeficitCalories: $storedWeekendDeficitCalories,
                    trackedNutrientKeys: trackedNutrientKeys,
                    nutrientGoals: $nutrientGoals,
                    healthAuthorizationState: healthKitService.authorizationState,
                    healthProfile: healthKitService.profile,
                    bmrCalories: currentDailyCalorieModel.bmr,
                    burnedCaloriesToday: burnedCaloriesToday,
                    activeBurnedCaloriesToday: activityCaloriesToday,
                    isUsingAutomatedCalories: currentDailyCalorieModel.usesBMR,
                    onRequestHealthAccess: {
                        Task {
                            await healthKitService.requestAccessAndRefresh()
                        }
                    }
                )
            }
            .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 4, trailing: 0))
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
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 110)
        }
    }

    private var settingsTabView: some View {
        List {
            pageHeader(title: "Settings", subtitle: "Tracked nutrients and app appearance")

            Section {
                AppSettingsTabView(
                    trackedNutrientKeys: $trackedNutrientKeys,
                    availableNutrients: availableNutrients,
                    selectedAppIconChoiceRaw: $selectedAppIconChoiceRaw
                )
            }
            .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 4, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            Section {
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

    private func tabHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(textPrimary)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(textSecondary)
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

    private var summarySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 14) {
                Text("DAILY SUMMARY")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(textSecondary)

                HStack(spacing: 16) {
                    summaryMetric(title: "Calories", value: "\(totalCalories)")
                    summaryMetric(title: primaryNutrient.name, value: "\(totalNutrient(for: primaryNutrient.key))\(primaryNutrient.unit)")
                    summaryMetric(title: "Items", value: "\(entries.count)")
                }
            }
            .padding(16)
            .cardStyle(surface: surfacePrimary, stroke: textSecondary.opacity(0.15))
            .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 4, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
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
        let nutrientTotals = nutrientTotals(for: summary.dayIdentifier)
        let dayMealDistribution = mealDistributionData(for: summary.dayIdentifier)
        let calorieColor = historyBarColor(calories: summary.totalCalories, goal: dayGoal, burned: dayBurned)
        let rawProgress = Double(summary.totalCalories) / Double(max(dayBurned, 1))
        let barProgress = min(max(rawProgress, 0), 1)
        let statusText: String
        let statusColor: Color
        if summary.totalCalories == 0 {
            statusText = "No Intake"
            statusColor = textSecondary
        } else if summary.totalCalories <= dayGoal {
            statusText = "On Target"
            statusColor = Color.green
        } else if summary.totalCalories <= dayBurned {
            statusText = "Above Goal"
            statusColor = Color.yellow
        } else {
            statusText = "Over Burned"
            statusColor = Color.red
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
                    Text("Net Calorie Intake")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(textPrimary)
                    Text("Consumed minus estimated calories burned.")
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

            Text(signedCalorieString(summary.net))
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(netColor)

            HStack(spacing: 12) {
                statTile(title: "Consumed", value: summary.consumed.formatted(), detail: "calories")
                statTile(title: "Burned", value: summary.burned.formatted(), detail: "bmr + steps")
                statTile(title: "Status", value: netCalorieStatus(summary.net), detail: netHistoryRange.title.lowercased())
            }

            if summary.consumed == 0 {
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
        let safeBurned = max(max(burned, safeGoal), 1)
        if calories > safeBurned {
            return Color.red
        }
        if calories >= safeGoal {
            return Color.yellow
        }
        return Color.green
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

    private func calorieBarPalette(consumed: Int, goal: Int, burned: Int) -> (start: Color, end: Color) {
        let safeGoal = max(goal, 1)
        let safeBurned = max(burned, safeGoal)
        let consumedValue = max(consumed, 0)

        if safeBurned == safeGoal {
            let progress = min(Double(consumedValue) / Double(safeGoal), 1.0)
            return (
                interpolateColor(from: UIColor.systemGreen, to: UIColor.systemRed, progress: progress),
                interpolateColor(from: UIColor.systemMint, to: UIColor.systemOrange, progress: progress)
            )
        }

        if consumedValue <= safeGoal {
            let progress = min(Double(consumedValue) / Double(safeGoal), 1.0)
            return (
                interpolateColor(from: UIColor.systemGreen, to: UIColor.systemYellow, progress: progress),
                interpolateColor(from: UIColor.systemMint, to: UIColor.systemOrange, progress: progress)
            )
        }

        if consumedValue <= safeBurned {
            let progress = min(Double(consumedValue - safeGoal) / Double(max(safeBurned - safeGoal, 1)), 1.0)
            return (
                interpolateColor(from: UIColor.systemYellow, to: UIColor.systemOrange, progress: progress),
                interpolateColor(from: UIColor.systemOrange, to: UIColor.systemRed.withAlphaComponent(0.82), progress: progress)
            )
        }

        let overflow = min(Double(consumedValue - safeBurned) / Double(max(safeBurned, 1)), 1.0)
        return (
            interpolateColor(from: UIColor.systemRed, to: UIColor(red: 0.70, green: 0.12, blue: 0.18, alpha: 1.0), progress: overflow),
            interpolateColor(from: UIColor.systemOrange, to: UIColor.systemRed, progress: overflow)
        )
    }

    @ViewBuilder
    private var foodLogSections: some View {
        if groupedTodayEntries.isEmpty {
            Section {
                Text("No entries yet.")
                    .foregroundStyle(textSecondary)
                    .listRowBackground(surfacePrimary)
            } header: {
                HStack {
                    Text("Today's Food Log")
                    Spacer()
                    Button("Reset", role: .destructive) {
                        isResetConfirmationPresented = true
                        Haptics.impact(.light)
                    }
                    .font(.caption.weight(.semibold))
                }
                .foregroundStyle(textSecondary)
            }
        } else {
            ForEach(Array(groupedTodayEntries.enumerated()), id: \.element.group.id) { index, groupData in
                Section {
                    if !collapsedMealGroups.contains(groupData.group) {
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
                    }
                } header: {
                    VStack(alignment: .leading, spacing: index == 0 ? 18 : 12) {
                        if index == 0 {
                            HStack {
                                Text("Today's Food Log")
                                Spacer()
                                Button("Reset", role: .destructive) {
                                    isResetConfirmationPresented = true
                                    Haptics.impact(.light)
                                }
                                .font(.caption.weight(.semibold))
                            }
                            .padding(.bottom, 2)
                        }
                        HStack(spacing: 8) {
                            Button {
                                toggleMealGroup(groupData.group)
                            } label: {
                                HStack(spacing: 6) {
                                    Text(groupData.group.title)
                                        .font(.caption.weight(.bold))
                                    Text("\(groupData.entries.reduce(0) { $0 + $1.calories }) cal")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(textSecondary.opacity(0.82))
                                    Image(systemName: collapsedMealGroups.contains(groupData.group) ? "chevron.down" : "chevron.up")
                                        .font(.caption2.weight(.bold))
                                }
                                .foregroundStyle(textSecondary.opacity(0.92))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(surfacePrimary.opacity(0.82))
                                )
                                .overlay(
                                    Capsule(style: .continuous)
                                        .stroke(textSecondary.opacity(0.12), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)

                            Spacer()
                        }
                    }
                    .padding(.top, index == 0 ? 8 : 0)
                    .foregroundStyle(textSecondary)
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

    private func toggleMealGroup(_ group: MealGroup) {
        if collapsedMealGroups.contains(group) {
            collapsedMealGroups.remove(group)
        } else {
            collapsedMealGroups.insert(group)
        }
        Haptics.selection()
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

    private var shouldExpandCaloriesField: Bool {
        !activeNutrients.isEmpty && activeNutrients.count.isMultiple(of: 2)
    }

    private func shouldExpandLastNutrientField(at index: Int) -> Bool {
        let isLastNutrient = index == activeNutrients.count - 1
        let totalNumericFields = activeNutrients.count + 1
        return isLastNutrient && totalNumericFields % 2 != 0
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
        if lastLoadedMenuSignature != signature {
            firebaseMenu = .empty
            menuLoadError = nil
        }
        isMenuSheetPresented = true
        if firebaseMenu.lines.isEmpty || lastLoadedMenuSignature != signature || menuLoadError != nil {
            Task {
                await loadMenuFromFirebase(for: venue)
            }
        }
    }

    @MainActor
    private func loadMenuFromFirebase(for venue: DiningVenue? = nil) async {
        let venue = venue ?? selectedMenuVenue
        isMenuLoading = true
        menuLoadError = nil
        do {
            firebaseMenu = try await menuService.fetchTodayMenu(for: venue)
            lastLoadedMenuSignature = menuService.currentMenuSignature(for: venue)
            selectedMenuItemQuantities.removeAll()
            selectedMenuItemMultipliers.removeAll()
        } catch {
            menuLoadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            firebaseMenu = .empty
            selectedMenuItemQuantities.removeAll()
            selectedMenuItemMultipliers.removeAll()
        }
        isMenuLoading = false
    }

    @MainActor
    private func preloadMenuForNutrientDiscovery() async {
        let currentSignature = menuService.currentMenuSignature(for: selectedMenuVenue)
        guard firebaseMenu.lines.isEmpty || lastLoadedMenuSignature != currentSignature else {
            return
        }
        do {
            firebaseMenu = try await menuService.fetchTodayMenu(for: selectedMenuVenue)
            lastLoadedMenuSignature = currentSignature
        } catch {
            // Keep this silent so startup does not show menu errors.
        }
    }

    private func applyCentralTimeTransitions(forceMenuReload: Bool) {
        let currentCentralDay = menuService.currentCentralDayIdentifier()
        let currentMenuSignature = menuService.currentMenuSignature(for: selectedMenuVenue)

        if lastCentralDayIdentifier.isEmpty {
            lastCentralDayIdentifier = currentCentralDay
            if dailyEntryArchive[currentCentralDay] == nil {
                dailyEntryArchive[currentCentralDay] = normalizedEntries(entries)
            }
            dailyCalorieGoalArchive[currentCentralDay] = calorieGoal
            dailyBurnedCalorieArchive[currentCentralDay] = burnedCaloriesToday
            saveDailyEntryArchive()
            saveDailyCalorieGoalArchive()
            saveDailyBurnedCalorieArchive()
        }

        if lastCentralDayIdentifier != currentCentralDay {
            dailyEntryArchive[lastCentralDayIdentifier] = normalizedEntries(entries)
            dailyCalorieGoalArchive[lastCentralDayIdentifier] = calorieGoalForDay(lastCentralDayIdentifier)
            dailyBurnedCalorieArchive[lastCentralDayIdentifier] = burnedCaloriesForDay(lastCentralDayIdentifier)
            lastCentralDayIdentifier = currentCentralDay
            entries = entries(forDayIdentifier: currentCentralDay)
            if dailyEntryArchive[currentCentralDay] == nil {
                dailyEntryArchive[currentCentralDay] = []
            }
            dailyCalorieGoalArchive[currentCentralDay] = calorieGoal
            dailyBurnedCalorieArchive[currentCentralDay] = burnedCaloriesToday
            saveEntries()
            saveDailyEntryArchive()
            saveDailyCalorieGoalArchive()
            saveDailyBurnedCalorieArchive()
            selectedMenuItemQuantities.removeAll()
            selectedMenuItemMultipliers.removeAll()
            firebaseMenu = .empty
            lastLoadedMenuSignature = ""
            menuLoadError = nil
            syncHistorySelection(preferToday: true)
        }

        if forceMenuReload || (!firebaseMenu.lines.isEmpty && lastLoadedMenuSignature != currentMenuSignature) {
            firebaseMenu = .empty
            lastLoadedMenuSignature = ""
            Task {
                await preloadMenuForNutrientDiscovery()
            }
        }
    }

    private func addSelectedMenuItems() {
        var itemByID: [String: MenuItem] = [:]
        for item in firebaseMenu.lines.flatMap(\.items) {
            if itemByID[item.id] == nil {
                itemByID[item.id] = item
            }
        }

        var expandedSelections: [MealEntry] = []
        let now = Date()

        for (id, quantity) in selectedMenuItemQuantities {
            guard let item = itemByID[id], quantity > 0 else { continue }
            let multiplier = selectedMenuItemMultipliers[id] ?? 1.0
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

        selectedMenuItemQuantities.removeAll()
        selectedMenuItemMultipliers.removeAll()
        isMenuSheetPresented = false
        selectedTab = .today
    }

    private func clearMenuSelection() {
        selectedMenuItemQuantities.removeAll()
        selectedMenuItemMultipliers.removeAll()
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
        var valid = trackedNutrientKeys
            .map { $0.lowercased() }
            .filter { !$0.isEmpty && !NutrientCatalog.nonTrackableKeys.contains($0) }
            .filter { !excludedNutrientKeys.contains($0) }
        if valid.isEmpty {
            valid = ["g_protein"]
        }
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
        entries = entries(forDayIdentifier: todayDayIdentifier)
        loadDailyCalorieGoalArchive()
        loadDailyBurnedCalorieArchive()
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

    private func syncCurrentEntriesToArchive() {
        dailyEntryArchive[todayDayIdentifier] = normalizedEntries(entries)
        saveEntries()
        saveDailyEntryArchive()
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
        if let archived = dailyCalorieGoalArchive[identifier] {
            return max(archived, 1)
        }
        if identifier == todayDayIdentifier {
            return max(calorieGoal, 1)
        }

        let fallbackBurned = max(ContentView.fallbackAverageBMR, 1)
        return max(fallbackBurned - deficitForDay(identifier), 1)
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
        dailyCalorieGoalArchive[todayDayIdentifier] = calorieGoal
        dailyBurnedCalorieArchive[todayDayIdentifier] = burnedCaloriesToday
        saveDailyCalorieGoalArchive()
        saveDailyBurnedCalorieArchive()
    }

    private func historySummary(for identifier: String) -> HistoryDaySummary {
        let dayEntries = entries(forDayIdentifier: identifier)
        let total = dayEntries.reduce(0) { $0 + $1.calories }
        let date = date(fromCentralDayIdentifier: identifier) ?? currentCentralDate()
        let goal = calorieGoalForDay(identifier)

        return HistoryDaySummary(
            dayIdentifier: identifier,
            date: date,
            totalCalories: total,
            entryCount: dayEntries.count,
            goalMet: total > 0 && total <= goal
        )
    }

    private func dayIdentifiers(forLast dayCount: Int) -> [String] {
        let today = centralCalendar.startOfDay(for: Date())
        return (0..<dayCount).compactMap { offset in
            centralCalendar.date(byAdding: .day, value: -((dayCount - 1) - offset), to: today)
                .map { centralDayIdentifier(for: $0) }
        }
    }

    private func netCalorieColor(_ net: Int) -> Color {
        if net > 500 {
            return .red
        }
        if net < -500 {
            return .green
        }
        return .yellow
    }

    private func netCalorieStatus(_ net: Int) -> String {
        if net > 500 {
            return "Over"
        }
        if net < -500 {
            return "Under"
        }
        return "Near Even"
    }

    private func signedCalorieString(_ value: Int) -> String {
        let prefix = value > 0 ? "+" : ""
        return "\(prefix)\(value.formatted()) cal"
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

private struct DeficitGoalEditor: View {
    @Binding var deficitCalories: Int
    let title: String
    let subtitle: String
    let helperText: String?
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Text("\(deficitCalories) cal")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }

            HStack(spacing: 10) {
                Button(action: { adjust(by: -50) }) {
                    Image(systemName: "minus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white.opacity(0.92))
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.white.opacity(0.10)))
                }
                .buttonStyle(.plain)

                TextField("", value: deficitBinding, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.96))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                    )

                Button(action: { adjust(by: 50) }) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white.opacity(0.92))
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(accent))
                }
                .buttonStyle(.plain)
            }

            if let helperText {
                Text(helperText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }

    private var deficitBinding: Binding<Int> {
        Binding(
            get: { deficitCalories },
            set: { deficitCalories = min(max($0, 0), 2500) }
        )
    }

    private func adjust(by delta: Int) {
        deficitCalories = min(max(deficitCalories + delta, 0), 2500)
        Haptics.selection()
    }
}

private struct ProfileGoalsView: View {
    @Binding var deficitCalories: Int
    @Binding var useWeekendDeficit: Bool
    @Binding var weekendDeficitCalories: Int
    let trackedNutrientKeys: [String]
    @Binding var nutrientGoals: [String: Int]
    let healthAuthorizationState: HealthKitService.AuthorizationState
    let healthProfile: HealthKitService.SyncedProfile?
    let bmrCalories: Int?
    let burnedCaloriesToday: Int
    let activeBurnedCaloriesToday: Int
    let isUsingAutomatedCalories: Bool
    let onRequestHealthAccess: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            profileSummaryCard

            Divider()
                .overlay(Color.white.opacity(0.08))

            VStack(alignment: .leading, spacing: 16) {
                Text("Nutrient Goals")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                ForEach(trackedNutrientKeys, id: \.self) { key in
                    let nutrient = NutrientCatalog.definition(for: key)
                    goalField(
                        title: "\(nutrient.name) (\(nutrient.unit))",
                        subtitle: nil,
                        value: nutrientGoalBinding(for: key),
                        onDecrement: { adjustNutrientGoal(for: key, delta: -nutrient.step) },
                        onIncrement: { adjustNutrientGoal(for: key, delta: nutrient.step) }
                    )
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground).opacity(0.55))
        )
    }

    private var profileSummaryCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Body Profile")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text("BMR is calculated from Health data.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                if healthAuthorizationState == .connected {
                    healthStatusBadge
                }
            }

            if let healthProfile {
                HStack(spacing: 8) {
                    healthValueChip(title: "Sex", value: healthProfile.bmrProfile.sex.title)
                    healthValueChip(title: "Height", value: healthProfile.heightDisplay)
                    healthValueChip(title: "Weight", value: healthProfile.weightDisplay)
                }
            } else {
                Text(healthAuthorizationState.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                statPill(title: "BMR", value: bmrCalories.map { "\($0) cal" } ?? "--")
                statPill(title: "Burned", value: "\(burnedCaloriesToday) cal")
                statPill(title: "Step Burn", value: "\(activeBurnedCaloriesToday) cal")
            }

            DeficitGoalEditor(
                deficitCalories: $deficitCalories,
                title: "Deficit Goal",
                subtitle: "Subtracted from burned calories",
                helperText: nil,
                accent: Color(red: 0.19, green: 0.52, blue: 1.0)
            )

            Toggle(isOn: $useWeekendDeficit) {
                Text("Different goal on weekend")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .tint(Color(red: 0.19, green: 0.52, blue: 1.0))

            if useWeekendDeficit {
                DeficitGoalEditor(
                    deficitCalories: $weekendDeficitCalories,
                    title: "Weekend Deficit",
                    subtitle: "Used on Saturday & Sunday",
                    helperText: nil,
                    accent: Color(red: 0.19, green: 0.52, blue: 1.0)
                )
            }

                if healthAuthorizationState != .connected {
                    Button(action: onRequestHealthAccess) {
                        Text("Connect Health Data")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.19, green: 0.52, blue: 1.0))

                    Text("Using a fallback average BMR until Health data is connected.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if !isUsingAutomatedCalories {
                    Text("Health is connected, but some body data is still missing. Using a fallback average BMR until Health provides height, weight, sex, and age.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Burned today includes BMR plus estimated step activity calories personalized with your available profile data.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
        }
    }

    private func goalField(title: String, subtitle: String?, value: Binding<Int>, onDecrement: @escaping () -> Void, onIncrement: @escaping () -> Void) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary.opacity(0.8))
                }
            }

            Spacer(minLength: 0)

            goalControl(value: value, onDecrement: onDecrement, onIncrement: onIncrement)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }

    private var healthStatusBadge: some View {
        Text(healthAuthorizationState.title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(healthAuthorizationState == .connected ? Color(red: 0.46, green: 0.90, blue: 0.60) : .white)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(healthAuthorizationState == .connected ? Color(red: 0.13, green: 0.28, blue: 0.18) : Color.white.opacity(0.08))
            )
    }

    private func healthValueChip(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }

    private func goalControl(value: Binding<Int>, onDecrement: @escaping () -> Void, onIncrement: @escaping () -> Void) -> some View {
        HStack(spacing: 0) {
            Button(action: onDecrement) {
                Image(systemName: "minus")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white.opacity(0.92))
                    .frame(width: 34, height: 30)
                    .background(Circle().fill(Color.white.opacity(0.10)))
            }
            .buttonStyle(.plain)

            Rectangle()
                .fill(Color.white.opacity(0.10))
                .frame(width: 1, height: 18)
                .padding(.horizontal, 4)

            TextField("", value: value, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.body.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.96))
                .frame(minWidth: 64, idealWidth: 74, maxWidth: 86)

            Rectangle()
                .fill(Color.white.opacity(0.10))
                .frame(width: 1, height: 18)
                .padding(.horizontal, 4)

            Button(action: onIncrement) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white.opacity(0.92))
                    .frame(width: 34, height: 30)
                    .background(Circle().fill(Color(red: 0.19, green: 0.52, blue: 1.0)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.07))
        )
    }

    private func adjustNutrientGoal(for key: String, delta: Int) {
        let definition = NutrientCatalog.definition(for: key)
        let current = nutrientGoals[key] ?? definition.defaultGoal
        nutrientGoals[key] = min(max(current + delta, definition.minGoal), definition.maxGoal)
        Haptics.selection()
    }

    private func nutrientGoalBinding(for key: String) -> Binding<Int> {
        let definition = NutrientCatalog.definition(for: key)
        return Binding(
            get: { nutrientGoals[key] ?? definition.defaultGoal },
            set: { nutrientGoals[key] = min(max($0, definition.minGoal), definition.maxGoal) }
        )
    }

    private func statPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(value)
                .font(.title3.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }
}

private struct QuickAddManagerView: View {
    private struct EditorContext: Identifiable {
        let id = UUID()
        let item: QuickAddFood?
    }

    @Binding var quickAddFoods: [QuickAddFood]
    let trackedNutrientKeys: [String]
    let surfacePrimary: Color
    let surfaceSecondary: Color
    let textPrimary: Color
    let textSecondary: Color
    let accent: Color

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var editorContext: EditorContext?

    private var filteredFoods: [QuickAddFood] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return quickAddFoods }
        return quickAddFoods.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.04, green: 0.06, blue: 0.15),
                        Color(red: 0.07, green: 0.09, blue: 0.19),
                        Color(red: 0.04, green: 0.05, blue: 0.12)
                    ],
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
                            Text("Quick Add Foods")
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .foregroundStyle(textPrimary)
                            Text("Create and edit reusable foods.")
                                .font(.subheadline)
                                .foregroundStyle(textSecondary)
                        }

                        HStack(spacing: 10) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(textSecondary)

                            TextField("Search quick add foods", text: $searchText)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .foregroundStyle(textPrimary)

                            if !searchText.isEmpty {
                                Button {
                                    searchText = ""
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

                        if filteredFoods.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(quickAddFoods.isEmpty ? "No quick add foods yet." : "No quick add foods match your search.")
                                    .font(.headline.weight(.semibold))
                                    .foregroundStyle(textPrimary)
                                Text(quickAddFoods.isEmpty ? "Create foods you use often and add them in one tap." : "Try a broader search term.")
                                    .font(.subheadline)
                                    .foregroundStyle(textSecondary)
                            }
                            .padding(18)
                            .cardStyle(surface: surfacePrimary.opacity(0.95), stroke: textSecondary.opacity(0.15))
                        } else {
                            LazyVStack(spacing: 12) {
                                ForEach(filteredFoods) { item in
                                    Button {
                                        editorContext = EditorContext(item: item)
                                        Haptics.selection()
                                    } label: {
                                        HStack(alignment: .top, spacing: 12) {
                                            VStack(alignment: .leading, spacing: 6) {
                                                Text(item.name)
                                                    .font(.headline.weight(.semibold))
                                                    .foregroundStyle(textPrimary)
                                                Text("\(item.calories) cal" + quickAddSummary(for: item))
                                                    .font(.caption)
                                                    .foregroundStyle(textSecondary)
                                                    .lineLimit(2)
                                            }
                                            Spacer()
                                            Image(systemName: "chevron.right")
                                                .font(.caption.weight(.bold))
                                                .foregroundStyle(textSecondary)
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
                                    .contextMenu {
                                        Button {
                                            editorContext = EditorContext(item: item)
                                        } label: {
                                            Label("Edit", systemImage: "pencil")
                                        }
                                        Button(role: .destructive) {
                                            quickAddFoods.removeAll { $0.id == item.id }
                                            Haptics.selection()
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                    .padding(.bottom, 120)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    editorContext = EditorContext(item: nil)
                    Haptics.impact(.light)
                } label: {
                    Text("New Quick Add Food")
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
            .sheet(item: $editorContext) { context in
                QuickAddEditorView(
                    item: context.item,
                    trackedNutrientKeys: trackedNutrientKeys,
                    surfacePrimary: surfacePrimary,
                    surfaceSecondary: surfaceSecondary,
                    textPrimary: textPrimary,
                    textSecondary: textSecondary,
                    accent: accent
                ) { savedItem in
                    if let index = quickAddFoods.firstIndex(where: { $0.id == savedItem.id }) {
                        quickAddFoods[index] = savedItem
                    } else {
                        quickAddFoods.insert(savedItem, at: 0)
                    }
                    quickAddFoods.sort { $0.createdAt > $1.createdAt }
                }
            }
        }
    }

    private func quickAddSummary(for item: QuickAddFood) -> String {
        let summary = item.nutrientValues
            .filter { $0.value > 0 }
            .sorted { lhs, rhs in
                let lhsRank = NutrientCatalog.preferredOrder.firstIndex(of: lhs.key) ?? Int.max
                let rhsRank = NutrientCatalog.preferredOrder.firstIndex(of: rhs.key) ?? Int.max
                return lhsRank < rhsRank
            }
            .prefix(2)
            .map { nutrient in
                let definition = NutrientCatalog.definition(for: nutrient.key)
                return "\(nutrient.value)\(definition.unit) \(definition.name)"
            }
            .joined(separator: " • ")

        return summary.isEmpty ? "" : " • \(summary)"
    }
}

private struct QuickAddPickerView: View {
    let quickAddFoods: [QuickAddFood]
    let surfacePrimary: Color
    let surfaceSecondary: Color
    let textPrimary: Color
    let textSecondary: Color
    let accent: Color
    let onSelect: (QuickAddFood) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filteredFoods: [QuickAddFood] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return quickAddFoods }
        return quickAddFoods.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.04, green: 0.06, blue: 0.15),
                        Color(red: 0.07, green: 0.09, blue: 0.19),
                        Color(red: 0.04, green: 0.05, blue: 0.12)
                    ],
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
                            Text("Quick Add")
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .foregroundStyle(textPrimary)
                            Text("Pick a saved food to add instantly.")
                                .font(.subheadline)
                                .foregroundStyle(textSecondary)
                        }

                        HStack(spacing: 10) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(textSecondary)
                            TextField("Search quick add foods", text: $searchText)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .foregroundStyle(textPrimary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .cardStyle(surface: surfacePrimary.opacity(0.95), stroke: textSecondary.opacity(0.15))

                        if filteredFoods.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(quickAddFoods.isEmpty ? "No quick add foods yet." : "No quick add foods match your search.")
                                    .font(.headline.weight(.semibold))
                                    .foregroundStyle(textPrimary)
                                Text(quickAddFoods.isEmpty ? "Create them from Profile." : "Try a broader search term.")
                                    .font(.subheadline)
                                    .foregroundStyle(textSecondary)
                            }
                            .padding(18)
                            .cardStyle(surface: surfacePrimary.opacity(0.95), stroke: textSecondary.opacity(0.15))
                        } else {
                            LazyVStack(spacing: 12) {
                                ForEach(filteredFoods) { item in
                                    Button {
                                        onSelect(item)
                                    } label: {
                                        HStack(alignment: .top, spacing: 12) {
                                            VStack(alignment: .leading, spacing: 6) {
                                                Text(item.name)
                                                    .font(.headline.weight(.semibold))
                                                    .foregroundStyle(textPrimary)
                                                Text("\(item.calories) cal")
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
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                    .padding(.bottom, 32)
                }
            }
        }
    }
}

private struct QuickAddEditorView: View {
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
                    colors: [
                        Color(red: 0.04, green: 0.06, blue: 0.15),
                        Color(red: 0.07, green: 0.09, blue: 0.19),
                        Color(red: 0.04, green: 0.05, blue: 0.12)
                    ],
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

                            labeledField("Calories") {
                                TextField("Calories", text: $caloriesText)
                                    .keyboardType(.numberPad)
                                    .inputStyle(surface: surfaceSecondary, text: textPrimary, secondary: textSecondary)
                            }

                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                                ForEach(Array(editableNutrients.enumerated()), id: \.element.id) { index, nutrient in
                                    labeledField("\(nutrient.name) (\(nutrient.unit))", spacing: 8) {
                                        TextField("\(nutrient.name) (\(nutrient.unit))", text: nutrientBinding(for: nutrient.key))
                                            .keyboardType(.numberPad)
                                            .inputStyle(surface: surfaceSecondary, text: textPrimary, secondary: textSecondary)
                                    }
                                    .gridCellColumns(editableNutrients.count.isMultiple(of: 2) == false && index == editableNutrients.count - 1 ? 2 : 1)
                                }
                            }

                            if let errorText = validationError {
                                Text(errorText)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }

                            if let barcodeLookupError {
                                Text(barcodeLookupError)
                                    .font(.caption)
                                    .foregroundStyle(.orange)
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
                    menu: importedMenu,
                    sourceTitle: selectedMenuVenue.title,
                    mealTitle: menuService.currentMenuType().title,
                    isLoading: isMenuLoading,
                    errorMessage: menuLoadError,
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

        do {
            importedMenu = try await menuService.fetchTodayMenu(for: venue)
        } catch {
            importedMenu = .empty
            menuLoadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
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

    private static func editableNutrientDefinitions(for item: QuickAddFood?, trackedNutrientKeys: [String]) -> [NutrientDefinition] {
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
                    colors: [
                        Color(red: 0.04, green: 0.06, blue: 0.15),
                        Color(red: 0.07, green: 0.09, blue: 0.19),
                        Color(red: 0.04, green: 0.05, blue: 0.12)
                    ],
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

    private var quickAddUSDASearchSheet: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.04, green: 0.06, blue: 0.15),
                        Color(red: 0.07, green: 0.09, blue: 0.19),
                        Color(red: 0.04, green: 0.05, blue: 0.12)
                    ],
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
    }
}

private struct EditMealEntrySheet: View {
    let entry: MealEntry
    let editableNutrients: [NutrientDefinition]
    let initialMealGroup: MealGroup
    let surfacePrimary: Color
    let surfaceSecondary: Color
    let textPrimary: Color
    let textSecondary: Color
    let accent: Color
    let onSave: (MealEntry) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var nameText: String
    @State private var caloriesText: String
    @State private var nutrientTexts: [String: String]
    @State private var preservedHiddenNutrients: [String: Int]
    @State private var mealGroup: MealGroup
    @FocusState private var focusedField: EditField?

    private enum EditField: Hashable {
        case name
        case calories
    }

    init(
        entry: MealEntry,
        editableNutrients: [NutrientDefinition],
        initialMealGroup: MealGroup,
        surfacePrimary: Color,
        surfaceSecondary: Color,
        textPrimary: Color,
        textSecondary: Color,
        accent: Color,
        onSave: @escaping (MealEntry) -> Void
    ) {
        self.entry = entry
        self.editableNutrients = editableNutrients
        self.initialMealGroup = initialMealGroup
        self.surfacePrimary = surfacePrimary
        self.surfaceSecondary = surfaceSecondary
        self.textPrimary = textPrimary
        self.textSecondary = textSecondary
        self.accent = accent
        self.onSave = onSave
        _nameText = State(initialValue: entry.name)
        _caloriesText = State(initialValue: entry.calories == 0 ? "" : "\(entry.calories)")
        _mealGroup = State(initialValue: initialMealGroup)
        _nutrientTexts = State(initialValue: editableNutrients.reduce(into: [:]) { partialResult, nutrient in
            let value = entry.nutrientValues[nutrient.key] ?? 0
            partialResult[nutrient.key] = value == 0 ? "" : "\(value)"
        })
        let editableKeys = Set(editableNutrients.map(\.key))
        _preservedHiddenNutrients = State(initialValue: entry.nutrientValues.filter { !editableKeys.contains($0.key) })
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.06, blue: 0.15),
                    Color(red: 0.07, green: 0.09, blue: 0.19),
                    Color(red: 0.04, green: 0.05, blue: 0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Color.black.opacity(0.001)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    dismissKeyboard()
                }

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
                        Text("Edit Entry")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(textPrimary)
                        Text("Adjust food name, calories, and nutrients.")
                            .font(.subheadline)
                            .foregroundStyle(textSecondary)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        labeledField("Food name") {
                            TextField("Food name", text: $nameText)
                                .focused($focusedField, equals: .name)
                                .submitLabel(.next)
                                .onSubmit {
                                    focusedField = .calories
                                }
                                .inputStyle(surface: surfaceSecondary, text: textPrimary, secondary: textSecondary)
                        }

                        labeledField("Calories") {
                            TextField("Calories", text: $caloriesText)
                                .keyboardType(.numberPad)
                                .focused($focusedField, equals: .calories)
                                .inputStyle(surface: surfaceSecondary, text: textPrimary, secondary: textSecondary)
                        }

                        labeledField("Meal Group") {
                            Picker("Meal Group", selection: $mealGroup) {
                                ForEach(MealGroup.allCases) { group in
                                    Text(group.title).tag(group)
                                }
                            }
                            .pickerStyle(.segmented)
                        }

                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                            ForEach(Array(editableNutrients.enumerated()), id: \.element.id) { index, nutrient in
                                labeledField("\(nutrient.name) (\(nutrient.unit))", spacing: 8) {
                                    TextField("\(nutrient.name) (\(nutrient.unit))", text: nutrientBinding(for: nutrient.key))
                                        .keyboardType(.numberPad)
                                        .inputStyle(surface: surfaceSecondary, text: textPrimary, secondary: textSecondary)
                                }
                                .gridCellColumns(shouldExpandLastNutrientField(at: index) ? 2 : 1)
                            }
                        }

                        if let errorText = validationError {
                            Text(errorText)
                                .font(.caption)
                                .foregroundStyle(Color.red)
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
                Text("Save Changes")
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
        guard parsedCalories != nil, let nutrients = parsedNutrients else {
            return false
        }
        let total = (parsedCalories ?? 0) + nutrients.values.reduce(0, +)
        return total > 0
    }

    private var validationError: String? {
        let hasAnyText = !nameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !caloriesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            nutrientTexts.values.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        guard hasAnyText else {
            return nil
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

    private func shouldExpandLastNutrientField(at index: Int) -> Bool {
        editableNutrients.count.isMultiple(of: 2) == false && index == editableNutrients.count - 1
    }

    private func parseInput(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return 0
        }
        guard let value = Int(trimmed), value >= 0 else {
            return nil
        }
        return value
    }

    private func save() {
        guard let calories = parsedCalories, let nutrients = parsedNutrients else {
            return
        }
        let mergedNutrients = preservedHiddenNutrients.merging(nutrients) { _, new in new }

        let updatedEntry = MealEntry(
            id: entry.id,
            name: nameText,
            calories: calories,
            nutrientValues: mergedNutrients,
            createdAt: entry.createdAt,
            mealGroup: mealGroup
        )

        focusedField = nil
        dismissKeyboard()
        onSave(updatedEntry)
        dismiss()
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

private struct QuickAddMenuImportView: View {
    @Environment(\.dismiss) private var dismiss

    let menu: NutrisliceMenu
    let sourceTitle: String
    let mealTitle: String
    let isLoading: Bool
    let errorMessage: String?
    let surfacePrimary: Color
    let surfaceSecondary: Color
    let textPrimary: Color
    let textSecondary: Color
    let accent: Color
    let onRetry: () async -> Void
    let onSelect: (MenuItem) -> Void

    @State private var searchText = ""
    @State private var isRetrying = false
    @State private var expandedLineIDs: Set<String> = []

    private var filteredLines: [MenuLine] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return menu.lines }
        return menu.lines.compactMap { line in
            let items = line.items.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
            guard !items.isEmpty else { return nil }
            return MenuLine(id: line.id, name: line.name, items: items)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.04, green: 0.06, blue: 0.15),
                        Color(red: 0.07, green: 0.09, blue: 0.19),
                        Color(red: 0.04, green: 0.05, blue: 0.12)
                    ],
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
                            Text("PCC Menu")
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .foregroundStyle(textPrimary)
                            Text("\(sourceTitle) • \(mealTitle)")
                                .font(.subheadline)
                                .foregroundStyle(textSecondary)
                        }

                        HStack(spacing: 10) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(textSecondary)
                            TextField("Search menu", text: $searchText)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .foregroundStyle(textPrimary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .cardStyle(surface: surfacePrimary.opacity(0.95), stroke: textSecondary.opacity(0.15))

                        if isLoading {
                            statusCard(title: "Loading menu", message: "Pulling today's dining options.") {
                                ProgressView().tint(accent)
                            }
                        } else if let errorMessage {
                            statusCard(title: "Could not load menu", message: errorMessage) {
                                Button {
                                    Task {
                                        isRetrying = true
                                        await onRetry()
                                        isRetrying = false
                                    }
                                } label: {
                                    if isRetrying {
                                        ProgressView()
                                            .tint(.white)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 12)
                                    } else {
                                        Text("Retry")
                                            .font(.headline.weight(.semibold))
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 12)
                                    }
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.white)
                                .background(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(accent)
                                )
                            }
                        } else if filteredLines.isEmpty {
                            statusCard(title: "No menu items available", message: "Today's menu has not been published yet.") {
                                EmptyView()
                            }
                        } else {
                            LazyVStack(alignment: .leading, spacing: 14) {
                                ForEach(filteredLines) { line in
                                    lineCard(for: line)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                    .padding(.bottom, 32)
                }
            }
            .onAppear {
                expandedLineIDs = Set(menu.lines.map(\.id))
            }
        }
    }

    private func lineCard(for line: MenuLine) -> some View {
        let isExpanded = expandedLineIDs.contains(line.id)

        return VStack(spacing: 0) {
            Button {
                toggleLine(line.id)
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(line.name)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(textPrimary)
                        Text("\(line.items.count) options")
                            .font(.caption)
                            .foregroundStyle(textSecondary)
                    }

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(textSecondary)
                }
                .padding(18)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 10) {
                    ForEach(line.items) { item in
                        Button {
                            onSelect(item)
                            dismiss()
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.name)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(textPrimary)
                                    Text("\(item.calories) cal • \(item.protein)g protein")
                                        .font(.caption)
                                        .foregroundStyle(textSecondary)
                                }
                                Spacer()
                            }
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(surfaceSecondary.opacity(0.92))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(textSecondary.opacity(0.10), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 18)
            }
        }
        .cardStyle(surface: surfacePrimary.opacity(0.95), stroke: textSecondary.opacity(0.15))
    }

    private func toggleLine(_ lineID: String) {
        if expandedLineIDs.contains(lineID) {
            expandedLineIDs.remove(lineID)
        } else {
            expandedLineIDs.insert(lineID)
        }
        Haptics.selection()
    }

    private func statusCard<Accessory: View>(title: String, message: String, @ViewBuilder accessory: () -> Accessory) -> some View {
        VStack(spacing: 16) {
            VStack(spacing: 6) {
                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(textPrimary)
                Text(message)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(textSecondary)
            }
            accessory()
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .cardStyle(surface: surfacePrimary.opacity(0.95), stroke: textSecondary.opacity(0.15))
    }
}

private struct NutrientSelectionList: View {
    @Binding var trackedNutrientKeys: [String]
    let availableNutrients: [NutrientDefinition]

    private var selectedKeys: Set<String> {
        Set(trackedNutrientKeys)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(availableNutrients) { nutrient in
                let isSelected = selectedKeys.contains(nutrient.key)
                let isLocked = isSelected && selectedKeys.count == 1

                Button {
                    toggleSelection(for: nutrient.key)
                } label: {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .strokeBorder(
                                    isSelected ? Color(red: 0.20, green: 0.50, blue: 0.98) : Color.white.opacity(0.24),
                                    lineWidth: 2
                                )
                                .frame(width: 24, height: 24)

                            if isSelected {
                                Circle()
                                    .fill(Color(red: 0.20, green: 0.50, blue: 0.98))
                                    .frame(width: 12, height: 12)
                            }
                        }

                        Text(nutrient.name)
                            .foregroundStyle(isLocked ? Color.white.opacity(0.7) : .primary)

                        Spacer()

                        Text(nutrient.unit)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.white.opacity(0.08))
                            )
                    }
                    .contentShape(Rectangle())
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .disabled(isLocked)
                .opacity(isLocked ? 0.82 : 1)
                .accessibilityLabel("\(nutrient.name), \(isSelected ? "selected" : "not selected")")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityHint(isLocked ? "At least one nutrient must remain selected." : "Double tap to toggle selection.")
            }
        }
    }

    private func toggleSelection(for key: String) {
        if selectedKeys.contains(key) {
            trackedNutrientKeys.removeAll { $0 == key }
            if trackedNutrientKeys.isEmpty {
                trackedNutrientKeys = ["g_protein"]
            }
        } else if !trackedNutrientKeys.contains(key) {
            trackedNutrientKeys.append(key)
        }
    }
}

private struct AppSettingsTabView: View {
    @Binding var trackedNutrientKeys: [String]
    let availableNutrients: [NutrientDefinition]
    @Binding var selectedAppIconChoiceRaw: String

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Track Nutrients")
                    .font(.headline.weight(.semibold))

                Text("Choose which nutrients appear throughout the app.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                NutrientSelectionList(
                    trackedNutrientKeys: $trackedNutrientKeys,
                    availableNutrients: availableNutrients
                )
            }

            Divider()
                .overlay(Color.secondary.opacity(0.18))

            VStack(alignment: .leading, spacing: 12) {
                Text("App Icon")
                    .font(.headline.weight(.semibold))

                Picker("Icon", selection: $selectedAppIconChoiceRaw) {
                    ForEach(AppIconChoice.allCases) { option in
                        Text(option.title).tag(option.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground).opacity(0.55))
        )
    }
}

private struct OnboardingFlowView: View {
    @Binding var currentPage: Int
    @Binding var deficitCalories: Int
    @Binding var trackedNutrientKeys: [String]
    @Binding var nutrientGoals: [String: Int]
    let availableNutrients: [NutrientDefinition]
    let healthAuthorizationState: HealthKitService.AuthorizationState
    let healthProfile: HealthKitService.SyncedProfile?
    let hasRequestedHealthAccess: Bool
    let backgroundTop: Color
    let backgroundBottom: Color
    let surfacePrimary: Color
    let textPrimary: Color
    let textSecondary: Color
    let accent: Color
    let onRequestHealthAccess: () -> Void
    let onSkip: () -> Void
    let onFinish: () -> Void

    private let pageCount = 4

    private var canFinish: Bool {
        !trackedNutrientKeys.isEmpty
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [backgroundTop, backgroundBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                header

                TabView(selection: $currentPage) {
                    onboardingCard {
                        welcomeSlide
                    }
                    .tag(0)

                    onboardingCard {
                        healthSlide
                    }
                    .tag(1)

                    onboardingCard {
                        deficitSlide
                    }
                    .tag(2)

                    onboardingCard {
                        nutrientSlide
                    }
                    .tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                footer
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 20)
        }
        .onAppear(perform: ensureNutrientGoalsExist)
        .onChange(of: trackedNutrientKeys) { _, _ in
            ensureNutrientGoalsExist()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Welcome")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(textPrimary)

                Spacer()

                if currentPage < pageCount - 1 {
                    Button("Skip", action: onSkip)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(textSecondary)
                }
            }

            HStack(spacing: 8) {
                ForEach(0..<pageCount, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(index == currentPage ? accent : Color.white.opacity(0.12))
                        .frame(maxWidth: .infinity)
                        .frame(height: 6)
                        .animation(.easeInOut(duration: 0.2), value: currentPage)
                }
            }
        }
        .padding(.bottom, 20)
    }

    private func onboardingCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
            .frame(minHeight: 580, alignment: .top)
        }
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(surfacePrimary.opacity(0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(textSecondary.opacity(0.16), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.22), radius: 24, x: 0, y: 12)
    }

    private var welcomeSlide: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Calorie Tracker")
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundStyle(textPrimary)

                Text("Set up the app once and start logging with calorie goals, Health data, and the nutrients that matter to you.")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(textSecondary)
            }

            VStack(spacing: 14) {
                welcomeFeatureCard(
                    icon: "heart.text.square.fill",
                    title: "Connect Health",
                    detail: "Use Apple Health for automatic BMR and more accurate step-calorie estimates.",
                    tint: Color(red: 0.46, green: 0.90, blue: 0.60)
                )
                welcomeFeatureCard(
                    icon: "target",
                    title: "Set a deficit",
                    detail: "Choose how aggressively your calorie goal is reduced.",
                    tint: accent
                )
                welcomeFeatureCard(
                    icon: "list.bullet.rectangle.portrait.fill",
                    title: "Pick nutrients",
                    detail: "Control which nutrient fields and progress cards appear across the app.",
                    tint: Color(red: 0.96, green: 0.63, blue: 0.28)
                )
            }
        }
    }

    private var healthSlide: some View {
        VStack(alignment: .leading, spacing: 18) {
            slideHeading(
                eyebrow: "Slide 2 of 4",
                title: "Connect Apple Health",
                detail: "Read height, weight, sex, and age so the app can calculate BMR and personalize step-calorie estimates."
            )

            if let healthProfile, healthAuthorizationState == .connected {
                HStack {
                    statusBadge(title: healthAuthorizationState.title, isConnected: true)
                    Spacer()
                }

                HStack(spacing: 10) {
                    healthValueChip(title: "Sex", value: healthProfile.bmrProfile.sex.title)
                    healthValueChip(title: "Height", value: healthProfile.heightDisplay)
                    healthValueChip(title: "Weight", value: healthProfile.weightDisplay)
                }

                Text("Health is connected. The app will keep using the latest profile data it can read from Apple Health.")
                    .font(.subheadline)
                    .foregroundStyle(textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Button(action: onRequestHealthAccess) {
                        Text("Connect Apple Health")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(accent)

                    Text(healthFallbackText)
                        .font(.caption)
                        .foregroundStyle(textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
            }
        }
    }

    private var deficitSlide: some View {
        VStack(alignment: .leading, spacing: 18) {
            slideHeading(
                eyebrow: "Slide 3 of 4",
                title: "Set Your Deficit Goal",
                detail: "This amount is subtracted from calories burned to create your daily intake target."
            )

            DeficitGoalEditor(
                deficitCalories: $deficitCalories,
                title: "Daily deficit",
                subtitle: "Common moderate range: 250-500 cal",
                helperText: "You can change this later in Profile. The app allows any value from 0 to 2500 calories.",
                accent: accent
            )
        }
    }

    private var nutrientSlide: some View {
        VStack(alignment: .leading, spacing: 18) {
            slideHeading(
                eyebrow: "Slide 4 of 4",
                title: "Choose Nutrients to Track",
                detail: "Your selections determine which nutrient inputs, progress cards, and goals appear throughout the app."
            )

            Text("You can change this later in Settings. At least one nutrient stays selected at all times.")
                .font(.subheadline)
                .foregroundStyle(textSecondary)

            NutrientSelectionList(
                trackedNutrientKeys: $trackedNutrientKeys,
                availableNutrients: availableNutrients
            )
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if currentPage > 0 {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        currentPage = max(currentPage - 1, 0)
                    }
                } label: {
                    Text("Back")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            Button {
                if currentPage == pageCount - 1 {
                    onFinish()
                } else {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        currentPage = min(currentPage + 1, pageCount - 1)
                    }
                }
            } label: {
                Text(currentPage == pageCount - 1 ? "Finish" : "Continue")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(accent)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(currentPage == pageCount - 1 && !canFinish)
            .opacity(currentPage == pageCount - 1 && !canFinish ? 0.6 : 1)
        }
        .padding(.top, 18)
    }

    private var healthFallbackText: String {
        switch healthAuthorizationState {
        case .connected:
            return "Health is connected."
        case .unavailable:
            return "Health data is not available on this device. The app will use its fallback average BMR until you use a supported device."
        case .notConnected:
            if hasRequestedHealthAccess {
                return "If you skipped or denied access, onboarding can still continue. You can connect Health later from the Profile tab."
            }
            return "Health is optional. If you skip it now, the app uses its fallback average BMR until you connect later."
        }
    }

    private func welcomeFeatureCard(icon: String, title: String, detail: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(tint)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(textPrimary)

                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(textSecondary)
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private func slideHeading(eyebrow: String, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(eyebrow)
                .font(.caption.weight(.semibold))
                .foregroundStyle(textSecondary)

            Text(title)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(textPrimary)

            Text(detail)
                .font(.subheadline)
                .foregroundStyle(textSecondary)
        }
    }

    private func statusBadge(title: String, isConnected: Bool) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(isConnected ? Color(red: 0.46, green: 0.90, blue: 0.60) : .white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(isConnected ? Color(red: 0.13, green: 0.28, blue: 0.18) : Color.white.opacity(0.08))
            )
    }

    private func healthValueChip(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(textSecondary)

            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }

    private func ensureNutrientGoalsExist() {
        for key in trackedNutrientKeys {
            if nutrientGoals[key] == nil {
                nutrientGoals[key] = NutrientCatalog.definition(for: key).defaultGoal
            }
        }
    }
}

private extension View {
    func cardStyle(surface: Color, stroke: Color) -> some View {
        background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(stroke, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.14), radius: 14, x: 0, y: 8)
    }

    func inputStyle(surface: Color, text: Color, secondary: Color) -> some View {
        padding(.horizontal, 12)
            .padding(.vertical, 10)
            .foregroundStyle(text)
            .tint(text)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(secondary.opacity(0.35), lineWidth: 1)
            )
    }
}

private enum Haptics {
    static func selection() {
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
    }

    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }

    static func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(type)
    }
}

#Preview {
    ContentView()
}

private struct MenuSheetView: View {
    private struct MultiplierSheetContext: Identifiable {
        let id = UUID()
        let item: MenuItem
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let menu: NutrisliceMenu
    let venue: DiningVenue
    let sourceTitle: String
    let mealTitle: String
    @Binding var selectedItemQuantities: [String: Int]
    @Binding var selectedItemMultipliers: [String: Double]
    let isLoading: Bool
    let errorMessage: String?
    let onRetry: () async -> Void
    let onAddSelected: () -> Void

    @State private var isRetrying = false
    @State private var expandedLineIDs: Set<String> = []
    @State private var searchText = ""
    @State private var multiplierSheetContext: MultiplierSheetContext?
    @State private var selectedMultiplierValue = 1.0
    @FocusState private var isSearchFocused: Bool
    private let minMultiplier = 0.25
    private let maxMultiplier = 2.0
    private let multiplierStep = 0.25

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

    private var accent: Color {
        Color(red: 0.20, green: 0.50, blue: 0.98)
    }

    private var backgroundTop: Color {
        colorScheme == .dark ? Color(red: 0.07, green: 0.08, blue: 0.12) : Color(red: 0.95, green: 0.97, blue: 0.99)
    }

    private var backgroundBottom: Color {
        colorScheme == .dark ? Color(red: 0.10, green: 0.11, blue: 0.17) : Color(red: 0.91, green: 0.94, blue: 0.98)
    }

    private var selectedCount: Int {
        selectedItemQuantities.values.reduce(0, +)
    }

    private var filteredLines: [MenuLine] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return menu.lines
        }

        return menu.lines.compactMap { line in
            let items = line.items.filter { item in
                item.name.localizedCaseInsensitiveContains(trimmed)
            }
            guard !items.isEmpty else {
                return nil
            }
            return MenuLine(id: line.id, name: line.name, items: items)
        }
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [backgroundTop, backgroundBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    searchCard
                    content
                }
                .padding(.horizontal, 16)
                .padding(.top, 28)
                .padding(.bottom, 132)
            }
            .scrollIndicators(.hidden)
        }
        .safeAreaInset(edge: .bottom) {
            bottomCTA
        }
        .sheet(item: $multiplierSheetContext, onDismiss: {
            multiplierSheetContext = nil
        }) { context in
            multiplierSheet(item: context.item)
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            statusCard(
                systemImage: "fork.knife.circle",
                title: "Loading menu",
                message: "Pulling today's dining options and nutrition data."
            ) {
                ProgressView()
                    .tint(accent)
            }
        } else if let errorMessage {
            statusCard(
                systemImage: "exclamationmark.triangle.fill",
                title: "Could not load menu",
                message: errorMessage
            ) {
                Button {
                    Task {
                        isRetrying = true
                        await onRetry()
                        isRetrying = false
                    }
                } label: {
                    if isRetrying {
                        ProgressView()
                            .tint(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    } else {
                        Text("Retry")
                            .font(.headline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(accent)
                )
                .disabled(isRetrying)
            }
        } else if filteredLines.isEmpty {
            statusCard(
                systemImage: searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "fork.knife" : "magnifyingglass",
                title: searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No menu items available" : "No matches found",
                message: searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Today's menu has not been published yet." : "Try a broader search term."
            )
        } else {
            LazyVStack(alignment: .leading, spacing: 14) {
                ForEach(filteredLines) { line in
                    lineCard(for: line)
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Button {
                Haptics.selection()
                dismiss()
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
                Text("Menu")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(textPrimary)
                Text("\(sourceTitle) • \(mealTitle)")
                    .font(.subheadline)
                    .foregroundStyle(textSecondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("\(selectedCount)")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(textPrimary)
                    .monospacedDigit()
                Text("selected")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(textSecondary)
            }
        }
    }

    private var searchCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(textSecondary)

            TextField("Search menu", text: $searchText)
                .focused($isSearchFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(textPrimary)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
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
    }

    private func lineCard(for line: MenuLine) -> some View {
        let expanded = isLineExpandedBinding(for: line.id)

        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(line.name)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(textPrimary)
                    Text("\(line.items.count) options")
                        .font(.caption)
                        .foregroundStyle(textSecondary)
                }

                Spacer()

                Text("\(line.items.count)")
                    .font(.caption.monospacedDigit().weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule(style: .continuous)
                            .fill(accent.opacity(0.95))
                    )

                Image(systemName: expanded.wrappedValue ? "chevron.up" : "chevron.down")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(textSecondary)
            }
            .padding(18)
            .contentShape(Rectangle())
            .onTapGesture {
                expanded.wrappedValue.toggle()
                Haptics.selection()
            }

            if expanded.wrappedValue {
                Divider()
                    .overlay(textSecondary.opacity(0.10))
                    .padding(.horizontal, 18)

                VStack(spacing: 10) {
                    if venue == .grabNGo {
                        grabNGoSelectAllRow(for: line)
                    }
                    ForEach(line.items) { item in
                        menuItemRow(item)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 14)
            }
        }
        .cardStyle(surface: surfacePrimary.opacity(0.95), stroke: textSecondary.opacity(0.15))
    }

    private func grabNGoSelectAllRow(for line: MenuLine) -> some View {
        let allSelected = areAllItemsSelected(in: line)

        return Button {
            selectAllItems(in: line)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: allSelected ? "checkmark.circle.fill" : "checkmark.circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(allSelected ? accent : textSecondary)

                VStack(alignment: .leading, spacing: 3) {
                    Text(allSelected ? "All items selected" : "Select all")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(textPrimary)
                    Text("\(line.items.count) item\(line.items.count == 1 ? "" : "s") in this section")
                        .font(.caption)
                        .foregroundStyle(textSecondary)
                }

                Spacer()

                Text(allSelected ? "Done" : "Add All")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule(style: .continuous)
                            .fill(accent.opacity(0.12))
                    )
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(surfaceSecondary.opacity(0.82))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(textSecondary.opacity(0.10), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(allSelected)
    }

    private func statusCard<Accessory: View>(systemImage: String, title: String, message: String, @ViewBuilder accessory: () -> Accessory) -> some View {
        VStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(systemImage.contains("exclamationmark") ? Color.orange : accent)

            VStack(spacing: 6) {
                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(textPrimary)
                Text(message)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(textSecondary)
            }

            accessory()
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .cardStyle(surface: surfacePrimary.opacity(0.95), stroke: textSecondary.opacity(0.15))
    }

    private func statusCard(systemImage: String, title: String, message: String) -> some View {
        statusCard(systemImage: systemImage, title: title, message: message) {
            EmptyView()
        }
    }

    private var bottomCTA: some View {
        VStack(spacing: 0) {
            Button {
                isSearchFocused = false
                dismissKeyboard()
                guard selectedCount > 0 else {
                    Haptics.notification(.warning)
                    return
                }
                Haptics.impact(.medium)
                onAddSelected()
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Add Selected")
                            .font(.headline.weight(.semibold))
                        Text("\(selectedCount) item\(selectedCount == 1 ? "" : "s") ready")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.78))
                    }

                    Spacer()

                    Text("\(selectedCount)")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule(style: .continuous)
                                .fill(.white.opacity(0.14))
                        )
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(selectedCount == 0 || isLoading || errorMessage != nil ? surfaceSecondary.opacity(0.98) : accent)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(
                            selectedCount == 0 || isLoading || errorMessage != nil
                                ? textSecondary.opacity(0.18)
                                : accent.opacity(0.0),
                            lineWidth: 1
                        )
                )
            }
            .buttonStyle(.plain)
            .disabled(selectedCount == 0 || isLoading || errorMessage != nil)
        }
        .padding(.horizontal, 16)
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

    private func quantity(for id: String) -> Int {
        selectedItemQuantities[id] ?? 0
    }

    private func multiplier(for id: String) -> Double {
        selectedItemMultipliers[id] ?? 1.0
    }

    private func increment(_ id: String) {
        selectedItemQuantities[id] = quantity(for: id) + 1
        Haptics.selection()
    }

    private func decrement(_ id: String) {
        let next = quantity(for: id) - 1
        if next <= 0 {
            selectedItemQuantities.removeValue(forKey: id)
            selectedItemMultipliers[id] = nil
        } else {
            selectedItemQuantities[id] = next
        }
        Haptics.selection()
    }

    private func openMultiplierSheet(for item: MenuItem) {
        selectedMultiplierValue = snappedMultiplier(multiplier(for: item.id))
        isSearchFocused = false
        dismissKeyboard()
        multiplierSheetContext = nil
        Haptics.impact(.light)
        DispatchQueue.main.async {
            multiplierSheetContext = MultiplierSheetContext(item: item)
        }
    }

    private func applySelectedMultiplier() {
        guard let item = multiplierSheetContext?.item else { return }
        selectedItemMultipliers[item.id] = snappedMultiplier(selectedMultiplierValue)
        if quantity(for: item.id) == 0 {
            selectedItemQuantities[item.id] = 1
        }
        Haptics.notification(.success)
        multiplierSheetContext = nil
    }

    private func areAllItemsSelected(in line: MenuLine) -> Bool {
        !line.items.isEmpty && line.items.allSatisfy { quantity(for: $0.id) > 0 }
    }

    private func selectAllItems(in line: MenuLine) {
        var changed = false

        for item in line.items where quantity(for: item.id) == 0 {
            selectedItemQuantities[item.id] = 1
            if selectedItemMultipliers[item.id] == nil {
                selectedItemMultipliers[item.id] = 1.0
            }
            changed = true
        }

        if changed {
            Haptics.notification(.success)
        } else {
            Haptics.selection()
        }
    }

    private func isLineExpandedBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: {
                if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return true
                }
                return expandedLineIDs.contains(id)
            },
            set: { expanded in
                if expanded {
                    expandedLineIDs.insert(id)
                } else {
                    expandedLineIDs.remove(id)
                }
            }
        )
    }

    private func menuItemRow(_ item: MenuItem) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(textPrimary)
                HStack(spacing: 6) {
                    Text("\(item.calories) cal • \(item.protein)g protein")
                    if multiplier(for: item.id) != 1 {
                        Text("\(formattedDisplayServingAmount(item.servingAmount * multiplier(for: item.id), unit: item.servingUnit)) \(displayServingUnit(for: item.servingUnit)) (\(multiplier(for: item.id), specifier: "%.2f")x)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.cyan)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule(style: .continuous).fill(.cyan.opacity(0.14))
                            )
                    }
                }
                .font(.caption)
                .foregroundStyle(textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                openMultiplierSheet(for: item)
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
                Capsule(style: .continuous).fill(Color.white.opacity(0.05))
            )
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(surfaceSecondary.opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(textSecondary.opacity(0.10), lineWidth: 1)
        )
    }

    private func multiplierSheet(item: MenuItem) -> some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(item.name)
                    .font(.title3.weight(.bold))
                Text("Base serve: \(formattedDisplayServingAmount(item.servingAmount, unit: item.servingUnit)) \(displayServingUnit(for: item.servingUnit))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 20) {
                    VerticalServeSlider(
                        value: $selectedMultiplierValue,
                        range: minMultiplier...maxMultiplier,
                        step: multiplierStep
                    ) {
                        Haptics.selection()
                    }
                    .frame(width: 96, height: 320)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Serve")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text("\(formattedDisplayServingAmount(item.servingAmount * selectedMultiplierValue, unit: item.servingUnit)) \(displayServingUnit(for: item.servingUnit))")
                            .font(.title3.weight(.bold))
                            .monospacedDigit()

                        Text("Multiplier")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text("\(selectedMultiplierValue, specifier: "%.2f")x")
                            .font(.title3.weight(.bold))
                            .monospacedDigit()

                        Text("Move up for more, down for less")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 6)
                    }
                    Spacer(minLength: 0)
                }

                let scaledCalories = Int((Double(item.calories) * selectedMultiplierValue).rounded())
                let scaledProtein = Int((Double(item.protein) * selectedMultiplierValue).rounded())
                Text("Final per serving: \(scaledCalories) cal • \(scaledProtein)g protein")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)

                Spacer()

                Button {
                    applySelectedMultiplier()
                } label: {
                    Text("Set Serve")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
            }
            .padding(20)
            .background(
                LinearGradient(
                    colors: [backgroundTop, backgroundBottom],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            )
            .navigationTitle("Serve")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        multiplierSheetContext = nil
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                }
            }
        }
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func snappedMultiplier(_ value: Double) -> Double {
        let clamped = min(max(value, minMultiplier), maxMultiplier)
        let steps = (clamped / multiplierStep).rounded()
        return min(max(steps * multiplierStep, minMultiplier), maxMultiplier)
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

private struct MealDistributionRingView: View {
    let segments: [(group: MealGroup, calories: Int, color: Color)]

    private var totalCalories: Double {
        Double(segments.reduce(0) { $0 + $1.calories })
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 18)

            ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                Circle()
                    .trim(from: startTrim(for: index), to: endTrim(for: index))
                    .stroke(segment.color, style: StrokeStyle(lineWidth: 18, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }

            VStack(spacing: 2) {
                Text("\(Int(totalCalories))")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                Text("calories")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.62))
            }
        }
        .padding(6)
    }

    private func startTrim(for index: Int) -> CGFloat {
        guard totalCalories > 0, index > 0 else { return 0 }
        let previous = segments.prefix(index).reduce(0) { $0 + $1.calories }
        return CGFloat(Double(previous) / totalCalories)
    }

    private func endTrim(for index: Int) -> CGFloat {
        guard totalCalories > 0 else { return 0 }
        let current = segments.prefix(index + 1).reduce(0) { $0 + $1.calories }
        return CGFloat(Double(current) / totalCalories)
    }
}

private struct VerticalServeSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let onStepChange: () -> Void

    private var values: [Double] {
        var result: [Double] = []
        var current = range.lowerBound
        while current <= range.upperBound + 0.0001 {
            result.append(current)
            current += step
        }
        return result
    }

    var body: some View {
        GeometryReader { proxy in
            let height = proxy.size.height
            let availableHeight = max(height - 28, 1)
            let positions = values.enumerated().map { index, option in
                let progress = CGFloat(index) / CGFloat(max(values.count - 1, 1))
                let y = height - 14 - (progress * availableHeight)
                return (option, y)
            }
            let knobY = positions.first(where: { abs($0.0 - value) < 0.001 })?.1 ?? (height / 2)

            ZStack {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 16)

                ForEach(Array(positions.enumerated()), id: \.offset) { _, pair in
                    let option = pair.0
                    let y = pair.1
                    let isMajor = abs((option * 100).truncatingRemainder(dividingBy: 50)) < 0.001 || abs(option - 1.0) < 0.001

                    Rectangle()
                        .fill(Color.white.opacity(isMajor ? 0.55 : 0.28))
                        .frame(width: isMajor ? 28 : 18, height: 2)
                        .position(x: proxy.size.width / 2, y: y)
                }

                Circle()
                    .fill(Color.white)
                    .frame(width: 30, height: 30)
                    .shadow(color: Color.cyan.opacity(0.45), radius: 12, x: 0, y: 4)
                    .overlay(
                        Circle()
                            .stroke(Color.blue.opacity(0.55), lineWidth: 3)
                    )
                    .position(x: proxy.size.width / 2, y: knobY)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let nearest = positions.min(by: { abs($0.1 - gesture.location.y) < abs($1.1 - gesture.location.y) })?.0 ?? value
                        let snapped = snap(nearest)
                        if abs(snapped - value) > 0.0001 {
                            value = snapped
                            onStepChange()
                        }
                    }
            )
        }
    }

    private func snap(_ raw: Double) -> Double {
        let clamped = min(max(raw, range.lowerBound), range.upperBound)
        let steps = (clamped / step).rounded()
        return min(max(steps * step, range.lowerBound), range.upperBound)
    }
}
