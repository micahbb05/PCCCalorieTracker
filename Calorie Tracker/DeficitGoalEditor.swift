import SwiftUI

struct DeficitGoalEditor: View {
    @Binding var deficitCalories: Int
    let title: String
    let subtitle: String
    let helperText: String?
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Text("\(deficitCalories) cal")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }

            HStack(spacing: 10) {
                Button(action: { adjust(by: -50) }) {
                    Image(systemName: "minus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white.opacity(0.92))
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.white.opacity(0.10)))
                }
                .buttonStyle(.plain)

                TextField("", value: deficitBinding, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.96))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                    )

                Button(action: { adjust(by: 50) }) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white.opacity(0.92))
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(accent))
                }
                .buttonStyle(.plain)
            }

            if let helperText {
                Text(helperText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }

    private var deficitBinding: Binding<Int> {
        Binding(
            get: { deficitCalories },
            set: { deficitCalories = min(max($0, 0), 2500) }
        )
    }

    private func adjust(by delta: Int) {
        deficitCalories = min(max(deficitCalories + delta, 0), 2500)
        Haptics.selection()
    }
}
