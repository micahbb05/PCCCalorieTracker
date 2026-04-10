import SwiftUI

func roundToServingSelectorIncrement(_ value: Double) -> Double {
    ((value * 20).rounded()) / 20
}

func formatServingSelectorAmount(_ amount: Double) -> String {
    let rounded = roundToServingSelectorIncrement(amount)
    if abs(rounded.rounded() - rounded) < 0.001 {
        return String(format: "%.0f", rounded)
    }
    if abs((rounded * 10).rounded() - (rounded * 10)) < 0.001 {
        return String(format: "%.1f", rounded)
    }
    return String(format: "%.2f", rounded)
}

func isSingularQuantity(_ quantity: Double) -> Bool {
    abs(quantity - 1.0) <= 0.0001
}

func inflectServingUnitToken(
    _ unit: String,
    quantity: Double,
    defaultSingular: String = "serving",
    defaultPlural: String = "servings"
) -> String {
    let trimmed = unit.trimmingCharacters(in: .whitespacesAndNewlines)
    let isSingular = isSingularQuantity(quantity)
    guard !trimmed.isEmpty else { return isSingular ? defaultSingular : defaultPlural }

    let lower = trimmed.lowercased()
    let invariant = ["oz", "fl oz", "g", "mg", "kg", "lb", "lbs", "ml", "l", "tbsp", "tsp", "each", "ea"]
    if invariant.contains(lower) { return lower }

    if isSingular {
        if lower.hasSuffix("ies"), lower.count > 3 { return String(lower.dropLast(3) + "y") }
        if lower.hasSuffix("ses"), lower.count > 3 { return String(lower.dropLast(2)) }
        if lower.hasSuffix("s"), lower.count > 1 { return String(lower.dropLast()) }
        return lower
    }

    if lower.hasSuffix("s") { return lower }
    if lower.hasSuffix("y"), lower.count > 1 { return String(lower.dropLast() + "ies") }
    if lower.hasSuffix("ch") || lower.hasSuffix("sh") || lower.hasSuffix("x") || lower.hasSuffix("z") {
        return lower + "es"
    }
    return lower + "s"
}

func inflectCountUnitToken(_ unit: String, quantity: Double) -> String {
    let normalized = unit.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let isSingular = isSingularQuantity(quantity)

    if normalized.isEmpty { return isSingular ? "item" : "items" }
    if normalized == "each" || normalized == "ea" { return isSingular ? "item" : "items" }
    if normalized == "pc" || normalized == "pcs" { return isSingular ? "piece" : "pieces" }

    return inflectServingUnitToken(
        normalized,
        quantity: quantity,
        defaultSingular: "item",
        defaultPlural: "items"
    )
}

/// Horizontal slider for oz (or other numeric range), similar to VerticalServeSlider.
struct HorizontalServeSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let onStepChange: () -> Void

    private var values: [Double] {
        var result: [Double] = []
        var current = range.lowerBound
        while current <= range.upperBound + 0.0001 {
            result.append(roundToServingSelectorIncrement(current))
            current += step
        }
        return result
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let availableWidth = max(width - 28, 1)
            let positions = values.enumerated().map { index, option in
                let progress = CGFloat(index) / CGFloat(max(values.count - 1, 1))
                let x = 14 + (progress * availableWidth)
                return (option, x)
            }
            let knobX = positions.first(where: { abs($0.0 - value) < 0.001 })?.1 ?? (width / 2)

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 16)

                ForEach(Array(positions.enumerated()), id: \.offset) { _, pair in
                    let option = pair.0
                    let x = pair.1
                    let isMajor = abs((option * 10).truncatingRemainder(dividingBy: 1)) < 0.001 || abs(option - 1.0) < 0.001
                    Rectangle()
                        .fill(Color.white.opacity(isMajor ? 0.55 : 0.28))
                        .frame(width: 2, height: isMajor ? 28 : 18)
                        .position(x: x, y: proxy.size.height / 2)
                }

                Circle()
                    .fill(Color.white)
                    .frame(width: 30, height: 30)
                    .shadow(color: Color(red: 0.769, green: 0.588, blue: 0.353).opacity(0.45), radius: 12, x: 0, y: 4)
                    .position(x: knobX, y: proxy.size.height / 2)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let nearest = positions.min(by: { abs($0.1 - gesture.location.x) < abs($1.1 - gesture.location.x) })?.0 ?? value
                        let snapped = snap(nearest)
                        if abs(snapped - value) > 0.0001 {
                            value = snapped
                            onStepChange()
                        }
                    }
            )
        }
    }

    private func snap(_ raw: Double) -> Double {
        let clamped = min(max(raw, range.lowerBound), range.upperBound)
        guard step > 0 else {
            let rounded = roundToServingSelectorIncrement(clamped)
            return min(max(rounded, range.lowerBound), range.upperBound)
        }
        let steps = (clamped / step).rounded()
        let stepped = steps * step
        let rounded = roundToServingSelectorIncrement(stepped)
        return min(max(rounded, range.lowerBound), range.upperBound)
    }
}
