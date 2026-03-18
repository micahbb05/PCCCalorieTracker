import SwiftUI

struct ProfileGoalsView: View {
    @Binding var deficitCalories: Int
    @Binding var goalTypeRaw: String
    @Binding var surplusCalories: Int
    @Binding var fixedGoalCalories: Int
    @Binding var useWeekendDeficit: Bool
    @Binding var weekendDeficitCalories: Int
    let trackedNutrientKeys: [String]
    @Binding var nutrientGoals: [String: Int]
    let healthAuthorizationState: HealthKitService.AuthorizationState
    let healthProfile: HealthKitService.SyncedProfile?
    let isUsingSyncedHealthFallback: Bool
    let syncedHealthSourceLabel: String?
    let bmrCalories: Int?
    let burnedCaloriesToday: Int
    let activeBurnedCaloriesToday: Int
    let isUsingAutomatedCalories: Bool
    @Binding var isCalibrationEnabled: Bool
    let calibrationOffsetCalories: Int
    let calibrationStatusText: String
    let calibrationSkipReason: String?
    let calibrationLastRunText: String
    let calibrationNextRunText: String
    let calibrationConfidenceText: String
    let onRequestHealthAccess: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var cardBackground: some View {
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
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionCard(title: "Calorie Goals") {
                calorieGoalsSection
            }

            sectionCard(title: "Nutrient Goals") {
                nutrientGoalsSection
            }

            sectionCard(title: "Body Profile") {
                bodyProfileSection
            }

            if goalTypeRaw != "fixed" {
                if isCalibrationEnabled {
                    sectionCard(
                        title: "Smart Adjustment",
                        trailing: {
                            Toggle("", isOn: $isCalibrationEnabled)
                                .labelsHidden()
                                .accessibilityLabel("Enable smart adjustment")
                                .tint(Color(red: 0.19, green: 0.52, blue: 1.0))
                        }
                    ) {
                        smartAdjustmentSection
                    }
                } else {
                    sectionCard(
                        title: "Smart Adjustment",
                        trailing: {
                            Toggle("", isOn: $isCalibrationEnabled)
                                .labelsHidden()
                                .accessibilityLabel("Enable smart adjustment")
                                .tint(Color(red: 0.19, green: 0.52, blue: 1.0))
                        }
                    ) {
                        Text("Auto-adjusts burned calories from your weekly Health weigh-ins.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func sectionCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        sectionCard(title: title, trailing: { EmptyView() }, content: content)
    }

    private func sectionCard<Content: View, Trailing: View>(
        title: String,
        @ViewBuilder trailing: () -> Trailing,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)

                Spacer(minLength: 0)

                trailing()
            }

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(cardBackground)
    }

    private var bodyProfileSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(isUsingSyncedHealthFallback ? "BMR is using synced Health data." : "BMR is calculated from Health data.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if isUsingSyncedHealthFallback {
                        Text("Source: \(syncedHealthSourceLabel ?? "iPhone").")
                            .font(.caption2)
                            .foregroundStyle(.secondary.opacity(0.85))
                    }
                }

                Spacer(minLength: 0)

                if healthAuthorizationState == .connected || isUsingSyncedHealthFallback {
                    healthStatusBadge
                }
            }

            if let healthProfile {
                HStack(spacing: 8) {
                    healthValueChip(title: "Sex", value: healthProfile.bmrProfile.sex.title)
                    healthValueChip(title: "Height", value: healthProfile.heightDisplay)
                    healthValueChip(title: "Weight", value: healthProfile.weightDisplay)
                }
            } else if healthAuthorizationState != .connected, !isUsingSyncedHealthFallback {
                Text(healthAuthorizationState.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                statPill(title: "BMR", value: bmrCalories.map { "\($0) cal" } ?? "--")
                statPill(title: "Burned", value: "\(burnedCaloriesToday) cal")
                statPill(title: "Activity", value: "\(activeBurnedCaloriesToday) cal")
            }

            if healthAuthorizationState == .notConnected {
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
            } else if healthAuthorizationState == .unavailable, isUsingSyncedHealthFallback {
                Text("This device cannot read Health directly. Showing synced profile and workout data from your \(syncedHealthSourceLabel ?? "iPhone").")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if healthAuthorizationState == .unavailable {
                Text("This device cannot read Health directly. Open the app on iPhone to sync profile and workout data.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !isUsingAutomatedCalories {
                Text("Health is connected, but some body data is still missing. Using a fallback average BMR until Health provides height, weight, sex, and age.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var calorieGoalsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Goal Type", selection: $goalTypeRaw) {
                Text("Deficit").tag("deficit")
                Text("Surplus").tag("surplus")
                Text("Fixed").tag("fixed")
            }
            .pickerStyle(.segmented)

            if goalTypeRaw == "surplus" {
                DeficitGoalEditor(
                    deficitCalories: $surplusCalories,
                    title: "Surplus Goal",
                    subtitle: "Added to burned calories",
                    helperText: nil,
                    accent: Color(red: 0.19, green: 0.52, blue: 1.0)
                )
            } else if goalTypeRaw == "fixed" {
                DeficitGoalEditor(
                    deficitCalories: $fixedGoalCalories,
                    title: "Fixed Calorie Goal",
                    subtitle: "Total calories to eat each day",
                    helperText: nil,
                    accent: Color(red: 0.19, green: 0.52, blue: 1.0),
                    maxCalories: 6000
                )
            } else {
                DeficitGoalEditor(
                    deficitCalories: $deficitCalories,
                    title: "Deficit Goal",
                    subtitle: "Subtracted from burned calories",
                    helperText: nil,
                    accent: Color(red: 0.19, green: 0.52, blue: 1.0)
                )
            }

            if goalTypeRaw != "fixed" {
                Toggle(isOn: $useWeekendDeficit) {
                    Text("Different goal on weekend")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                .tint(Color(red: 0.19, green: 0.52, blue: 1.0))

                if useWeekendDeficit {
                    DeficitGoalEditor(
                        deficitCalories: $weekendDeficitCalories,
                        title: goalTypeRaw == "surplus" ? "Weekend Surplus" : "Weekend Deficit",
                        subtitle: "Used on Saturday & Sunday",
                        helperText: nil,
                        accent: Color(red: 0.19, green: 0.52, blue: 1.0)
                    )
                }
            }

            if healthAuthorizationState == .connected, isUsingAutomatedCalories, goalTypeRaw != "fixed" {
                Text("Burned today includes BMR plus active calories (steps and exercise) personalized with your available profile data.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var smartAdjustmentSection: some View {
        Text(smartAdjustmentSummaryText)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var smartAdjustmentSummaryText: String {
        if let calibrationSkipReason, !calibrationSkipReason.isEmpty {
            return "Smart adjustment pending: \(calibrationSkipReason)"
        }

        if calibrationStatusText.localizedCaseInsensitiveContains("applied") {
            if calibrationOffsetCalories == 0 {
                return "No adjustment needed this week."
            }
            return "Adjusted by \(String(format: "%+d", calibrationOffsetCalories)) cal/day this week."
        }

        return "Smart adjustment pending: no adjustment applied yet."
    }

    private var nutrientGoalsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(trackedNutrientKeys, id: \.self) { key in
                let nutrient = NutrientCatalog.definition(for: key)
                let label = nutrient.unit.uppercased() == "CALORIES" ? nutrient.name : "\(nutrient.name) (\(nutrient.unit))"
                goalField(
                    title: label,
                    subtitle: nil,
                    value: nutrientGoalBinding(for: key),
                    onDecrement: { adjustNutrientGoal(for: key, delta: -nutrient.step) },
                    onIncrement: { adjustNutrientGoal(for: key, delta: nutrient.step) }
                )
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
        Text(isUsingSyncedHealthFallback ? "Synced" : healthAuthorizationState.title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(
                (healthAuthorizationState == .connected || isUsingSyncedHealthFallback)
                ? Color(red: 0.46, green: 0.90, blue: 0.60)
                : .white
            )
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(
                        (healthAuthorizationState == .connected || isUsingSyncedHealthFallback)
                        ? Color(red: 0.13, green: 0.28, blue: 0.18)
                        : Color.white.opacity(0.08)
                    )
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
