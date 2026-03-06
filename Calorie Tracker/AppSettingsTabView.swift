import SwiftUI

struct AppSettingsTabView: View {
    @Binding var trackedNutrientKeys: [String]
    let availableNutrients: [NutrientDefinition]
    @Binding var selectedAppIconChoiceRaw: String
    @Binding var useAIBaseServings: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Track Nutrients")
                    .font(.headline.weight(.semibold))

                Text("Choose which nutrients appear throughout the app.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                NutrientSelectionList(
                    trackedNutrientKeys: $trackedNutrientKeys,
                    availableNutrients: availableNutrients
                )
            }

            Divider()
                .overlay(Color.secondary.opacity(0.18))

            VStack(alignment: .leading, spacing: 12) {
                Text("AI Plate Estimates")
                    .font(.headline.weight(.semibold))

                Toggle(isOn: $useAIBaseServings) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Let AI adjust base servings")
                            .font(.subheadline.weight(.medium))
                        Text("Only affects AI plate estimates for items with unclear menu units like \"serving\" or \"each.\" When on, AI can infer the base serving. When off, the menu serving is used.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(SwitchToggleStyle(tint: .accentColor))
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
                .fill(Color(uiColor: .secondarySystemBackground).opacity(colorScheme == .dark ? 0.82 : 0.55))
        )
    }
}
