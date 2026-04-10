import SwiftUI

/// Horizontal slider matching VerticalServeSlider / HorizontalServeSlider style.
/// For plate portion adjustment: center = Gemini estimate,
/// ±20% range, stays where dragged.
struct PlateAdjustSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let onValueChange: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let trackHeight: CGFloat = 16
            let knobSize: CGFloat = 30
            let knobRadius = knobSize / 2
            let trackY = proxy.size.height / 2
            let minX = knobRadius
            let maxX = width - knobRadius
            let trackWidth = maxX - minX
            let values = sliderValues()
            let positions = values.enumerated().map { index, option in
                let progress = CGFloat(index) / CGFloat(max(values.count - 1, 1))
                let x = minX + (progress * trackWidth)
                return (index, option, x)
            }

            let knobX: CGFloat = {
                let t = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
                return minX + CGFloat(t) * trackWidth
            }()

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .frame(height: trackHeight)
                    .frame(maxWidth: .infinity)
                    .position(x: width / 2, y: trackY)

                ForEach(Array(positions.enumerated()), id: \.offset) { _, pair in
                    let index = pair.0
                    let option = pair.1
                    let x = pair.2
                    let isMajor = index % 10 == 0 || abs(option) < 0.0001

                    Rectangle()
                        .fill(Color.white.opacity(isMajor ? 0.55 : 0.28))
                        .frame(width: 2, height: isMajor ? 24 : 14)
                        .position(x: x, y: trackY)
                }

                Circle()
                    .fill(Color.white)
                    .frame(width: knobSize, height: knobSize)
                    .shadow(color: Color(red: 0.769, green: 0.588, blue: 0.353).opacity(0.45), radius: 12, x: 0, y: 4)
                    .position(x: knobX, y: trackY)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let rawT = (gesture.location.x - minX) / trackWidth
                        let clampedT = min(max(rawT, 0), 1)
                        let rawValue = range.lowerBound + Double(clampedT) * (range.upperBound - range.lowerBound)
                        let stepped = stepValue(rawValue)
                        if abs(stepped - value) > 0.0001 {
                            value = stepped
                            onValueChange()
                        }
                    }
            )
        }
    }

    private func stepValue(_ raw: Double) -> Double {
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

    private func sliderValues() -> [Double] {
        var values: [Double] = []
        var current = range.lowerBound
        while current <= range.upperBound + 0.0001 {
            values.append(roundToServingSelectorIncrement(current))
            current += step
        }
        return values
    }
}
