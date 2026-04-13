// Calorie Tracker 2026

import SwiftUI

extension ContentView {

    private var isHeroBlueprint: Bool {
        appThemeStyleRaw == AppThemeStyle.blueprint.rawValue
    }

    /// Slightly higher contrast than `textPrimary` on the dark hero card.
    private var heroPrimaryText: Color {
        guard colorScheme == .dark else { return textPrimary }
        return isHeroBlueprint
            ? Color(red: 0.98, green: 0.985, blue: 0.995)
            : Color(red: 0.988, green: 0.982, blue: 0.972)
    }

    private var heroSecondaryText: Color {
        textPrimary.opacity(colorScheme == .dark ? 0.68 : 0.54)
    }

    private var heroFooterText: Color {
        textPrimary.opacity(colorScheme == .dark ? 0.58 : 0.46)
    }

    var aiPhotoCaptureCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Scan Food or Nutrition Label")
                .font(.headline.weight(.semibold))
                .foregroundStyle(textPrimary)

            VStack(spacing: 12) {
                aiPhotoActionButton(
                    title: "Take Photo",
                    subtitle: "Use the camera for food or labels",
                    systemImage: "camera.fill"
                ) {
                    aiFoodPhotoRequestedPickerSource = .camera
                }

                aiPhotoActionButton(
                    title: "Choose From Library",
                    subtitle: "Pick an existing photo",
                    systemImage: "photo.on.rectangle.angled"
                ) {
                    aiFoodPhotoRequestedPickerSource = .photoLibrary
                }
            }
        }
        .padding(18)
        .cardStyle(surface: surfacePrimary, stroke: textSecondary.opacity(0.18))
    }

    var aiTextMealCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Describe Your Meal")
                .font(.headline.weight(.semibold))
                .foregroundStyle(textPrimary)

            Text("Type what you ate and AI will estimate calories and macros, using web lookup when needed for more accurate nutrient info.")
                .font(.caption)
                .foregroundStyle(textSecondary)

            TextEditor(text: $aiMealTextInput)
                .frame(minHeight: 108)
                .padding(10)
                .focused($aiMealTextFocused)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(surfaceSecondary.opacity(0.75))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(aiMealTextFocused ? accent.opacity(0.4) : textSecondary.opacity(0.12), lineWidth: 1)
                )
                .foregroundStyle(textPrimary)
                .scrollContentBackground(.hidden)
                .animation(.easeInOut(duration: 0.18), value: aiMealTextFocused)

            Button {
                analyzeAITextMeal()
            } label: {
                if isAITextLoading {
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                } else {
                    Text("Analyze Description")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(accent)
            .disabled(isAITextLoading || aiMealTextInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

        }
        .padding(18)
        .cardStyle(surface: surfacePrimary, stroke: textSecondary.opacity(0.18))
    }

    var aiModeOrDivider: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(textSecondary.opacity(0.25))
                .frame(height: 1)
            Text("or")
                .font(.caption.weight(.semibold))
                .foregroundStyle(textSecondary)
            Rectangle()
                .fill(textSecondary.opacity(0.25))
                .frame(height: 1)
        }
        .padding(.horizontal, 8)
    }

    func aiPhotoActionButton(title: String, subtitle: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(accent.opacity(0.12))
                        .frame(width: 44, height: 44)
                    Image(systemName: systemImage)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(accent)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(textPrimary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(textSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(textSecondary.opacity(0.5))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(surfaceSecondary.opacity(0.95))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(textSecondary.opacity(0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isAIFoodPhotoLoading || isAITextLoading)
    }

    var todayHistorySummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Today")
                .font(.headline)
                .foregroundStyle(textPrimary)

            HStack(spacing: 16) {
                summaryMetric(title: "Calories", value: "\(totalCalories)")
                summaryMetric(title: "Items", value: "\(entries.count)")
            }
        }
        .padding(16)
        .cardStyle(surface: surfacePrimary, stroke: textSecondary.opacity(0.18))
        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    func summaryMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: 30, weight: .bold, design: .default))
                .monospacedDigit()
                .foregroundStyle(textPrimary)
                .contentTransition(.numericText())
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: value)
            Text(title)
                .font(.caption)
                .foregroundStyle(textSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var calorieHeroSection: some View {
        Section {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: isHeroBlueprint
                                ? [Color(red: 0.03, green: 0.07, blue: 0.19), Color(red: 0.05, green: 0.10, blue: 0.24)]
                                : [
                                    Color(red: 0.085, green: 0.10, blue: 0.145),
                                    Color(red: 0.125, green: 0.135, blue: 0.195),
                                ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Circle()
                    .fill(isHeroBlueprint
                        ? Color(red: 0.20, green: 0.23, blue: 0.48).opacity(0.38)
                        : Color(red: 0.30, green: 0.48, blue: 0.68).opacity(0.14))
                    .frame(width: 230, height: 230)
                    .offset(x: 74, y: -26)

                VStack(alignment: .leading, spacing: 18) {
                    let caloriePalette = calorieBarPalette(consumed: totalCalories, goal: calorieGoal, burned: burnedCaloriesToday)
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(calorieHeroDisplay.value.map(String.init) ?? "--")
                                .font(.system(size: 56, weight: .bold, design: .default))
                                .monospacedDigit()
                                .foregroundStyle(heroPrimaryText)
                                .contentTransition(.numericText(value: Double(calorieHeroDisplay.value ?? 0)))
                                .animation(.spring(response: 0.5, dampingFraction: 0.8), value: calorieHeroDisplay.value)
                            Text(calorieHeroDisplay.title)
                                .font(.system(size: 20, weight: .medium, design: .default))
                                .foregroundStyle(heroSecondaryText)
                        }

                        Spacer()

                        Image(systemName: "flame")
                            .font(.system(size: 34, weight: .light))
                            .foregroundStyle(Color(red: 0.722, green: 0.573, blue: 0.290))
                            .padding(.top, 10)
                    }

                    GeometryReader { proxy in
                        let fillWidth = proxy.size.width * displayedCalorieProgress
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.10))
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [caloriePalette.start, caloriePalette.end],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(fillWidth, displayedCalorieProgress > 0 ? 8 : 0))
                        }
                        .animation(.spring(response: 0.7, dampingFraction: 0.85), value: displayedCalorieProgress)
                    }
                    .frame(height: 20)

                    HStack {
                        Text("Consumed: \(totalCalories)")
                            .font(.system(size: 18, weight: .medium, design: .default))
                            .monospacedDigit()
                            .foregroundStyle(heroFooterText)
                            .contentTransition(.numericText())
                            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: totalCalories)
                        Spacer()
                        Text("Goal: \(displayedCalorieGoal.map(String.init) ?? "--")")
                            .font(.system(size: 18, weight: .medium, design: .default))
                            .monospacedDigit()
                            .foregroundStyle(heroFooterText)
                    }
                }
                .padding(24)
            }
            .frame(minHeight: 248)
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    var progressSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 10) {
                    Text(activeNutrients.count <= 3 ? "Daily Macros" : "Daily Goals")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(textPrimary)
                    Spacer()
                    Text("\(activeNutrients.count) tracked")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(accent.opacity(0.85))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule(style: .continuous)
                                .fill(accent.opacity(0.10))
                        )
                }

                ForEach(activeNutrients) { nutrient in
                    let total = totalNutrient(for: nutrient.key)
                    let goal = goalForNutrient(nutrient.key)
                    let progress = min(Double(total) / Double(max(goal, 1)), 1.0)
                    let palette = paletteForNutrient(nutrient.key, progress: progress)
                    progressRow(
                        title: nutrient.name,
                        detail: "\(total)\(nutrient.unit) / \(goal)\(nutrient.unit)",
                        progress: progress,
                        start: palette.start,
                        end: palette.end
                    )
                }
            }
            .padding(20)
            .cardStyle(surface: surfacePrimary, stroke: textSecondary.opacity(0.18))
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

}
