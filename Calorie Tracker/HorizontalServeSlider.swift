import SwiftUI

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
            result.append(current)
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
                    .shadow(color: Color.cyan.opacity(0.45), radius: 12, x: 0, y: 4)
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
        let steps = (clamped / step).rounded()
        return min(max(steps * step, range.lowerBound), range.upperBound)
    }
}
