import SwiftUI

struct VerticalServeSlider: View {
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
            let height = proxy.size.height
            let availableHeight = max(height - 28, 1)
            let positions = values.enumerated().map { index, option in
                let progress = CGFloat(index) / CGFloat(max(values.count - 1, 1))
                let y = height - 14 - (progress * availableHeight)
                return (option, y)
            }
            let knobY = positions.first(where: { abs($0.0 - value) < 0.001 })?.1 ?? (height / 2)

            ZStack {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 16)

                ForEach(Array(positions.enumerated()), id: \.offset) { _, pair in
                    let option = pair.0
                    let y = pair.1
                    let isMajor = abs((option * 100).truncatingRemainder(dividingBy: 50)) < 0.001 || abs(option - 1.0) < 0.001

                    Rectangle()
                        .fill(Color.white.opacity(isMajor ? 0.55 : 0.28))
                        .frame(width: isMajor ? 28 : 18, height: 2)
                        .position(x: proxy.size.width / 2, y: y)
                }

                Circle()
                    .fill(Color.white)
                    .frame(width: 30, height: 30)
                    .shadow(color: Color.cyan.opacity(0.45), radius: 12, x: 0, y: 4)
                    .overlay(
                        Circle()
                            .stroke(Color.blue.opacity(0.55), lineWidth: 3)
                    )
                    .position(x: proxy.size.width / 2, y: knobY)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let nearest = positions.min(by: { abs($0.1 - gesture.location.y) < abs($1.1 - gesture.location.y) })?.0 ?? value
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
