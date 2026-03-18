import WidgetKit
import SwiftUI

struct WidgetCalorieSnapshot: Codable, Equatable {
    struct TrackedNutrient: Codable, Equatable, Identifiable {
        let key: String
        let name: String
        let unit: String
        let total: Int
        let goal: Int
        let progress: Double

        var id: String { key }
    }

    let updatedAt: Date
    let consumedCalories: Int
    let goalCalories: Int
    let burnedCalories: Int
    let caloriesLeft: Int
    let progress: Double
    let goalTypeRaw: String
    let selectedAppIconChoiceRaw: String
    let trackedNutrients: [TrackedNutrient]

    private enum CodingKeys: String, CodingKey {
        case updatedAt
        case consumedCalories
        case goalCalories
        case burnedCalories
        case caloriesLeft
        case progress
        case goalTypeRaw
        case selectedAppIconChoiceRaw
        case trackedNutrients
    }

    init(
        updatedAt: Date,
        consumedCalories: Int,
        goalCalories: Int,
        burnedCalories: Int,
        caloriesLeft: Int,
        progress: Double,
        goalTypeRaw: String,
        selectedAppIconChoiceRaw: String,
        trackedNutrients: [TrackedNutrient]
    ) {
        self.updatedAt = updatedAt
        self.consumedCalories = consumedCalories
        self.goalCalories = goalCalories
        self.burnedCalories = burnedCalories
        self.caloriesLeft = caloriesLeft
        self.progress = progress
        self.goalTypeRaw = goalTypeRaw
        self.selectedAppIconChoiceRaw = selectedAppIconChoiceRaw
        self.trackedNutrients = trackedNutrients
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        consumedCalories = try container.decode(Int.self, forKey: .consumedCalories)
        goalCalories = try container.decode(Int.self, forKey: .goalCalories)
        burnedCalories = try container.decode(Int.self, forKey: .burnedCalories)
        caloriesLeft = try container.decode(Int.self, forKey: .caloriesLeft)
        progress = try container.decode(Double.self, forKey: .progress)
        goalTypeRaw = try container.decodeIfPresent(String.self, forKey: .goalTypeRaw)
            ?? Self.inferredGoalTypeRaw(goalCalories: goalCalories, burnedCalories: burnedCalories)
        selectedAppIconChoiceRaw = try container.decodeIfPresent(String.self, forKey: .selectedAppIconChoiceRaw) ?? "standard"
        trackedNutrients = try container.decodeIfPresent([TrackedNutrient].self, forKey: .trackedNutrients) ?? []
    }

    private static func inferredGoalTypeRaw(goalCalories: Int, burnedCalories: Int) -> String {
        if goalCalories > burnedCalories { return "surplus" }
        if goalCalories == burnedCalories { return "fixed" }
        return "deficit"
    }
}

enum WidgetSnapshotStore {
    static let appGroupID = "group.Micah.Calorie-Tracker"
    private static let snapshotKey = "widget.calorieSnapshot"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    static func load() -> WidgetCalorieSnapshot? {
        guard
            let data = defaults.data(forKey: snapshotKey),
            let snapshot = try? JSONDecoder().decode(WidgetCalorieSnapshot.self, from: data)
        else {
            return nil
        }

        if isCurrentDay(snapshot.updatedAt) {
            return snapshot
        }

        let safeGoal = max(snapshot.goalCalories, 1)
        let normalizedNutrients = snapshot.trackedNutrients.map {
            WidgetCalorieSnapshot.TrackedNutrient(
                key: $0.key,
                name: $0.name,
                unit: $0.unit,
                total: 0,
                goal: max($0.goal, 1),
                progress: 0
            )
        }
        return WidgetCalorieSnapshot(
            updatedAt: Date(),
            consumedCalories: 0,
            goalCalories: safeGoal,
            burnedCalories: max(snapshot.burnedCalories, 0),
            caloriesLeft: safeGoal,
            progress: 0,
            goalTypeRaw: snapshot.goalTypeRaw,
            selectedAppIconChoiceRaw: snapshot.selectedAppIconChoiceRaw,
            trackedNutrients: normalizedNutrients
        )
    }

    private static func isCurrentDay(_ date: Date) -> Bool {
        Calendar.autoupdatingCurrent.isDateInToday(date)
    }
}

private enum CalorieWidgetData {
    static let kind = "CalorieTrackerCalorieWidget"
    static let dashboardKind = "CalorieTrackerDashboardWidget"
}

struct CalorieWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetCalorieSnapshot
}

struct CalorieWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> CalorieWidgetEntry {
        CalorieWidgetEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (CalorieWidgetEntry) -> Void) {
        let snapshot = WidgetSnapshotStore.load() ?? .placeholder
        completion(CalorieWidgetEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CalorieWidgetEntry>) -> Void) {
        let snapshot = WidgetSnapshotStore.load() ?? .placeholder
        let entry = CalorieWidgetEntry(date: Date(), snapshot: snapshot)
        let refresh = Calendar.current.date(byAdding: .minute, value: 10, to: Date()) ?? Date().addingTimeInterval(600)
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }
}

extension WidgetCalorieSnapshot {
    static let placeholder = WidgetCalorieSnapshot(
        updatedAt: Date(),
        consumedCalories: 1320,
        goalCalories: 2200,
        burnedCalories: 2480,
        caloriesLeft: 880,
        progress: 1320.0 / 2200.0,
        goalTypeRaw: "deficit",
        selectedAppIconChoiceRaw: "standard",
        trackedNutrients: [
            .init(key: "g_protein", name: "Protein", unit: "g", total: 123, goal: 150, progress: 0.82),
            .init(key: "g_fat", name: "Fat", unit: "g", total: 56, goal: 75, progress: 0.74)
        ]
    )

    var nonNegativeProgress: Double {
        max(progress, 0)
    }

    var clampedProgress: Double {
        min(nonNegativeProgress, 1)
    }

}

private enum WidgetRingColor {
    static func forSnapshot(_ snapshot: WidgetCalorieSnapshot) -> Color {
        let consumed = max(snapshot.consumedCalories, 0)
        let goal = max(snapshot.goalCalories, 1)
        let burned = max(snapshot.burnedCalories, 1)
        let goalTypeRaw = snapshot.goalTypeRaw

        if goalTypeRaw == "fixed" {
            if consumed <= goal { return Color(red: 0.22, green: 0.78, blue: 0.35) }
            if consumed < burned { return Color(red: 1.0, green: 0.76, blue: 0.12) }
            return Color(red: 0.95, green: 0.26, blue: 0.21)
        }

        let isSurplus = goalTypeRaw == "surplus" || goal > burned
        if isSurplus {
            if consumed < burned { return Color(red: 1.0, green: 0.76, blue: 0.12) }
            if consumed <= goal { return Color(red: 0.22, green: 0.78, blue: 0.35) }
            return Color(red: 0.95, green: 0.26, blue: 0.21)
        }
        if consumed > burned { return Color(red: 0.95, green: 0.26, blue: 0.21) }
        if consumed <= goal { return Color(red: 0.22, green: 0.78, blue: 0.35) }
        return Color(red: 1.0, green: 0.76, blue: 0.12)
    }
}

private struct DashboardLeftRingCore: View {
    let snapshot: WidgetCalorieSnapshot
    let ringColor: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.20), lineWidth: 10)

            Circle()
                .trim(from: 0, to: snapshot.clampedProgress)
                .stroke(
                    ringColor,
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 0) {
                Text("\(snapshot.caloriesLeft)")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .foregroundStyle(.white)
                Text("Left")
                    .font(.system(size: 8, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.72))
            }
        }
    }
}

struct CalorieWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CalorieWidgetEntry

    var body: some View {
        widgetContent
            .containerBackground(for: .widget) {
                #if os(watchOS)
                Color.clear
                #else
                switch family {
                case .systemSmall:
                    cardBackground(size: CGSize(width: 170, height: 170), family: .systemSmall)
                case .systemMedium:
                    cardBackground(size: CGSize(width: 360, height: 170), family: .systemMedium)
                default:
                    Color.clear
                }
                #endif
            }
    }

    @ViewBuilder
    private var widgetContent: some View {
        #if os(watchOS)
        switch family {
        case .accessoryCircular:
            accessoryCircularWidget
        case .accessoryRectangular:
            accessoryRectangularWidget
        case .accessoryInline:
            accessoryInlineWidget
        default:
            accessoryRectangularWidget
        }
        #else
        switch family {
        case .systemSmall:
            smallWidget
        case .accessoryCircular:
            accessoryCircularWidget
        case .accessoryRectangular:
            accessoryRectangularWidget
        case .accessoryInline:
            accessoryInlineWidget
        default:
            mediumWidget
        }
        #endif
    }

    private var barColor: Color {
        WidgetRingColor.forSnapshot(entry.snapshot)
    }

    #if !os(watchOS)
    private func cardBackground(size: CGSize, family: WidgetFamily) -> some View {
        if family == .systemSmall {
            return AnyView(
                Color.black
            )
        }

        let orbSize: CGFloat = family == .systemSmall ? min(size.width, size.height) * 0.92 : max(size.height * 1.35, 180)
        let orbOffsetX: CGFloat = family == .systemSmall ? size.width * 0.20 : size.width * 0.18
        let orbOffsetY: CGFloat = family == .systemSmall ? -size.height * 0.13 : -size.height * 0.14
        return AnyView(
            ZStack(alignment: .topTrailing) {
                LinearGradient(
                    colors: [
                        Color(red: 0.02, green: 0.07, blue: 0.23),
                        Color(red: 0.03, green: 0.09, blue: 0.25)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Circle()
                    .fill(Color(red: 0.20, green: 0.23, blue: 0.48).opacity(0.28))
                    .frame(width: orbSize, height: orbSize)
                    .offset(x: orbOffsetX, y: orbOffsetY)
            }
        )
    }
    #endif

    #if !os(watchOS)
    private var smallWidget: some View {
        DashboardLeftRingCore(snapshot: entry.snapshot, ringColor: barColor)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(width: 112, height: 112)
    }

    private var mediumWidget: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let scale = max(0.62, min(size.height / 248, size.width / 360))

            VStack(alignment: .leading, spacing: 18 * scale) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2 * scale) {
                        Text("\(entry.snapshot.caloriesLeft)")
                            .font(.system(size: 56 * scale, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                            .foregroundStyle(.white)
                        Text("Calories Left")
                            .font(.system(size: 20 * scale, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.70))
                    }

                    Spacer()

                    Image(systemName: "flame")
                        .font(.system(size: 34 * scale, weight: .regular))
                        .foregroundStyle(Color.orange)
                        .padding(.top, 10 * scale)
                }

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.10))
                    GeometryReader { barProxy in
                        Capsule()
                            .fill(barColor)
                            .frame(width: max(barProxy.size.width * entry.snapshot.clampedProgress, entry.snapshot.clampedProgress > 0 ? 8 : 0))
                    }
                }
                .frame(height: 20 * scale)

                HStack {
                    Text("Consumed: \(entry.snapshot.consumedCalories)")
                        .font(.system(size: 18 * scale, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .foregroundStyle(Color.white.opacity(0.72))
                    Spacer(minLength: 8 * scale)
                    Text("Goal: \(entry.snapshot.goalCalories)")
                        .font(.system(size: 18 * scale, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .foregroundStyle(Color.white.opacity(0.72))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(24 * scale)
        }
    }
    #endif

    private var accessoryCircularWidget: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.20), lineWidth: 6)

            Circle()
                .trim(from: 0, to: entry.snapshot.clampedProgress)
                .stroke(
                    barColor,
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            Text("\(Int((entry.snapshot.clampedProgress * 100).rounded()))%")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .allowsTightening(true)
        }
        .padding(4)
    }

    private var accessoryRectangularWidget: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Calories Left")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .foregroundStyle(.secondary)

            Text("\(entry.snapshot.caloriesLeft)")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            ProgressView(value: entry.snapshot.clampedProgress)
                .tint(barColor)
                .scaleEffect(x: 1, y: 1.18, anchor: .center)
        }
        .frame(maxHeight: .infinity, alignment: .center)
        .padding(.vertical, 1)
    }

    private var accessoryInlineWidget: some View {
        Text("Left \(entry.snapshot.caloriesLeft) • Goal \(entry.snapshot.goalCalories)")
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
    }
}

private enum WidgetDeepLink {
    static let pccMenu = URL(string: "calorietracker://open?dest=pcc-menu")!
    static let barcode = URL(string: "calorietracker://open?dest=barcode")!
    static let aiMode = URL(string: "calorietracker://open?dest=ai")!
}

struct CalorieDashboardWidgetView: View {
    let entry: CalorieWidgetEntry

    private var ringColor: Color {
        WidgetRingColor.forSnapshot(entry.snapshot)
    }

    private var nutrientRows: [WidgetCalorieSnapshot.TrackedNutrient] {
        if entry.snapshot.trackedNutrients.isEmpty {
            return [
                .init(key: "g_protein", name: "Protein", unit: "g", total: 0, goal: 150, progress: 0),
                .init(key: "g_fat", name: "Fat", unit: "g", total: 0, goal: 70, progress: 0)
            ]
        }
        return Array(entry.snapshot.trackedNutrients.prefix(3))
    }

    private var hasThreeNutrients: Bool {
        nutrientRows.count >= 3
    }

    var body: some View {
        HStack(spacing: 14) {
            leftRing
                .frame(width: 112, height: 112)
                .padding(.leading, 4)

            rightNutrients
                .frame(maxWidth: .infinity, alignment: .leading)

            actionButtons
                .frame(width: 46)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .containerBackground(for: .widget) { Color.black }
    }

    private var leftRing: some View {
        DashboardLeftRingCore(snapshot: entry.snapshot, ringColor: ringColor)
    }

    private var rightNutrients: some View {
        VStack(alignment: .leading, spacing: hasThreeNutrients ? 4 : 8) {
            ForEach(nutrientRows) { nutrient in
                VStack(alignment: .leading, spacing: 1) {
                    Text(nutrient.name)
                        .font(.system(size: hasThreeNutrients ? 10 : 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                    Text("\(Int((nutrient.progress * 100).rounded()))% • \(nutrient.total.formatted()) \(nutrient.unit)")
                        .font(.system(size: hasThreeNutrients ? 12 : 13, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }
            }
        }
        .padding(.leading, 6)
    }

    private var actionButtons: some View {
        VStack(spacing: 0) {
            actionButton(icon: "fork.knife", url: WidgetDeepLink.pccMenu)
            divider
            actionButton(icon: "barcode.viewfinder", url: WidgetDeepLink.barcode)
            divider
            actionButton(icon: "sparkles", url: WidgetDeepLink.aiMode)
        }
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.12))
        )
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.16))
            .frame(height: 1)
            .padding(.horizontal, 8)
    }

    private func actionButton(icon: String, url: URL) -> some View {
        Link(destination: url) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.90))
                .frame(maxWidth: .infinity)
                .frame(height: 36)
        }
        .buttonStyle(.plain)
    }
}

struct CalorieTrackerCalorieWidget: Widget {
    let kind: String = CalorieWidgetData.kind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CalorieWidgetProvider()) { entry in
            CalorieWidgetView(entry: entry)
        }
        .configurationDisplayName("Calories")
        .description("Track your daily calories with a compact progress view.")
        #if os(watchOS)
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
        #else
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline])
        #endif
        .contentMarginsDisabled()
        .containerBackgroundRemovable(false)
    }
}

#if !os(watchOS)
struct CalorieTrackerDashboardWidget: Widget {
    let kind: String = CalorieWidgetData.dashboardKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CalorieWidgetProvider()) { entry in
            CalorieDashboardWidgetView(entry: entry)
        }
        .configurationDisplayName("Calories Dashboard")
        .description("Ring, calories left, nutrient percentages, and quick actions.")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
        .containerBackgroundRemovable(false)
    }
}
#endif

@main
struct CalorieTrackerWidgets: WidgetBundle {
    var body: some Widget {
        CalorieTrackerCalorieWidget()
        #if !os(watchOS)
        CalorieTrackerDashboardWidget()
        #endif
    }
}
