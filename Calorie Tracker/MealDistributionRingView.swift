import SwiftUI

struct MealDistributionRingView: View {
    let segments: [(group: MealGroup, calories: Int, color: Color)]

    private var totalCalories: Double {
        Double(segments.reduce(0) { $0 + $1.calories })
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 18)

            ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                Circle()
                    .trim(from: startTrim(for: index), to: endTrim(for: index))
                    .stroke(segment.color, style: StrokeStyle(lineWidth: 18, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }

            VStack(spacing: 2) {
                Text("\(Int(totalCalories))")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                Text("calories")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.62))
            }
        }
        .padding(6)
    }

    private func startTrim(for index: Int) -> CGFloat {
        guard totalCalories > 0, index > 0 else { return 0 }
        let previous = segments.prefix(index).reduce(0) { $0 + $1.calories }
        return CGFloat(Double(previous) / totalCalories)
    }

    private func endTrim(for index: Int) -> CGFloat {
        guard totalCalories > 0 else { return 0 }
        let current = segments.prefix(index + 1).reduce(0) { $0 + $1.calories }
        return CGFloat(Double(current) / totalCalories)
    }
}
