import SwiftUI

struct EditMealEntrySheet: View {
    let entry: MealEntry
    let editableNutrients: [NutrientDefinition]
    let initialMealGroup: MealGroup
    let surfacePrimary: Color
    let surfaceSecondary: Color
    let textPrimary: Color
    let textSecondary: Color
    let accent: Color
    let onSave: (MealEntry) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var nameText: String
    @State private var caloriesText: String
    @State private var nutrientTexts: [String: String]
    @State private var preservedHiddenNutrients: [String: Int]
    @State private var mealGroup: MealGroup
    @FocusState private var focusedField: EditField?

    private enum EditField: Hashable {
        case name
        case calories
    }

    init(
        entry: MealEntry,
        editableNutrients: [NutrientDefinition],
        initialMealGroup: MealGroup,
        surfacePrimary: Color,
        surfaceSecondary: Color,
        textPrimary: Color,
        textSecondary: Color,
        accent: Color,
        onSave: @escaping (MealEntry) -> Void
    ) {
        self.entry = entry
        self.editableNutrients = editableNutrients
        self.initialMealGroup = initialMealGroup
        self.surfacePrimary = surfacePrimary
        self.surfaceSecondary = surfaceSecondary
        self.textPrimary = textPrimary
        self.textSecondary = textSecondary
        self.accent = accent
        self.onSave = onSave
        _nameText = State(initialValue: entry.name)
        _caloriesText = State(initialValue: entry.calories == 0 ? "" : "\(entry.calories)")
        _mealGroup = State(initialValue: initialMealGroup)
        _nutrientTexts = State(initialValue: editableNutrients.reduce(into: [:]) { partialResult, nutrient in
            let value = entry.nutrientValues[nutrient.key] ?? 0
            partialResult[nutrient.key] = value == 0 ? "" : "\(value)"
        })
        let editableKeys = Set(editableNutrients.map(\.key))
        _preservedHiddenNutrients = State(initialValue: entry.nutrientValues.filter { !editableKeys.contains($0.key) })
    }

    var body: some View {
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
                .onTapGesture {
                    dismissKeyboard()
                }

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Button {
                            dismiss()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "chevron.left")
                                    .font(.caption.weight(.bold))
                                Text("Cancel")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .foregroundStyle(textPrimary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(surfacePrimary.opacity(0.94))
                            )
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(textSecondary.opacity(0.14), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)

                        Spacer()
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Edit Entry")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(textPrimary)
                        Text("Adjust food name, calories, and nutrients.")
                            .font(.subheadline)
                            .foregroundStyle(textSecondary)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        labeledField("Food name") {
                            TextField("Food name", text: $nameText)
                                .focused($focusedField, equals: .name)
                                .submitLabel(.next)
                                .onSubmit {
                                    focusedField = .calories
                                }
                                .inputStyle(surface: surfaceSecondary, text: textPrimary, secondary: textSecondary)
                        }

                        labeledField("Calories") {
                            TextField("Calories", text: $caloriesText)
                                .keyboardType(.numberPad)
                                .focused($focusedField, equals: .calories)
                                .inputStyle(surface: surfaceSecondary, text: textPrimary, secondary: textSecondary)
                        }

                        labeledField("Meal Group") {
                            Picker("Meal Group", selection: $mealGroup) {
                                ForEach(MealGroup.allCases) { group in
                                    Text(group.title).tag(group)
                                }
                            }
                            .pickerStyle(.segmented)
                        }

                        if !editableNutrients.isEmpty {
                            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                                ForEach(Array(stride(from: 0, to: editableNutrients.count, by: 2)), id: \.self) { startIndex in
                                    GridRow {
                                        if startIndex + 1 < editableNutrients.count {
                                            nutrientGridCell(at: startIndex)
                                            nutrientGridCell(at: startIndex + 1)
                                        } else {
                                            nutrientGridCell(at: startIndex)
                                                .gridCellColumns(2)
                                        }
                                    }
                                }
                            }
                        }

                        if let errorText = validationError {
                            Text(errorText)
                                .font(.caption)
                                .foregroundStyle(Color.red)
                        }
                    }
                    .padding(18)
                    .cardStyle(surface: surfacePrimary, stroke: textSecondary.opacity(0.15))
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 120)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                save()
            } label: {
                Text("Save Changes")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(accent)
            .disabled(!canSave)
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 12)
            .background(
                ZStack {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                    LinearGradient(
                        colors: [surfacePrimary.opacity(0.24), surfacePrimary.opacity(0.96)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .ignoresSafeArea(edges: .bottom)
            )
        }
    }

    private var parsedCalories: Int? {
        parseInput(caloriesText)
    }

    private var parsedNutrients: [String: Int]? {
        var result: [String: Int] = [:]
        for nutrient in editableNutrients {
            guard let parsed = parseInput(nutrientTexts[nutrient.key] ?? "") else {
                return nil
            }
            result[nutrient.key] = parsed
        }
        return result
    }

    private var canSave: Bool {
        guard parsedCalories != nil, let nutrients = parsedNutrients else {
            return false
        }
        let total = (parsedCalories ?? 0) + nutrients.values.reduce(0, +)
        return total > 0
    }

    private var validationError: String? {
        let hasAnyText = !nameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !caloriesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            nutrientTexts.values.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        guard hasAnyText else {
            return nil
        }
        guard parsedCalories != nil, parsedNutrients != nil else {
            return "Use non-negative whole numbers."
        }
        return canSave ? nil : "Enter calories or nutrients above 0."
    }

    private func nutrientBinding(for key: String) -> Binding<String> {
        Binding(
            get: { nutrientTexts[key] ?? "" },
            set: { nutrientTexts[key] = $0 }
        )
    }

    private func labeledField<Content: View>(_ title: String, spacing: CGFloat = 6, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: spacing) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(textSecondary)
            content()
        }
    }

    @ViewBuilder
    private func nutrientGridCell(at index: Int) -> some View {
        let nutrient = editableNutrients[index]
        let label = nutrient.unit.uppercased() == "CALORIES" ? nutrient.name : "\(nutrient.name) (\(nutrient.unit))"
        labeledField(label, spacing: 8) {
            TextField(label, text: nutrientBinding(for: nutrient.key))
                .keyboardType(.numberPad)
                .inputStyle(surface: surfaceSecondary, text: textPrimary, secondary: textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func parseInput(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return 0
        }
        guard let value = Int(trimmed), value >= 0 else {
            return nil
        }
        return value
    }

    private func save() {
        guard let calories = parsedCalories, let nutrients = parsedNutrients else {
            return
        }
        let mergedNutrients = preservedHiddenNutrients.merging(nutrients) { _, new in new }

        let updatedEntry = MealEntry(
            id: entry.id,
            name: nameText,
            calories: calories,
            nutrientValues: mergedNutrients,
            createdAt: entry.createdAt,
            mealGroup: mealGroup
        )

        focusedField = nil
        dismissKeyboard()
        onSave(updatedEntry)
        dismiss()
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
