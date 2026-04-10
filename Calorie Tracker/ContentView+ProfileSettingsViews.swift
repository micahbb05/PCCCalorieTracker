// Calorie Tracker 2026

import SwiftUI
import UniformTypeIdentifiers

extension ContentView {

    var profileTabView: some View {
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
                            fixedGoalCalories: $storedFixedGoalCalories,
                            useWeekendDeficit: $useWeekendDeficit,
                            weekendDeficitCalories: $storedWeekendDeficitCalories,
                            trackedNutrientKeys: trackedNutrientKeys,
                            nutrientGoals: $nutrientGoals,
                            healthAuthorizationState: healthKitService.authorizationState,
                            healthProfile: effectiveHealthProfile,
                            isUsingSyncedHealthFallback: isUsingSyncedHealthFallback,
                            syncedHealthSourceLabel: syncedHealthSourceDeviceType == .iphone ? "iPhone" : nil,
                            bmrSourceRaw: bmrSourceRaw,
                            bmrCalories: currentDailyCalorieModel.bmr,
                            burnedCaloriesToday: burnedCaloriesToday,
                            activeBurnedCaloriesToday: effectiveActivityCaloriesToday + exerciseCaloriesToday,
                            isUsingHealthDerivedBMR: currentDailyCalorieModel.usesBMR,
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
                                    await requestUnifiedHealthAccessAndRefresh()
                                }
                            }
                        )
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

    var settingsTabView: some View {
        VStack(alignment: .leading, spacing: 0) {
            tabHeader(title: "Settings", subtitle: "App preferences that apply everywhere")
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 6)

            ScrollView {
                VStack(spacing: 14) {
                    AppSettingsTabView(
                        trackedNutrientKeys: $trackedNutrientKeys,
                        availableNutrients: availableNutrients,
                        selectedAppIconChoiceRaw: $selectedAppIconChoiceRaw,
                        bmrSourceRaw: $bmrSourceRaw,
                        manualBMRCalories: $storedManualBMRCalories,
                        useAIBaseServings: $useAIBaseServings,
                        smartMealRemindersEnabled: $smartMealRemindersEnabled,
                        appThemeStyleRaw: $appThemeStyleRaw,
                        cloudSyncStatusTitle: cloudSyncStatusTitle,
                        cloudSyncStatusDetail: cloudSyncStatusDetail,
                        cloudSyncStatusTint: cloudSyncStatusTint,
                        cloudSyncLastSuccessText: cloudSyncLastSuccessText,
                        isCloudSyncInFlight: isCloudSyncInFlight,
                        onRetryCloudSync: {
                            Task(priority: .utility) {
                                await bootstrapCloudSync(trigger: .manual)
                            }
                        }
                    )

                    VStack(alignment: .leading, spacing: 12) {
                        Text("App & Privacy")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(textPrimary)

                        VStack(spacing: 0) {
                            Button {
                                hasCompletedOnboarding = false
                                Haptics.impact(.light)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "arrow.counterclockwise")
                                        .symbolRenderingMode(.monochrome)
                                        .foregroundStyle(textPrimary)
                                        .frame(width: 20)
                                    Text("Replay Onboarding")
                                        .foregroundStyle(textPrimary)
                                    Spacer()
                                }
                                .padding(.horizontal, 18)
                                .padding(.vertical, 16)
                            }
                            .buttonStyle(.plain)

                            Divider()
                                .overlay(Color.white.opacity(0.08))

                            Button {
                                do {
                                    exportShareURL = try Self.makeUserDataExportFileURL()
                                    isShowingExportShareSheet = true
                                    exportErrorMessage = nil
                                } catch {
                                    exportErrorMessage = "Couldn’t generate export. Please try again."
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "square.and.arrow.up")
                                        .symbolRenderingMode(.monochrome)
                                        .foregroundStyle(textPrimary)
                                        .frame(width: 20)
                                    Text("Export Data")
                                        .foregroundStyle(textPrimary)
                                    Spacer()
                                }
                                .padding(.horizontal, 18)
                                .padding(.vertical, 16)
                            }
                            .buttonStyle(.plain)
                            .sheet(isPresented: $isShowingExportShareSheet, onDismiss: {
                                exportShareURL = nil
                            }) {
                                if let exportShareURL {
                                    ShareSheet(activityItems: [ExportFileActivityItemSource(fileURL: exportShareURL)])
                                } else {
                                    EmptyView()
                                }
                            }

                            Divider()
                                .overlay(Color.white.opacity(0.08))

                            Button {
                                if let url = URL(string: "https://calorie-tracker-364e3.web.app/privacy") {
                                    UIApplication.shared.open(url)
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "doc.text")
                                        .symbolRenderingMode(.monochrome)
                                        .foregroundStyle(textPrimary)
                                        .frame(width: 20)
                                    Text("Privacy Policy")
                                        .foregroundStyle(textPrimary)
                                    Spacer()
                                    Image(systemName: "arrow.up.right")
                                        .font(.caption.weight(.semibold))
                                        .symbolRenderingMode(.monochrome)
                                        .foregroundStyle(textSecondary)
                                }
                                .padding(.horizontal, 18)
                                .padding(.vertical, 16)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(18)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(surfacePrimary)
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(0.20), radius: 14, x: 0, y: 8)
                    )
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 4)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollIndicators(.hidden)
        }
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 110)
        }
        .alert("Export Data", isPresented: Binding(
            get: { exportErrorMessage != nil },
            set: { if !$0 { exportErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportErrorMessage ?? "")
        }
    }

    struct UserDataExportPayloadV2: Codable {
        let schema: String
        let exportedAt: Date
        let app: AppInfo
        let settings: Settings
        let totals: Totals
        let days: [DaySummary]
        let meals: [MealLog]
        let exercises: [ExerciseLog]
        let weighIns: [WeighInLog]
        let quickAddFoods: [QuickAddFood]
        let analysis: Analysis

        struct AppInfo: Codable {
            let bundleID: String
            let version: String
            let build: String
        }

        struct Settings: Codable {
            let goalTypeRaw: String
            let deficitCalories: Int
            let useWeekendDeficit: Bool
            let weekendDeficitCalories: Int
            let surplusCalories: Int
            let fixedGoalCalories: Int
            let proteinGoal: Int
            let useAIBaseServings: Bool
            let trackedNutrientKeys: [String]
            let nutrientGoals: [String: Int]
        }

        struct DaySummary: Codable {
            let dayIdentifier: String
            let caloriesConsumed: Int?
            let caloriesBurned: Int?
            let netCalories: Int?
            let calorieGoal: Int?
            let goalDeltaCalories: Int?
            let goalTypeRaw: String?
            let mealCount: Int?
            let exerciseCount: Int?
            let exerciseCalories: Int?
            let nutrientTotals: [String: Int]?
            let weighInPounds: Double?
        }

        struct MealLog: Codable {
            let dayIdentifier: String
            let createdAt: Date
            let mealGroup: String
            let name: String
            /// Total calories for this logged entry.
            let calories: Int
            /// Alias of `calories` kept for export compatibility.
            let totalCalories: Int
            /// All nutrients including protein (`g_protein`). Use `nutrientValues["g_protein"]` for protein.
            let nutrientValues: [String: Int]
            let loggedCount: Int
        }

        struct ExerciseLog: Codable {
            let dayIdentifier: String?
            let createdAt: Date
            let exerciseType: String
            let displayTitle: String
            let durationMinutes: Int
            let distanceMiles: Double?
            let calories: Int
        }

        struct WeighInLog: Codable {
            let dayIdentifier: String
            let representativePounds: Double
            let selectedSampleDate: Date
            let selectionMethod: String
            let sampleCount: Int
            let samples: [Sample]

            struct Sample: Codable {
                let timestamp: Date
                let pounds: Double
            }
        }

        struct Analysis: Codable {
            let calorieAccuracy: CalorieAccuracy
            let smartAdjustment: SmartAdjustment

            struct CalorieAccuracy: Codable {
                /// Mean absolute daily error from calibration, in calories.
                let meanAbsoluteDailyErrorCalories: Double?
                /// Root-mean-square daily error from calibration, in calories.
                let rmsDailyErrorCalories: Double?
                /// Most recent daily errors (as stored), newest last.
                let recentDailyErrorsCalories: [Double]
                /// Number of weekly calibration runs represented in the error arrays above (max 4).
                let dataWindowWeeks: Int
            }

            struct SmartAdjustment: Codable {
                let isEnabled: Bool
                /// Current calibration offset value (may differ from values used for past archived days).
                let calibrationOffsetCalories: Int
                /// Historical per-day offsets are not archived, so exact baseline reconstruction for older days may be approximate.
                let historicalCalibrationOffsetByDayAvailable: Bool
                let burnedBaselineReconstructionExact: Bool
                let appliedWeekCount: Int
                let lastAppliedWeekID: String?
                let lastRunDate: Date?
                let lastRunStatus: String
                let lastSkipReason: String?
                let dataQualityChecks: Int
                let dataQualityPasses: Int
                let dataQualityPassRate: Double?
                /// `caloriesBurned` in each DaySummary is the stored effective burned value used for that day.
                let burnedCaloriesIncludeOffset: Bool
            }
        }

        struct Totals: Codable {
            let daysWithMeals: Int
            let daysWithBurned: Int
            let totalMealsLogged: Int
            let totalExercisesLogged: Int
            let totalCaloriesConsumed: Int
            let totalCaloriesBurned: Int
            let totalNetCalories: Int
            let averageCaloriesConsumedPerMealDay: Double?
            let averageCaloriesBurnedPerBurnedDay: Double?
        }
    }

    struct ShareSheet: UIViewControllerRepresentable {
        let activityItems: [Any]
        var applicationActivities: [UIActivity]? = nil
        var excludedActivityTypes: [UIActivity.ActivityType]? = nil

        func makeUIViewController(context: Context) -> UIActivityViewController {
            let vc = UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
            vc.excludedActivityTypes = excludedActivityTypes
            return vc
        }

        func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
    }

    final class ExportFileActivityItemSource: NSObject, UIActivityItemSource {
        private let fileURL: URL

        init(fileURL: URL) {
            self.fileURL = fileURL
        }

        func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
            fileURL
        }

        func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
            fileURL
        }

        func activityViewController(_ activityViewController: UIActivityViewController, dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?) -> String {
            UTType.json.identifier
        }

        func activityViewController(_ activityViewController: UIActivityViewController, subjectForActivityType activityType: UIActivity.ActivityType?) -> String {
            "Calorie Tracker Data Export"
        }
    }

    @MainActor
    static func makeUserDataExportFileURL() throws -> URL {
        let bundle = Bundle.main
        let bundleID = bundle.bundleIdentifier ?? "unknown"
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"

        let snapshot = PersistentAppStateStore.shared.exportSnapshot(defaults: .standard)
        let decoded = decodeSnapshotForAI(snapshot)

        let payload = UserDataExportPayloadV2(
            schema: "calorie-tracker-export/v3",
            exportedAt: Date(),
            app: .init(bundleID: bundleID, version: version, build: build),
            settings: decoded.settings,
            totals: decoded.totals,
            days: decoded.days,
            meals: decoded.meals,
            exercises: decoded.exercises,
            weighIns: decoded.weighIns,
            quickAddFoods: decoded.quickAddFoods,
            analysis: decoded.analysis
        )

        let encoder = JSONEncoder()
        // Keep export stable and human/AI-readable; also preserves struct ordering (analysis at bottom).
        encoder.outputFormatting = [.prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let ts = formatter.string(from: payload.exportedAt)
            .replacingOccurrences(of: ":", with: "-")
        let filename = "calorie-tracker-export-\(ts).json"

        let fm = FileManager.default
        let base = (try? fm.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? fm.temporaryDirectory
        let url = base.appendingPathComponent(filename)
        try data.write(to: url, options: [.atomic])
        return url
    }

    @MainActor
    static func decodeSnapshotForAI(
        _ snapshot: PersistentAppStateSnapshot?
    ) -> (
        settings: UserDataExportPayloadV2.Settings,
        totals: UserDataExportPayloadV2.Totals,
        days: [UserDataExportPayloadV2.DaySummary],
        meals: [UserDataExportPayloadV2.MealLog],
        exercises: [UserDataExportPayloadV2.ExerciseLog],
        weighIns: [UserDataExportPayloadV2.WeighInLog],
        quickAddFoods: [QuickAddFood],
        analysis: UserDataExportPayloadV2.Analysis
    ) {
        guard let snapshot else {
            return (
                settings: .init(
                    goalTypeRaw: "unknown",
                    deficitCalories: 0,
                    useWeekendDeficit: false,
                    weekendDeficitCalories: 0,
                    surplusCalories: 0,
                    fixedGoalCalories: 0,
                    proteinGoal: 0,
                    useAIBaseServings: false,
                    trackedNutrientKeys: [],
                    nutrientGoals: [:]
                ),
                totals: .init(
                    daysWithMeals: 0,
                    daysWithBurned: 0,
                    totalMealsLogged: 0,
                    totalExercisesLogged: 0,
                    totalCaloriesConsumed: 0,
                    totalCaloriesBurned: 0,
                    totalNetCalories: 0,
                    averageCaloriesConsumedPerMealDay: nil,
                    averageCaloriesBurnedPerBurnedDay: nil
                ),
                days: [],
                meals: [],
                exercises: [],
                weighIns: [],
                quickAddFoods: [],
                analysis: .init(
                    calorieAccuracy: .init(
                        meanAbsoluteDailyErrorCalories: nil,
                        rmsDailyErrorCalories: nil,
                        recentDailyErrorsCalories: [],
                        dataWindowWeeks: 0
                    ),
                    smartAdjustment: .init(
                        isEnabled: false,
                        calibrationOffsetCalories: 0,
                        historicalCalibrationOffsetByDayAvailable: false,
                        burnedBaselineReconstructionExact: true,
                        appliedWeekCount: 0,
                        lastAppliedWeekID: nil,
                        lastRunDate: nil,
                        lastRunStatus: "unknown",
                        lastSkipReason: nil,
                        dataQualityChecks: 0,
                        dataQualityPasses: 0,
                        dataQualityPassRate: nil,
                        burnedCaloriesIncludeOffset: false
                    )
                )
            )
        }

        let dayEntries: [String: [MealEntry]] = decodeJSONString(snapshot.dailyEntryArchiveData) ?? [:]
        let dayBurned: [String: Int] = decodeJSONString(snapshot.dailyBurnedCalorieArchiveData) ?? [:]
        let dayGoal: [String: Int] = decodeJSONString(snapshot.dailyCalorieGoalArchiveData) ?? [:]
        let dayGoalType: [String: String] = decodeJSONString(snapshot.dailyGoalTypeArchiveData) ?? [:]
        let dayExercises: [String: [ExerciseEntry]] = decodeJSONString(snapshot.dailyExerciseArchiveData) ?? [:]
        let trackedKeys: [String] = decodeJSONString(snapshot.trackedNutrientsData) ?? []
        let nutrientGoals: [String: Int] = decodeJSONString(snapshot.nutrientGoalsData) ?? [:]
        let quickAdds: [QuickAddFood] = decodeJSONString(snapshot.quickAddFoodsData) ?? []
        let weighIns: [HealthWeighInDay] = decodeJSONString(snapshot.healthWeighInsData) ?? []
        let calibration: CalibrationState = decodeJSONString(snapshot.calibrationStateData) ?? .default

        let settings = UserDataExportPayloadV2.Settings(
            goalTypeRaw: snapshot.goalTypeRaw,
            deficitCalories: snapshot.deficitCalories,
            useWeekendDeficit: snapshot.useWeekendDeficit,
            weekendDeficitCalories: snapshot.weekendDeficitCalories,
            surplusCalories: snapshot.surplusCalories,
            fixedGoalCalories: snapshot.fixedGoalCalories,
            proteinGoal: snapshot.proteinGoal,
            useAIBaseServings: snapshot.useAIBaseServings,
            trackedNutrientKeys: trackedKeys,
            nutrientGoals: nutrientGoals
        )

        var meals: [UserDataExportPayloadV2.MealLog] = []
        meals.reserveCapacity(dayEntries.values.reduce(0) { $0 + $1.count })
        for (dayID, entries) in dayEntries {
            for e in entries {
                let count = max(1, e.loggedCount ?? 1)
                meals.append(.init(
                    dayIdentifier: dayID,
                    createdAt: e.createdAt,
                    mealGroup: e.mealGroup.rawValue,
                    name: e.name,
                    calories: e.calories,
                    totalCalories: e.calories,
                    nutrientValues: e.nutrientValues,
                    loggedCount: count
                ))
            }
        }
        meals.sort { $0.createdAt > $1.createdAt }

        var exercises: [UserDataExportPayloadV2.ExerciseLog] = []
        exercises.reserveCapacity(dayExercises.values.reduce(0) { $0 + $1.count })
        for (dayID, items) in dayExercises {
            for ex in items {
                exercises.append(.init(
                    dayIdentifier: dayID,
                    createdAt: ex.createdAt,
                    exerciseType: ex.exerciseType.rawValue,
                    displayTitle: ex.displayTitle,
                    durationMinutes: ex.durationMinutes,
                    distanceMiles: ex.distanceMiles,
                    calories: ex.calories
                ))
            }
        }
        exercises.sort { $0.createdAt > $1.createdAt }

        let weighInLogs: [UserDataExportPayloadV2.WeighInLog] = weighIns.map { day in
            .init(
                dayIdentifier: day.dayIdentifier,
                representativePounds: day.representativePounds,
                selectedSampleDate: day.selectedSampleDate,
                selectionMethod: day.selectionMethod.rawValue,
                sampleCount: day.sampleCount,
                samples: day.samples.map { .init(timestamp: $0.timestamp, pounds: $0.pounds) }
            )
        }.sorted { $0.selectedSampleDate > $1.selectedSampleDate }

        let weighInByDay = Dictionary(uniqueKeysWithValues: weighInLogs.map { ($0.dayIdentifier, $0.representativePounds) })

        let allDays = Set(dayEntries.keys)
            .union(dayBurned.keys)
            .union(dayGoal.keys)
            .union(dayGoalType.keys)
            .union(dayExercises.keys)
            .union(weighInByDay.keys)

        let days: [UserDataExportPayloadV2.DaySummary] = allDays.sorted().map { dayID in
            let entries = dayEntries[dayID] ?? []
            let consumed = entries.reduce(0) { partial, item in partial + item.calories }
            let hasConsumed = !entries.isEmpty
            let exerciseCount = dayExercises[dayID]?.count
            let exerciseCalories = dayExercises[dayID]?.reduce(0) { $0 + $1.calories }
            let nutrientTotals = entries.reduce(into: [String: Int]()) { partial, item in
                for (key, value) in item.nutrientValues {
                    partial[key, default: 0] += value
                }
            }
            let burned = dayBurned[dayID]
            let goal = dayGoal[dayID]
            let netCalories = (hasConsumed && burned != nil) ? (consumed - (burned ?? 0)) : nil
            let goalDeltaCalories = (hasConsumed && goal != nil) ? (consumed - (goal ?? 0)) : nil
            return .init(
                dayIdentifier: dayID,
                caloriesConsumed: hasConsumed ? consumed : nil,
                caloriesBurned: burned,
                netCalories: netCalories,
                calorieGoal: goal,
                goalDeltaCalories: goalDeltaCalories,
                goalTypeRaw: dayGoalType[dayID],
                mealCount: entries.isEmpty ? nil : entries.count,
                exerciseCount: (exerciseCount ?? 0) > 0 ? exerciseCount : nil,
                exerciseCalories: (exerciseCalories ?? 0) > 0 ? exerciseCalories : nil,
                nutrientTotals: nutrientTotals.isEmpty ? nil : nutrientTotals,
                weighInPounds: weighInByDay[dayID]
            )
        }

        let daysWithMeals = days.filter { $0.caloriesConsumed != nil }.count
        let daysWithBurned = days.filter { $0.caloriesBurned != nil }.count
        let totalCaloriesConsumed = days.compactMap(\.caloriesConsumed).reduce(0, +)
        let totalCaloriesBurned = days.compactMap(\.caloriesBurned).reduce(0, +)
        let totals = UserDataExportPayloadV2.Totals(
            daysWithMeals: daysWithMeals,
            daysWithBurned: daysWithBurned,
            totalMealsLogged: meals.count,
            totalExercisesLogged: exercises.count,
            totalCaloriesConsumed: totalCaloriesConsumed,
            totalCaloriesBurned: totalCaloriesBurned,
            totalNetCalories: totalCaloriesConsumed - totalCaloriesBurned,
            averageCaloriesConsumedPerMealDay: daysWithMeals > 0 ? (Double(totalCaloriesConsumed) / Double(daysWithMeals)) : nil,
            averageCaloriesBurnedPerBurnedDay: daysWithBurned > 0 ? (Double(totalCaloriesBurned) / Double(daysWithBurned)) : nil
        )

        let recentErrors = calibration.recentDailyErrors
        let absErrors = recentErrors.map { abs($0) }
        let meanAbs = absErrors.isEmpty ? nil : (absErrors.reduce(0, +) / Double(absErrors.count))
        let rms: Double? = {
            guard !recentErrors.isEmpty else { return nil }
            let meanSq = recentErrors.map { $0 * $0 }.reduce(0, +) / Double(recentErrors.count)
            return sqrt(meanSq)
        }()
        let passRate: Double? = {
            guard calibration.dataQualityChecks > 0 else { return nil }
            return Double(calibration.dataQualityPasses) / Double(calibration.dataQualityChecks)
        }()

        let analysis = UserDataExportPayloadV2.Analysis(
            calorieAccuracy: .init(
                meanAbsoluteDailyErrorCalories: meanAbs,
                rmsDailyErrorCalories: rms,
                recentDailyErrorsCalories: recentErrors,
                dataWindowWeeks: recentErrors.count
            ),
            smartAdjustment: .init(
                isEnabled: calibration.isEnabled,
                calibrationOffsetCalories: calibration.calibrationOffsetCalories,
                historicalCalibrationOffsetByDayAvailable: false,
                burnedBaselineReconstructionExact: calibration.appliedWeekCount == 0,
                appliedWeekCount: calibration.appliedWeekCount,
                lastAppliedWeekID: calibration.lastAppliedWeekID,
                lastRunDate: calibration.lastRunDate,
                lastRunStatus: calibration.lastRunStatus.rawValue,
                lastSkipReason: calibration.lastSkipReason,
                dataQualityChecks: calibration.dataQualityChecks,
                dataQualityPasses: calibration.dataQualityPasses,
                dataQualityPassRate: passRate,
                burnedCaloriesIncludeOffset: true
            )
        )

        return (
            settings: settings,
            totals: totals,
            days: days,
            meals: meals,
            exercises: exercises,
            weighIns: weighInLogs,
            quickAddFoods: quickAdds,
            analysis: analysis
        )
    }

    static func decodeJSONString<T: Decodable>(_ jsonString: String) -> T? {
        guard !jsonString.isEmpty, let data = jsonString.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }


}
