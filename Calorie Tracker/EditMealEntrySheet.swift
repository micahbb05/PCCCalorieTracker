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
    @State private var quantityText: String
    @State private var caloriesText: String
    @State private var nutrientTexts: [String: String]
    @State private var preservedHiddenNutrients: [String: Int]
    @State private var mealGroup: MealGroup
    @FocusState private var focusedField: EditField?

    private enum EditField: Hashable {
        case name
        case quantity
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
        _quantityText = State(initialValue: entry.loggedCount.map(String.init) ?? "1")
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

                        if showsQuantityEditor {
                            HStack(alignment: .top, spacing: 12) {
                                labeledField("Calories") {
                                    TextField("Calories", text: $caloriesText)
                                        .keyboardType(.numberPad)
                                        .focused($focusedField, equals: .calories)
                                        .inputStyle(surface: surfaceSecondary, text: textPrimary, secondary: textSecondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)

                                labeledField("Quantity") {
                                    HStack(spacing: 10) {
                                        let currentQuantity = parsedQuantity ?? max(entry.loggedCount ?? 1, 1)
                                        Button {
                                            let next = max(1, currentQuantity - 1)
                                            quantityText = "\(next)"
                                            Haptics.selection()
                                        } label: {
                                            Image(systemName: "minus")
                                                .font(.subheadline.weight(.bold))
                                                .frame(width: 32, height: 32)
                                                .foregroundStyle(currentQuantity > 1 ? accent : textSecondary.opacity(0.45))
                                                .background(
                                                    Circle()
                                                        .fill(surfaceSecondary)
                                                )
                                        }
                                        .buttonStyle(.plain)
                                        .disabled(currentQuantity <= 1)

                                        TextField("Qty", text: $quantityText)
                                            .keyboardType(.numberPad)
                                            .multilineTextAlignment(.center)
                                            .focused($focusedField, equals: .quantity)
                                            .frame(width: 56)
                                            .padding(.vertical, 7)
                                            .foregroundStyle(textPrimary)
                                            .background(
                                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                    .fill(surfaceSecondary)
                                            )
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                    .stroke(textSecondary.opacity(0.24), lineWidth: 1)
                                            )

                                        Button {
                                            let next = min(99, currentQuantity + 1)
                                            quantityText = "\(next)"
                                            Haptics.selection()
                                        } label: {
                                            Image(systemName: "plus")
                                                .font(.subheadline.weight(.bold))
                                                .frame(width: 32, height: 32)
                                                .foregroundStyle(accent)
                                                .background(
                                                    Circle()
                                                        .fill(surfaceSecondary)
                                                )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        else {
                            labeledField("Calories") {
                                TextField("Calories", text: $caloriesText)
                                    .keyboardType(.numberPad)
                                    .focused($focusedField, equals: .calories)
                                    .inputStyle(surface: surfaceSecondary, text: textPrimary, secondary: textSecondary)
                            }
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

    private var parsedQuantity: Int? {
        let trimmed = quantityText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return 1
        }
        guard let value = Int(trimmed), value > 0 else {
            return nil
        }
        return value
    }

    private var showsQuantityEditor: Bool {
        entry.loggedCount != nil
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
        guard !showsQuantityEditor || parsedQuantity != nil else {
            return false
        }
        let total = (parsedCalories ?? 0) + nutrients.values.reduce(0, +)
        return total > 0
    }

    private var validationError: String? {
        let hasAnyText = !nameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            (showsQuantityEditor && !quantityText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) ||
            !caloriesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            nutrientTexts.values.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        guard hasAnyText else {
            return nil
        }
        guard parsedCalories != nil, parsedNutrients != nil, (!showsQuantityEditor || parsedQuantity != nil) else {
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
        let quantity = parsedQuantity ?? max(entry.loggedCount ?? 1, 1)
        let oldQuantity = max(entry.loggedCount ?? 1, 1)
        var mergedNutrients = preservedHiddenNutrients.merging(nutrients) { _, new in new }
        var finalCalories = calories

        let didManuallyEditCalories = calories != entry.calories
        let didManuallyEditNutrients = mergedNutrients != entry.nutrientValues
        let didManuallyEditNutrition = didManuallyEditCalories || didManuallyEditNutrients

        if showsQuantityEditor, quantity != oldQuantity, !didManuallyEditNutrition {
            let scale = Double(quantity) / Double(oldQuantity)
            finalCalories = Int((Double(entry.calories) * scale).rounded())
            mergedNutrients = entry.nutrientValues.mapValues { Int((Double($0) * scale).rounded()) }
        }

        let updatedEntry = MealEntry(
            id: entry.id,
            name: nameText,
            calories: finalCalories,
            nutrientValues: mergedNutrients,
            loggedCount: quantity > 1 ? quantity : nil,
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
