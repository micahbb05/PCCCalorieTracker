import SwiftUI

extension View {
    func cardStyle(surface: Color, stroke: Color) -> some View {
        background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(stroke, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.14), radius: 14, x: 0, y: 8)
    }

    func inputStyle(surface: Color, text: Color, secondary: Color) -> some View {
        padding(.horizontal, 12)
            .padding(.vertical, 10)
            .foregroundStyle(text)
            .tint(text)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(secondary.opacity(0.35), lineWidth: 1)
            )
    }

    func pressableCardStyle() -> some View {
        buttonStyle(PressableCardButtonStyle())
    }
}

private struct PressableCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

struct ServingNutrientGridCard: View {
    private struct NutrientRow: Identifiable {
        let id: String
        let label: String
        let value: String?
        let unit: String
    }

    let title: String
    let calories: Int
    let nutrientValues: [String: Int]
    let multiplier: Double
    let trackedNutrientKeys: [String]
    let displayedNutrientKeys: [String]?
    let showNAForMissingNutrients: Bool
    let surface: Color
    let stroke: Color
    let titleColor: Color
    let labelColor: Color
    let valueColor: Color

    private var nutrientRows: [NutrientRow] {
        let trackedKeys = trackedNutrientKeys.map { $0.lowercased() }
        let trackedSet = Set(trackedKeys)
        let sourceKeys = (displayedNutrientKeys ?? trackedNutrientKeys).map { $0.lowercased() }
        let orderedUniqueKeys = Array(NSOrderedSet(array: sourceKeys)) as? [String] ?? sourceKeys

        let trackedRows = orderedUniqueKeys
            .filter { key in
                key != "calories" &&
                trackedSet.contains(key) &&
                !NutrientCatalog.nonTrackableKeys.contains(key)
            }
            .compactMap { key -> NutrientRow? in
                let definition = NutrientCatalog.definition(for: key)
                let scaledValue: String?
                if let rawValue = nutrientValues[key] {
                    scaledValue = "\(Int((Double(rawValue) * multiplier).rounded()))"
                } else {
                    if showNAForMissingNutrients {
                        return nil
                    }
                    scaledValue = "0"
                }
                return NutrientRow(
                    id: key,
                    label: definition.name,
                    value: scaledValue,
                    unit: definition.unit
                )
            }

        return [
            NutrientRow(
                id: "calories",
                label: "Calories",
                value: "\(Int((Double(calories) * multiplier).rounded()))",
                unit: "cal"
            )
        ] + trackedRows
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(titleColor)

            VStack(spacing: 0) {
                ForEach(Array(nutrientRows.enumerated()), id: \.element.id) { index, row in
                    HStack(spacing: 12) {
                        Text(row.label)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(labelColor)
                        Spacer(minLength: 8)
                        Text(row.value.map { "\($0) \(row.unit)" } ?? "")
                            .font(.headline.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(valueColor)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)

                    if index < nutrientRows.count - 1 {
                        Divider()
                            .overlay(stroke.opacity(0.8))
                            .padding(.horizontal, 14)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(surface.opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(stroke.opacity(0.7), lineWidth: 1)
            )
        }
        .padding(18)
        .cardStyle(surface: surface, stroke: stroke)
        .accessibilityLabel(title)
    }
}

extension ServingNutrientGridCard {
    init(
        title: String,
        calories: Int,
        nutrientValues: [String: Int],
        multiplier: Double,
        trackedNutrientKeys: [String],
        displayedNutrientKeys: [String]?,
        surface: Color,
        stroke: Color,
        titleColor: Color,
        labelColor: Color,
        valueColor: Color
    ) {
        self.init(
            title: title,
            calories: calories,
            nutrientValues: nutrientValues,
            multiplier: multiplier,
            trackedNutrientKeys: trackedNutrientKeys,
            displayedNutrientKeys: displayedNutrientKeys,
            showNAForMissingNutrients: false,
            surface: surface,
            stroke: stroke,
            titleColor: titleColor,
            labelColor: labelColor,
            valueColor: valueColor
        )
    }
}
