import SwiftUI

/// Horizontal slider matching VerticalServeSlider / HorizontalServeSlider style,
/// but without tick marks. For plate portion adjustment: center = Gemini estimate,
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

                Circle()
                    .fill(Color.white)
                    .frame(width: knobSize, height: knobSize)
                    .shadow(color: Color.cyan.opacity(0.45), radius: 12, x: 0, y: 4)
                    .overlay(
                        Circle()
                            .stroke(Color.blue.opacity(0.55), lineWidth: 3)
                    )
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
        guard step > 0 else { return clamped }
        let steps = (clamped / step).rounded()
        return min(max(steps * step, range.lowerBound), range.upperBound)
    }
}
