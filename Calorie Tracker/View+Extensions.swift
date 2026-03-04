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
}

struct ServingNutrientGridCard: View {
    private struct NutrientTile: Identifiable {
        let id: String
        let title: String
        let value: String
    }

    let title: String
    let calories: Int
    let nutrientValues: [String: Int]
    let multiplier: Double
    let trackedNutrientKeys: [String]
    let displayedNutrientKeys: [String]?
    let surface: Color
    let stroke: Color
    let titleColor: Color
    let labelColor: Color
    let valueColor: Color

    private var nutrientTiles: [NutrientTile] {
        let sourceKeys = displayedNutrientKeys ?? trackedNutrientKeys
        let trackedKeys = Array(NSOrderedSet(array: sourceKeys.map { $0.lowercased() })) as? [String] ?? sourceKeys.map { $0.lowercased() }

        let tracked = trackedKeys
            .filter { key in
                let normalized = key.lowercased()
                return normalized != "calories" && !NutrientCatalog.nonTrackableKeys.contains(normalized)
            }
            .map { key -> NutrientTile in
                let definition = NutrientCatalog.definition(for: key)
                let scaledValue = Int((Double(nutrientValues[key] ?? 0) * multiplier).rounded())
                return NutrientTile(
                    id: key,
                    title: definition.name,
                    value: "\(scaledValue) \(definition.unit)"
                )
            }

        return [
            NutrientTile(
                id: "calories",
                title: "Calories",
                value: "\(Int((Double(calories) * multiplier).rounded()))"
            )
        ] + tracked
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(titleColor)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(nutrientTiles) { tile in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(tile.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(labelColor)

                        Text(tile.value)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(valueColor)
                            .minimumScaleFactor(0.75)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(surface.opacity(0.72))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(stroke.opacity(0.6), lineWidth: 1)
                    )
                }
            }
        }
        .padding(18)
        .cardStyle(surface: surface, stroke: stroke)
    }
}
