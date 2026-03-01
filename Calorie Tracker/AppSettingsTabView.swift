import SwiftUI

struct AppSettingsTabView: View {
    @Binding var trackedNutrientKeys: [String]
    let availableNutrients: [NutrientDefinition]
    @Binding var selectedAppIconChoiceRaw: String

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Track Nutrients")
                    .font(.headline.weight(.semibold))

                Text("Choose which nutrients appear throughout the app.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                NutrientSelectionList(
                    trackedNutrientKeys: $trackedNutrientKeys,
                    availableNutrients: availableNutrients
                )
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
                .fill(Color(uiColor: .secondarySystemBackground).opacity(0.55))
        )
    }
}
