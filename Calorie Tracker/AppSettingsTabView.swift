import SwiftUI

struct AppSettingsTabView: View {
    @Binding var trackedNutrientKeys: [String]
    let availableNutrients: [NutrientDefinition]
    @Binding var selectedAppIconChoiceRaw: String
    @Binding var bmrSourceRaw: String
    @Binding var manualBMRCalories: Int
    @Binding var useAIBaseServings: Bool
    @Binding var smartMealRemindersEnabled: Bool
    @Binding var appThemeStyleRaw: String
    let cloudSyncStatusTitle: String
    let cloudSyncStatusDetail: String
    let cloudSyncStatusTint: Color
    let cloudSyncLastSuccessText: String
    let isCloudSyncInFlight: Bool
    let onRetryCloudSync: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var isBlueprint: Bool { appThemeStyleRaw == AppThemeStyle.blueprint.rawValue }

    private var cardSurface: Color {
        AppTheme.cardSurface(for: activeThemeStyle)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(cardSurface)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(secondaryTextColor.opacity(0.18), lineWidth: 1)
            )
    }

    private var titleColor: Color {
        isBlueprint ? Color(red: 0.95, green: 0.96, blue: 0.98) : Color(red: 0.961, green: 0.941, blue: 0.902)
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? AppTheme.secondaryText : Color(red: 0.45, green: 0.42, blue: 0.38)
    }

    private var activeThemeStyle: AppThemeStyle {
        AppThemeStyle(rawValue: appThemeStyleRaw) ?? .ember
    }

    private var nutritionAccentColor: Color {
        AppTheme.accent(for: activeThemeStyle)
    }

    private var nutritionNeutralColor: Color {
        AppTheme.neutral(for: activeThemeStyle)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            settingsCard(
                title: "Nutrition Tracking",
                subtitle: "Choose which nutrients appear throughout the app."
            ) {
                NutrientSelectionList(
                    trackedNutrientKeys: $trackedNutrientKeys,
                    availableNutrients: availableNutrients,
                    accentColor: nutritionAccentColor,
                    neutralColor: nutritionNeutralColor
                )
            }

            settingsCard(title: "App Appearance") {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Theme")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(titleColor)

                        Picker("Theme", selection: $appThemeStyleRaw) {
                            ForEach(AppThemeStyle.allCases) { style in
                                Text(style.title).tag(style.rawValue)
                            }
                        }
                        .accessibilityLabel("App Theme")
                        .pickerStyle(.segmented)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Icon")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(titleColor)

                        Picker("Icon", selection: selectedAppIconBinding) {
                            ForEach(AppIconChoice.allCases) { option in
                                Text(option.title).tag(option.rawValue)
                            }
                        }
                        .accessibilityLabel("App Icon")
                        .pickerStyle(.segmented)
                    }
                }
            }

            settingsCard(title: "AI Features") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Let AI adjust base servings")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(titleColor)
                        }

                        Spacer(minLength: 0)

                        Toggle("", isOn: $useAIBaseServings)
                            .labelsHidden()
                    }

                    Text("Only affects AI plate estimates for items with unclear menu units like \"serving\" or \"each.\" When on, AI can infer the base serving. When off, the menu serving is used.")
                        .font(.caption)
                        .foregroundStyle(secondaryTextColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            settingsCard(title: "Reminders") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Smart meal reminders")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(titleColor)
                        }

                        Spacer(minLength: 0)

                        Toggle("", isOn: $smartMealRemindersEnabled)
                            .labelsHidden()
                    }

                    Text("Learns the meal types and times you usually log, then reminds you only after that meal appears to be missed.")
                        .font(.caption)
                        .foregroundStyle(secondaryTextColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            settingsCard(title: "BMR Source") {
                Picker("BMR Source", selection: bmrSourceBinding) {
                    Text("Automatic").tag(ContentView.BMRSource.automatic.rawValue)
                    Text("Manual").tag(ContentView.BMRSource.manual.rawValue)
                }
                .accessibilityLabel("BMR Source")
                .pickerStyle(.segmented)

                Text("Automatic uses Health profile data when available. Manual always uses your configured manual BMR.")
                    .font(.caption)
                    .foregroundStyle(secondaryTextColor)
                    .fixedSize(horizontal: false, vertical: true)

                if bmrSourceRaw == ContentView.BMRSource.manual.rawValue {
                    DeficitGoalEditor(
                        deficitCalories: $manualBMRCalories,
                        title: "Manual BMR",
                        subtitle: "Calories burned at rest each day",
                        helperText: "Used while BMR Source is set to Manual.",
                        accent: AppTheme.accent,
                        minCalories: 800,
                        maxCalories: 4000
                    )
                }
            }
        }
        .onAppear(perform: normalizePickerSelections)
    }

    private var selectedAppIconBinding: Binding<String> {
        Binding(
            get: {
                AppIconChoice(rawValue: selectedAppIconChoiceRaw)?.rawValue
                    ?? AppIconChoice.standard.rawValue
            },
            set: { newValue in
                selectedAppIconChoiceRaw = AppIconChoice(rawValue: newValue)?.rawValue
                    ?? AppIconChoice.standard.rawValue
            }
        )
    }

    private var bmrSourceBinding: Binding<String> {
        Binding(
            get: {
                ContentView.BMRSource(rawValue: bmrSourceRaw)?.rawValue
                    ?? ContentView.BMRSource.automatic.rawValue
            },
            set: { newValue in
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    bmrSourceRaw = ContentView.BMRSource(rawValue: newValue)?.rawValue
                        ?? ContentView.BMRSource.automatic.rawValue
                }
            }
        )
    }

    private func normalizePickerSelections() {
        if AppIconChoice(rawValue: selectedAppIconChoiceRaw) == nil {
            selectedAppIconChoiceRaw = AppIconChoice.standard.rawValue
        }
        if ContentView.BMRSource(rawValue: bmrSourceRaw) == nil {
            bmrSourceRaw = ContentView.BMRSource.automatic.rawValue
        }
    }

    private func settingsCard<Content: View>(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(titleColor)

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(secondaryTextColor)
                    .fixedSize(horizontal: false, vertical: true)
            }

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(cardBackground)
    }
}
