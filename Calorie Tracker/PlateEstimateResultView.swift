import SwiftUI

/// One row: item name, estimated oz, horizontal slider to tweak, and calories at that serving.
struct PlateEstimateResultView: View {
    let items: [MenuItem]
    @Binding var ozByItemId: [String: Double]
    let baseOzByItemId: [String: Double]
    let mealGroup: MealGroup
    let onConfirm: ([(MenuItem, oz: Double, baseOz: Double)]) -> Void
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    /// Original Gemini estimates, captured once when sheet appears. Never changes during the session.
    @State private var geminiOzByItemId: [String: Double] = [:]

    private var surfacePrimary: Color {
        colorScheme == .dark ? Color(red: 0.13, green: 0.15, blue: 0.20) : Color.white
    }
    private var textPrimary: Color {
        colorScheme == .dark ? Color(red: 0.95, green: 0.96, blue: 0.98) : Color(red: 0.12, green: 0.14, blue: 0.18)
    }
    private var textSecondary: Color {
        colorScheme == .dark ? Color(red: 0.78, green: 0.81, blue: 0.86) : Color(red: 0.43, green: 0.47, blue: 0.54)
    }
    private var accent: Color { AppTheme.accent }

    private let ozStep = 0.25
    private let ozRange = 0.25...20.0

    var body: some View {
        let hasLoggableItems = items.contains { (ozByItemId[$0.id] ?? 0) > 0 }
        let gradientBg = LinearGradient(
            colors: [
                colorScheme == .dark ? Color(red: 0.07, green: 0.08, blue: 0.12) : Color(red: 0.95, green: 0.97, blue: 0.99),
                colorScheme == .dark ? Color(red: 0.10, green: 0.11, blue: 0.17) : Color(red: 0.91, green: 0.94, blue: 0.98)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        NavigationStack {
            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: 12) {
                    Button("Cancel") { onDismiss() }
                        .font(.body.weight(.medium))
                        .foregroundStyle(accent)

                    Spacer(minLength: 0)

                    Button {
                        let pairs = items.compactMap { item -> (MenuItem, oz: Double, baseOz: Double)? in
                            let oz = ozByItemId[item.id] ?? 0
                            guard oz > 0 else { return nil }
                            let baseOz = baseOzByItemId[item.id] ?? item.servingOzForPortions
                            return (item, oz, baseOz)
                        }
                        onConfirm(pairs)
                    } label: {
                        Text("Add to log")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(hasLoggableItems ? .white : .white.opacity(0.6))
                            .frame(minWidth: 100)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(hasLoggableItems ? accent : accent.opacity(0.5))
                            .clipShape(Capsule(style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(!hasLoggableItems)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 12)

                Text("Adjust Portion Size")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Color.orange)
                            Text("AI portions are estimates — please double-check before logging.")
                                .font(.caption)
                                .foregroundStyle(textSecondary)
                                .multilineTextAlignment(.leading)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.orange.opacity(0.10))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.orange.opacity(0.35), lineWidth: 0.5)
                        )
                        .padding(.top, 6)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 0)

                        ForEach(items) { item in
                            itemCard(item)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(gradientBg.ignoresSafeArea())
            .navigationBarHidden(true)
            .onAppear {
                if geminiOzByItemId.isEmpty {
                    geminiOzByItemId = ozByItemId
                }
            }
        }
    }

    private func itemCard(_ item: MenuItem) -> some View {
        let ozBinding = Binding(
            get: { ozByItemId[item.id] ?? 0 },
            set: { newOz in
                var updated = ozByItemId
                updated[item.id] = newOz
                ozByItemId = updated
            }
        )
        let baseOz = baseOzByItemId[item.id] ?? item.servingOzForPortions
        // Use the original Gemini estimate (captured on appear), not the current oz. Missing/zero → treat as 0.01 for slider math.
        let geminiOz = max(geminiOzByItemId[item.id] ?? ozByItemId[item.id] ?? 0, 0.01)

        // Slider controls a -20% ... +20% multiplier around Gemini's estimate.
        let deltaBinding = Binding<Double>(
            get: {
                guard geminiOz > 0 else { return 0 }
                return (ozBinding.wrappedValue / geminiOz) - 1.0
            },
            set: { newDelta in
                let clamped = min(max(newDelta, -0.2), 0.2)
                let newOz = geminiOz * (1.0 + clamped)
                ozBinding.wrappedValue = max(newOz, 0.01)
            }
        )

        let currentOz = ozBinding.wrappedValue
        let multiplier = baseOz > 0 ? (currentOz / baseOz) : 1.0
        let caloriesAtOz = Int((Double(item.calories) * multiplier).rounded())
        let proteinAtOz = Int((Double(item.nutrientValues["g_protein"] ?? 0) * multiplier).rounded())

        let minOz = geminiOz * 0.8
        let maxOz = geminiOz * 1.2
        let isNotOnPlate = currentOz <= 0

        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(item.name)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(textPrimary)
                    Spacer()
                    if !isNotOnPlate {
                        Button("Remove from plate") {
                            var updated = ozByItemId
                            updated[item.id] = 0
                            ozByItemId = updated
                            Haptics.selection()
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color(red: 0.92, green: 0.35, blue: 0.35))
                    }
                }
                Text(item.isCountBased
                     ? String(format: "1 serving • %d cal • %dg protein", item.calories, item.nutrientValues["g_protein"] ?? 0)
                     : String(format: "Base serving: %.1f oz • %d cal • %dg protein", baseOz, item.calories, item.nutrientValues["g_protein"] ?? 0))
                    .font(.caption)
                    .foregroundStyle(textSecondary)
            }

            if isNotOnPlate {
                HStack {
                    Text("Not on plate")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(textSecondary)
                    Spacer()
                    Button("Add to plate") {
                        // If we have a Gemini guess, use it; else use the menu's base serving.
                        let geminiGuess = geminiOzByItemId[item.id] ?? 0
                        let restore: Double = item.isCountBased ? 1 : (geminiGuess > 0 ? geminiGuess : baseOz)
                        var updated = ozByItemId
                        updated[item.id] = restore
                        ozByItemId = updated
                        if !item.isCountBased && geminiGuess <= 0 {
                            var updatedGemini = geminiOzByItemId
                            updatedGemini[item.id] = baseOz
                            geminiOzByItemId = updatedGemini
                        }
                        Haptics.selection()
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(accent)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(surfacePrimary.opacity(0.6))
                )
            } else if item.isCountBased {
                let quantity = max(1, Int(currentOz))
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Quantity")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(textSecondary)
                        Spacer()
                        HStack(spacing: 16) {
                            Button {
                                let newVal = max(1, quantity - 1)
                                var updated = ozByItemId
                                updated[item.id] = Double(newVal)
                                ozByItemId = updated
                                Haptics.selection()
                            } label: { Image(systemName: "minus.circle.fill") }
                            .font(.title2)
                            .foregroundStyle(quantity > 1 ? accent : textSecondary.opacity(0.5))
                            .disabled(quantity <= 1)
                            Text("\(quantity)")
                                .font(.title3.weight(.bold))
                                .monospacedDigit()
                                .frame(minWidth: 28)
                            Button {
                                let newVal = min(99, quantity + 1)
                                var updated = ozByItemId
                                updated[item.id] = Double(newVal)
                                ozByItemId = updated
                                Haptics.selection()
                            } label: { Image(systemName: "plus.circle.fill") }
                            .font(.title2)
                            .foregroundStyle(accent)
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Portion")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(textSecondary)
                        Spacer()
                        Text(String(format: "%.2f oz", currentOz))
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(textPrimary)
                    }
                    PlateAdjustSlider(
                        value: deltaBinding,
                        range: -0.2...0.2,
                        step: 0.01
                    ) {
                        Haptics.selection()
                    }
                    .frame(height: 44)
                    HStack {
                        Text(String(format: "%.1f oz", minOz))
                            .font(.caption2)
                            .foregroundStyle(textSecondary.opacity(0.8))
                        Spacer()
                        Text(String(format: "%.1f oz", maxOz))
                            .font(.caption2)
                            .foregroundStyle(textSecondary.opacity(0.8))
                    }
                }
            }

            if !isNotOnPlate {
                HStack {
                    Text("Nutrition at this portion")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(textSecondary)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(caloriesAtOz) cal")
                            .font(.title3.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(accent)
                        Text("\(proteinAtOz)g protein")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(textSecondary)
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(accent.opacity(0.12))
                )
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(surfacePrimary.opacity(0.95))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(textSecondary.opacity(0.15), lineWidth: 1)
        )
        .padding(16)
    }

}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
