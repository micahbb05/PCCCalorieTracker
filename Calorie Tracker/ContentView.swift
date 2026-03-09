import SwiftUI
import Charts
import UIKit
import Combine
import CloudKit

extension Notification.Name {
    static let cloudKitAppStateDidChange = Notification.Name("cloudKitAppStateDidChange")
}

private typealias StoredVenueMenuCache = [DiningVenue: [NutrisliceMenuService.MenuType: NutrisliceMenu]]
private typealias StoredVenueMenuSignatureCache = [DiningVenue: [NutrisliceMenuService.MenuType: String]]

struct CloudSyncPayload: Codable, Equatable, Sendable {
    let hasCompletedOnboarding: Bool
    let deficitCalories: Int
    let useWeekendDeficit: Bool
    let weekendDeficitCalories: Int
    let goalTypeRaw: String
    let surplusCalories: Int
    let dailyGoalTypeArchiveData: String
    let proteinGoal: Int
    let mealEntriesData: String
    let trackedNutrientsData: String
    let nutrientGoalsData: String
    let lastCentralDayIdentifier: String
    let selectedAppIconChoiceRaw: String
    let dailyEntryArchiveData: String
    let dailyCalorieGoalArchiveData: String
    let dailyBurnedCalorieArchiveData: String
    let dailyExerciseArchiveData: String
    let venueMenusData: String
    let venueMenuSignaturesData: String
    let quickAddFoodsData: String
    let useAIBaseServings: Bool
    let calibrationStateData: String?
    let healthWeighInsData: String?
}

struct CloudSyncEnvelope: Codable, Sendable {
    let updatedAt: Double
    let payload: CloudSyncPayload
}

actor AppCloudSyncService {
    static let shared = AppCloudSyncService()

    private let container = CKContainer.default()
    private let recordID = CKRecord.ID(recordName: "user-state")
    private let recordType = "AppState"
    private let assetFieldName = "payloadAsset"
    private let updatedAtFieldName = "updatedAt"
    private let subscriptionID = "app-state-private-changes"

    func fetchEnvelope() async throws -> CloudSyncEnvelope? {
        guard try await isCloudAccountAvailable() else { return nil }

        do {
            let record = try await fetchRecord()
            guard
                let asset = record[assetFieldName] as? CKAsset,
                let fileURL = asset.fileURL
            else {
                return nil
            }

            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode(CloudSyncEnvelope.self, from: data)
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    func saveEnvelope(_ envelope: CloudSyncEnvelope) async throws {
        guard try await isCloudAccountAvailable() else { return }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cloud-sync-\(UUID().uuidString).json")
        let data = try JSONEncoder().encode(envelope)
        try data.write(to: tempURL, options: .atomic)

        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }

        let record: CKRecord
        do {
            record = try await fetchRecord()
        } catch let error as CKError where error.code == .unknownItem {
            record = CKRecord(recordType: recordType, recordID: recordID)
        }

        record[assetFieldName] = CKAsset(fileURL: tempURL)
        record[updatedAtFieldName] = envelope.updatedAt as NSNumber
        _ = try await saveRecord(record)
    }

    func ensureSubscription() async throws {
        guard try await isCloudAccountAvailable() else { return }

        do {
            _ = try await fetchSubscription()
        } catch let error as CKError where error.code == .unknownItem {
            let subscription = CKDatabaseSubscription(subscriptionID: subscriptionID)
            let notificationInfo = CKSubscription.NotificationInfo()
            notificationInfo.shouldSendContentAvailable = true
            subscription.notificationInfo = notificationInfo
            _ = try await saveSubscription(subscription)
        }
    }

    nonisolated static func isAppStateChangeNotification(userInfo: [AnyHashable: Any]) -> Bool {
        guard let notification = CKNotification(fromRemoteNotificationDictionary: userInfo) else {
            return false
        }

        return notification.subscriptionID == "app-state-private-changes"
    }

    private func isCloudAccountAvailable() async throws -> Bool {
        let status: CKAccountStatus = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CKAccountStatus, Error>) in
            container.accountStatus { status, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: status)
                }
            }
        }

        return status == .available
    }

    private func fetchRecord() async throws -> CKRecord {
        try await withCheckedThrowingContinuation { continuation in
            container.privateCloudDatabase.fetch(withRecordID: recordID) { record, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let record {
                    continuation.resume(returning: record)
                } else {
                    continuation.resume(throwing: CKError(.unknownItem))
                }
            }
        }
    }

    private func saveRecord(_ record: CKRecord) async throws -> CKRecord {
        try await withCheckedThrowingContinuation { continuation in
            container.privateCloudDatabase.save(record) { savedRecord, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let savedRecord {
                    continuation.resume(returning: savedRecord)
                } else {
                    continuation.resume(throwing: CKError(.internalError))
                }
            }
        }
    }

    private func fetchSubscription() async throws -> CKSubscription {
        try await withCheckedThrowingContinuation { continuation in
            container.privateCloudDatabase.fetch(withSubscriptionID: subscriptionID) { subscription, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let subscription {
                    continuation.resume(returning: subscription)
                } else {
                    continuation.resume(throwing: CKError(.unknownItem))
                }
            }
        }
    }

    private func saveSubscription(_ subscription: CKSubscription) async throws -> CKSubscription {
        try await withCheckedThrowingContinuation { continuation in
            container.privateCloudDatabase.save(subscription) { savedSubscription, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let savedSubscription {
                    continuation.resume(returning: savedSubscription)
                } else {
                    continuation.resume(throwing: CKError(.internalError))
                }
            }
        }
    }
}

actor AppMenuPreloadService {
    static let shared = AppMenuPreloadService()

    private let defaults = UserDefaults.standard
    private let menuService = NutrisliceMenuService()
    private let venueMenusKey = "venueMenusData"
    private let venueMenuSignaturesKey = "venueMenuSignaturesData"

    func preloadTodayMenus() async -> Bool {
        var venueMenus = loadVenueMenus()
        var venueMenuSignatures = loadVenueMenuSignatures()
        var didUpdate = false

        for venue in DiningVenue.allCases {
            for menuType in menuService.allMenuTypes where venue.supportedMenuTypes.contains(menuType) {
                let currentSignature = menuService.currentMenuSignature(for: venue, menuType: menuType)
                let existingMenu = venueMenus[venue]?[menuType] ?? .empty
                let lastSignature = venueMenuSignatures[venue]?[menuType]
                guard existingMenu.lines.isEmpty || lastSignature != currentSignature else {
                    continue
                }

                do {
                    let menu = try await menuService.fetchTodayMenu(for: venue, menuType: menuType)
                    var venueCache = venueMenus[venue] ?? [:]
                    venueCache[menuType] = menu
                    venueMenus[venue] = venueCache

                    var signatureCache = venueMenuSignatures[venue] ?? [:]
                    signatureCache[menuType] = currentSignature
                    venueMenuSignatures[venue] = signatureCache
                    didUpdate = true
                } catch {
                    continue
                }
            }
        }

        if didUpdate {
            saveVenueMenus(venueMenus)
            saveVenueMenuSignatures(venueMenuSignatures)
        }

        return didUpdate
    }

    private func loadVenueMenus() -> StoredVenueMenuCache {
        guard
            let stored = defaults.string(forKey: venueMenusKey),
            !stored.isEmpty,
            let data = stored.data(using: .utf8),
            let decoded = try? JSONDecoder().decode(StoredVenueMenuCache.self, from: data)
        else {
            return [:]
        }

        return decoded
    }

    private func loadVenueMenuSignatures() -> StoredVenueMenuSignatureCache {
        guard
            let stored = defaults.string(forKey: venueMenuSignaturesKey),
            !stored.isEmpty,
            let data = stored.data(using: .utf8),
            let decoded = try? JSONDecoder().decode(StoredVenueMenuSignatureCache.self, from: data)
        else {
            return [:]
        }

        return decoded
    }

    private func saveVenueMenus(_ venueMenus: StoredVenueMenuCache) {
        guard let data = try? JSONEncoder().encode(venueMenus) else { return }
        defaults.set(String(decoding: data, as: UTF8.self), forKey: venueMenusKey)
    }

    private func saveVenueMenuSignatures(_ signatures: StoredVenueMenuSignatureCache) {
        guard let data = try? JSONEncoder().encode(signatures) else { return }
        defaults.set(String(decoding: data, as: UTF8.self), forKey: venueMenuSignaturesKey)
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

struct ContentView: View {
    private struct FoodSearchResult: Identifiable {
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

    private struct FoodReviewItem: Identifiable {
        let id = UUID()
        let name: String
        let subtitle: String?
        let calories: Int
        let nutrientValues: [String: Int]
        let servingAmount: Double
        let servingUnit: String
        let entrySource: EntrySource
        let displayedNutrientKeys: [String]?
    }

    private struct FoodLogDisplayEntry: Identifiable {
        let entries: [MealEntry]
        let name: String
        let calories: Int
        let nutrientValues: [String: Int]
        let createdAt: Date
        let servingCount: Int

        var id: String {
            let primaryID = entries.first?.id.uuidString ?? UUID().uuidString
            return "\(primaryID)-\(servingCount)"
        }

        var primaryEntry: MealEntry? { entries.first }
    }

    private struct FoodLogEntryPickerContext: Identifiable {
        let id = UUID()
        let title: String
        var entries: [MealEntry]
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
        case aiFoodPhoto
        case aiNutritionLabel
        case aiText
        case pccMenu(NutrisliceMenuService.MenuType)
    }

    private enum AddDestination: String, CaseIterable, Identifiable {
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
            case .aiPhoto: return "AI Mode"
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

    private typealias VenueMenuCache = [DiningVenue: [NutrisliceMenuService.MenuType: NutrisliceMenu]]
    private typealias VenueMenuSignatureCache = [DiningVenue: [NutrisliceMenuService.MenuType: String]]
    private typealias VenueMenuSelectionCache = [DiningVenue: [NutrisliceMenuService.MenuType: [String: Int]]]
    private typealias VenueMenuMultiplierCache = [DiningVenue: [NutrisliceMenuService.MenuType: [String: Double]]]
    private typealias VenueMenuErrorCache = [DiningVenue: [NutrisliceMenuService.MenuType: String]]

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
        let burnedBaseline: Int
        let goal: Int
        let deficit: Int
        let usesBMR: Bool
    }

    private enum CalibrationConfidence: String {
        case low = "Low"
        case medium = "Medium"
        case high = "High"
    }

    private static let fallbackAverageBMR = 1800
    private static let pccMenuUITestLaunchArgument = "UITEST_PCC_MENU"
    private static let embeddedMenuBottomClearance: CGFloat = 130
    private static let manualEntryContentMaxWidth: CGFloat = 680
    private static let calibrationErrorWeights: [Double] = [0.1, 0.2, 0.3, 0.4]

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
    @AppStorage("calibrationStateData") private var storedCalibrationStateData: String = ""
    @AppStorage("healthWeighInsData") private var storedHealthWeighInsData: String = ""
    @AppStorage("cloudSyncLocalModifiedAt") private var cloudSyncLocalModifiedAt: Double = 0
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
    @State private var calibrationState: CalibrationState = .default
    @State private var healthWeighIns: [HealthWeighInDay] = []
    @State private var trackedNutrientKeys: [String] = ["g_protein"]
    @State private var nutrientGoals: [String: Int] = [:]
    @State private var entryNameText = ""
    @State private var entryCaloriesText = ""
    @State private var nutrientInputTexts: [String: String] = [:]

    @State private var isMenuSheetPresented = false
    @State private var isBarcodeLookupInFlight = false
    @State private var barcodeLookupError: String?
    @State private var hasScannedBarcodeInCurrentSheet = false
    @State private var isUSDASearchPresented = false
    @State private var usdaSearchText = ""
    @State private var foodSearchResults: [FoodSearchResult] = []
    @State private var isUSDASearchLoading = false
    @State private var usdaSearchError: String?
    @State private var usdaSearchDebounceTask: Task<Void, Never>?
    @State private var latestFoodSearchRequestID = 0
    @State private var foodReviewItem: FoodReviewItem?
    @State private var foodReviewNameText = ""
    @State private var selectedFoodReviewMultiplier = 1.0
    @State private var selectedFoodReviewBaselineAmount = 1.0
    @State private var foodReviewSliderBaselineBySignature: [String: Double] = [:]
    @State private var foodReviewSliderValueBySignature: [String: Double] = [:]
    @State private var selectedFoodReviewAmountText = ""
    @State private var isUpdatingFoodReviewTextFromSlider = false
    @State private var isFoodReviewKeyboardVisible = false
    @State private var selectedFoodReviewQuantity = 1
    @State private var aiFoodPhotoRequestedPickerSource: PlateImagePickerView.Source?
    @State private var isAIFoodPhotoLoading = false
    @State private var aiFoodPhotoErrorMessage: String?
    @State private var aiMealTextInput = ""
    @State private var isAITextLoading = false
    @State private var aiTextErrorMessage: String?
    @State private var aiTextMealResults: [AITextMealAnalysisResult.Item] = []
    @State private var aiTextPlateItems: [MenuItem]?
    @State private var aiTextOzByItemId: [String: Double] = [:]
    @State private var aiTextBaseOzByItemId: [String: Double] = [:]
    @State private var aiPhotoItems: [MenuItem]?
    @State private var aiPhotoOzByItemId: [String: Double] = [:]
    @State private var aiPhotoBaseOzByItemId: [String: Double] = [:]
    @State private var selectedTab: AppTab = .today
    @State private var selectedAddDestination: AddDestination = .manualEntry
    @State private var isAddDestinationPickerPresented = false
    @State private var selectedMenuVenue: DiningVenue = .fourWinds
    @State private var selectedMenuType: NutrisliceMenuService.MenuType = .dinner
    @State private var selectedHistoryDayIdentifier = ""
    @State private var displayedHistoryMonth = Date()
    @State private var presentedHistoryDaySummary: HistoryDaySummary?
    @State private var isExpandedHistoryChartPresented = false
    @State private var expandedHistoryChartRange: HistoryChartRange = .thirtyDays
    @State private var netHistoryRange: NetHistoryRange = .sevenDays
    @State private var historyDistributionRange: NetHistoryRange = .sevenDays
    @State private var editingEntry: MealEntry?
    @State private var foodLogEntryPickerContext: FoodLogEntryPickerContext?
    @State private var isQuickAddManagerPresented = false
    @State private var isQuickAddPickerPresented = false
    @State private var onboardingPage = 0
    @State private var hasRequestedHealthDuringOnboarding = false

    @State private var venueMenus: VenueMenuCache = [:]
    @State private var selectedMenuItemQuantitiesByVenue: VenueMenuSelectionCache = [:]
    @State private var selectedMenuItemMultipliersByVenue: VenueMenuMultiplierCache = [:]
    @State private var isMenuLoading = false
    @State private var menuLoadErrorsByVenue: VenueMenuErrorCache = [:]
    @State private var lastLoadedMenuSignatureByVenue: VenueMenuSignatureCache = [:]
    @State private var isResetConfirmationPresented = false
    @State private var isKeyboardVisible = false
    @State private var keyboardHeight: CGFloat = 0
    @State private var isExerciseSectionCollapsed = false
    @State private var isAddExerciseSheetPresented = false
    @State private var plateEstimateItems: [MenuItem]?
    @State private var plateEstimateOzByItemId: [String: Double] = [:]
    @State private var plateEstimateBaseOzByItemId: [String: Double] = [:]
    @State private var isPlateEstimateLoading = false
    @State private var plateEstimateErrorMessage: String?
    @State private var isEmbeddedMenuAIPopupPresented = false
    @State private var embeddedMenuRequestedAIPickerSource: PlateImagePickerView.Source?
    @State private var hasBootstrappedCloudSync = false
    @State private var isApplyingCloudSync = false
    @State private var cloudSyncUploadTask: Task<Void, Never>?
    @State private var calibrationEvaluationTask: Task<Void, Never>?
    @State private var lastCalibrationEvaluationAt: Date?
    @State private var isAddConfirmationPresented = false
    @State private var addConfirmationTask: Task<Void, Never>?
    @State private var barcodeErrorToastMessage: String?
    @State private var barcodeErrorToastTask: Task<Void, Never>?

    private var selectedFoodReviewEffectiveMultiplier: Double {
        guard let item = foodReviewItem else { return 1.0 }
        let selectedAmount = roundToServingSelectorIncrement(selectedFoodReviewBaselineAmount * selectedFoodReviewMultiplier)
        let baseAmount = convertedServingAmount(item.servingAmount, unit: item.servingUnit)
        guard baseAmount > 0 else { return 1.0 }
        return max(selectedAmount / baseAmount, 0)
    }

    private var selectedFoodReviewTotalMultiplier: Double {
        selectedFoodReviewEffectiveMultiplier * Double(selectedFoodReviewQuantity)
    }

    @FocusState private var focusedField: Field?
    @FocusState private var foodReviewFocusedField: FoodReviewField?
    @FocusState private var aiMealTextFocused: Bool
    @StateObject private var stepActivityService = StepActivityService()
    @StateObject private var healthKitService = HealthKitService()

    private let menuService = NutrisliceMenuService()
    private let openFoodFactsService = OpenFoodFactsService()
    private let usdaFoodService = USDAFoodService()
    private let aiTextMealService = AITextMealService()
    private let clockTimer = Timer.publish(every: 120, on: .main, in: .common).autoconnect()
    private let disableUSDASearchForDebug = false

    private enum Field: Hashable {
        case name
        case calories
        case nutrient(String)
    }

    private enum FoodReviewField: Hashable {
        case name
        case amount
    }

    private enum ManualEntryGridField: Hashable {
        case calories
        case nutrient(NutrientDefinition)
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

    private var reclassifiedWalkingCaloriesToday: Int {
        let totalRequestedReclassification = (exercises + healthKitService.todayWorkouts)
            .reduce(0) { $0 + $1.reclassifiedWalkingCalories }
        return min(totalRequestedReclassification, activityCaloriesToday)
    }

    private var effectiveActivityCaloriesToday: Int {
        max(activityCaloriesToday - reclassifiedWalkingCaloriesToday, 0)
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
            let effectiveOffset = calibrationState.isEnabled ? calibrationState.calibrationOffsetCalories : 0
            return DailyCalorieModel(
                bmr: nil,
                burned: archivedBurned,
                burnedBaseline: max(archivedBurned - effectiveOffset, 1),
                goal: archivedGoal,
                deficit: deficitForDay(todayDayIdentifier),
                usesBMR: false
            )
        }

        let bmr = resolvedBMRProfile.flatMap(calculatedBMR(for:)) ?? ContentView.fallbackAverageBMR
        let burnedBaseline = max(bmr + effectiveActivityCaloriesToday + exerciseCaloriesToday, 1)
        let effectiveOffset = calibrationState.isEnabled ? calibrationState.calibrationOffsetCalories : 0
        let burned = max(burnedBaseline + effectiveOffset, 1)
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
            burnedBaseline: burnedBaseline,
            goal: goal,
            deficit: amount,
            usesBMR: resolvedBMRProfile != nil
        )
    }
    private var burnedCaloriesToday: Int { currentDailyCalorieModel.burned }
    private var calorieGoal: Int { currentDailyCalorieModel.goal }
    private var calibrationOffsetCalories: Int { calibrationState.calibrationOffsetCalories }
    private var calibrationConfidence: CalibrationConfidence {
        let checks = max(calibrationState.dataQualityChecks, 1)
        let passRate = Double(calibrationState.dataQualityPasses) / Double(checks)
        let recent = calibrationState.recentDailyErrors.suffix(4)
        guard !recent.isEmpty else { return .low }
        let mean = recent.reduce(0, +) / Double(recent.count)
        let variance = recent.reduce(0.0) { partial, value in
            let delta = value - mean
            return partial + (delta * delta)
        } / Double(recent.count)
        let stdDev = sqrt(variance)

        if passRate >= 0.8, stdDev <= 20, recent.count >= 3 {
            return .high
        }
        if passRate >= 0.5, stdDev <= 40 {
            return .medium
        }
        return .low
    }

    private var calibrationStatusText: String {
        guard calibrationState.isEnabled else { return "Off" }
        switch calibrationState.lastRunStatus {
        case .never: return "Not enough data yet"
        case .applied: return "Applied"
        case .skipped: return "Skipped"
        }
    }

    private var calibrationLastRunText: String {
        guard let lastRunDate = calibrationState.lastRunDate else { return "--" }
        return lastRunDate.formatted(date: .abbreviated, time: .omitted)
    }

    private var calibrationNextRunText: String {
        guard let next = nextCalibrationRunDate(from: Date()) else { return "--" }
        return next.formatted(date: .abbreviated, time: .omitted)
    }
    private var selectedAppIconChoice: AppIconChoice {
        AppIconChoice(rawValue: selectedAppIconChoiceRaw) ?? .standard
    }

    private var cloudSyncPayload: CloudSyncPayload {
        CloudSyncPayload(
            hasCompletedOnboarding: hasCompletedOnboarding,
            deficitCalories: storedDeficitCalories,
            useWeekendDeficit: useWeekendDeficit,
            weekendDeficitCalories: storedWeekendDeficitCalories,
            goalTypeRaw: goalTypeRaw,
            surplusCalories: storedSurplusCalories,
            dailyGoalTypeArchiveData: storedDailyGoalTypeArchiveData,
            proteinGoal: legacyStoredProteinGoal,
            mealEntriesData: storedEntriesData,
            trackedNutrientsData: storedTrackedNutrientsData,
            nutrientGoalsData: storedNutrientGoalsData,
            lastCentralDayIdentifier: lastCentralDayIdentifier,
            selectedAppIconChoiceRaw: selectedAppIconChoiceRaw,
            dailyEntryArchiveData: storedDailyEntryArchiveData,
            dailyCalorieGoalArchiveData: storedDailyCalorieGoalArchiveData,
            dailyBurnedCalorieArchiveData: storedDailyBurnedCalorieArchiveData,
            dailyExerciseArchiveData: storedDailyExerciseArchiveData,
            venueMenusData: storedVenueMenusData,
            venueMenuSignaturesData: storedVenueMenuSignaturesData,
            quickAddFoodsData: storedQuickAddFoodsData,
            useAIBaseServings: useAIBaseServings,
            calibrationStateData: storedCalibrationStateData,
            healthWeighInsData: storedHealthWeighInsData
        )
    }

    private var currentMenu: NutrisliceMenu {
        menu(for: selectedMenuVenue, menuType: selectedMenuType)
    }

    private var currentMenuError: String? {
        menuLoadErrorsByVenue[selectedMenuVenue]?[selectedMenuType]
    }

    private var availableMenuTypesForSelectedVenue: [NutrisliceMenuService.MenuType] {
        menuService.allMenuTypes.filter { selectedMenuVenue.supportedMenuTypes.contains($0) }
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

    private var manualEntryGridRows: [[ManualEntryGridField]] {
        guard !activeNutrients.isEmpty else {
            return [[.calories]]
        }

        if activeNutrients.count.isMultiple(of: 2) {
            var rows: [[ManualEntryGridField]] = [[.calories]]
            for startIndex in stride(from: 0, to: activeNutrients.count, by: 2) {
                rows.append([
                    .nutrient(activeNutrients[startIndex]),
                    .nutrient(activeNutrients[startIndex + 1])
                ])
            }
            return rows
        }

        var rows: [[ManualEntryGridField]] = [[.calories, .nutrient(activeNutrients[0])]]
        for startIndex in stride(from: 1, to: activeNutrients.count, by: 2) {
            if startIndex + 1 < activeNutrients.count {
                rows.append([
                    .nutrient(activeNutrients[startIndex]),
                    .nutrient(activeNutrients[startIndex + 1])
                ])
            } else {
                rows.append([.nutrient(activeNutrients[startIndex])])
            }
        }
        return rows
    }

    private var primaryNutrient: NutrientDefinition {
        activeNutrients.first ?? NutrientCatalog.definition(for: "g_protein")
    }

    private var isManualEntryEditing: Bool {
        focusedField != nil && isKeyboardVisible
    }

    private var manualEntryBottomPadding: CGFloat {
        guard isManualEntryEditing else { return 140 }
        return max(124, keyboardHeight + 24)
    }

    private var aiModeBottomPadding: CGFloat {
        guard isKeyboardVisible else { return 120 }
        return max(120, keyboardHeight + 32)
    }

    private func menu(for venue: DiningVenue, menuType: NutrisliceMenuService.MenuType) -> NutrisliceMenu {
        venueMenus[venue]?[menuType] ?? .empty
    }

    private func setMenu(_ menu: NutrisliceMenu, for venue: DiningVenue, menuType: NutrisliceMenuService.MenuType) {
        var venueCache = venueMenus[venue] ?? [:]
        venueCache[menuType] = menu
        venueMenus[venue] = venueCache
    }

    private func menuSignature(for venue: DiningVenue, menuType: NutrisliceMenuService.MenuType) -> String? {
        lastLoadedMenuSignatureByVenue[venue]?[menuType]
    }

    private func setMenuSignature(_ signature: String?, for venue: DiningVenue, menuType: NutrisliceMenuService.MenuType) {
        var venueCache = lastLoadedMenuSignatureByVenue[venue] ?? [:]
        venueCache[menuType] = signature
        lastLoadedMenuSignatureByVenue[venue] = venueCache
    }

    private func setMenuError(_ error: String?, for venue: DiningVenue, menuType: NutrisliceMenuService.MenuType) {
        var venueCache = menuLoadErrorsByVenue[venue] ?? [:]
        if let error {
            venueCache[menuType] = error
        } else {
            venueCache.removeValue(forKey: menuType)
        }
        menuLoadErrorsByVenue[venue] = venueCache
    }

    private func menuQuantities(for venue: DiningVenue, menuType: NutrisliceMenuService.MenuType) -> [String: Int] {
        selectedMenuItemQuantitiesByVenue[venue]?[menuType] ?? [:]
    }

    private func setMenuQuantities(_ quantities: [String: Int], for venue: DiningVenue, menuType: NutrisliceMenuService.MenuType) {
        var venueCache = selectedMenuItemQuantitiesByVenue[venue] ?? [:]
        venueCache[menuType] = quantities
        selectedMenuItemQuantitiesByVenue[venue] = venueCache
    }

    private func menuMultipliers(for venue: DiningVenue, menuType: NutrisliceMenuService.MenuType) -> [String: Double] {
        selectedMenuItemMultipliersByVenue[venue]?[menuType] ?? [:]
    }

    private func setMenuMultipliers(_ multipliers: [String: Double], for venue: DiningVenue, menuType: NutrisliceMenuService.MenuType) {
        var venueCache = selectedMenuItemMultipliersByVenue[venue] ?? [:]
        venueCache[menuType] = multipliers
        selectedMenuItemMultipliersByVenue[venue] = venueCache
    }

    private func loadVenueMenus() {
        if !storedVenueMenusData.isEmpty,
           let data = storedVenueMenusData.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(VenueMenuCache.self, from: data) {
            venueMenus = decoded
        } else {
            venueMenus = [:]
        }

        if !storedVenueMenuSignaturesData.isEmpty,
           let data = storedVenueMenuSignaturesData.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(VenueMenuSignatureCache.self, from: data) {
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

    private var groupedTodayEntries: [(group: MealGroup, entries: [FoodLogDisplayEntry])] {
        MealGroup.logDisplayOrder.compactMap { group in
            let groupEntries = aggregatedFoodLogEntries(
                from: sortedEntries.filter { $0.mealGroup == group }
            )
            guard !groupEntries.isEmpty else { return nil }
            return (group, groupEntries)
        }
    }

    private func aggregatedFoodLogEntries(from entries: [MealEntry]) -> [FoodLogDisplayEntry] {
        struct GroupedEntry {
            let key: String
            var entries: [MealEntry]
        }

        let grouped = entries.reduce(into: [GroupedEntry]()) { partialResult, entry in
            let key = foodLogAggregationKey(for: entry)
            if let index = partialResult.firstIndex(where: { $0.key == key }) {
                partialResult[index].entries.append(entry)
            } else {
                partialResult.append(GroupedEntry(key: key, entries: [entry]))
            }
        }

        return grouped.map { groupedEntry in
            let sortedGroupEntries = groupedEntry.entries.sorted { $0.createdAt > $1.createdAt }
            let totalCalories = sortedGroupEntries.reduce(0) { $0 + $1.calories }
            let totalNutrients = sortedGroupEntries.reduce(into: [String: Int]()) { partialResult, entry in
                for (key, value) in entry.nutrientValues {
                    partialResult[key, default: 0] += value
                }
            }

            return FoodLogDisplayEntry(
                entries: sortedGroupEntries,
                name: sortedGroupEntries.first?.name ?? "Unnamed food",
                calories: totalCalories,
                nutrientValues: totalNutrients,
                createdAt: sortedGroupEntries.first?.createdAt ?? .distantPast,
                servingCount: sortedGroupEntries.count
            )
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    private func foodLogAggregationKey(for entry: MealEntry) -> String {
        "\(entry.mealGroup.rawValue)|\(entry.name.lowercased())"
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
        if isPCCMenuUITestMode {
            uiTestPCCMenuRoot
        } else if hasCompletedOnboarding {
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
                scheduleCalibrationEvaluation()
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
            .onChange(of: cloudSyncPayload) { oldPayload, newPayload in
                handleCloudSyncPayloadChange(oldPayload: oldPayload, newPayload: newPayload)
            }
            .onReceive(NotificationCenter.default.publisher(for: .cloudKitAppStateDidChange)) { _ in
                Task(priority: .utility) {
                    await bootstrapCloudSync()
                }
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
            .sheet(isPresented: $isUSDASearchPresented) {
                usdaSearchSheet
            }
            .sheet(item: $foodReviewItem, onDismiss: {
                foodReviewNameText = ""
                selectedFoodReviewBaselineAmount = 1.0
                selectedFoodReviewAmountText = ""
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

    private var addDestinationPickerSheet: some View {
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

                    addDestinationSquareButton(title: "AI Mode", icon: "sparkles") {
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

    private func addDestinationSquareButton(
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

            feedbackToast

            bottomTabBar

            embeddedMenuAIPopupOverlay
        }
        .animation(.easeInOut(duration: 0.18), value: isEmbeddedMenuAIPopupPresented)
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

    private var feedbackToast: some View {
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

    private var barcodeErrorToastView: some View {
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

    private var embeddedMenuAIPopupOverlay: some View {
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

    private var embeddedMenuAIPopupCard: some View {
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

    private func embeddedMenuAIPopupButton(title: String, action: @escaping () -> Void) -> some View {
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

    private var menuSheet: some View {
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

    private func menuPage(
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

    private var pccMenuPage: some View {
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
            },
            onClose: nil,
            showsStandaloneChrome: true
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

    private func foodLogEntryPickerSheet(initialContext: FoodLogEntryPickerContext, context: Binding<FoodLogEntryPickerContext?>) -> some View {
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

    private func handleCloudSyncPayloadChange(oldPayload: CloudSyncPayload, newPayload: CloudSyncPayload) {
        guard hasBootstrappedCloudSync, !isApplyingCloudSync, oldPayload != newPayload else { return }
        scheduleCloudSyncUpload(for: newPayload)
    }

    private func scheduleCloudSyncUpload(for payload: CloudSyncPayload) {
        let timestamp = Date().timeIntervalSince1970
        cloudSyncLocalModifiedAt = timestamp
        cloudSyncUploadTask?.cancel()
        cloudSyncUploadTask = Task {
            try? await Task.sleep(for: .seconds(1.0))
            guard !Task.isCancelled else { return }
            try? await AppCloudSyncService.shared.saveEnvelope(
                CloudSyncEnvelope(updatedAt: timestamp, payload: payload)
            )
        }
    }

    private func bootstrapCloudSync() async {
        defer {
            hasBootstrappedCloudSync = true
        }

        do {
            try await AppCloudSyncService.shared.ensureSubscription()
        } catch {
            // Keep subscription setup silent; launch should not fail on notification issues.
        }

        let localPayload = cloudSyncPayload
        let localUpdatedAt = cloudSyncLocalModifiedAt

        do {
            if let cloudEnvelope = try await AppCloudSyncService.shared.fetchEnvelope() {
                if cloudEnvelope.updatedAt > localUpdatedAt {
                    await MainActor.run {
                        applyCloudSyncPayload(cloudEnvelope.payload, updatedAt: cloudEnvelope.updatedAt)
                    }
                } else if localPayload != cloudEnvelope.payload || localUpdatedAt > cloudEnvelope.updatedAt {
                    let timestamp = max(localUpdatedAt, Date().timeIntervalSince1970)
                    cloudSyncLocalModifiedAt = timestamp
                    try await AppCloudSyncService.shared.saveEnvelope(
                        CloudSyncEnvelope(updatedAt: timestamp, payload: localPayload)
                    )
                }
            } else {
                let timestamp = max(localUpdatedAt, Date().timeIntervalSince1970)
                cloudSyncLocalModifiedAt = timestamp
                try await AppCloudSyncService.shared.saveEnvelope(
                    CloudSyncEnvelope(updatedAt: timestamp, payload: localPayload)
                )
            }
        } catch {
            // Keep cloud sync silent; the app still works fully offline/local-only.
        }
    }

    @MainActor
    private func applyCloudSyncPayload(_ payload: CloudSyncPayload, updatedAt: Double) {
        isApplyingCloudSync = true

        hasCompletedOnboarding = payload.hasCompletedOnboarding
        storedDeficitCalories = payload.deficitCalories
        useWeekendDeficit = payload.useWeekendDeficit
        storedWeekendDeficitCalories = payload.weekendDeficitCalories
        goalTypeRaw = payload.goalTypeRaw
        storedSurplusCalories = payload.surplusCalories
        storedDailyGoalTypeArchiveData = payload.dailyGoalTypeArchiveData
        legacyStoredProteinGoal = payload.proteinGoal
        storedEntriesData = payload.mealEntriesData
        storedTrackedNutrientsData = payload.trackedNutrientsData
        storedNutrientGoalsData = payload.nutrientGoalsData
        lastCentralDayIdentifier = payload.lastCentralDayIdentifier
        selectedAppIconChoiceRaw = payload.selectedAppIconChoiceRaw
        storedDailyEntryArchiveData = payload.dailyEntryArchiveData
        storedDailyCalorieGoalArchiveData = payload.dailyCalorieGoalArchiveData
        storedDailyBurnedCalorieArchiveData = payload.dailyBurnedCalorieArchiveData
        storedDailyExerciseArchiveData = payload.dailyExerciseArchiveData
        storedVenueMenusData = payload.venueMenusData
        storedVenueMenuSignaturesData = payload.venueMenuSignaturesData
        storedQuickAddFoodsData = payload.quickAddFoodsData
        useAIBaseServings = payload.useAIBaseServings
        storedCalibrationStateData = payload.calibrationStateData ?? ""
        storedHealthWeighInsData = payload.healthWeighInsData ?? ""
        cloudSyncLocalModifiedAt = updatedAt

        loadTrackingPreferences()
        loadDailyEntryArchive()
        loadCalibrationState()
        loadHealthWeighIns()
        loadQuickAddFoods()
        loadVenueMenus()
        selectedMenuType = menuService.currentMenuType()
        applyCentralTimeTransitions(forceMenuReload: false)
        syncInputFieldsToTrackedNutrients()
        AppIconManager.apply(selectedAppIconChoice)
        syncCurrentDayGoalArchive()

        isApplyingCloudSync = false
    }

    private func handleOnAppear() {
        if isPCCMenuUITestMode {
            return
        }

        sanitizeStoredGoals()
        loadTrackingPreferences()
        loadDailyEntryArchive()
        loadCalibrationState()
        loadHealthWeighIns()
        loadQuickAddFoods()
        loadVenueMenus()
        selectedMenuType = menuService.currentMenuType()
        Task(priority: .userInitiated) {
            await preloadMenuForNutrientDiscovery()
        }
        Task(priority: .utility) {
            await bootstrapCloudSync()
        }
        applyCentralTimeTransitions(forceMenuReload: false)
        syncInputFieldsToTrackedNutrients()
        AppIconManager.apply(selectedAppIconChoice)
        stepActivityService.requestAccessAndRefresh()
        Task {
            await healthKitService.refreshIfPossible()
            await MainActor.run {
                scheduleCalibrationEvaluation()
            }
        }
        syncCurrentDayGoalArchive()
        scheduleCalibrationEvaluation()
    }

    private var isPCCMenuUITestMode: Bool {
        UserDefaults.standard.bool(forKey: Self.pccMenuUITestLaunchArgument)
            || ProcessInfo.processInfo.arguments.contains("-\(Self.pccMenuUITestLaunchArgument)")
            || ProcessInfo.processInfo.arguments.contains(Self.pccMenuUITestLaunchArgument)
            || ProcessInfo.processInfo.environment[Self.pccMenuUITestLaunchArgument] == "1"
    }

    private var uiTestPCCMenuRoot: some View {
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

    private static var pccMenuUITestFixture: NutrisliceMenu {
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
        scheduleCalibrationEvaluation()
    }

    private func handleScenePhaseChange(_ newPhase: ScenePhase) {
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
            await bootstrapCloudSync()
        }
        syncCurrentDayGoalArchive()
        syncHistorySelection(preferToday: true)
        scheduleCalibrationEvaluation()
        Task {
            await preloadMenuForNutrientDiscovery()
        }
    }

    private func handleClockTick() {
        applyCentralTimeTransitions(forceMenuReload: false)
        stepActivityService.refreshIfAuthorized()
        Task {
            await healthKitService.refreshIfPossible()
            await MainActor.run {
                scheduleCalibrationEvaluation()
            }
        }
        Task(priority: .utility) {
            await bootstrapCloudSync()
        }
        syncCurrentDayGoalArchive()
        scheduleCalibrationEvaluation()
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

    private var bottomTabBar: some View {
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

    private func tabBarButton(for tab: AppTab, isCenter: Bool = false) -> some View {
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
        VStack(alignment: .leading, spacing: 0) {
            tabHeader(title: "History", subtitle: "Calendar, calorie trends, and stats")
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 6)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    historyCalendarCard
                    historyGraphCard
                    historyStatisticsCard
                    netCalorieHistoryCard
                    historyMealDistributionCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 140)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
    }

    @ViewBuilder
    private var addTabView: some View {
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

    private var aiPhotoTabView: some View {
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

    private func scheduleAITextCardScroll(using proxy: ScrollViewProxy) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            withAnimation(.easeInOut(duration: 0.2)) {
                proxy.scrollTo("aiTextMealCard", anchor: .top)
            }
        }
    }

    private var manualEntryTabView: some View {
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

    private var pccMenuTabView: some View {
        pccMenuPage
    }

    private var usdaSearchTabView: some View {
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
                foodSearchResults = []
                isUSDASearchLoading = false
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

    private var quickAddTabView: some View {
        VStack(alignment: .leading, spacing: 0) {
            addWorkspaceHeader(
                title: AddDestination.quickAdd.title,
                subtitle: AddDestination.quickAdd.subtitle
            )

            QuickAddPickerView(
                quickAddFoods: quickAddFoods,
                surfacePrimary: surfacePrimary,
                surfaceSecondary: surfaceSecondary,
                textPrimary: textPrimary,
                textSecondary: textSecondary,
                accent: accent,
                onSelect: { item in
                    addQuickAddFood(item)
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

    private var barcodeTabView: some View {
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

    private func addWorkspaceHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            tabHeader(title: title, subtitle: subtitle)
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 6)
    }

    private var manualEntryFormCard: some View {
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
        .cardStyle(surface: surfacePrimary, stroke: textSecondary.opacity(0.15))
        .id("addManualEntryCard")
    }

    private var profileTabView: some View {
        VStack(alignment: .leading, spacing: 0) {
            tabHeader(title: "Profile", subtitle: "Calorie and nutrient goals")
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 6)

            List {
                Section {
                    VStack(alignment: .leading, spacing: 14) {
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
                            activeBurnedCaloriesToday: effectiveActivityCaloriesToday + exerciseCaloriesToday,
                            isUsingAutomatedCalories: currentDailyCalorieModel.usesBMR,
                            isCalibrationEnabled: Binding(
                                get: { calibrationState.isEnabled },
                                set: { newValue in
                                    calibrationState.isEnabled = newValue
                                    saveCalibrationState()
                                    syncCurrentDayGoalArchive()
                                    if newValue {
                                        scheduleCalibrationEvaluation(force: true)
                                    } else {
                                        calibrationEvaluationTask?.cancel()
                                    }
                                }
                            ),
                            calibrationOffsetCalories: calibrationOffsetCalories,
                            calibrationStatusText: calibrationStatusText,
                            calibrationSkipReason: calibrationState.isEnabled && calibrationState.lastRunStatus == .skipped ? calibrationState.lastSkipReason : nil,
                            calibrationLastRunText: calibrationLastRunText,
                            calibrationNextRunText: calibrationNextRunText,
                            calibrationConfidenceText: calibrationConfidence.rawValue,
                            onRequestHealthAccess: {
                                Task {
                                    await healthKitService.requestAccessAndRefresh()
                                }
                            }
                        )

                        quickAddManagementCard
                    }
                }
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 4, trailing: 0))
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
            tabHeader(title: "Settings", subtitle: "App preferences that apply everywhere")
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
                    VStack(alignment: .leading, spacing: 12) {
                        Text("App & Privacy")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.primary)

                        VStack(spacing: 0) {
                            Button {
                                hasCompletedOnboarding = false
                                Haptics.impact(.light)
                            } label: {
                                HStack {
                                    Label("Replay Onboarding", systemImage: "arrow.counterclockwise")
                                        .foregroundStyle(.primary)
                                    Spacer()
                                }
                                .padding(18)
                            }
                            .buttonStyle(.plain)

                            Divider()
                                .overlay(Color.secondary.opacity(0.18))

                            Button {
                                if let url = URL(string: "https://calorie-tracker-364e3.web.app/privacy") {
                                    UIApplication.shared.open(url)
                                }
                            } label: {
                                HStack {
                                    Label("Privacy Policy", systemImage: "doc.text")
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: "arrow.up.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(18)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(18)
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 4, trailing: 0))
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemBackground).opacity(colorScheme == .dark ? 0.82 : 0.55))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.14), lineWidth: 1)
                        )
                        .shadow(
                            color: Color.black.opacity(colorScheme == .dark ? 0.20 : 0.08),
                            radius: colorScheme == .dark ? 10 : 6,
                            x: 0,
                            y: 2
                        )
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

    private var aiPhotoCaptureCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Scan Food or Nutrition Label")
                .font(.headline.weight(.semibold))
                .foregroundStyle(textPrimary)

            VStack(spacing: 12) {
                aiPhotoActionButton(
                    title: "Take Photo",
                    subtitle: "Use the camera for food or labels",
                    systemImage: "camera.fill"
                ) {
                    aiFoodPhotoRequestedPickerSource = .camera
                }

                aiPhotoActionButton(
                    title: "Choose From Library",
                    subtitle: "Pick an existing photo",
                    systemImage: "photo.on.rectangle.angled"
                ) {
                    aiFoodPhotoRequestedPickerSource = .photoLibrary
                }
            }
        }
        .padding(18)
        .cardStyle(surface: surfacePrimary, stroke: textSecondary.opacity(0.15))
    }

    private var aiTextMealCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Describe Your Meal")
                .font(.headline.weight(.semibold))
                .foregroundStyle(textPrimary)

            Text("Type what you ate and AI will estimate calories and macros, using web lookup when needed for more accurate nutrient info.")
                .font(.caption)
                .foregroundStyle(textSecondary)

            TextEditor(text: $aiMealTextInput)
                .frame(minHeight: 108)
                .padding(10)
                .focused($aiMealTextFocused)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(surfaceSecondary.opacity(0.95))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(textSecondary.opacity(0.16), lineWidth: 1)
                )
                .foregroundStyle(textPrimary)
                .scrollContentBackground(.hidden)

            Button {
                analyzeAITextMeal()
            } label: {
                if isAITextLoading {
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                } else {
                    Text("Analyze Description")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(accent)
            .disabled(isAITextLoading || aiMealTextInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

        }
        .padding(18)
        .cardStyle(surface: surfacePrimary, stroke: textSecondary.opacity(0.15))
    }

    private var aiModeOrDivider: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(textSecondary.opacity(0.25))
                .frame(height: 1)
            Text("or")
                .font(.caption.weight(.semibold))
                .foregroundStyle(textSecondary)
            Rectangle()
                .fill(textSecondary.opacity(0.25))
                .frame(height: 1)
        }
        .padding(.horizontal, 8)
    }

    private func aiPhotoActionButton(title: String, subtitle: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                    .frame(width: 22)
                    .foregroundStyle(accent)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(textPrimary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(textSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(textSecondary.opacity(0.85))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(surfaceSecondary.opacity(0.95))
            )
        }
        .buttonStyle(.plain)
        .disabled(isAIFoodPhotoLoading || isAITextLoading)
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
            let isToday = identifier == todayDayIdentifier
            let dayEntries = entries(forDayIdentifier: identifier)
            let hasEntries = !dayEntries.isEmpty
            let dayCalories = dayEntries.reduce(0) { $0 + $1.calories }
            let dayGoal = calorieGoalForDay(identifier)
            let dayBurned = burnedCaloriesForDay(identifier)
            let dayDotColor = historyBarColor(calories: dayCalories, goal: dayGoal, burned: dayBurned)

            Button {
                presentedHistoryDaySummary = historySummary(for: identifier)
                Haptics.selection()
            } label: {
                VStack(spacing: 4) {
                    Text("\(centralCalendar.component(.day, from: date))")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isToday ? Color.white : textPrimary)

                    Circle()
                        .fill(hasEntries ? dayDotColor : Color.clear)
                        .frame(width: 5, height: 5)
                }
                .frame(maxWidth: .infinity, minHeight: 38)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(isToday ? accent : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(.clear, lineWidth: 1)
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
        VStack(alignment: .leading, spacing: 4) {
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
                                if let primaryEntry = entry.primaryEntry, entry.servingCount == 1 {
                                    Button {
                                        editingEntry = primaryEntry
                                        Haptics.selection()
                                    } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }

                                    Button(role: .destructive) {
                                        deleteEntry(primaryEntry)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                } else if entry.servingCount > 1 {
                                    Button {
                                        foodLogEntryPickerContext = FoodLogEntryPickerContext(
                                            title: entry.name,
                                            entries: entry.entries
                                        )
                                        Haptics.selection()
                                    } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }

                                    Button(role: .destructive) {
                                        deleteEntries(entry.entries)
                                    } label: {
                                        Label("Delete All", systemImage: "trash")
                                    }
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                if let primaryEntry = entry.primaryEntry, entry.servingCount == 1 {
                                    Button(role: .destructive) {
                                        deleteEntry(primaryEntry)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                } else if entry.servingCount > 1 {
                                    Button(role: .destructive) {
                                        deleteEntries(entry.entries)
                                    } label: {
                                        Label("Delete All", systemImage: "trash")
                                    }
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
            if allExercises.isEmpty && effectiveActivityCaloriesToday == 0 {
                Text("No exercise logged.")
                    .foregroundStyle(textSecondary)
                    .listRowBackground(surfacePrimary)
            } else {
                ForEach(allExercises.sorted(by: { $0.createdAt > $1.createdAt })) { entry in
                    exerciseLogRow(entry, isDeletable: exercises.contains(where: { $0.id == entry.id }))
                }
                if effectiveActivityCaloriesToday > 0 {
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
                        Text("\(effectiveActivityCaloriesToday) cal")
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
                    Text("\(exerciseCalTotal + effectiveActivityCaloriesToday) cal")
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
                Text(entry.displayTitle)
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

    private func logRow(_ entry: FoodLogDisplayEntry) -> some View {
        let nutrientSummary = activeNutrients.prefix(2).map {
            "\(entryValue(for: $0.key, in: entry))\($0.unit) \($0.name)"
        }.joined(separator: " • ")

        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(entry.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(textPrimary)

                    if entry.servingCount > 1 {
                        Text("x\(entry.servingCount)")
                            .font(.caption2.monospacedDigit().weight(.semibold))
                            .foregroundStyle(textSecondary)
                            .frame(minWidth: 22, minHeight: 22)
                            .padding(.horizontal, 2)
                            .background(
                                Circle()
                                    .fill(surfaceSecondary.opacity(0.95))
                            )
                    }
                }
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
                .fill(Color(uiColor: .secondarySystemBackground).opacity(colorScheme == .dark ? 0.82 : 0.55))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.14), lineWidth: 1)
                )
                .shadow(
                    color: Color.black.opacity(colorScheme == .dark ? 0.20 : 0.08),
                    radius: colorScheme == .dark ? 10 : 6,
                    x: 0,
                    y: 2
                )
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
        withAnimation(.easeOut(duration: 0.25)) {
            if case .nutrient(let key) = field,
               isKeyboardVisible,
               let rowIndex = manualEntryGridRows.firstIndex(where: { row in
                   row.contains {
                       if case .nutrient(let nutrient) = $0 {
                           return nutrient.key == key
                       }
                       return false
                   }
               }) {
                let lastRowIndex = manualEntryGridRows.count - 1
                if rowIndex == lastRowIndex {
                    proxy.scrollTo("addEntryButton", anchor: .bottom)
                    return
                }

                proxy.scrollTo(manualEntryScrollID(for: field), anchor: .center)
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
    private func manualEntryGridCell(_ field: ManualEntryGridField) -> some View {
        switch field {
        case .calories:
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
        case .nutrient(let nutrient):
            nutrientFieldCell(nutrient)
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
        showAddConfirmation()

        entryNameText = ""
        entryCaloriesText = ""
        barcodeLookupError = nil
        for nutrient in activeNutrients {
            nutrientInputTexts[nutrient.key] = ""
        }
        focusedField = nil
        dismissKeyboard()
    }

    private var usdaSearchSheet: some View {
        usdaSearchPage(onClose: {
            isUSDASearchPresented = false
            dismissKeyboard()
            Haptics.selection()
        })
    }

    private func usdaSearchPage(onClose: (() -> Void)?) -> some View {
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

    private var usdaSearchPageContent: some View {
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
                            Task {
                                await performUSDASearch()
                            }
                        }
                        .foregroundStyle(textPrimary)

                    if !usdaSearchText.isEmpty {
                        Button {
                            latestFoodSearchRequestID += 1
                            usdaSearchText = ""
                            foodSearchResults = []
                            isUSDASearchLoading = false
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

                if !foodSearchResults.isEmpty {
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
                    Text("Search to see matching foods.")
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

                            VStack(alignment: .leading, spacing: 6) {
                                TextField("Food name", text: $foodReviewNameText)
                                    .font(.system(size: 28, weight: .bold, design: .rounded))
                                    .foregroundStyle(textPrimary)
                                    .submitLabel(.done)
                                    .focused($foodReviewFocusedField, equals: .name)
                                    .inputStyle(surface: surfacePrimary.opacity(0.94), text: textPrimary, secondary: textSecondary)
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

    private func foodSearchResultCard(_ result: FoodSearchResult) -> some View {
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

    private func foodReviewNutrientCard(for item: FoodReviewItem) -> some View {
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

    private func reviewStatCard(title: String, value: String) -> some View {
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

    private var foodReviewQuantityCard: some View {
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

    private func foodReviewServingAmountCard(for item: FoodReviewItem) -> some View {
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

    private func presentMenu(for venue: DiningVenue) {
        let shouldLoadMenu = prepareMenuDestination(for: venue)
        isMenuSheetPresented = true

        if shouldLoadMenu {
            Task {
                await loadMenuFromFirebase(for: selectedMenuVenue)
            }
        }
    }

    @discardableResult
    private func prepareMenuDestination(for venue: DiningVenue) -> Bool {
        let initialMenuType = menuService.currentMenuType()
        let resolvedVenue = preferredMenuVenue(startingFrom: venue, menuType: initialMenuType)
        let resolvedMenuType = preferredMenuType(startingFrom: initialMenuType, for: resolvedVenue)
        selectedMenuVenue = resolvedVenue
        selectedMenuType = resolvedMenuType
        let signature = menuService.currentMenuSignature(for: resolvedVenue, menuType: resolvedMenuType)
        let shouldLoadMenu = menu(for: resolvedVenue, menuType: resolvedMenuType).lines.isEmpty
            || menuSignature(for: resolvedVenue, menuType: resolvedMenuType) != signature
            || menuLoadErrorsByVenue[resolvedVenue]?[resolvedMenuType] != nil

        if menuSignature(for: resolvedVenue, menuType: resolvedMenuType) != signature {
            setMenu(.empty, for: resolvedVenue, menuType: resolvedMenuType)
            setMenuError(nil, for: resolvedVenue, menuType: resolvedMenuType)
        }

        isMenuLoading = shouldLoadMenu
        return shouldLoadMenu
    }

    private func switchMenuToVenue(_ venue: DiningVenue) {
        guard venue != selectedMenuVenue else { return }
        selectedMenuVenue = venue
        let currentMenuType = menuService.currentMenuType()
        let resolvedMenuType = preferredMenuType(startingFrom: currentMenuType, for: venue)
        selectedMenuType = resolvedMenuType
        let signature = menuService.currentMenuSignature(for: venue, menuType: resolvedMenuType)
        let shouldLoadMenu = menu(for: venue, menuType: resolvedMenuType).lines.isEmpty
            || menuSignature(for: venue, menuType: resolvedMenuType) != signature
            || menuLoadErrorsByVenue[venue]?[resolvedMenuType] != nil

        if menuSignature(for: venue, menuType: resolvedMenuType) != signature {
            setMenu(.empty, for: venue, menuType: resolvedMenuType)
            setMenuError(nil, for: venue, menuType: resolvedMenuType)
        }

        isMenuLoading = shouldLoadMenu

        if shouldLoadMenu {
            Task {
                await loadMenuFromFirebase(for: venue, menuType: resolvedMenuType)
            }
        }
    }

    private func switchMenuToMealType(_ menuType: NutrisliceMenuService.MenuType) {
        let resolvedVenue = preferredMenuVenue(startingFrom: selectedMenuVenue, menuType: menuType)
        let resolvedMenuType = preferredMenuType(startingFrom: menuType, for: resolvedVenue)
        selectedMenuVenue = resolvedVenue
        selectedMenuType = resolvedMenuType

        let signature = menuService.currentMenuSignature(for: resolvedVenue, menuType: resolvedMenuType)
        let shouldLoadMenu = menu(for: resolvedVenue, menuType: resolvedMenuType).lines.isEmpty
            || menuSignature(for: resolvedVenue, menuType: resolvedMenuType) != signature
            || menuLoadErrorsByVenue[resolvedVenue]?[resolvedMenuType] != nil

        if menuSignature(for: resolvedVenue, menuType: resolvedMenuType) != signature {
            setMenu(.empty, for: resolvedVenue, menuType: resolvedMenuType)
            setMenuError(nil, for: resolvedVenue, menuType: resolvedMenuType)
        }

        isMenuLoading = shouldLoadMenu

        if shouldLoadMenu {
            Task {
                await loadMenuFromFirebase(for: resolvedVenue, menuType: resolvedMenuType)
            }
        }
    }

    @MainActor
    private func loadMenuFromFirebase(
        for venue: DiningVenue? = nil,
        menuType: NutrisliceMenuService.MenuType? = nil,
        showLoadingIndicator: Bool = true
    ) async {
        let venue = venue ?? selectedMenuVenue
        let menuType = menuType ?? selectedMenuType
        let shouldDriveLoadingIndicator = showLoadingIndicator && venue == selectedMenuVenue && menuType == selectedMenuType
        if shouldDriveLoadingIndicator {
            isMenuLoading = true
        }
        setMenuError(nil, for: venue, menuType: menuType)
        do {
            let menu = try await menuService.fetchTodayMenu(for: venue, menuType: menuType)
            setMenu(menu, for: venue, menuType: menuType)
            setMenuSignature(menuService.currentMenuSignature(for: venue, menuType: menuType), for: venue, menuType: menuType)
            setMenuQuantities([:], for: venue, menuType: menuType)
            setMenuMultipliers([:], for: venue, menuType: menuType)
            saveVenueMenus()
        } catch {
            if let nutrisliceError = error as? NutrisliceMenuError {
                switch nutrisliceError {
                case .noMenuAvailable, .unavailableAtThisTime:
                    setMenu(.empty, for: venue, menuType: menuType)
                    setMenuError(nil, for: venue, menuType: menuType)
                default:
                    setMenuError(nutrisliceError.errorDescription ?? nutrisliceError.localizedDescription, for: venue, menuType: menuType)
                    setMenu(.empty, for: venue, menuType: menuType)
                }
            } else {
                setMenuError((error as? LocalizedError)?.errorDescription ?? error.localizedDescription, for: venue, menuType: menuType)
                setMenu(.empty, for: venue, menuType: menuType)
            }
            setMenu(.empty, for: venue, menuType: menuType)
            setMenuQuantities([:], for: venue, menuType: menuType)
            setMenuMultipliers([:], for: venue, menuType: menuType)
        }
        saveVenueMenus()
        if shouldDriveLoadingIndicator {
            isMenuLoading = false
        }
    }

    @MainActor
    private func preloadMenuForNutrientDiscovery() async {
        let combos = DiningVenue.allCases.flatMap { venue in
            menuService.allMenuTypes
                .filter { venue.supportedMenuTypes.contains($0) }
                .map { (venue, $0) }
        }

        for (venue, menuType) in combos {
            let currentSignature = menuService.currentMenuSignature(for: venue, menuType: menuType)
            let existingMenu = menu(for: venue, menuType: menuType)
            let lastSignature = menuSignature(for: venue, menuType: menuType)
            guard existingMenu.lines.isEmpty || lastSignature != currentSignature else {
                continue
            }

            await loadMenuFromFirebase(for: venue, menuType: menuType, showLoadingIndicator: false)
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
            selectedMenuType = menuService.currentMenuType()
            saveVenueMenus()
            syncHistorySelection(preferToday: true)
        }

        if forceMenuReload {
            venueMenus = [:]
            lastLoadedMenuSignatureByVenue = [:]
            menuLoadErrorsByVenue = [:]
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

        let quantities = menuQuantities(for: selectedMenuVenue, menuType: selectedMenuType)
        let multipliers = menuMultipliers(for: selectedMenuVenue, menuType: selectedMenuType)
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
                        mealGroup: mealGroup(for: selectedMenuType)
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

        setMenuQuantities([:], for: selectedMenuVenue, menuType: selectedMenuType)
        setMenuMultipliers([:], for: selectedMenuVenue, menuType: selectedMenuType)
        isMenuSheetPresented = false
        showAddConfirmation()
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

    private func analyzeAIFoodPhoto(_ imageData: Data) {
        isAIFoodPhotoLoading = true
        aiFoodPhotoErrorMessage = nil

        Task {
            do {
                let service = AIFoodPhotoService()
                let result = try await service.analyze(imageData: imageData)
                await MainActor.run {
                    handleAIFoodPhotoResult(result)
                    isAIFoodPhotoLoading = false
                }
            } catch {
                await MainActor.run {
                    aiFoodPhotoErrorMessage = error.localizedDescription
                    isAIFoodPhotoLoading = false
                }
            }
        }
    }

    private func analyzeAITextMeal() {
        let mealText = aiMealTextInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !mealText.isEmpty else {
            aiTextErrorMessage = "Enter what you ate."
            return
        }

        dismissKeyboard()
        isAITextLoading = true
        aiTextErrorMessage = nil
        aiTextMealResults = []

        Task {
            do {
                let result = try await aiTextMealService.analyze(mealText: mealText)
                await MainActor.run {
                    isAITextLoading = false
                    if result.items.isEmpty {
                        aiTextErrorMessage = "AI could not find any foods from that text."
                    } else {
                        aiTextMealResults = result.items
                        presentAITextPlateResults()
                        Haptics.selection()
                    }
                }
            } catch {
                await MainActor.run {
                    isAITextLoading = false
                    aiTextErrorMessage = error.localizedDescription
                }
            }
        }
    }

    private func isAmbiguousAIServingUnit(_ unit: String) -> Bool {
        let normalized = unit.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty
            || normalized == "serving"
            || normalized == "servings"
            || normalized == "each"
            || normalized == "ea"
            || normalized == "item"
            || normalized == "items"
            || normalized == "portion"
            || normalized == "portions"
    }

    private func isLikelyCountServingUnit(name: String, unit: String) -> Bool {
        let normalizedUnit = unit.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let countUnits: Set<String> = [
            "piece", "pieces",
            "slice", "slices",
            "nugget", "nuggets",
            "sandwich", "sandwiches",
            "burger", "burgers",
            "taco", "tacos",
            "burrito", "burritos",
            "wrap", "wraps",
            "quesadilla", "quesadillas",
            "cookie", "cookies",
            "chip", "chips"
        ]
        if countUnits.contains(normalizedUnit) { return true }
        return normalizedName.contains("nugget")
            || normalizedName.contains("quesadilla")
            || normalizedName.contains("sandwich")
            || normalizedName.contains("burger")
            || normalizedName.contains("taco")
            || normalizedName.contains("burrito")
            || normalizedName.contains("wrap")
            || normalizedName.contains("cookie")
            || normalizedName.contains("chips")
            || normalizedName.hasSuffix(" chip")
    }

    private struct AICountServingNormalization {
        let servingAmount: Double
        let servingUnit: String
        let estimatedServings: Double
        let consumedItemCount: Double?
    }

    private func inferredCountUnitFromName(_ name: String) -> String? {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalizedName.contains("nugget") { return "nuggets" }
        if normalizedName.contains("quesadilla") { return "quesadillas" }
        if normalizedName.contains("sandwich") { return "sandwiches" }
        if normalizedName.contains("burger") { return "burgers" }
        if normalizedName.contains("taco") { return "tacos" }
        if normalizedName.contains("burrito") { return "burritos" }
        if normalizedName.contains("wrap") { return "wraps" }
        if normalizedName.contains("slice") { return "slices" }
        if normalizedName.contains("cookie") { return "cookies" }
        if normalizedName.contains("chip") || normalizedName.contains("chips") { return "chips" }
        return nil
    }

    private func normalizedCountServingForAIItem(
        name: String,
        servingAmount: Double,
        servingUnit: String,
        servingItemsCount: Double?,
        estimatedServings: Double,
        estimatedItemCount: Double?
    ) -> AICountServingNormalization {
        let safeServingAmount = max(servingAmount, 1)
        let safeEstimatedServings = max(min(estimatedServings, 100), 0.01)
        let safeServingItemsCount = (servingItemsCount ?? 0) > 0 ? servingItemsCount : nil
        let safeEstimatedItemCount = (estimatedItemCount ?? 0) > 0 ? estimatedItemCount : nil
        let likelyCountBased = isLikelyCountServingUnit(name: name, unit: servingUnit)

        guard likelyCountBased else {
            return AICountServingNormalization(
                servingAmount: safeServingAmount,
                servingUnit: servingUnit,
                estimatedServings: safeEstimatedServings,
                consumedItemCount: nil
            )
        }

        var normalizedServingAmount = safeServingItemsCount ?? safeServingAmount
        var normalizedServingUnit = servingUnit
        if isAmbiguousAIServingUnit(normalizedServingUnit), let inferredUnit = inferredCountUnitFromName(name) {
            normalizedServingUnit = inferredUnit
        }

        let consumedCount: Double
        if let explicitConsumedCount = safeEstimatedItemCount {
            consumedCount = explicitConsumedCount
        } else {
            consumedCount = max(normalizedServingAmount * safeEstimatedServings, 0.01)
        }

        if normalizedServingAmount <= 0 {
            normalizedServingAmount = 1
        }

        return AICountServingNormalization(
            servingAmount: normalizedServingAmount,
            servingUnit: normalizedServingUnit,
            estimatedServings: safeEstimatedServings,
            consumedItemCount: consumedCount
        )
    }

    private func normalizedEstimatedServingsForCountItems(
        name: String,
        servingAmount: Double,
        servingUnit: String,
        estimatedServings: Double
    ) -> Double {
        let safeEstimated = max(min(estimatedServings, 100), 0.01)
        let safeServingAmount = max(servingAmount, 1)
        guard safeServingAmount > 1 else { return safeEstimated }
        guard isLikelyCountServingUnit(name: name, unit: servingUnit) else { return safeEstimated }

        // Guard against AI returning total piece count (e.g. 5 nuggets) as servings.
        let roundedEstimate = safeEstimated.rounded()
        let looksIntegerCount = abs(safeEstimated - roundedEstimate) <= 0.05
        if looksIntegerCount && safeEstimated + 0.05 >= safeServingAmount {
            return max(safeEstimated / safeServingAmount, 0.01)
        }
        return safeEstimated
    }

    private func presentAITextPlateResults() {
        guard !aiTextMealResults.isEmpty else { return }

        let normalizedItems = aiTextMealResults.map {
            normalizedCountServingForAIItem(
                name: $0.name,
                servingAmount: $0.servingAmount,
                servingUnit: $0.servingUnit,
                servingItemsCount: $0.servingItemsCount,
                estimatedServings: $0.estimatedServings,
                estimatedItemCount: $0.estimatedItemCount
            )
        }

        let menuItems = zip(aiTextMealResults.enumerated(), normalizedItems).map { pair -> MenuItem in
            let (indexedItem, normalized) = pair
            let (index, item) = indexedItem
            let cleanedNutrients = NutrientCatalog.acceptedImportedNutrientValues(item.nutrients)
            let calories = max(item.calories, cleanedNutrients["calories"] ?? 0)
            let protein = max(item.protein, cleanedNutrients["g_protein"] ?? 0)
            var nutrientValues = cleanedNutrients
            nutrientValues.removeValue(forKey: "calories")
            if protein > 0, nutrientValues["g_protein"] == nil {
                nutrientValues["g_protein"] = protein
            }
            return MenuItem(
                id: "ai-text-\(index)-\(UUID().uuidString)",
                name: item.name,
                calories: calories,
                nutrientValues: nutrientValues,
                servingAmount: normalized.servingAmount,
                servingUnit: normalized.servingUnit,
                calorieSource: item.sourceType == "real" ? .web : .estimated
            )
        }

        var ozById: [String: Double] = [:]
        var baseOzById: [String: Double] = [:]
        for ((menuItem, aiItem), normalized) in zip(zip(menuItems, aiTextMealResults), normalizedItems) {
            let estimatedServings = normalizedEstimatedServingsForCountItems(
                name: aiItem.name,
                servingAmount: normalized.servingAmount,
                servingUnit: normalized.servingUnit,
                estimatedServings: normalized.estimatedServings
            )
            if menuItem.isCountBased {
                let consumedCount = normalized.consumedItemCount ?? max(normalized.servingAmount * estimatedServings, 0.01)
                ozById[menuItem.id] = max(consumedCount, 0.25)
            } else if isAmbiguousAIServingUnit(menuItem.servingUnit) {
                // For ambiguous AI units (serving/each/item), treat estimatedServings as direct serving count.
                baseOzById[menuItem.id] = 1.0
                ozById[menuItem.id] = max(estimatedServings, 0.01)
            } else {
                let baseOz = menuItem.servingOzForPortions
                baseOzById[menuItem.id] = baseOz
                ozById[menuItem.id] = max(baseOz * estimatedServings, 0.01)
            }
        }

        aiTextPlateItems = menuItems
        aiTextOzByItemId = ozById
        aiTextBaseOzByItemId = baseOzById
    }

    @MainActor
    private func handleAIFoodPhotoResult(_ result: AIFoodPhotoAnalysisResult) {
        func makeAIPhotoMenuItem(
            _ item: AIFoodPhotoAnalysisResult.Item,
            normalized: AICountServingNormalization,
            index: Int
        ) -> MenuItem {
            let cleanedNutrients = NutrientCatalog.acceptedImportedNutrientValues(item.nutrients)
            let calories = max(item.calories, cleanedNutrients["calories"] ?? 0)
            let protein = max(item.protein, cleanedNutrients["g_protein"] ?? 0)
            var nutrientValues = cleanedNutrients
            nutrientValues.removeValue(forKey: "calories")
            if protein > 0, nutrientValues["g_protein"] == nil {
                nutrientValues["g_protein"] = protein
            }
            return MenuItem(
                id: "ai-photo-\(index)-\(UUID().uuidString)",
                name: item.name,
                calories: calories,
                nutrientValues: nutrientValues,
                servingAmount: normalized.servingAmount,
                servingUnit: normalized.servingUnit,
                calorieSource: item.sourceType == .real ? .web : .estimated
            )
        }

        switch result.mode {
        case .foodPhoto:
            guard let firstItem = result.items.first else {
                aiFoodPhotoErrorMessage = "AI did not find any foods."
                return
            }

            if result.items.count == 1 {
                let normalized = normalizedCountServingForAIItem(
                    name: firstItem.name,
                    servingAmount: firstItem.servingAmount,
                    servingUnit: firstItem.servingUnit,
                    servingItemsCount: firstItem.servingItemsCount,
                    estimatedServings: firstItem.estimatedServings,
                    estimatedItemCount: firstItem.estimatedItemCount
                )
                let menuItem = makeAIPhotoMenuItem(firstItem, normalized: normalized, index: 0)

                aiPhotoOzByItemId = [:]
                aiPhotoBaseOzByItemId = [:]
                let estimatedServings = normalizedEstimatedServingsForCountItems(
                    name: firstItem.name,
                    servingAmount: normalized.servingAmount,
                    servingUnit: normalized.servingUnit,
                    estimatedServings: normalized.estimatedServings
                )
                if menuItem.isCountBased {
                    let consumedCount = normalized.consumedItemCount ?? max(normalized.servingAmount * estimatedServings, 0.01)
                    aiPhotoOzByItemId[menuItem.id] = max(consumedCount, 0.25)
                } else if isAmbiguousAIServingUnit(menuItem.servingUnit) {
                    aiPhotoBaseOzByItemId[menuItem.id] = 1.0
                    aiPhotoOzByItemId[menuItem.id] = max(estimatedServings, 0.01)
                } else {
                    let baseOz = menuItem.servingOzForPortions
                    aiPhotoBaseOzByItemId[menuItem.id] = baseOz
                    aiPhotoOzByItemId[menuItem.id] = max(baseOz * estimatedServings, 0.01)
                }
                aiPhotoItems = [menuItem]
                return
            }

            let normalizedItems = result.items.map {
                normalizedCountServingForAIItem(
                    name: $0.name,
                    servingAmount: $0.servingAmount,
                    servingUnit: $0.servingUnit,
                    servingItemsCount: $0.servingItemsCount,
                    estimatedServings: $0.estimatedServings,
                    estimatedItemCount: $0.estimatedItemCount
                )
            }

            let menuItems = zip(result.items.enumerated(), normalizedItems).map { pair in
                let (indexedItem, normalized) = pair
                let (index, item) = indexedItem
                return makeAIPhotoMenuItem(item, normalized: normalized, index: index)
            }

            var ozById: [String: Double] = [:]
            var baseOzById: [String: Double] = [:]
            for ((menuItem, aiItem), normalized) in zip(zip(menuItems, result.items), normalizedItems) {
                let estimatedServings = normalizedEstimatedServingsForCountItems(
                    name: aiItem.name,
                    servingAmount: normalized.servingAmount,
                    servingUnit: normalized.servingUnit,
                    estimatedServings: normalized.estimatedServings
                )
                if menuItem.isCountBased {
                    let consumedCount = normalized.consumedItemCount ?? max(normalized.servingAmount * estimatedServings, 0.01)
                    ozById[menuItem.id] = max(consumedCount, 0.25)
                } else if isAmbiguousAIServingUnit(menuItem.servingUnit) {
                    baseOzById[menuItem.id] = 1.0
                    ozById[menuItem.id] = max(estimatedServings, 0.01)
                } else {
                    let baseOz = menuItem.servingOzForPortions
                    baseOzById[menuItem.id] = baseOz
                    ozById[menuItem.id] = max(baseOz * estimatedServings, 0.01)
                }
            }

            aiPhotoItems = menuItems
            aiPhotoOzByItemId = ozById
            aiPhotoBaseOzByItemId = baseOzById

        case .nutritionLabel:
            guard let item = result.items.first else {
                aiFoodPhotoErrorMessage = "AI could not read the nutrition label."
                return
            }

            let nutrientValues = NutrientCatalog.acceptedImportedNutrientValues(item.nutrients)
            let displayedKeys = trackedNutrientKeys
                .map { $0.lowercased() }
                .filter { nutrientValues[$0] != nil }
            presentFoodReview(
                FoodReviewItem(
                    name: item.name,
                    subtitle: "AI nutrition label scan",
                    calories: item.calories,
                    nutrientValues: nutrientValues,
                    servingAmount: item.servingAmount,
                    servingUnit: item.servingUnit,
                    entrySource: .aiNutritionLabel,
                    displayedNutrientKeys: displayedKeys
                ),
                initialMultiplier: 1.0
            )
        }
    }

    private func clearAIPhotoMultiItemState() {
        aiPhotoItems = nil
        aiPhotoOzByItemId = [:]
        aiPhotoBaseOzByItemId = [:]
    }

    private func clearAITextPlateState() {
        aiTextPlateItems = nil
        aiTextOzByItemId = [:]
        aiTextBaseOzByItemId = [:]
    }

    private func addAIPhotoItemsWithPortions(_ pairs: [(item: MenuItem, oz: Double, baseOz: Double)]) {
        let now = Date()
        let mealGrp = genericMealGroup(for: now)
        let newEntries = pairs.map { pair -> MealEntry in
            let multiplier: Double
            if pair.item.isCountBased {
                let baseCount = max(pair.item.servingAmount, 1)
                multiplier = pair.oz / baseCount
            } else {
                multiplier = pair.baseOz > 0 ? (pair.oz / pair.baseOz) : 1.0
            }
            let scaledNutrients = pair.item.nutrientValues.mapValues { Int((Double($0) * multiplier).rounded()) }
            let scaledCalories = Int((Double(pair.item.calories) * multiplier).rounded())
            return MealEntry(
                id: UUID(),
                name: pair.item.name,
                calories: scaledCalories,
                nutrientValues: scaledNutrients,
                createdAt: now,
                mealGroup: mealGrp
            )
        }

        guard !newEntries.isEmpty else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            entries.append(contentsOf: newEntries)
        }
        showAddConfirmation()
    }

    private func addAITextItemsWithPortions(_ pairs: [(item: MenuItem, oz: Double, baseOz: Double)]) {
        let now = Date()
        let mealGrp = genericMealGroup(for: now)
        let newEntries = pairs.map { pair -> MealEntry in
            let multiplier: Double
            if pair.item.isCountBased {
                let baseCount = max(pair.item.servingAmount, 1)
                multiplier = pair.oz / baseCount
            } else {
                multiplier = pair.baseOz > 0 ? (pair.oz / pair.baseOz) : 1.0
            }

            let scaledNutrients = pair.item.nutrientValues.mapValues { Int((Double($0) * multiplier).rounded()) }
            let scaledCalories = Int((Double(pair.item.calories) * multiplier).rounded())
            return MealEntry(
                id: UUID(),
                name: MealEntry.normalizedName(pair.item.name),
                calories: scaledCalories,
                nutrientValues: scaledNutrients,
                createdAt: now,
                mealGroup: mealGrp
            )
        }

        guard !newEntries.isEmpty else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            entries.append(contentsOf: newEntries)
        }
        Haptics.notification(.success)
        showAddConfirmation()
    }

    private func addMenuItemsWithPortions(_ pairs: [(item: MenuItem, oz: Double, baseOz: Double)]) {
        let now = Date()
        let mealGrp = mealGroup(for: selectedMenuType)
        var expandedSelections: [MealEntry] = []
        for (item, oz, baseOz) in pairs {
            let multiplier: Double
            if item.isCountBased {
                let baseCount = max(item.servingAmount, 1)
                multiplier = oz / baseCount
            } else {
                multiplier = baseOz > 0 ? (oz / baseOz) : 1.0
            }
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
        showAddConfirmation()
    }

    private func preferredMenuType(
        startingFrom menuType: NutrisliceMenuService.MenuType,
        for venue: DiningVenue
    ) -> NutrisliceMenuService.MenuType {
        if venue.supportedMenuTypes.contains(menuType) {
            return menuType
        }

        return menuService.allMenuTypes.first(where: { venue.supportedMenuTypes.contains($0) }) ?? .lunch
    }

    private func preferredMenuVenue(
        startingFrom venue: DiningVenue,
        menuType: NutrisliceMenuService.MenuType
    ) -> DiningVenue {
        if venue.supportedMenuTypes.contains(menuType) {
            return venue
        }

        if menuType == .breakfast {
            return .varsity
        }

        return DiningVenue.allCases.first(where: { $0.supportedMenuTypes.contains(menuType) }) ?? venue
    }

    private func openAddDestination(_ destination: AddDestination) {
        dismissKeyboard()
        if selectedAddDestination == .pccMenu, destination != .pccMenu {
            clearMenuSelection()
        }
        if destination != .aiPhoto {
            clearAITextMealState()
        }
        selectedAddDestination = destination
        isAddDestinationPickerPresented = false
        withAnimation(.none) {
            selectedTab = .add
        }

        switch destination {
        case .aiPhoto:
            aiFoodPhotoErrorMessage = nil
            aiTextErrorMessage = nil
        case .pccMenu:
            let shouldLoadMenu = prepareMenuDestination(for: .fourWinds)
            if shouldLoadMenu {
                Task {
                    await loadMenuFromFirebase(for: selectedMenuVenue)
                }
            }
        case .usdaSearch:
            usdaSearchError = nil
        case .barcode:
            hasScannedBarcodeInCurrentSheet = false
            barcodeLookupError = nil
        case .quickAdd, .manualEntry:
            break
        }
    }

    private func openBarcodeScannerFromPicker() {
        openAddDestination(.barcode)
        hasScannedBarcodeInCurrentSheet = false
        barcodeLookupError = nil
    }

    private func clearAITextMealState() {
        aiMealTextInput = ""
        aiTextMealResults = []
        aiTextErrorMessage = nil
        isAITextLoading = false
        clearAITextPlateState()
    }

    private func clearMenuSelection() {
        selectedMenuItemQuantitiesByVenue = [:]
        selectedMenuItemMultipliersByVenue = [:]
        selectedMenuType = menuService.currentMenuType()
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
            selectedFoodReviewMultiplier = 1.0
            DispatchQueue.main.async {
                openFoodReview(for: product)
            }
            Haptics.notification(.success)
        } catch {
            isBarcodeLookupInFlight = false
            hasScannedBarcodeInCurrentSheet = false
            barcodeLookupError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            showBarcodeErrorToast(barcodeLookupError ?? "Barcode lookup failed.")
            Haptics.notification(.warning)
        }
    }

    @MainActor
    private func performUSDASearch() async {
        let query = usdaSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else {
            latestFoodSearchRequestID += 1
            foodSearchResults = []
            isUSDASearchLoading = false
            usdaSearchError = nil
            return
        }

        latestFoodSearchRequestID += 1
        let requestID = latestFoodSearchRequestID
        isUSDASearchLoading = true
        usdaSearchError = nil

        do {
            let results = try await searchFoodsAcrossSources(query: query)
            guard requestID == latestFoodSearchRequestID else { return }
            foodSearchResults = results
            Haptics.selection()
        } catch {
            guard requestID == latestFoodSearchRequestID else { return }
            foodSearchResults = []
            if case USDAFoodError.noResults = error {
                usdaSearchError = nil
            } else {
                usdaSearchError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                Haptics.notification(.warning)
            }
        }

        if requestID == latestFoodSearchRequestID {
            isUSDASearchLoading = false
        }
    }

    private func searchFoodsAcrossSources(query: String) async throws -> [FoodSearchResult] {
        let merged = mergeAndRankSearchResults(
            usda: await searchUSDAResults(query: query),
            query: query
        )
        if merged.isEmpty {
            throw USDAFoodError.noResults
        }
        return merged
    }

    private func searchUSDAResults(query: String) async -> [USDAFoodSearchResult] {
        if disableUSDASearchForDebug {
            return []
        }
        do {
            return try await usdaFoodService.searchFoods(query: query)
        } catch {
            return []
        }
    }

    private func mergeAndRankSearchResults(
        usda: [USDAFoodSearchResult],
        query: String
    ) -> [FoodSearchResult] {
        let combined = usda.map(mapUSDAResult)
        var bestByKey: [String: (FoodSearchResult, Int)] = [:]

        for result in combined {
            let score = searchRelevanceScore(for: result, query: query)
            guard isSearchResultRelevant(result, query: query, score: score) else {
                continue
            }
            let key = normalizedSearchKey(name: result.name, brand: result.brand)
            if let existing = bestByKey[key], existing.1 >= score {
                continue
            }
            bestByKey[key] = (result, score)
        }

        return bestByKey.values
            .sorted {
                if $0.1 == $1.1 {
                    return $0.0.name.localizedCaseInsensitiveCompare($1.0.name) == .orderedAscending
                }
                return $0.1 > $1.1
            }
            .map(\.0)
            .prefix(25)
            .map { $0 }
    }

    private func mapUSDAResult(_ result: USDAFoodSearchResult) -> FoodSearchResult {
        FoodSearchResult(
            id: "usda-\(result.fdcId)",
            source: .usda,
            name: result.name,
            brand: result.brand,
            calories: result.calories,
            nutrientValues: result.nutrientValues,
            servingAmount: result.servingAmount,
            servingUnit: result.servingUnit,
            servingDescription: result.servingDescription
        )
    }

    private func searchRelevanceScore(for result: FoodSearchResult, query: String) -> Int {
        let normalizedQuery = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let name = result.name.lowercased()
        let brand = (result.brand ?? "").lowercased()
        let tokens = normalizedQuery.split(whereSeparator: \.isWhitespace).map(String.init)

        var score = 0
        if name == normalizedQuery { score += 140 }
        if name.hasPrefix(normalizedQuery) { score += 90 }
        if name.contains(normalizedQuery) { score += 60 }
        if !brand.isEmpty, brand.contains(normalizedQuery) { score += 24 }

        for token in tokens {
            if name.contains(token) { score += 22 }
            if !brand.isEmpty, brand.contains(token) { score += 10 }
        }

        if result.calories > 0 { score += 8 }
        if (result.nutrientValues["g_protein"] ?? 0) > 0 { score += 6 }
        return score
    }

    private func isSearchResultRelevant(_ result: FoodSearchResult, query: String, score: Int) -> Bool {
        let normalizedQuery = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalizedQuery.isEmpty else { return false }

        let name = result.name.lowercased()
        let brand = (result.brand ?? "").lowercased()
        let searchable = "\(name) \(brand)"
        if searchable.contains(normalizedQuery) {
            return true
        }

        let tokens = normalizedQuery.split(whereSeparator: \.isWhitespace).map(String.init)
        let longTokens = tokens.filter { $0.count >= 3 }
        let matchedLongTokenCount = longTokens.filter { searchable.contains($0) }.count

        switch result.source {
        case .usda:
            if longTokens.count <= 1 {
                return matchedLongTokenCount >= 1 && score >= 28
            }
            let requiredLongMatches = min(2, longTokens.count)
            return matchedLongTokenCount >= requiredLongMatches && score >= 34
        case .openFoodFacts:
            return matchedLongTokenCount >= 1 && score >= 20
        }
    }

    private func normalizedSearchKey(name: String, brand: String?) -> String {
        let normalizedName = name
            .lowercased()
            .components(separatedBy: .alphanumerics.inverted)
            .joined()
        let normalizedBrand = (brand ?? "")
            .lowercased()
            .components(separatedBy: .alphanumerics.inverted)
            .joined()
        return "\(normalizedName)|\(normalizedBrand)"
    }

    private func addReviewedFood(_ item: FoodReviewItem) {
        let multiplier = selectedFoodReviewEffectiveMultiplier
        let signature = foodReviewSliderSignature(for: item)
        let quantity = max(1, selectedFoodReviewQuantity)
        let editedName = MealEntry.normalizedName(foodReviewNameText)
        var scaledNutrients: [String: Int] = [:]
        for (key, value) in item.nutrientValues {
            scaledNutrients[key] = Int((Double(value) * multiplier).rounded())
        }

        let now = Date()
        let resolvedMealGroup = mealGroup(for: now, source: item.entrySource)
        let scaledCalories = Int((Double(item.calories) * multiplier).rounded())
        let newEntries = (0..<quantity).map { _ in
            MealEntry(
                id: UUID(),
                name: editedName,
                calories: scaledCalories,
                nutrientValues: scaledNutrients,
                createdAt: now,
                mealGroup: resolvedMealGroup
            )
        }

        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            entries.append(contentsOf: newEntries)
        }

        foodReviewItem = nil
        foodReviewNameText = ""
        foodReviewSliderBaselineBySignature[signature] = max(roundToServingSelectorIncrement(selectedFoodReviewBaselineAmount), 0)
        foodReviewSliderValueBySignature[signature] = min(max(selectedFoodReviewMultiplier, 0.25), 1.75)
        selectedFoodReviewMultiplier = 1.0
        selectedFoodReviewBaselineAmount = 1.0
        selectedFoodReviewAmountText = ""
        selectedFoodReviewQuantity = 1
        barcodeLookupError = nil
        usdaSearchError = nil
        showAddConfirmation()
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

    private func deleteEntries(_ entriesToDelete: [MealEntry]) {
        let idsToDelete = Set(entriesToDelete.map(\.id))
        guard !idsToDelete.isEmpty else { return }

        withAnimation(.easeInOut(duration: 0.2)) {
            entries.removeAll { idsToDelete.contains($0.id) }
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

    private func entryValue(for key: String, in entry: FoodLogDisplayEntry) -> Int {
        entry.nutrientValues[key] ?? 0
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

    private func loadCalibrationState() {
        guard
            !storedCalibrationStateData.isEmpty,
            let data = storedCalibrationStateData.data(using: .utf8),
            let decoded = try? JSONDecoder().decode(CalibrationState.self, from: data)
        else {
            calibrationState = .default
            return
        }
        calibrationState = decoded
    }

    private func saveCalibrationState() {
        guard let data = try? JSONEncoder().encode(calibrationState) else { return }
        storedCalibrationStateData = String(decoding: data, as: UTF8.self)
    }

    private func loadHealthWeighIns() {
        guard
            !storedHealthWeighInsData.isEmpty,
            let data = storedHealthWeighInsData.data(using: .utf8),
            let decoded = try? JSONDecoder().decode([HealthWeighInDay].self, from: data)
        else {
            healthWeighIns = []
            return
        }
        healthWeighIns = decoded
    }

    private func saveHealthWeighIns() {
        guard let data = try? JSONEncoder().encode(healthWeighIns) else { return }
        storedHealthWeighInsData = String(decoding: data, as: UTF8.self)
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

    private func scheduleCalibrationEvaluation(force: Bool = false) {
        guard calibrationState.isEnabled else { return }
        guard healthKitService.authorizationState == .connected else { return }
        if !force, let last = lastCalibrationEvaluationAt, Date().timeIntervalSince(last) < 60 * 60 * 6 {
            return
        }

        calibrationEvaluationTask?.cancel()
        calibrationEvaluationTask = Task(priority: .utility) {
            let reducedWeights = await healthKitService.fetchReducedBodyMassHistory(days: 21)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                lastCalibrationEvaluationAt = Date()
                healthWeighIns = reducedWeights
                saveHealthWeighIns()
                evaluateWeeklyCalibrationIfNeeded(referenceDate: Date())
            }
        }
    }

    private func evaluateWeeklyCalibrationIfNeeded(referenceDate: Date) {
        guard calibrationState.isEnabled else { return }
        let weekID = calibrationWeekID(for: referenceDate)
        if calibrationState.lastAppliedWeekID == weekID {
            return
        }

        let currentWeekIDs = trailingDayIdentifiers(endingAt: referenceDate, count: 7, endingOffsetDays: 0)
        let priorWeekIDs = trailingDayIdentifiers(endingAt: referenceDate, count: 7, endingOffsetDays: 7)
        guard currentWeekIDs.count == 7, priorWeekIDs.count == 7 else {
            markCalibrationSkipped(reason: "Unable to build weekly windows.")
            return
        }

        let combinedDayIDs = priorWeekIDs + currentWeekIDs
        let weightByDay = Dictionary(uniqueKeysWithValues: healthWeighIns.map { ($0.dayIdentifier, $0.representativePounds) })
        let spikeExcludedDays = spikeExcludedDayIDs(orderedDayIDs: combinedDayIDs, weightByDay: weightByDay)

        let validPriorWeights = priorWeekIDs.compactMap { dayID -> Double? in
            guard !spikeExcludedDays.contains(dayID) else { return nil }
            return weightByDay[dayID]
        }
        let validCurrentWeights = currentWeekIDs.compactMap { dayID -> Double? in
            guard !spikeExcludedDays.contains(dayID) else { return nil }
            return weightByDay[dayID]
        }
        guard validPriorWeights.count >= 5 else {
            markCalibrationSkipped(reason: "Need at least 5 valid Health weigh-ins in the prior week.")
            return
        }
        guard validCurrentWeights.count >= 5 else {
            markCalibrationSkipped(reason: "Need at least 5 valid Health weigh-ins in the current week.")
            return
        }

        let intakeLoggedDays = currentWeekIDs.filter { dailyCalories(for: $0) > 0 }.count
        let intakeCompleteness = Double(intakeLoggedDays) / 7.0
        guard intakeCompleteness >= 0.85 else {
            markCalibrationSkipped(reason: "Intake logging is below 85% for the week.")
            return
        }

        let currentWeekBaselineBurns = currentWeekIDs.map { burnedBaselineForCalibration(dayIdentifier: $0) }
        let missingBurnDays = currentWeekBaselineBurns.filter { $0 == nil }.count
        guard missingBurnDays <= 2 else {
            markCalibrationSkipped(reason: "Burn baseline is missing for too many days this week.")
            return
        }

        let wPrev = validPriorWeights.reduce(0, +) / Double(validPriorWeights.count)
        let wCurr = validCurrentWeights.reduce(0, +) / Double(validCurrentWeights.count)
        let jumpLimit = max(wPrev * 0.025, 0.01)
        guard abs(wCurr - wPrev) <= jumpLimit else {
            markCalibrationSkipped(reason: "Week-over-week average weight jump exceeded 2.5%.")
            return
        }

        let fallbackBurn = {
            let available = currentWeekBaselineBurns.compactMap { $0 }
            if available.isEmpty { return ContentView.fallbackAverageBMR }
            let avg = Double(available.reduce(0, +)) / Double(available.count)
            return max(Int(avg.rounded()), 1)
        }()

        let predictedDeltaKcal = currentWeekIDs.reduce(0.0) { partial, dayID in
            let intake = Double(dailyCalories(for: dayID))
            let burned = Double(burnedBaselineForCalibration(dayIdentifier: dayID) ?? fallbackBurn)
            return partial + (intake - burned)
        }
        let actualDeltaKcal = (wCurr - wPrev) * 3500.0
        let dailyError = (actualDeltaKcal - predictedDeltaKcal) / 7.0

        var recentErrors = calibrationState.recentDailyErrors
        recentErrors.append(dailyError)
        if recentErrors.count > 4 {
            recentErrors = Array(recentErrors.suffix(4))
        }

        let isFastStart = calibrationState.appliedWeekCount < 3
        let adjustmentParams = calibrationAdjustmentParameters(recentErrors: recentErrors, isFastStart: isFastStart)
        let smoothedDailyError = clamp(
            weightedErrorMean(recentErrors),
            lower: -adjustmentParams.errorClamp,
            upper: adjustmentParams.errorClamp
        )
        // Invert correction sign: positive error implies burn was overestimated, so offset must decrease.
        let offsetStep = clamp(
            (-smoothedDailyError) * adjustmentParams.alpha,
            lower: -adjustmentParams.maxStep,
            upper: adjustmentParams.maxStep
        )
        let newOffset = Int(
            clamp(
                Double(calibrationState.calibrationOffsetCalories) + offsetStep,
                lower: -adjustmentParams.offsetLimit,
                upper: adjustmentParams.offsetLimit
            ).rounded()
        )

        calibrationState.calibrationOffsetCalories = newOffset
        calibrationState.recentDailyErrors = recentErrors
        calibrationState.appliedWeekCount += 1
        calibrationState.lastAppliedWeekID = weekID
        calibrationState.lastRunDate = Date()
        calibrationState.lastRunStatus = .applied
        calibrationState.lastSkipReason = nil
        calibrationState.dataQualityChecks += 1
        calibrationState.dataQualityPasses += 1
        saveCalibrationState()
        syncCurrentDayGoalArchive()
    }

    private func markCalibrationSkipped(reason: String) {
        calibrationState.lastRunDate = Date()
        calibrationState.lastRunStatus = .skipped
        calibrationState.lastSkipReason = reason
        calibrationState.dataQualityChecks += 1
        saveCalibrationState()
    }

    private func burnedBaselineForCalibration(dayIdentifier: String) -> Int? {
        if dayIdentifier == todayDayIdentifier {
            return currentDailyCalorieModel.burnedBaseline
        }
        guard let burned = dailyBurnedCalorieArchive[dayIdentifier] else { return nil }
        let effectiveOffset = calibrationState.isEnabled ? calibrationState.calibrationOffsetCalories : 0
        return max(burned - effectiveOffset, 1)
    }

    private func trailingDayIdentifiers(endingAt referenceDate: Date, count: Int, endingOffsetDays: Int) -> [String] {
        guard count > 0 else { return [] }
        let referenceDay = centralCalendar.startOfDay(for: referenceDate)
        guard let endingDay = centralCalendar.date(byAdding: .day, value: -endingOffsetDays, to: referenceDay) else {
            return []
        }

        return (0..<count).compactMap { index in
            let offset = -(count - 1 - index)
            guard let day = centralCalendar.date(byAdding: .day, value: offset, to: endingDay) else { return nil }
            return centralDayIdentifier(for: day)
        }
    }

    private func spikeExcludedDayIDs(orderedDayIDs: [String], weightByDay: [String: Double]) -> Set<String> {
        guard orderedDayIDs.count > 1 else { return [] }
        var excluded: Set<String> = []
        for index in 1..<orderedDayIDs.count {
            let previous = orderedDayIDs[index - 1]
            let current = orderedDayIDs[index]
            guard let previousWeight = weightByDay[previous], let currentWeight = weightByDay[current] else {
                continue
            }
            if abs(currentWeight - previousWeight) > 4.0 {
                excluded.insert(current)
            }
        }
        return excluded
    }

    private func weightedErrorMean(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let trimmed = Array(values.suffix(Self.calibrationErrorWeights.count))
        let weights = Array(Self.calibrationErrorWeights.suffix(trimmed.count))
        let weightedSum = zip(trimmed, weights).reduce(0.0) { partial, element in
            partial + (element.0 * element.1)
        }
        let totalWeight = weights.reduce(0, +)
        guard totalWeight > 0 else { return 0 }
        return weightedSum / totalWeight
    }

    private struct CalibrationAdjustmentParameters {
        let errorClamp: Double
        let alpha: Double
        let maxStep: Double
        let offsetLimit: Double
    }

    private func calibrationAdjustmentParameters(recentErrors: [Double], isFastStart: Bool) -> CalibrationAdjustmentParameters {
        let defaultParams = CalibrationAdjustmentParameters(
            errorClamp: 100,
            alpha: isFastStart ? 0.5 : 0.2,
            maxStep: isFastStart ? 60 : 40,
            offsetLimit: 300
        )

        let trailing = Array(recentErrors.suffix(3))
        guard trailing.count == 3 else { return defaultParams }

        let signs = trailing.map { value -> Int in
            if value > 0 { return 1 }
            if value < 0 { return -1 }
            return 0
        }
        guard let firstSign = signs.first, firstSign != 0, signs.allSatisfy({ $0 == firstSign }) else {
            return defaultParams
        }

        let absErrors = trailing.map { abs($0) }
        guard absErrors.allSatisfy({ $0 >= 250 }) else { return defaultParams }

        let meanAbs = absErrors.reduce(0, +) / Double(absErrors.count)
        let intensity = clamp((meanAbs - 250) / 600 + 1, lower: 1, upper: 2)

        return CalibrationAdjustmentParameters(
            errorClamp: 100 * intensity,
            alpha: (isFastStart ? 0.5 : 0.2) + (isFastStart ? 0.1 : 0.15) * (intensity - 1),
            maxStep: (isFastStart ? 60 : 40) * intensity,
            offsetLimit: 300 + (300 * (intensity - 1))
        )
    }

    private func calibrationWeekID(for date: Date) -> String {
        let components = centralCalendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        let year = components.yearForWeekOfYear ?? 0
        let week = components.weekOfYear ?? 0
        return String(format: "%04d-W%02d", year, week)
    }

    private func nextCalibrationRunDate(from date: Date) -> Date? {
        let startOfDay = centralCalendar.startOfDay(for: date)
        guard let startOfWeek = centralCalendar.dateInterval(of: .weekOfYear, for: startOfDay)?.start else {
            return nil
        }
        return centralCalendar.date(byAdding: .day, value: 7, to: startOfWeek)
    }

    private func clamp(_ value: Double, lower: Double, upper: Double) -> Double {
        min(max(value, lower), upper)
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

    private func presentFoodReview(_ item: FoodReviewItem, initialMultiplier: Double = 1.0) {
        let baseAmount = convertedServingAmount(item.servingAmount, unit: item.servingUnit)
        let signature = foodReviewSliderSignature(for: item)
        if let savedBaseline = foodReviewSliderBaselineBySignature[signature],
           let savedSliderValue = foodReviewSliderValueBySignature[signature] {
            selectedFoodReviewBaselineAmount = max(roundToServingSelectorIncrement(savedBaseline), 0)
            selectedFoodReviewMultiplier = min(max(savedSliderValue, 0.25), 1.75)
        } else {
            selectedFoodReviewBaselineAmount = max(roundToServingSelectorIncrement(baseAmount * initialMultiplier), 0)
            selectedFoodReviewMultiplier = 1.0
        }
        selectedFoodReviewAmountText = formattedServingAmount(selectedFoodReviewBaselineAmount * selectedFoodReviewMultiplier)
        selectedFoodReviewQuantity = 1
        foodReviewNameText = item.name
        foodReviewItem = item
    }

    private func foodReviewSliderSignature(for item: FoodReviewItem) -> String {
        let normalizedName = MealEntry.normalizedName(item.name).lowercased()
        let normalizedSubtitle = MealEntry.normalizedName(item.subtitle ?? "").lowercased()
        let unit = item.servingUnit.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let sourceKey: String
        switch item.entrySource {
        case .manual:
            sourceKey = "manual"
        case .quickAdd:
            sourceKey = "quickAdd"
        case .barcode:
            sourceKey = "barcode"
        case .usda:
            sourceKey = "usda"
        case .aiFoodPhoto:
            sourceKey = "aiFoodPhoto"
        case .aiNutritionLabel:
            sourceKey = "aiNutritionLabel"
        case .aiText:
            sourceKey = "aiText"
        case .pccMenu(let menuType):
            sourceKey = "pccMenu:\(menuType.rawValue)"
        }
        let roundedServing = roundToServingSelectorIncrement(convertedServingAmount(item.servingAmount, unit: item.servingUnit))
        let servingKey = String(format: "%.4f", roundedServing)
        return "\(sourceKey)|\(normalizedName)|\(normalizedSubtitle)|\(servingKey)|\(unit)"
    }

    private func syncFoodReviewAmountText() {
        let amount = formattedServingAmount(selectedFoodReviewBaselineAmount * selectedFoodReviewMultiplier)
        if selectedFoodReviewAmountText != amount {
            isUpdatingFoodReviewTextFromSlider = true
            selectedFoodReviewAmountText = amount
        }
    }

    private func applyTypedFoodReviewAmountIfPossible(text: String) {
        if isUpdatingFoodReviewTextFromSlider {
            isUpdatingFoodReviewTextFromSlider = false
            return
        }
        guard let typedAmount = parsedDecimalAmount(text), typedAmount >= 0 else { return }
        let roundedTypedAmount = roundToServingSelectorIncrement(typedAmount)
        let currentAmount = roundToServingSelectorIncrement(selectedFoodReviewBaselineAmount * selectedFoodReviewMultiplier)
        if abs(roundedTypedAmount - currentAmount) > 0.0005 {
            selectedFoodReviewBaselineAmount = roundedTypedAmount
            selectedFoodReviewMultiplier = 1.0
        }
    }

    private func parsedDecimalAmount(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
    }

    private func openFoodReview(for product: OpenFoodFactsProduct) {
        presentFoodReview(
            FoodReviewItem(
            name: product.name,
            subtitle: product.brand,
            calories: product.calories,
            nutrientValues: product.nutrientValues,
            servingAmount: product.servingAmount,
            servingUnit: product.servingUnit,
            entrySource: .barcode,
            displayedNutrientKeys: nil
        )
        )
    }

    private func openFoodReview(for result: USDAFoodSearchResult) {
        isUSDASearchPresented = false
        dismissKeyboard()
        DispatchQueue.main.async {
            presentFoodReview(
                FoodReviewItem(
                name: result.name,
                subtitle: result.brand,
                calories: result.calories,
                nutrientValues: result.nutrientValues,
                servingAmount: result.servingAmount,
                servingUnit: result.servingUnit,
                entrySource: .usda,
                displayedNutrientKeys: nil
            )
            )
        }
    }

    private func openFoodReview(for result: FoodSearchResult) {
        isUSDASearchPresented = false
        dismissKeyboard()
        let source: EntrySource
        switch result.source {
        case .usda:
            source = .usda
        case .openFoodFacts:
            source = .barcode
        }
        DispatchQueue.main.async {
            presentFoodReview(
                FoodReviewItem(
                    name: result.name,
                    subtitle: result.brand,
                    calories: result.calories,
                    nutrientValues: result.nutrientValues,
                    servingAmount: result.servingAmount,
                    servingUnit: result.servingUnit,
                    entrySource: source,
                    displayedNutrientKeys: nil
                )
            )
        }
    }

    private func openFoodReview(for item: AITextMealAnalysisResult.Item) {
        let normalizedCountServing = normalizedCountServingForAIItem(
            name: item.name,
            servingAmount: item.servingAmount,
            servingUnit: item.servingUnit,
            servingItemsCount: item.servingItemsCount,
            estimatedServings: item.estimatedServings,
            estimatedItemCount: item.estimatedItemCount
        )
        let cleanedNutrients = NutrientCatalog.acceptedImportedNutrientValues(item.nutrients)
        let calories = max(item.calories, cleanedNutrients["calories"] ?? 0)
        let protein = max(item.protein, cleanedNutrients["g_protein"] ?? 0)
        var nutrientValues = cleanedNutrients
        nutrientValues.removeValue(forKey: "calories")
        if protein > 0, nutrientValues["g_protein"] == nil {
            nutrientValues["g_protein"] = protein
        }

        let subtitlePrefix = item.sourceType == "real" ? "AI web match" : "AI estimate"
        let subtitle = [subtitlePrefix, item.brand].compactMap { $0 }.joined(separator: " • ")

        presentFoodReview(
            FoodReviewItem(
                name: item.name,
                subtitle: subtitle,
                calories: calories,
                nutrientValues: nutrientValues,
                servingAmount: normalizedCountServing.servingAmount,
                servingUnit: normalizedCountServing.servingUnit,
                entrySource: .aiText,
                displayedNutrientKeys: nil
            ),
            initialMultiplier: {
                let estimatedServings = normalizedEstimatedServingsForCountItems(
                    name: item.name,
                    servingAmount: normalizedCountServing.servingAmount,
                    servingUnit: normalizedCountServing.servingUnit,
                    estimatedServings: normalizedCountServing.estimatedServings
                )
                if let consumedCount = normalizedCountServing.consumedItemCount {
                    return max(consumedCount / max(normalizedCountServing.servingAmount, 1), 0.01)
                }
                return estimatedServings
            }()
        )
    }

    private func mealGroup(for date: Date, source: EntrySource) -> MealGroup {
        switch source {
        case let .pccMenu(menuType):
            return mealGroup(for: menuType)
        case .manual, .quickAdd, .barcode, .usda, .aiFoodPhoto, .aiNutritionLabel, .aiText:
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
        showAddConfirmation()
    }

    @MainActor
    private func showAddConfirmation() {
        addConfirmationTask?.cancel()
        barcodeErrorToastTask?.cancel()
        barcodeErrorToastMessage = nil
        Haptics.notification(.success)

        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            isAddConfirmationPresented = true
        }

        addConfirmationTask = Task {
            try? await Task.sleep(for: .seconds(1.35))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                    isAddConfirmationPresented = false
                }
            }
        }
    }

    @MainActor
    private func showBarcodeErrorToast(_ message: String) {
        addConfirmationTask?.cancel()
        withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
            isAddConfirmationPresented = false
        }

        barcodeErrorToastTask?.cancel()
        barcodeErrorToastMessage = message

        barcodeErrorToastTask = Task {
            try? await Task.sleep(for: .seconds(1.35))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                    barcodeErrorToastMessage = nil
                }
            }
        }
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
        isGramUnit(unit) ? "oz" : unit
    }

    private func inflectedTextFieldUnit(for unit: String, amountText: String) -> String {
        let displayUnit = displayServingUnit(for: unit)
        guard let amount = parsedDecimalAmount(amountText) else { return displayUnit }
        return inflectedUnit(displayUnit, quantity: amount)
    }

    private func inflectedUnit(_ unit: String, quantity: Double) -> String {
        inflectServingUnitToken(unit, quantity: quantity)
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
