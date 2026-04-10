// Calorie Tracker 2026

import SwiftUI
import Charts

extension ContentView {

    var expandedHistoryChartSheet: some View {
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
                                .font(.system(size: 30, weight: .bold, design: .default))
                                .foregroundStyle(textPrimary)
                            Spacer()
                            Menu {
                                ForEach(HistoryChartRange.allCases) { range in
                                    Button {
                                        expandedHistoryChartRange = range
                                        Haptics.selection()
                                    } label: {
                                        if range == expandedHistoryChartRange {
                                            Label(range.title, systemImage: "checkmark")
                                        } else {
                                            Text(range.title)
                                        }
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

                        Text("Consumed and Burned across the selected range.")
                            .font(.subheadline)
                            .foregroundStyle(textSecondary)

                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 14) {
                                calorieTrendLegendChip(title: "Consumed", color: calorieTrendConsumedColor)
                                calorieTrendLegendChip(title: "Burned", color: calorieTrendBurnedColor)
                                calorieTrendLegendChip(title: "Average", color: textSecondary.opacity(0.75), isDashed: true)
                                Spacer()
                            }

                            calorieChart(
                                points: expandedCalorieGraphPoints,
                                labelMode: .adaptive,
                                style: .line,
                                historyRange: expandedHistoryChartRange
                            )
                            .frame(height: 320)
                        }
                        .padding(18)
                        .cardStyle(surface: surfacePrimary, stroke: textSecondary.opacity(0.18))
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

    var weightChangeComparisonSheet: some View {
        let points = weightChangeComparisonPoints(for: weightChangeComparisonRange)
        let expectedChange = expectedWeightChangeSummary(for: weightChangeComparisonRange)
        let actualChange = actualWeightChangeSummary(for: weightChangeComparisonRange)

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
                        HStack {
                            Text("Weight Change")
                                .font(.system(size: 30, weight: .bold, design: .default))
                                .foregroundStyle(textPrimary)
                            Spacer()
                            Menu {
                                ForEach(NetHistoryRange.allCases) { range in
                                    Button {
                                        weightChangeComparisonRange = range
                                        Haptics.selection()
                                    } label: {
                                        if range == weightChangeComparisonRange {
                                            Label(range.title, systemImage: "checkmark")
                                        } else {
                                            Text(range.title)
                                        }
                                    }
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Text(weightChangeComparisonRange.title)
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

                        Text("Expected uses logged calorie net and a 3,500 calorie-per-pound estimate. Actual uses Apple Health weigh-ins.")
                            .font(.subheadline)
                            .foregroundStyle(textSecondary)

                        HStack(spacing: 12) {
                            statTile(
                                title: "Expected",
                                value: formattedWeightChange(expectedChange),
                                detail: weightChangeComparisonRange.title
                            )

                            statTile(
                                title: "Actual",
                                value: actualChange.map(formattedWeightChange) ?? "--",
                                detail: actualChange == nil ? "Need weigh-ins" : weightChangeComparisonRange.title
                            )
                        }

                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 14) {
                                weightChangeLegendChip(title: "Expected", color: color(for: .expected))
                                weightChangeLegendChip(title: "Actual", color: color(for: .actual))
                                Spacer()
                                if isRefreshingWeightChangeComparison {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                            }

                            weightChangeChart(
                                points: points,
                                range: weightChangeComparisonRange
                            )
                            .frame(height: 320)

                            if actualChange == nil {
                                Text("Log weigh-ins in Apple Health to compare actual change against the expected trend.")
                                    .font(.caption)
                                    .foregroundStyle(textSecondary)
                            }
                        }
                        .padding(18)
                        .cardStyle(surface: surfacePrimary, stroke: textSecondary.opacity(0.18))
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 32)
                }
                .scrollIndicators(.hidden)
            }
            .task {
                await refreshWeightChangeComparisonIfNeeded()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") {
                        isWeightChangeComparisonPresented = false
                    }
                    .foregroundStyle(textPrimary)
                }
            }
        }
    }

    func weightChangeLegendChip(title: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(textSecondary)
        }
    }

    func calorieTrendLegendChip(title: String, color: Color, isDashed: Bool = false) -> some View {
        HStack(spacing: 8) {
            if isDashed {
                Rectangle()
                    .fill(.clear)
                    .frame(width: 21, height: 8)
                    .overlay(alignment: .center) {
                        Path { path in
                            path.move(to: CGPoint(x: 0, y: 4))
                            path.addLine(to: CGPoint(x: 3, y: 4))
                            path.move(to: CGPoint(x: 8, y: 4))
                            path.addLine(to: CGPoint(x: 13, y: 4))
                            path.move(to: CGPoint(x: 18, y: 4))
                            path.addLine(to: CGPoint(x: 21, y: 4))
                        }
                        .stroke(style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .foregroundStyle(color)
                    }
            } else {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
            }
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(textSecondary)
        }
    }

    func statTile(title: String, value: String, detail: String) -> some View {
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

    enum ChartAxisLabelMode {
        case weekday
        case adaptive
    }

    enum CalorieChartStyle {
        case bars
        case line
    }

    func calorieChart(
        points: [CalorieGraphPoint],
        labelMode: ChartAxisLabelMode,
        style: CalorieChartStyle = .bars,
        historyRange: HistoryChartRange? = nil
    ) -> some View {
        let yAxisValues = chartYAxisValues(for: points)
        let linePoints = calorieLinePoints(for: points, range: historyRange)
        let averageLinePoints = calorieAverageLinePoints(for: points)
        let interpolation: InterpolationMethod = .monotone

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
                ForEach(averageLinePoints) { point in
                    LineMark(
                        x: .value("Day", point.date, unit: .day),
                        y: .value(point.series == .consumed ? "Consumed Average" : "Burned Average", point.calories),
                        series: .value("Series", point.series == .consumed ? "Consumed Average" : "Burned Average")
                    )
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .foregroundStyle(point.series == .consumed ? calorieTrendConsumedColor.opacity(0.5) : calorieTrendBurnedColor.opacity(0.5))
                }

                ForEach(linePoints) { point in
                    LineMark(
                        x: .value("Day", point.date, unit: .day),
                        y: .value("Consumed", point.consumed),
                        series: .value("Series", "Consumed")
                    )
                    .interpolationMethod(interpolation)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(calorieTrendConsumedColor)
                }

                ForEach(linePoints) { point in
                    LineMark(
                        x: .value("Day", point.date, unit: .day),
                        y: .value("Burned", point.burned),
                        series: .value("Series", "Burned")
                    )
                    .interpolationMethod(interpolation)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(calorieTrendBurnedColor)
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

    private var calorieTrendConsumedColor: Color { accent }

    private var calorieTrendBurnedColor: Color { AppTheme.info }

    // MARK: - Weight Change

    func weightChangeChart(points: [WeightChangePoint], range: NetHistoryRange) -> some View {
        let sortedDates = points.map(\.date).sorted()
        let yAxisValues = weightChangeYAxisValues(for: points)
        let yDomain = weightChangeYDomain(for: points)
        let showsActualMarkers = weightChangeAggregation(for: range) == .daily

        return Chart {
            RuleMark(y: .value("No Change", 0.0))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .foregroundStyle(textSecondary.opacity(0.35))

            ForEach(points) { point in
                LineMark(
                    x: .value("Day", point.date, unit: .day),
                    y: .value("Weight Change", point.change),
                    series: .value("Series", point.series.title)
                )
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: point.series == .expected ? 3 : 2.5, lineCap: .round, lineJoin: .round))
                .foregroundStyle(color(for: point.series))

                if point.series == .actual && showsActualMarkers {
                    PointMark(
                        x: .value("Day", point.date, unit: .day),
                        y: .value("Weight Change", point.change)
                    )
                    .symbolSize(40)
                    .foregroundStyle(color(for: point.series))
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: chartXAxisValues(for: sortedDates)) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(adaptiveChartLabel(for: date, totalPoints: range.dayCount))
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
                    if let doubleValue = value.as(Double.self) {
                        Text(weightAxisLabel(for: doubleValue))
                    }
                }
                .foregroundStyle(textSecondary)
            }
        }
        .chartYScale(domain: yDomain)
        .chartLegend(.hidden)
    }

    func chartXAxisValues(for points: [CalorieGraphPoint]) -> [Date] {
        chartXAxisValues(for: points.map(\.date))
    }

    func chartXAxisValues(for dates: [Date]) -> [Date] {
        guard !dates.isEmpty else { return [] }
        guard dates.count > 4 else { return dates }

        let targetMarks = min(4, dates.count)
        let lastIndex = dates.count - 1
        let step = max(1, lastIndex / max(targetMarks - 1, 1))
        var indices = Array(stride(from: 0, through: lastIndex, by: step))
        if indices.last != lastIndex {
            indices.append(lastIndex)
        }
        return indices.map { dates[$0] }
    }

    func chartYAxisValues(for points: [CalorieGraphPoint]) -> [Int] {
        let maxValue = max(points.map(\.calories).max() ?? 0, points.map(\.goal).max() ?? 0, points.map(\.burned).max() ?? 0, 1)
        let roundedTop = max(500, ((maxValue + 499) / 500) * 500)
        let middle = roundedTop / 2
        return Array(Set([0, middle, roundedTop])).sorted()
    }

    func calorieLinePoints(for points: [CalorieGraphPoint], range: HistoryChartRange?) -> [CalorieLinePoint] {
        let visiblePoints: [CalorieLinePoint] = points.compactMap { point in
            guard point.calories > 0 else { return nil }
            guard !isDerivedBMRFallbackOnlyDay(point.dayIdentifier) else { return nil }

            return CalorieLinePoint(
                dayIdentifier: point.dayIdentifier,
                date: point.date,
                consumed: point.calories,
                burned: point.burned
            )
        }
        .sorted { $0.date < $1.date }

        guard let range else { return visiblePoints }
        let window = smoothingWindow(for: range)
        guard window > 1 else { return visiblePoints }
        return smoothedCalorieLinePoints(visiblePoints, window: window)
    }

    func smoothingWindow(for range: HistoryChartRange) -> Int {
        switch range {
        case .sevenDays, .thirtyDays:
            return 1
        case .sixMonths:
            return 5
        case .oneYear:
            return 9
        case .twoYears:
            return 15
        }
    }

    func smoothedCalorieLinePoints(_ points: [CalorieLinePoint], window: Int) -> [CalorieLinePoint] {
        guard points.count > 2, window > 1 else { return points }
        let radius = max((window - 1) / 2, 1)

        return points.enumerated().map { index, point in
            let start = max(0, index - radius)
            let end = min(points.count - 1, index + radius)
            let slice = points[start...end]

            let consumedAverage = Int((Double(slice.reduce(0) { $0 + $1.consumed }) / Double(slice.count)).rounded())
            let burnedAverage = Int((Double(slice.reduce(0) { $0 + $1.burned }) / Double(slice.count)).rounded())

            return CalorieLinePoint(
                dayIdentifier: point.dayIdentifier,
                date: point.date,
                consumed: consumedAverage,
                burned: burnedAverage
            )
        }
    }

    func averageValue(for values: [Int]) -> Int {
        guard !values.isEmpty else { return 0 }
        let total = values.reduce(0, +)
        return Int((Double(total) / Double(values.count)).rounded())
    }

    func calorieAverageLinePoints(for points: [CalorieGraphPoint]) -> [CalorieAverageLinePoint] {
        guard let firstDate = points.first?.date, let lastDate = points.last?.date else { return [] }

        let averageEligiblePoints = points.filter { $0.calories > 0 && !isDerivedBMRFallbackOnlyDay($0.dayIdentifier) }
        guard !averageEligiblePoints.isEmpty else { return [] }

        let consumedAverage = averageValue(for: averageEligiblePoints.map(\.calories))
        let burnedAverage = averageValue(for: averageEligiblePoints.map(\.burned))

        return [
            CalorieAverageLinePoint(date: firstDate, calories: consumedAverage, series: .consumed, index: 0),
            CalorieAverageLinePoint(date: lastDate, calories: consumedAverage, series: .consumed, index: 1),
            CalorieAverageLinePoint(date: firstDate, calories: burnedAverage, series: .burned, index: 0),
            CalorieAverageLinePoint(date: lastDate, calories: burnedAverage, series: .burned, index: 1)
        ]
    }

    func isDerivedBMRFallbackOnlyDay(_ identifier: String) -> Bool {
        guard identifier != todayDayIdentifier else { return false }
        guard dailyBurnedCalorieArchive[identifier] == nil else { return false }
        guard dailyCalorieGoalArchive[identifier] == nil else { return false }

        let hasFoodEntries = !entries(forDayIdentifier: identifier).isEmpty
        let hasExerciseEntries = !exercises(forDayIdentifier: identifier).isEmpty
        return !hasFoodEntries && !hasExerciseEntries
    }

    func weightChangeAggregation(for range: NetHistoryRange) -> WeightChangeAggregation {
        switch range {
        case .sevenDays, .thirtyDays:
            return .daily
        case .sixMonths:
            return .weekly
        case .oneYear, .twoYears:
            return .monthly
        }
    }

    func aggregatedWeightChangePoints(
        _ points: [WeightChangePoint],
        aggregation: WeightChangeAggregation
    ) -> [WeightChangePoint] {
        guard aggregation != .daily else { return points }
        guard !points.isEmpty else { return [] }

        let grouped = Dictionary(grouping: points) { point in
            aggregatedWeightBucketDate(for: point.date, aggregation: aggregation)
        }

        return grouped.keys.sorted().compactMap { bucketDate in
            guard let bucketPoints = grouped[bucketDate], let lastPoint = bucketPoints.max(by: { $0.date < $1.date }) else {
                return nil
            }

            return WeightChangePoint(
                date: bucketDate,
                change: lastPoint.change,
                series: lastPoint.series
            )
        }
    }

    func aggregatedWeightBucketDate(for date: Date, aggregation: WeightChangeAggregation) -> Date {
        switch aggregation {
        case .daily:
            return centralCalendar.startOfDay(for: date)
        case .weekly:
            let startOfDay = centralCalendar.startOfDay(for: date)
            return centralCalendar.dateInterval(of: .weekOfYear, for: startOfDay)?.start ?? startOfDay
        case .monthly:
            let startOfDay = centralCalendar.startOfDay(for: date)
            return centralCalendar.dateInterval(of: .month, for: startOfDay)?.start ?? startOfDay
        }
    }

    func weightChangeYDomain(for points: [WeightChangePoint]) -> ClosedRange<Double> {
        let minValue = min(points.map(\.change).min() ?? 0, 0)
        let maxValue = max(points.map(\.change).max() ?? 0, 0)
        let span = max(maxValue - minValue, 0.6)
        let padding = max(span * 0.15, 0.2)
        return (minValue - padding)...(maxValue + padding)
    }

    func weightChangeYAxisValues(for points: [WeightChangePoint]) -> [Double] {
        let domain = weightChangeYDomain(for: points)
        let lower = roundedWeightTick(domain.lowerBound)
        let upper = roundedWeightTick(domain.upperBound)
        let middle = roundedWeightTick((lower + upper) / 2)
        return Array(Set([lower, middle, 0, upper])).sorted()
    }

    func roundedWeightTick(_ value: Double) -> Double {
        (value * 2).rounded() / 2
    }

    func adaptiveChartLabel(for date: Date, totalPoints: Int) -> String {
        if totalPoints <= 30 {
            return date.formatted(.dateTime.month(.abbreviated).day())
        }
        return date.formatted(.dateTime.month(.abbreviated))
    }

    func weightAxisLabel(for value: Double) -> String {
        let sign = value > 0 ? "+" : ""
        return "\(sign)\(value.formatted(.number.precision(.fractionLength(1))))"
    }

    func formattedWeightChange(_ value: Double) -> String {
        let sign = value > 0 ? "+" : ""
        return "\(sign)\(value.formatted(.number.precision(.fractionLength(1)))) lb"
    }

    func color(for series: WeightChangeSeries) -> Color {
        switch series {
        case .expected:
            return accent
        case .actual:
            return .green
        }
    }

    func historyBarColor(for point: CalorieGraphPoint) -> Color {
        historyBarColor(
            calories: point.calories,
            goal: point.goal,
            burned: point.burned,
            goalType: goalTypeForDay(point.dayIdentifier)
        )
    }

    enum CalorieGoalState {
        case green
        case yellow
        case red
    }

    func historyBarColor(calories: Int, goal: Int, burned: Int, goalType: GoalType) -> Color {
        color(for: calorieGoalState(consumed: calories, goal: goal, burned: burned, goalType: goalType))
    }

    func calorieGoalState(consumed: Int, goal: Int, burned: Int, goalType: GoalType) -> CalorieGoalState {
        let safeGoal = max(goal, 1)
        let safeBurned = max(burned, 1)
        let consumedValue = max(consumed, 0)

        if goalType == .fixed {
            if consumedValue <= safeGoal { return .green }
            if consumedValue < safeBurned { return .yellow }
            return .red
        }

        let isSurplus = safeGoal > safeBurned

        if isSurplus {
            if consumedValue < safeBurned { return .yellow }
            if consumedValue <= safeGoal { return .green }
            return .red
        } else {
            // Deficit: goal < burned. Green = at or below goal, yellow = between goal and burned, red = over burned
            if consumedValue > safeBurned { return .red }
            if consumedValue <= safeGoal { return .green }
            return .yellow
        }
    }

    func color(for state: CalorieGoalState) -> Color {
        switch state {
        case .green:  return Color.green
        case .yellow: return Color.yellow
        case .red:    return Color.red
        }
    }

    func progressRow(
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

    func paletteForNutrient(_ key: String, progress: Double) -> (start: Color, end: Color) {
        if appThemeStyleRaw == AppThemeStyle.blueprint.rawValue {
            return blueprintPaletteForNutrient(key, progress: progress)
        }
        switch key.lowercased() {
        // Ember: each macro maps to the warm palette (teal / amber / clay)
        case "g_protein":
            return (
                interpolateColor(from: UIColor(red: 0.482, green: 0.659, blue: 0.620, alpha: 1.0),
                                 to: UIColor(red: 0.353, green: 0.565, blue: 0.533, alpha: 1.0), progress: progress),
                interpolateColor(from: UIColor(red: 0.353, green: 0.565, blue: 0.533, alpha: 1.0),
                                 to: UIColor(red: 0.282, green: 0.490, blue: 0.459, alpha: 1.0), progress: progress)
            )
        case "g_carbs":
            return (
                interpolateColor(from: UIColor(red: 0.769, green: 0.588, blue: 0.353, alpha: 1.0),
                                 to: UIColor(red: 0.651, green: 0.478, blue: 0.259, alpha: 1.0), progress: progress),
                interpolateColor(from: UIColor(red: 0.651, green: 0.478, blue: 0.259, alpha: 1.0),
                                 to: UIColor(red: 0.549, green: 0.384, blue: 0.188, alpha: 1.0), progress: progress)
            )
        case "g_fat", "g_saturated_fat", "g_trans_fat":
            return (
                interpolateColor(from: UIColor(red: 0.604, green: 0.533, blue: 0.471, alpha: 1.0),
                                 to: UIColor(red: 0.502, green: 0.435, blue: 0.380, alpha: 1.0), progress: progress),
                interpolateColor(from: UIColor(red: 0.502, green: 0.435, blue: 0.380, alpha: 1.0),
                                 to: UIColor(red: 0.412, green: 0.353, blue: 0.306, alpha: 1.0), progress: progress)
            )
        case "g_sugar", "g_added_sugar":
            return (
                interpolateColor(from: UIColor(red: 0.722, green: 0.447, blue: 0.290, alpha: 1.0),
                                 to: UIColor(red: 0.604, green: 0.353, blue: 0.216, alpha: 1.0), progress: progress),
                interpolateColor(from: UIColor(red: 0.604, green: 0.353, blue: 0.216, alpha: 1.0),
                                 to: UIColor(red: 0.510, green: 0.275, blue: 0.153, alpha: 1.0), progress: progress)
            )
        case "mg_sodium":
            return (
                interpolateColor(from: UIColor(red: 0.447, green: 0.518, blue: 0.580, alpha: 1.0),
                                 to: UIColor(red: 0.353, green: 0.420, blue: 0.490, alpha: 1.0), progress: progress),
                interpolateColor(from: UIColor(red: 0.353, green: 0.420, blue: 0.490, alpha: 1.0),
                                 to: UIColor(red: 0.275, green: 0.341, blue: 0.408, alpha: 1.0), progress: progress)
            )
        case "mg_calcium":
            return (
                interpolateColor(from: UIColor(red: 0.482, green: 0.659, blue: 0.620, alpha: 1.0),
                                 to: UIColor(red: 0.400, green: 0.576, blue: 0.620, alpha: 1.0), progress: progress),
                interpolateColor(from: UIColor(red: 0.400, green: 0.576, blue: 0.620, alpha: 1.0),
                                 to: UIColor(red: 0.318, green: 0.490, blue: 0.537, alpha: 1.0), progress: progress)
            )
        case "mg_iron":
            return (
                interpolateColor(from: UIColor(red: 0.722, green: 0.408, blue: 0.345, alpha: 1.0),
                                 to: UIColor(red: 0.580, green: 0.290, blue: 0.235, alpha: 1.0), progress: progress),
                interpolateColor(from: UIColor(red: 0.580, green: 0.290, blue: 0.235, alpha: 1.0),
                                 to: UIColor(red: 0.459, green: 0.208, blue: 0.165, alpha: 1.0), progress: progress)
            )
        case "mg_vitamin_c":
            return (
                interpolateColor(from: UIColor(red: 0.451, green: 0.647, blue: 0.502, alpha: 1.0),
                                 to: UIColor(red: 0.353, green: 0.549, blue: 0.404, alpha: 1.0), progress: progress),
                interpolateColor(from: UIColor(red: 0.353, green: 0.549, blue: 0.404, alpha: 1.0),
                                 to: UIColor(red: 0.275, green: 0.459, blue: 0.322, alpha: 1.0), progress: progress)
            )
        default:
            return (
                interpolateColor(from: UIColor(red: 0.553, green: 0.482, blue: 0.620, alpha: 1.0),
                                 to: UIColor(red: 0.451, green: 0.380, blue: 0.518, alpha: 1.0), progress: progress),
                interpolateColor(from: UIColor(red: 0.451, green: 0.380, blue: 0.518, alpha: 1.0),
                                 to: UIColor(red: 0.361, green: 0.298, blue: 0.427, alpha: 1.0), progress: progress)
            )
        }
    }

    private func blueprintPaletteForNutrient(_ key: String, progress: Double) -> (start: Color, end: Color) {
        switch key.lowercased() {
        case "g_protein":
            return (
                interpolateColor(from: UIColor.systemMint,  to: UIColor.systemTeal,   progress: progress),
                interpolateColor(from: UIColor.systemTeal,  to: UIColor.systemCyan,   progress: progress)
            )
        case "g_carbs":
            return (
                interpolateColor(from: UIColor.systemYellow, to: UIColor.systemOrange, progress: progress),
                interpolateColor(from: UIColor.systemOrange, to: UIColor.systemRed,    progress: progress)
            )
        case "g_fat", "g_saturated_fat", "g_trans_fat":
            return (
                interpolateColor(from: UIColor.systemOrange, to: UIColor.systemYellow, progress: progress),
                interpolateColor(from: UIColor.systemYellow, to: UIColor.systemOrange, progress: progress)
            )
        case "g_sugar", "g_added_sugar":
            return (
                interpolateColor(from: UIColor.systemPink, to: UIColor.systemRed,  progress: progress),
                interpolateColor(from: UIColor.systemRed,  to: UIColor.systemPink, progress: progress)
            )
        case "mg_sodium":
            return (
                interpolateColor(from: UIColor.systemBlue, to: UIColor.systemCyan, progress: progress),
                interpolateColor(from: UIColor.systemCyan, to: UIColor.systemBlue, progress: progress)
            )
        case "mg_calcium":
            return (
                interpolateColor(from: UIColor.systemGreen, to: UIColor.systemMint, progress: progress),
                interpolateColor(from: UIColor.systemMint,  to: UIColor.systemTeal, progress: progress)
            )
        case "mg_iron":
            return (
                interpolateColor(from: UIColor.systemRed,  to: UIColor.systemPink,  progress: progress),
                interpolateColor(from: UIColor.systemPink, to: UIColor.systemOrange, progress: progress)
            )
        case "mg_vitamin_c":
            return (
                interpolateColor(from: UIColor.systemGreen, to: UIColor.systemTeal, progress: progress),
                interpolateColor(from: UIColor.systemTeal,  to: UIColor.systemMint, progress: progress)
            )
        default:
            return (
                interpolateColor(from: UIColor.systemIndigo,  to: UIColor.systemPurple, progress: progress),
                interpolateColor(from: UIColor.systemPurple, to: UIColor.systemIndigo,  progress: progress)
            )
        }
    }

    /// Calorie progress bar colors — keep green/yellow/red for readability
    static let barGreen  = Color(red: 0.22, green: 0.78, blue: 0.35)
    static let barYellow = Color(red: 1.0,  green: 0.76, blue: 0.12)
    static let barRed    = Color(red: 0.95, green: 0.26, blue: 0.21)

    func calorieBarPalette(consumed: Int, goal: Int, burned: Int) -> (start: Color, end: Color) {
        switch calorieGoalState(consumed: consumed, goal: goal, burned: burned, goalType: goalType) {
        case .green:
            return (Self.barGreen, Self.barGreen)
        case .yellow:
            return (Self.barYellow, Self.barYellow)
        case .red:
            return (Self.barRed, Self.barRed)
        }
    }


}
