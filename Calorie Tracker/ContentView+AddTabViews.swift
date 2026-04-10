// Calorie Tracker 2026

import SwiftUI

extension ContentView {

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
        .cardStyle(surface: surfacePrimary, stroke: textSecondary.opacity(0.15))
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
                        .fill(surfaceSecondary.opacity(0.95))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(textSecondary.opacity(0.16), lineWidth: 1)
                )
                .foregroundStyle(textPrimary)
                .scrollContentBackground(.hidden)

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
        .cardStyle(surface: surfacePrimary, stroke: textSecondary.opacity(0.15))
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
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                    .frame(width: 22)
                    .foregroundStyle(accent)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(textPrimary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(textSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(textSecondary.opacity(0.85))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(surfaceSecondary.opacity(0.95))
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
        .cardStyle(surface: surfacePrimary, stroke: textSecondary.opacity(0.15))
        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    func summaryMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(textPrimary)
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
                            colors: [
                                Color(red: 0.03, green: 0.07, blue: 0.19),
                                Color(red: 0.05, green: 0.10, blue: 0.24)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Circle()
                    .fill(Color(red: 0.20, green: 0.23, blue: 0.48).opacity(0.38))
                    .frame(width: 230, height: 230)
                    .offset(x: 74, y: -26)

                VStack(alignment: .leading, spacing: 18) {
                    let caloriePalette = calorieBarPalette(consumed: totalCalories, goal: calorieGoal, burned: burnedCaloriesToday)
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(calorieHeroDisplay.value.map(String.init) ?? "--")
                                .font(.system(size: 56, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(.white)
                            Text(calorieHeroDisplay.title)
                                .font(.system(size: 20, weight: .medium, design: .rounded))
                                .foregroundStyle(Color.white.opacity(0.70))
                        }

                        Spacer()

                        Image(systemName: "flame")
                            .font(.system(size: 34, weight: .regular))
                            .foregroundStyle(Color.orange)
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
                        .animation(.easeInOut(duration: 0.5), value: displayedCalorieProgress)
                    }
                    .frame(height: 20)

                    HStack {
                        Text("Consumed: \(totalCalories)")
                            .font(.system(size: 18, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Color.white.opacity(0.72))
                        Spacer()
                        Text("Goal: \(displayedCalorieGoal.map(String.init) ?? "--")")
                            .font(.system(size: 18, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Color.white.opacity(0.72))
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
                Text(activeNutrients.count <= 3 ? "Daily Macros" : "Daily Goals")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(textPrimary)

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
            .cardStyle(surface: surfacePrimary, stroke: textSecondary.opacity(0.15))
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

}
