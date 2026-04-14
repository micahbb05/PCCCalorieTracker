// Calorie Tracker 2026

import SwiftUI
import UniformTypeIdentifiers
import Charts
import UIKit
import Combine
import CloudKit
import WidgetKit
import WatchConnectivity
import UserNotifications

struct ContentView: View {
    static let cloudSyncStorageVersion = 2
    static let dailyEntryArchiveStorageKey = "dailyEntryArchiveData"
    static let dailyCalorieGoalArchiveStorageKey = "dailyCalorieGoalArchiveData"
    static let dailyBurnedCalorieArchiveStorageKey = "dailyBurnedCalorieArchiveData"
    static let dailyExerciseArchiveStorageKey = "dailyExerciseArchiveData"
    static let dailyGoalTypeArchiveStorageKey = "dailyGoalTypeArchiveData"
    static let syncedHealthProfileStorageKey = "syncedHealthProfileData"
    static let syncedTodayWorkoutsStorageKey = "syncedTodayWorkoutsData"

    struct LaunchCacheState {
        let todayDayIdentifier: String
        let dailyEntryArchive: [String: [MealEntry]]
        let dailyCalorieGoalArchive: [String: Int]
        let dailyBurnedCalorieArchive: [String: Int]
        let dailyExerciseArchive: [String: [ExerciseEntry]]
        let dailyGoalTypeArchive: [String: String]
        let cloudSyncedHealthProfile: HealthKitService.SyncedProfile?
        let cloudSyncedTodayWorkouts: [ExerciseEntry]
    }

    struct FoodSearchResult: Identifiable {
        enum Source {
            case usda
            case openFoodFacts
        }

        let id: String
        let source: Source
        let name: String
        let brand: String?
        let calories: Int
        let nutrientValues: [String: Int]
        let servingAmount: Double
        let servingUnit: String
        let servingDescription: String?
    }

    struct FoodReviewItem: Identifiable {
        let id = UUID()
        let name: String
        let subtitle: String?
        let calories: Int
        let nutrientValues: [String: Int]
        let servingAmount: Double
        let servingUnit: String
        let entrySource: EntrySource
        let displayedNutrientKeys: [String]?
        let quickAddID: UUID?

        var isCountBased: Bool {
            let u = servingUnit.trimmingCharacters(in: .whitespaces).lowercased()
            let n = name.trimmingCharacters(in: .whitespaces).lowercased()

            if u.contains("cup")
                || u.contains("oz")
                || u == "g" || u == "gram" || u == "grams" || u == "grms"
                || u.contains("tbsp") || u.contains("tablespoon")
                || u.contains("tsp") || u.contains("teaspoon")
                || u == "ml" || u == "l" || u == "lb" || u == "lbs" {
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
            ].contains(u) { return true }
            if n.contains("nugget") { return true }
            if n.contains("quesadilla") { return true }
            if n.contains("cookie") || n.contains("chips") || n.hasSuffix(" chip") { return true }
            if n.contains("sandwich") || n.contains("burger") || n.contains("burrito") || n.contains("taco") || n.contains("wrap") {
                return true
            }

            let ambiguousUnits: Set<String> = ["", "serving", "servings", "each", "ea", "item", "items", "portion", "portions"]
            if !ambiguousUnits.contains(u) {
                let letters = CharacterSet.letters
                let unitChars = CharacterSet(charactersIn: u)
                let looksLikeSingleWordUnit = !u.contains(" ") && !u.isEmpty && letters.isSuperset(of: unitChars)
                if looksLikeSingleWordUnit {
                    return true
                }
            }
            return false
        }

        init(
            name: String,
            subtitle: String?,
            calories: Int,
            nutrientValues: [String: Int],
            servingAmount: Double,
            servingUnit: String,
            entrySource: EntrySource,
            displayedNutrientKeys: [String]?,
            quickAddID: UUID? = nil
        ) {
            self.name = name
            self.subtitle = subtitle
            self.calories = calories
            self.nutrientValues = nutrientValues
            self.servingAmount = servingAmount
            self.servingUnit = servingUnit
            self.entrySource = entrySource
            self.displayedNutrientKeys = displayedNutrientKeys
            self.quickAddID = quickAddID
        }
    }

    struct FoodLogDisplayEntry: Identifiable {
        let entries: [MealEntry]
        let name: String
        let calories: Int
        let nutrientValues: [String: Int]
        let createdAt: Date
        let servingCount: Int
        let displayCount: Int

        var id: String {
            let primaryID = entries.first?.id.uuidString ?? UUID().uuidString
            return "\(primaryID)-\(servingCount)-\(displayCount)"
        }

        var primaryEntry: MealEntry? { entries.first }
    }

    struct FoodLogEntryPickerContext: Identifiable {
        let id = UUID()
        let title: String
        var entries: [MealEntry]
    }

    struct HistoryDaySummary: Identifiable {
        let dayIdentifier: String
        let date: Date
        let totalCalories: Int
        let entryCount: Int
        let goalMet: Bool

        var id: String { dayIdentifier }
    }

    init() {
        let launchCache = Self.loadLaunchCacheState()
        _dailyEntryArchive = State(initialValue: launchCache.dailyEntryArchive)
        _dailyCalorieGoalArchive = State(initialValue: launchCache.dailyCalorieGoalArchive)
        _dailyBurnedCalorieArchive = State(initialValue: launchCache.dailyBurnedCalorieArchive)
        _dailyExerciseArchive = State(initialValue: launchCache.dailyExerciseArchive)
        _dailyGoalTypeArchive = State(initialValue: launchCache.dailyGoalTypeArchive)
        _cloudSyncedHealthProfile = State(initialValue: launchCache.cloudSyncedHealthProfile)
        _cloudSyncedTodayWorkouts = State(initialValue: launchCache.cloudSyncedTodayWorkouts)
        _entries = State(initialValue: launchCache.dailyEntryArchive[launchCache.todayDayIdentifier] ?? [])
        _exercises = State(initialValue: launchCache.dailyExerciseArchive[launchCache.todayDayIdentifier] ?? [])
        _selectedHistoryDayIdentifier = State(initialValue: launchCache.todayDayIdentifier)
    }

    static func loadLaunchCacheState(defaults: UserDefaults = .standard) -> LaunchCacheState {
        let snapshot = PersistentAppStateStore.shared.exportSnapshot(defaults: defaults)
        return loadLaunchCacheState(defaults: defaults, snapshot: snapshot)
    }

    static func loadLaunchCacheState(
        defaults: UserDefaults = .standard,
        snapshot: PersistentAppStateSnapshot?
    ) -> LaunchCacheState {
        let todayDayIdentifier = launchDayIdentifier()
        let dailyEntryArchive = decodeArchive(
            [String: [MealEntry]].self,
            key: dailyEntryArchiveStorageKey,
            defaults: defaults,
            fallbackJSONString: snapshot?.dailyEntryArchiveData
        ) ?? [:]
        let dailyCalorieGoalArchive = decodeArchive(
            [String: Int].self,
            key: dailyCalorieGoalArchiveStorageKey,
            defaults: defaults,
            fallbackJSONString: snapshot?.dailyCalorieGoalArchiveData
        ) ?? [:]
        let dailyBurnedCalorieArchive = decodeArchive(
            [String: Int].self,
            key: dailyBurnedCalorieArchiveStorageKey,
            defaults: defaults,
            fallbackJSONString: snapshot?.dailyBurnedCalorieArchiveData
        ) ?? [:]
        let dailyExerciseArchive = decodeArchive(
            [String: [ExerciseEntry]].self,
            key: dailyExerciseArchiveStorageKey,
            defaults: defaults,
            fallbackJSONString: snapshot?.dailyExerciseArchiveData
        ) ?? [:]
        let dailyGoalTypeArchive = decodeArchive(
            [String: String].self,
            key: dailyGoalTypeArchiveStorageKey,
            defaults: defaults,
            fallbackJSONString: snapshot?.dailyGoalTypeArchiveData
        ) ?? [:]
        let cloudSyncedHealthProfile = decodeArchive(
            HealthKitService.SyncedProfile.self,
            key: syncedHealthProfileStorageKey,
            defaults: defaults,
            fallbackJSONString: nil
        )
        let cloudSyncedTodayWorkouts = (decodeArchive(
            [ExerciseEntry].self,
            key: syncedTodayWorkoutsStorageKey,
            defaults: defaults,
            fallbackJSONString: nil
        ) ?? []).filter { entry in
            launchDayIdentifier(for: entry.createdAt) == todayDayIdentifier
        }

        return LaunchCacheState(
            todayDayIdentifier: todayDayIdentifier,
            dailyEntryArchive: dailyEntryArchive,
            dailyCalorieGoalArchive: dailyCalorieGoalArchive,
            dailyBurnedCalorieArchive: dailyBurnedCalorieArchive,
            dailyExerciseArchive: dailyExerciseArchive,
            dailyGoalTypeArchive: dailyGoalTypeArchive,
            cloudSyncedHealthProfile: cloudSyncedHealthProfile,
            cloudSyncedTodayWorkouts: cloudSyncedTodayWorkouts
        )
    }

    static func decodeArchive<T: Decodable>(
        _ type: T.Type,
        key: String,
        defaults: UserDefaults,
        fallbackJSONString: String? = nil
    ) -> T? {
        let stored = defaults.string(forKey: key)
        let resolved = ((stored?.isEmpty == false) ? stored : fallbackJSONString) ?? ""
        guard
            !resolved.isEmpty,
            let data = resolved.data(using: .utf8)
        else {
            return nil
        }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    static func launchDayIdentifier(for date: Date = Date()) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        let startOfDay = calendar.startOfDay(for: date)
        let components = calendar.dateComponents([.year, .month, .day], from: startOfDay)
        let year = components.year ?? 0
        let month = components.month ?? 1
        let day = components.day ?? 1
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    struct CalorieGraphPoint: Identifiable {
        let dayIdentifier: String
        let date: Date
        let calories: Int
        let goal: Int
        let burned: Int

        var id: String { dayIdentifier }
    }

    struct SegmentedCalorieLinePoint: Identifiable {
        let point: CalorieGraphPoint
        let segment: Int

        var id: String { "\(segment)-\(point.dayIdentifier)" }
    }

    enum CalorieAverageSeries: String {
        case consumed
        case burned
    }

    struct CalorieAverageLinePoint: Identifiable {
        let date: Date
        let calories: Int
        let series: CalorieAverageSeries
        let index: Int

        var id: String { "\(series.rawValue)-\(index)" }
    }

    struct CalorieLinePoint: Identifiable {
        let dayIdentifier: String
        let date: Date
        let consumed: Int
        let burned: Int

        var id: String { dayIdentifier }
    }

    enum WeightChangeSeries: String {
        case expected
        case actual

        var title: String {
            switch self {
            case .expected: return "Expected"
            case .actual: return "Actual"
            }
        }
    }

    struct WeightChangePoint: Identifiable {
        let date: Date
        let change: Double
        let series: WeightChangeSeries

        var id: String {
            "\(series.rawValue)-\(date.timeIntervalSince1970)"
        }
    }

    enum WeightChangeAggregation {
        case daily
        case weekly
        case monthly
    }

    enum EntrySource {
        case manual
        case quickAdd
        case barcode
        case usda
        case aiFoodPhoto
        case aiNutritionLabel
        case aiText
        case pccMenu(NutrisliceMenuService.MenuType)
    }

    enum AddDestination: String, CaseIterable, Identifiable {
        case pccMenu
        case usdaSearch
        case barcode
        case quickAdd
        case aiPhoto
        case manualEntry

        var id: String { rawValue }

        var title: String {
            switch self {
            case .pccMenu: return "PCC Menu"
            case .usdaSearch: return "Find Foods"
            case .barcode: return "Scan Barcode"
            case .quickAdd: return "Quick Add"
            case .aiPhoto: return "Smart Log"
            case .manualEntry: return "Manual Entry"
            }
        }

        var subtitle: String {
            switch self {
            case .pccMenu: return "Browse today's PCC dining menu."
            case .usdaSearch: return "Search USDA foods."
            case .barcode: return "Use your camera to scan packaged foods."
            case .quickAdd: return "Add one of your saved foods."
            case .aiPhoto: return "Use AI to estimate nutrition information."
            case .manualEntry: return "Type food and macro details yourself."
            }
        }

        var iconName: String {
            switch self {
            case .pccMenu: return "fork.knife"
            case .usdaSearch: return "magnifyingglass"
            case .barcode: return "barcode.viewfinder"
            case .quickAdd: return "bolt.fill"
            case .aiPhoto: return "sparkles"
            case .manualEntry: return "square.and.pencil"
            }
        }
    }

    typealias VenueMenuCache = [DiningVenue: [NutrisliceMenuService.MenuType: NutrisliceMenu]]
    typealias VenueMenuSignatureCache = [DiningVenue: [NutrisliceMenuService.MenuType: String]]
    typealias VenueMenuSelectionCache = [DiningVenue: [NutrisliceMenuService.MenuType: [String: Int]]]
    typealias VenueMenuMultiplierCache = [DiningVenue: [NutrisliceMenuService.MenuType: [String: Double]]]
    typealias VenueMenuErrorCache = [DiningVenue: [NutrisliceMenuService.MenuType: String]]

    enum HistoryChartRange: String, CaseIterable, Identifiable {
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

    enum NetHistoryRange: String, CaseIterable, Identifiable {
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

    struct DailyCalorieModel {
        let bmr: Int?
        let burned: Int
        let burnedBaseline: Int
        let goal: Int
        let deficit: Int
        let usesBMR: Bool
    }

    enum CalibrationConfidence: String {
        case low = "Low"
        case medium = "Medium"
        case high = "High"
    }

    static let fallbackAverageBMR = 1800
    static let pccMenuUITestLaunchArgument = "UITEST_PCC_MENU"
    static let embeddedMenuBottomClearance: CGFloat = 130
    static let manualEntryContentMaxWidth: CGFloat = 680
    static let calibrationErrorWeights: [Double] = [0.1, 0.2, 0.3, 0.4]

    @Environment(\.colorScheme) var colorScheme
    @State var exportShareURL: URL?
    @State var isShowingExportShareSheet = false
    @State var exportErrorMessage: String?
    @Environment(\.scenePhase) var scenePhase

    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding: Bool = false
    @AppStorage("deficitCalories") var storedDeficitCalories: Int = 500
    @AppStorage("useWeekendDeficit") var useWeekendDeficit: Bool = false
    @AppStorage("weekendDeficitCalories") var storedWeekendDeficitCalories: Int = 0
    @AppStorage("goalTypeRaw") var goalTypeRaw: String = GoalType.deficit.rawValue
    /// Remembers whether smart adjustment (calibration) was enabled before switching to a fixed goal.
    @AppStorage("calibrationWasEnabledBeforeFixed") var calibrationWasEnabledBeforeFixed: Bool = true
    @AppStorage("surplusCalories") var storedSurplusCalories: Int = 300
    @AppStorage("fixedGoalCalories") var storedFixedGoalCalories: Int = 2000
    @AppStorage("manualBMRCalories") var storedManualBMRCalories: Int = 1800
    @AppStorage("dailyGoalTypeArchiveData") var storedDailyGoalTypeArchiveData: String = ""

    enum GoalType: String, CaseIterable {
        case deficit
        case surplus
        case fixed

        var title: String {
            switch self {
            case .deficit: return "Deficit"
            case .surplus: return "Surplus"
            case .fixed: return "Fixed"
            }
        }

        var subtitle: String {
            switch self {
            case .deficit: return "Subtract from burned to lose weight"
            case .surplus: return "Add to burned to gain weight"
            case .fixed: return "Fixed daily intake goal"
            }
        }
    }

    var goalType: GoalType {
        GoalType(rawValue: goalTypeRaw) ?? .deficit
    }

    enum BMRSource: String, CaseIterable {
        case automatic
        case manual

        var title: String {
            switch self {
            case .automatic: return "Automatic"
            case .manual: return "Manual"
            }
        }
    }

    var bmrSource: BMRSource {
        BMRSource(rawValue: bmrSourceRaw) ?? .automatic
    }

    @AppStorage("bmrSourceRaw") var bmrSourceRaw: String = BMRSource.automatic.rawValue
    @AppStorage("proteinGoal") var legacyStoredProteinGoal: Int = 150
    @AppStorage("mealEntriesData") var storedEntriesData: String = ""
    @AppStorage("trackedNutrientsData") var storedTrackedNutrientsData: String = ""
    @AppStorage("nutrientGoalsData") var storedNutrientGoalsData: String = ""
    @AppStorage("lastCentralDayIdentifier") var lastCentralDayIdentifier: String = ""
    @AppStorage("selectedAppIconChoice") var selectedAppIconChoiceRaw: String = AppIconChoice.standard.rawValue
    @AppStorage("dailyEntryArchiveData") var storedDailyEntryArchiveData: String = ""
    @AppStorage("dailyCalorieGoalArchiveData") var storedDailyCalorieGoalArchiveData: String = ""
    @AppStorage("dailyBurnedCalorieArchiveData") var storedDailyBurnedCalorieArchiveData: String = ""
    @AppStorage("dailyExerciseArchiveData") var storedDailyExerciseArchiveData: String = ""
    @AppStorage("venueMenusData") var storedVenueMenusData: String = ""
    @AppStorage("venueMenuSignaturesData") var storedVenueMenuSignaturesData: String = ""
    @AppStorage("quickAddFoodsData") var storedQuickAddFoodsData: String = ""
    @AppStorage("calibrationStateData") var storedCalibrationStateData: String = ""
    @AppStorage("healthWeighInsData") var storedHealthWeighInsData: String = ""
    @AppStorage("syncedHealthProfileData") var storedSyncedHealthProfileData: String = ""
    @AppStorage("syncedTodayWorkoutsData") var storedSyncedTodayWorkoutsData: String = ""
    @AppStorage("syncedHealthSourceDeviceTypeRaw") var storedSyncedHealthSourceDeviceTypeRaw: String = ""
    @AppStorage("activityDetectedDayIdentifier") var activityDetectedDayIdentifier: String = ""
    @AppStorage("cloudSyncLocalModifiedAt") var cloudSyncLocalModifiedAt: Double = 0
    /// When true, Gemini can override ambiguous base servings (e.g. \"1 each\" entrees) with its inferred base oz.
    /// When false, base servings always come from the menu's serving size.
    @AppStorage("useAIBaseServings") var useAIBaseServings: Bool = true
    @AppStorage("smartMealRemindersEnabled") var smartMealRemindersEnabled: Bool = false
    @AppStorage("appThemeStyle") var appThemeStyleRaw: String = AppThemeStyle.ember.rawValue

    @State var entries: [MealEntry] = []
    @State var exercises: [ExerciseEntry] = []
    @State var dailyEntryArchive: [String: [MealEntry]] = [:]
    @State var dailyCalorieGoalArchive: [String: Int] = [:]
    @State var dailyBurnedCalorieArchive: [String: Int] = [:]
    @State var dailyExerciseArchive: [String: [ExerciseEntry]] = [:]
    @State var dailyGoalTypeArchive: [String: String] = [:]
    @State var quickAddFoods: [QuickAddFood] = []
    @State var calibrationState: CalibrationState = .default
    @State var healthWeighIns: [HealthWeighInDay] = []
    @State var cloudSyncedHealthProfile: HealthKitService.SyncedProfile?
    @State var cloudSyncedTodayWorkouts: [ExerciseEntry] = []
    @State var trackedNutrientKeys: [String] = ["g_protein"]
    @State var nutrientGoals: [String: Int] = [:]
    @State var entryNameText = ""
    @State var entryCaloriesText = ""
    @State var nutrientInputTexts: [String: String] = [:]

    @State var isMenuSheetPresented = false
    @State var isBarcodeLookupInFlight = false
    @State var barcodeLookupError: String?
    @State var hasScannedBarcodeInCurrentSheet = false
    @State var isUSDASearchPresented = false
    @State var usdaSearchText = ""
    @State var foodSearchResults: [FoodSearchResult] = []
    @State var isUSDASearchLoading = false
    @State var usdaSearchError: String?
    @State var hasCompletedUSDASearch = false
    @State var usdaSearchDebounceTask: Task<Void, Never>?
    @State var usdaSearchTask: Task<Void, Never>?
    @State var latestFoodSearchRequestID = 0
    @State var foodReviewItem: FoodReviewItem?
    @State var foodReviewNameText = ""
    @State var selectedFoodReviewMultiplier = 1.0
    @State var selectedFoodReviewBaselineAmount = 1.0
    @State var foodReviewSliderBaselineBySignature: [String: Double] = [:]
    @State var foodReviewSliderValueBySignature: [String: Double] = [:]
    @State var selectedFoodReviewAmountText = ""
    @State var isUpdatingFoodReviewTextFromSlider = false
    @State var isFoodReviewKeyboardVisible = false
    @State var selectedFoodReviewQuantity = 1
    @State var aiFoodPhotoRequestedPickerSource: PlateImagePickerView.Source?
    @State var isAIFoodPhotoLoading = false
    @State var aiFoodPhotoErrorMessage: String?
    @State var aiMealTextInput = ""
    @State var isAITextLoading = false
    @State var aiTextErrorMessage: String?
    @State var aiTextMealResults: [AITextMealAnalysisResult.Item] = []
    @State var aiTextPlateItems: [MenuItem]?
    @State var aiTextOzByItemId: [String: Double] = [:]
    @State var aiTextBaseOzByItemId: [String: Double] = [:]
    @State var aiPhotoItems: [MenuItem]?
    @State var aiPhotoOzByItemId: [String: Double] = [:]
    @State var aiPhotoBaseOzByItemId: [String: Double] = [:]
    @State var selectedTab: AppTab = .today
    @State var selectedAddDestination: AddDestination = .manualEntry
    @State var isAddDestinationPickerPresented = false
    @State var selectedMenuVenue: DiningVenue = .fourWinds
    @State var selectedMenuType: NutrisliceMenuService.MenuType = .dinner
    @State var selectedHistoryDayIdentifier = ""
    @State var displayedHistoryMonth = Date()
    @State var presentedHistoryDaySummary: HistoryDaySummary?
    @State var isExpandedHistoryChartPresented = false
    @State var expandedHistoryChartRange: HistoryChartRange = .sevenDays
    @State var isWeightChangeComparisonPresented = false
    @State var weightChangeComparisonRange: NetHistoryRange = .sevenDays
    @State var isRefreshingWeightChangeComparison = false
    @State var netHistoryRange: NetHistoryRange = .sevenDays
    @State var historyDistributionRange: NetHistoryRange = .sevenDays
    @State var isWeeklyInsightPresented = false
    @State var isWeeklyInsightLoading = false
    @State var weeklyInsightText: String?
    @State var weeklyInsightErrorMessage: String?
    @AppStorage("weeklyInsightCachedDayIdentifier") var weeklyInsightCachedDayIdentifier = ""
    @AppStorage("weeklyInsightCachedText") var weeklyInsightCachedText = ""
    @State var editingEntry: MealEntry?
    @State var foodLogEntryPickerContext: FoodLogEntryPickerContext?
    @State var isQuickAddManagerPresented = false
    @State var isQuickAddPickerPresented = false
    @State var onboardingPage = 0
    @State var hasRequestedHealthDuringOnboarding = false

    @State var venueMenus: VenueMenuCache = [:]
    @State var selectedMenuItemQuantitiesByVenue: VenueMenuSelectionCache = [:]
    @State var selectedMenuItemMultipliersByVenue: VenueMenuMultiplierCache = [:]
    @State var isMenuLoading = false
    @State var menuLoadErrorsByVenue: VenueMenuErrorCache = [:]
    @State var lastLoadedMenuSignatureByVenue: VenueMenuSignatureCache = [:]
    @State var isResetConfirmationPresented = false
    @State var isKeyboardVisible = false
    @State var keyboardHeight: CGFloat = 0
    @State var isExerciseSectionCollapsed = false
    @State var isAddExerciseSheetPresented = false
    @State var plateEstimateItems: [MenuItem]?
    @State var plateEstimateOzByItemId: [String: Double] = [:]
    @State var plateEstimateBaseOzByItemId: [String: Double] = [:]
    @State var isPlateEstimateLoading = false
    @State var plateEstimateErrorMessage: String?
    @State var isEmbeddedMenuAIPopupPresented = false
    @State var embeddedMenuRequestedAIPickerSource: PlateImagePickerView.Source?
    @State var hasBootstrappedCloudSync = false
    @State var isApplyingCloudSync = false
    @State var cloudSyncUploadTask: Task<Void, Never>?
    @State var cloudSyncStatusLevel: CloudSyncStatusLevel = .checking
    @State var cloudSyncStatusTitle = "Checking iCloud sync"
    @State var cloudSyncStatusDetail = "The app will keep working locally until iCloud sync is ready."
    @State var cloudSyncLastSuccessAt: Date?
    @State var isCloudSyncInFlight = false
    @State var calibrationEvaluationTask: Task<Void, Never>?
    @State var lastCalibrationEvaluationAt: Date?
    @State var isAddConfirmationPresented = false
    @State var addConfirmationTask: Task<Void, Never>?
    @State var barcodeErrorToastMessage: String?
    @State var barcodeErrorToastTask: Task<Void, Never>?

    @FocusState var focusedField: Field?
    @FocusState var foodReviewFocusedField: FoodReviewField?
    @FocusState var aiMealTextFocused: Bool
    @StateObject var stepActivityService = StepActivityService()
    @StateObject var healthKitService = HealthKitService()

    let menuService = NutrisliceMenuService()
    let openFoodFactsService = OpenFoodFactsService()
    let usdaFoodService = USDAFoodService()
    let aiTextMealService = AITextMealService()
    let weeklyInsightService = GeminiWeeklyInsightService()
    let clockTimer = Timer.publish(every: 120, on: .main, in: .common).autoconnect()
    let disableUSDASearchForDebug = false

    enum Field: Hashable {
        case name
        case calories
        case nutrient(String)
    }

    enum FoodReviewField: Hashable {
        case name
        case amount
    }

    enum ManualEntryGridField: Hashable {
        case calories
        case nutrient(NutrientDefinition)
    }

    enum OnboardingPage: Int, CaseIterable {
        case welcome
        case health
        case deficit
        case nutrients
    }

}

#Preview {
    ContentView()
}
