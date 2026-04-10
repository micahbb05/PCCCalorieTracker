import SwiftUI

struct NutrientSelectionList: View {
    @Binding var trackedNutrientKeys: [String]
    let availableNutrients: [NutrientDefinition]
    let accentColor: Color
    let neutralColor: Color

    init(
        trackedNutrientKeys: Binding<[String]>,
        availableNutrients: [NutrientDefinition],
        accentColor: Color = AppTheme.accent,
        neutralColor: Color = AppTheme.neutral
    ) {
        _trackedNutrientKeys = trackedNutrientKeys
        self.availableNutrients = availableNutrients
        self.accentColor = accentColor
        self.neutralColor = neutralColor
    }

    private var selectedKeys: Set<String> {
        Set(trackedNutrientKeys)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(availableNutrients) { nutrient in
                let isSelected = selectedKeys.contains(nutrient.key)

                Button {
                    toggleSelection(for: nutrient.key)
                } label: {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .strokeBorder(
                                    isSelected ? accentColor : neutralColor.opacity(0.45),
                                    lineWidth: 2
                                )
                                .frame(width: 24, height: 24)

                            if isSelected {
                                Circle()
                                    .fill(accentColor)
                                    .frame(width: 12, height: 12)
                            }
                        }

                        Text(nutrient.name)
                            .foregroundStyle(.primary)

                        Spacer()

                        Text(nutrient.unit)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(neutralColor.opacity(0.18))
                            )
                    }
                    .contentShape(Rectangle())
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(nutrient.name), \(isSelected ? "selected" : "not selected")")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityHint("Double tap to toggle selection.")
            }
        }
    }

    private func toggleSelection(for key: String) {
        if selectedKeys.contains(key) {
            trackedNutrientKeys.removeAll { $0 == key }
        } else if !trackedNutrientKeys.contains(key) {
            trackedNutrientKeys.append(key)
        }
    }
}
