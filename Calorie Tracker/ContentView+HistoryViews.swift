// Calorie Tracker 2026

import SwiftUI
import Charts

extension ContentView {

    var historyCalendarCard: some View {
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
    func historyCalendarDay(_ date: Date?) -> some View {
        if let date {
            let identifier = centralDayIdentifier(for: date)
            let isToday = identifier == todayDayIdentifier
            let dayEntries = entries(forDayIdentifier: identifier)
            let hasEntries = !dayEntries.isEmpty
            let dayCalories = dayEntries.reduce(0) { $0 + $1.calories }
            let dayGoal = calorieGoalForDay(identifier)
            let dayBurned = burnedCaloriesForDay(identifier)
            let dayDotColor = historyBarColor(
                calories: dayCalories,
                goal: dayGoal,
                burned: dayBurned,
                goalType: goalTypeForDay(identifier)
            )

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

    func historyDayDetailSheet(summary: HistoryDaySummary) -> some View {
        let dayGoal = calorieGoalForDay(summary.dayIdentifier)
        let dayBurned = burnedCaloriesForDay(summary.dayIdentifier)
        let dayGoalType = goalTypeForDay(summary.dayIdentifier)
        let nutrientTotals = nutrientTotals(for: summary.dayIdentifier)
        let dayMealDistribution = mealDistributionData(for: summary.dayIdentifier)
        let calorieColor = historyBarColor(
            calories: summary.totalCalories,
            goal: dayGoal,
            burned: dayBurned,
            goalType: dayGoalType
        )
        let rawProgress = Double(summary.totalCalories) / Double(max(dayGoal, 1))
        let barProgress = min(max(rawProgress, 0), 1)
        let statusText: String
        let statusColor: Color
        if summary.totalCalories == 0 {
            statusText = "No Intake"
            statusColor = textSecondary
        } else if dayGoalType == .fixed {
            if summary.totalCalories <= dayGoal {
                statusText = "Under Goal"
                statusColor = Color.green
            } else if summary.totalCalories < dayBurned {
                statusText = "Above Goal"
                statusColor = Color.yellow
            } else {
                statusText = "Over Burned"
                statusColor = Color.red
            }
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

    func calorieDetailBar(calories: Int, goal: Int, progress: Double, color: Color) -> some View {
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

    func nutrientDetailRow(nutrient: NutrientDefinition, total: Int, goal: Int) -> some View {
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

    func historySummaryMetric(title: String, value: String, valueColor: Color? = nil) -> some View {
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

    var historyGraphCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("7-Day Calorie Trends")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(textPrimary)
                Spacer()
                Button("See More") {
                    expandedHistoryChartRange = .sevenDays
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

    var netCalorieHistoryCard: some View {
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
                        Button {
                            netHistoryRange = range
                            Haptics.selection()
                        } label: {
                            if range == netHistoryRange {
                                Label(range.title, systemImage: "checkmark")
                            } else {
                                Text(range.title)
                            }
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

    var historyMealDistributionCard: some View {
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
                        Button {
                            historyDistributionRange = range
                            Haptics.selection()
                        } label: {
                            if range == historyDistributionRange {
                                Label(range.title, systemImage: "checkmark")
                            } else {
                                Text(range.title)
                            }
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

    var weightChangeComparisonButton: some View {
        Button {
            weightChangeComparisonRange = .sevenDays
            isWeightChangeComparisonPresented = true
            Haptics.selection()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "chart.xyaxis.line")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Compare Weight Change")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(textPrimary)
                        .multilineTextAlignment(.leading)
                    Text("See expected vs actual change from calorie balance and weigh-ins.")
                        .font(.subheadline)
                        .foregroundStyle(textSecondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 12)

                Image(systemName: "arrow.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(
                        Circle()
                            .fill(accent)
                    )
            }
            .frame(minHeight: 84)
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                accent.opacity(colorScheme == .dark ? 0.20 : 0.12),
                                surfacePrimary
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(accent.opacity(0.35), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .pressableCardStyle()
    }

    var weeklyInsightButton: some View {
        Button {
            Haptics.selection()
            Task {
                await generateWeeklyInsight()
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "sparkles")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 6) {
                    Text("View Weekly Insights")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(textPrimary)
                        .multilineTextAlignment(.leading)
                    Text(isWeeklyInsightLoading ? "Analyzing this week..." : "Get a brief AI summary of your current calendar week.")
                        .font(.subheadline)
                        .foregroundStyle(textSecondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 12)

                Image(systemName: "arrow.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(
                        Circle()
                            .fill(accent)
                    )
            }
            .frame(minHeight: 84)
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                accent.opacity(colorScheme == .dark ? 0.20 : 0.12),
                                surfacePrimary
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(accent.opacity(0.35), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .pressableCardStyle()
        .disabled(isWeeklyInsightLoading)
        .sheet(isPresented: $isWeeklyInsightPresented) {
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
                            HStack(spacing: 10) {
                                Image(systemName: "sparkles")
                                    .font(.title2.weight(.semibold))
                                    .foregroundStyle(accent)
                                Text("Weekly Insight")
                                    .font(.system(size: 28, weight: .bold, design: .rounded))
                                    .foregroundStyle(textPrimary)
                            }

                            let cachedFallbackInsight = weeklyInsightCachedText.trimmingCharacters(in: .whitespacesAndNewlines)
                            let liveInsight = weeklyInsightText?.trimmingCharacters(in: .whitespacesAndNewlines)
                            let displayInsight: String? = {
                                if let liveInsight, !liveInsight.isEmpty {
                                    return liveInsight
                                }
                                return cachedFallbackInsight.isEmpty ? nil : cachedFallbackInsight
                            }()

                            if let text = displayInsight {
                                let sections = Self.splitWeeklyInsightIntoSections(text)
                                VStack(alignment: .leading, spacing: 12) {
                                    ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(section.title)
                                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                                .foregroundStyle(textPrimary)
                                                .multilineTextAlignment(.leading)
                                                .fixedSize(horizontal: false, vertical: true)

                                            weeklyInsightSectionBodyView(section.body)
                                        }
                                    }
                                }
                            } else if let error = weeklyInsightErrorMessage {
                                Text(error)
                                    .font(.body)
                                    .foregroundStyle(.red)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            } else {
                                Text("No recent data to analyze yet. Log food, exercise, and weigh-ins to see insights here.")
                                    .font(.body)
                                    .foregroundStyle(textSecondary)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(22)
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            isWeeklyInsightPresented = false
                        }
                        .font(.body.weight(.semibold))
                    }
                }
            }
        }
    }

    struct WeeklyInsightSection {
        let title: String
        let body: String
    }

    @ViewBuilder
    func weeklyInsightSectionBodyView(_ body: String) -> some View {
        let rawLines = body.split(whereSeparator: \.isNewline).map { String($0) }
        let bulletPrefixCandidates = ["- ", "• ", "* "]

        let bulletTexts: [String] = rawLines.compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            for prefix in bulletPrefixCandidates {
                if trimmed.hasPrefix(prefix) {
                    return String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            return nil
        }

        if !bulletTexts.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(bulletTexts.indices, id: \.self) { idx in
                    let bulletText = bulletTexts[idx]
                    HStack(alignment: .top, spacing: 10) {
                        Text("•")
                            .font(.body)
                            .foregroundStyle(textPrimary)
                            .padding(.top, 2)

                        if let attributed = try? AttributedString(markdown: bulletText) {
                            Text(attributed)
                                .font(.body)
                                .foregroundStyle(textPrimary)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            Text(bulletText)
                                .font(.body)
                                .foregroundStyle(textPrimary)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        } else {
            if let attributed = try? AttributedString(markdown: body) {
                Text(attributed)
                    .font(.body)
                    .foregroundStyle(textPrimary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(body)
                    .font(.body)
                    .foregroundStyle(textPrimary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    static func splitWeeklyInsightIntoSections(_ text: String) -> [WeeklyInsightSection] {
        let headings = [
            "Week Overview",
            "Calorie Intake",
            "Activity & Calories Burned",
            "Calorie Balance",
            "Weight Trend",
            "Logging & Data Quality",
            "Macros / Nutrient Pattern"
        ]

        // Remove common markdown wrappers around headings so matching is reliable.
        var normalized = text
        for heading in headings {
            normalized = normalized.replacingOccurrences(of: "**\(heading)**", with: heading)
            normalized = normalized.replacingOccurrences(of: "## \(heading)", with: heading)
            normalized = normalized.replacingOccurrences(of: "# \(heading)", with: heading)
        }

        // Find the first occurrence of each heading, then build segments between them.
        var occurrences: [(heading: String, range: Range<String.Index>)] = []
        for heading in headings {
            if let range = normalized.range(of: heading) {
                occurrences.append((heading: heading, range: range))
            }
        }
        occurrences.sort { $0.range.lowerBound < $1.range.lowerBound }

        // If we failed to detect headings, just show everything under a default title.
        guard !occurrences.isEmpty else {
            return [WeeklyInsightSection(title: "Weekly Insight", body: text.trimmingCharacters(in: .whitespacesAndNewlines))]
        }

        var sections: [WeeklyInsightSection] = []
        sections.reserveCapacity(occurrences.count)

        for i in 0..<occurrences.count {
            let current = occurrences[i]
            let bodyStart = current.range.upperBound
            let bodyEnd = (i + 1 < occurrences.count) ? occurrences[i + 1].range.lowerBound : normalized.endIndex
            var body = String(normalized[bodyStart..<bodyEnd])
            body = body.trimmingCharacters(in: .whitespacesAndNewlines)
            sections.append(WeeklyInsightSection(title: current.heading, body: body))
        }

        return sections
    }


}
