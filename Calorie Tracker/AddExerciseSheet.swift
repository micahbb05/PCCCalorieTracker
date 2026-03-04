import SwiftUI

struct AddExerciseDraft {
    let exerciseType: ExerciseType
    let customName: String?
    let durationMinutes: Int
    let distanceMiles: Double?
    let calories: Int
}

struct AddExerciseSheet: View {
    let weightPounds: Int
    let surfacePrimary: Color
    let surfaceSecondary: Color
    let textPrimary: Color
    let textSecondary: Color
    let accent: Color
    let onAdd: (AddExerciseDraft) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedType: ExerciseType = .weightLifting
    @State private var customNameText: String = ""
    @State private var inputText: String = ""
    @FocusState private var isInputFocused: Bool

    private var usesDirectCalories: Bool {
        selectedType == .directCalories
    }

    private var usesDistance: Bool {
        selectedType == .running || selectedType == .cycling
    }

    private var inputLabel: String {
        if usesDirectCalories {
            return "Calories burned"
        }
        return usesDistance ? "Distance (miles)" : "Duration (minutes)"
    }

    private var inputPlaceholder: String {
        if usesDirectCalories {
            return "e.g. 220"
        }
        return usesDistance ? "e.g. 2.5" : "e.g. 30"
    }

    private var durationMinutes: Int? {
        guard !usesDistance, !usesDirectCalories, !inputText.isEmpty, let n = Int(inputText), n > 0 else { return nil }
        return n
    }

    private var distanceMiles: Double? {
        guard usesDistance, !inputText.isEmpty, let n = Double(inputText), n > 0 else { return nil }
        return n
    }

    private var directCalories: Int? {
        guard usesDirectCalories, !inputText.isEmpty, let n = Int(inputText), n > 0 else { return nil }
        return n
    }

    private var canAdd: Bool {
        if usesDirectCalories { return directCalories != nil }
        if usesDistance { return distanceMiles != nil }
        return durationMinutes != nil
    }

    private var estimatedCalories: Int {
        if let calories = directCalories {
            return calories
        }
        guard weightPounds > 0 else { return 0 }
        if usesDistance, let miles = distanceMiles {
            return ExerciseCalorieService.fullCalories(type: selectedType, durationMinutes: 0, distanceMiles: miles, weightPounds: weightPounds)
        }
        if let dur = durationMinutes {
            return ExerciseCalorieService.fullCalories(type: selectedType, durationMinutes: dur, distanceMiles: nil, weightPounds: weightPounds)
        }
        return 0
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: AppTheme.sheetBackgroundGradient,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { dismissKeyboard() }

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Exercise type")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(textPrimary)

                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                                ForEach(ExerciseType.allCases) { type in
                                    Button {
                                        selectedType = type
                                        customNameText = ""
                                        inputText = ""
                                    } label: {
                                        HStack(spacing: 8) {
                                            Image(systemName: type.iconName)
                                                .font(.body)
                                            Text(type.title)
                                                .font(.subheadline.weight(.medium))
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .fill(selectedType == type ? accent.opacity(0.3) : surfaceSecondary)
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .stroke(selectedType == type ? accent : Color.clear, lineWidth: 2)
                                        )
                                        .foregroundStyle(selectedType == type ? accent : textPrimary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        if usesDirectCalories {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Exercise name (optional)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(textPrimary)

                                TextField("e.g. Basketball, Yard work", text: $customNameText)
                                    .inputStyle(surface: surfaceSecondary, text: textPrimary, secondary: textSecondary)
                            }
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text(inputLabel)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(textPrimary)

                            TextField(inputPlaceholder, text: $inputText)
                                .keyboardType(usesDistance ? .decimalPad : .numberPad)
                                .focused($isInputFocused)
                                .inputStyle(surface: surfaceSecondary, text: textPrimary, secondary: textSecondary)
                        }

                        if canAdd && !usesDirectCalories {
                            HStack {
                                Text("Est. calories burned")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(textSecondary)
                                Spacer()
                                Text("\(estimatedCalories) cal")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(accent)
                                    .monospacedDigit()
                            }
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(surfaceSecondary.opacity(0.6))
                            )
                        }

                        Button {
                            addExercise()
                        } label: {
                            Text("Add Exercise")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(accent)
                        .disabled(!canAdd)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Add Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(textSecondary)
                }
            }
        }
    }

    private func addExercise() {
        let calories: Int
        let dur: Int
        let dist: Double?

        if let manualCalories = directCalories {
            calories = manualCalories
            dur = 0
            dist = nil
        } else if usesDistance, let miles = distanceMiles {
            calories = ExerciseCalorieService.fullCalories(type: selectedType, durationMinutes: 0, distanceMiles: miles, weightPounds: weightPounds)
            dur = Int(miles * (selectedType == .running ? 10 : 5))
            dist = miles
        } else if let d = durationMinutes {
            calories = ExerciseCalorieService.fullCalories(type: selectedType, durationMinutes: d, distanceMiles: nil, weightPounds: weightPounds)
            dur = d
            dist = nil
        } else {
            return
        }

        let draft = AddExerciseDraft(
            exerciseType: selectedType,
            customName: usesDirectCalories ? customNameText : nil,
            durationMinutes: dur,
            distanceMiles: dist,
            calories: calories
        )
        onAdd(draft)
        Haptics.notification(.success)
        dismiss()
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
