import SwiftUI

struct AppSettingsTabView: View {
    @Binding var trackedNutrientKeys: [String]
    let availableNutrients: [NutrientDefinition]
    @Binding var selectedAppIconChoiceRaw: String
    @Binding var useAIBaseServings: Bool
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
            settingsCard(
                title: "Nutrition Tracking",
                subtitle: "Choose which nutrients appear throughout the app."
            ) {
                NutrientSelectionList(
                    trackedNutrientKeys: $trackedNutrientKeys,
                    availableNutrients: availableNutrients
                )
            }

            settingsCard(title: "AI Features") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Let AI adjust base servings")
                                .font(.subheadline.weight(.semibold))
                        }

                        Spacer(minLength: 0)

                        Toggle("", isOn: $useAIBaseServings)
                            .labelsHidden()
                            .tint(Color(red: 0.19, green: 0.52, blue: 1.0))
                    }

                    Text("Only affects AI plate estimates for items with unclear menu units like \"serving\" or \"each.\" When on, AI can infer the base serving. When off, the menu serving is used.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            settingsCard(title: "App Icon") {
                Picker("App Icon", selection: $selectedAppIconChoiceRaw) {
                    ForEach(AppIconChoice.allCases) { option in
                        Text(option.title).tag(option.rawValue)
                    }
                }
                .accessibilityLabel("App Icon")
                .pickerStyle(.segmented)
            }
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
                .foregroundStyle(.primary)

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(cardBackground)
    }
}
