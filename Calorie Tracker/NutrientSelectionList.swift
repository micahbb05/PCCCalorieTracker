import SwiftUI

struct NutrientSelectionList: View {
    @Binding var trackedNutrientKeys: [String]
    let availableNutrients: [NutrientDefinition]

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
                                    isSelected ? Color(red: 0.20, green: 0.50, blue: 0.98) : Color.white.opacity(0.24),
                                    lineWidth: 2
                                )
                                .frame(width: 24, height: 24)

                            if isSelected {
                                Circle()
                                    .fill(Color(red: 0.20, green: 0.50, blue: 0.98))
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
                                    .fill(Color.white.opacity(0.08))
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
