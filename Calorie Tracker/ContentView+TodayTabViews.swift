// Calorie Tracker 2026

import SwiftUI

extension ContentView {

    @ViewBuilder
    var foodLogSections: some View {
        if groupedTodayEntries.isEmpty {
            Section {
                Text("No entries yet.")
                    .foregroundStyle(textSecondary)
                    .listRowBackground(surfacePrimary)
            } header: {
                Text("Today's Food Log")
                .foregroundStyle(textSecondary)
            }
        } else {
            ForEach(Array(groupedTodayEntries.enumerated()), id: \.element.group.id) { index, groupData in
                Section {
                    ForEach(groupData.entries) { entry in
                        logRow(entry)
                            .listRowBackground(surfacePrimary)
                            .contextMenu {
                                if let primaryEntry = entry.primaryEntry, entry.servingCount == 1 {
                                    Button {
                                        editingEntry = primaryEntry
                                        Haptics.selection()
                                    } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }

                                    Button(role: .destructive) {
                                        deleteEntry(primaryEntry)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                } else if entry.servingCount > 1 {
                                    Button {
                                        foodLogEntryPickerContext = FoodLogEntryPickerContext(
                                            title: entry.name,
                                            entries: entry.entries
                                        )
                                        Haptics.selection()
                                    } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }

                                    Button(role: .destructive) {
                                        deleteEntries(entry.entries)
                                    } label: {
                                        Label("Delete All", systemImage: "trash")
                                    }
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                if let primaryEntry = entry.primaryEntry, entry.servingCount == 1 {
                                    Button(role: .destructive) {
                                        deleteEntry(primaryEntry)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                } else if entry.servingCount > 1 {
                                    Button(role: .destructive) {
                                        deleteEntries(entry.entries)
                                    } label: {
                                        Label("Delete All", systemImage: "trash")
                                    }
                                }
                            }
                    }
                } header: {
                    VStack(alignment: .leading, spacing: index == 0 ? 18 : 12) {
                        if index == 0 {
                            Text("Today's Food Log")
                            .padding(.bottom, 2)
                        }
                        HStack(spacing: 12) {
                            Text(groupData.group.title)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(textSecondary.opacity(0.92))
                            Spacer()
                            Text("\(groupData.entries.reduce(0) { $0 + $1.calories }) cal")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(textSecondary.opacity(0.82))
                                .monospacedDigit()
                        }
                    }
                    .padding(.top, index == 0 ? 8 : 0)
                    .foregroundStyle(textSecondary)
                }
            }
        }
    }

    @ViewBuilder
    var todayResetSection: some View {
        Section {
            Button(role: .destructive) {
                isResetConfirmationPresented = true
                Haptics.impact(.light)
            } label: {
                Text("Reset Today")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.red)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .listRowBackground(surfacePrimary)
        }
    }

    @ViewBuilder
    var exerciseLogSection: some View {
        let allExercises = exercises + effectiveTodayHealthWorkouts
        let exerciseCalTotal = allExercises.reduce(0) { $0 + $1.calories }
        let hasStepData = stepActivityService.todayStepCount > 0
        Section {
            if allExercises.isEmpty && !hasStepData {
                Text(isUsingSyncedHealthFallback ? "No synced workouts from iPhone yet today." : "No exercise logged.")
                    .foregroundStyle(textSecondary)
                    .listRowBackground(surfacePrimary)
            } else {
                ForEach(allExercises.sorted(by: { $0.createdAt > $1.createdAt })) { entry in
                    exerciseLogRow(entry, isDeletable: exercises.contains(where: { $0.id == entry.id }))
                }
                if hasStepData {
                    HStack(spacing: 12) {
                        Image(systemName: "figure.walk")
                            .font(.body)
                            .foregroundStyle(accent)
                            .frame(width: 28, alignment: .center)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Walking")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(textPrimary)
                            Text("\(stepActivityService.todayStepCount.formatted()) steps")
                                .font(.caption)
                                .foregroundStyle(textSecondary)
                        }
                        Spacer()
                        Text("\(effectiveActivityCaloriesToday) cal")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(accent)
                            .monospacedDigit()
                    }
                    .listRowBackground(surfacePrimary)
                }
            }

            if isUsingSyncedHealthFallback {
                HStack(spacing: 10) {
                    Image(systemName: "iphone")
                        .foregroundStyle(accent)
                    Text("Showing synced exercise data from iPhone.")
                        .font(.caption)
                        .foregroundStyle(textSecondary)
                    Spacer(minLength: 0)
                }
                .listRowBackground(surfacePrimary)
            }

            Button {
                isAddExerciseSheetPresented = true
                Haptics.impact(.light)
            } label: {
                Label("Add Exercise", systemImage: "figure.run")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .listRowBackground(surfacePrimary)
        } header: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Text("Exercise")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(textSecondary.opacity(0.92))
                    Spacer()
                    Text("\(exerciseCalTotal + effectiveActivityCaloriesToday) cal")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(textSecondary.opacity(0.82))
                        .monospacedDigit()
                }
            }
            .padding(.top, 8)
            .foregroundStyle(textSecondary)
        }
    }


    func mergedWorkoutEntries(primary: [ExerciseEntry], secondary: [ExerciseEntry]) -> [ExerciseEntry] {
        var seen = Set<String>()
        var merged: [ExerciseEntry] = []

        for entry in (primary + secondary).sorted(by: { $0.createdAt > $1.createdAt }) {
            let key = workoutMergeKey(for: entry)
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            merged.append(entry)
        }

        return merged
    }

    func workoutMergeKey(for entry: ExerciseEntry) -> String {
        let roundedTimestamp = Int(entry.createdAt.timeIntervalSince1970.rounded())
        let distanceBucket = Int(((entry.distanceMiles ?? 0) * 100).rounded())
        let name = (entry.customName ?? "").lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(entry.exerciseType.rawValue)|\(name)|\(entry.durationMinutes)|\(entry.calories)|\(distanceBucket)|\(roundedTimestamp)"
    }

    func exerciseLogRow(_ entry: ExerciseEntry, isDeletable: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: entry.displayIconName)
                .font(.body)
                .foregroundStyle(accent)
                .frame(width: 28, alignment: .center)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(textPrimary)
                Text(entry.displayValue)
                    .font(.caption)
                    .foregroundStyle(textSecondary)
            }
            Spacer()
            Text("\(entry.calories) cal")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(accent)
                .monospacedDigit()
        }
        .listRowBackground(surfacePrimary)
        .contextMenu {
            if isDeletable {
                Button(role: .destructive) {
                    deleteExercise(entry)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if isDeletable {
                Button(role: .destructive) {
                    deleteExercise(entry)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    @ViewBuilder
    var mealDistributionSection: some View {
        Section {
            if mealDistributionData.isEmpty {
                Text("Log food to see your calorie split by meal.")
                    .foregroundStyle(textSecondary)
                    .listRowBackground(surfacePrimary)
            } else {
                mealDistributionCard(mealDistributionData)
                .padding(.vertical, 8)
                .listRowBackground(surfacePrimary)
            }
        } header: {
            Text("Meal Distribution")
                .foregroundStyle(textSecondary)
        }
    }

    func mealDistributionCard(_ distribution: [(group: MealGroup, calories: Int)], valueSuffix: String = "cal") -> some View {
        HStack(alignment: .center, spacing: 20) {
            MealDistributionRingView(
                segments: distribution.map { (group: $0.group, calories: $0.calories, color: color(for: $0.group)) }
            )
            .frame(width: 132, height: 132)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(distribution, id: \.group.id) { item in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(color(for: item.group))
                            .frame(width: 10, height: 10)

                        Text(item.group.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(textPrimary)

                        Spacer(minLength: 12)

                        Text("\(item.calories) \(valueSuffix)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(textSecondary)
                            .monospacedDigit()
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
            }
            .padding(.leading, 8)
        }
    }

    func color(for mealGroup: MealGroup) -> Color {
        if appThemeStyleRaw == AppThemeStyle.blueprint.rawValue {
            switch mealGroup {
            case .breakfast: return Color(red: 0.15, green: 0.83, blue: 0.55) // mint green
            case .lunch:     return Color(red: 0.99, green: 0.80, blue: 0.11) // golden yellow
            case .dinner:    return Color(red: 1.0,  green: 0.42, blue: 0.29) // coral red
            case .snack:     return Color(red: 0.23, green: 0.51, blue: 1.0)  // bright blue
            }
        }
        switch mealGroup {
        case .breakfast: return Color(red: 0.88, green: 0.68, blue: 0.36) // warm gold — morning
        case .lunch:     return Color(red: 0.42, green: 0.70, blue: 0.54) // muted sage — midday
        case .dinner:    return Color(red: 0.52, green: 0.56, blue: 0.80) // dusty slate blue — evening
        case .snack:     return Color(red: 0.76, green: 0.50, blue: 0.55) // muted rose — treat
        }
    }

    func logRow(_ entry: FoodLogDisplayEntry) -> some View {
        let nutrientSummary = activeNutrients.prefix(2).map {
            "\(entryValue(for: $0.key, in: entry))\($0.unit) \($0.name)"
        }.joined(separator: " • ")

        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(entry.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(textPrimary)

                    if entry.displayCount > 1 {
                        Text("x\(entry.displayCount)")
                            .font(.caption2.monospacedDigit().weight(.semibold))
                            .foregroundStyle(textSecondary)
                            .frame(minWidth: 22, minHeight: 22)
                            .padding(.horizontal, 2)
                            .background(
                                Circle()
                                    .fill(surfaceSecondary.opacity(0.95))
                            )
                    }
                }
                Text("\(entry.calories) cal" + (nutrientSummary.isEmpty ? "" : " • \(nutrientSummary)"))
                    .font(.caption)
                    .foregroundStyle(textSecondary)
                    .lineLimit(2)
            }

            Spacer()

            Text(entry.createdAt.formatted(date: .omitted, time: .shortened))
                .font(.caption)
                .foregroundStyle(textSecondary)
        }
        .padding(.vertical, 2)
    }

    func nutrientFieldBinding(for key: String) -> Binding<String> {
        Binding(
            get: { nutrientInputTexts[key] ?? "" },
            set: { nutrientInputTexts[key] = $0 }
        )
    }

    var addEntryButton: some View {
        Button {
            addEntry()
        } label: {
            Text("Add Entry")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.borderedProminent)
        .tint(accent)
        .disabled(!canAddEntry)
    }

    func examplePlaceholder(for nutrient: NutrientDefinition) -> String {
        let example = max(1, nutrient.defaultGoal / 6)
        return "e.g. \(example)"
    }

    func manualEntryScrollID(for field: Field) -> String {
        switch field {
        case .name:
            return "manualEntryField_name"
        case .calories:
            return "manualEntryField_calories"
        case .nutrient(let key):
            return "manualEntryField_\(key)"
        }
    }

    func scrollManualEntryField(_ field: Field?, using proxy: ScrollViewProxy) {
        guard let field else { return }
        withAnimation(.easeOut(duration: 0.25)) {
            if case .nutrient(let key) = field,
               isKeyboardVisible,
               let rowIndex = manualEntryGridRows.firstIndex(where: { row in
                   row.contains {
                       if case .nutrient(let nutrient) = $0 {
                           return nutrient.key == key
                       }
                       return false
                   }
               }) {
                let lastRowIndex = manualEntryGridRows.count - 1
                if rowIndex == lastRowIndex {
                    proxy.scrollTo("addEntryButton", anchor: .bottom)
                    return
                }

                proxy.scrollTo(manualEntryScrollID(for: field), anchor: .center)
                return
            }

            proxy.scrollTo(manualEntryScrollID(for: field), anchor: .center)
        }
    }

    func scheduleManualEntryScroll(for field: Field?, using proxy: ScrollViewProxy) {
        let delays: [TimeInterval] = [0.08, 0.28]
        for delay in delays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard field == focusedField || field == nil else { return }
                scrollManualEntryField(focusedField ?? field, using: proxy)
            }
        }
    }

    @ViewBuilder
    func manualEntryGridCell(_ field: ManualEntryGridField) -> some View {
        switch field {
        case .calories:
            VStack(alignment: .leading, spacing: 8) {
                Text("Calories")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(textPrimary)

                TextField("e.g. 250", text: $entryCaloriesText)
                    .keyboardType(.numberPad)
                    .focused($focusedField, equals: .calories)
                    .inputStyle(surface: surfaceSecondary, text: textPrimary, secondary: textSecondary)
                    .id(manualEntryScrollID(for: .calories))
            }
        case .nutrient(let nutrient):
            nutrientFieldCell(nutrient)
        }
    }

    @ViewBuilder
    func nutrientFieldCell(_ nutrient: NutrientDefinition) -> some View {
        let label = nutrient.unit.uppercased() == "CALORIES" ? nutrient.name : "\(nutrient.name) (\(nutrient.unit))"
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(textPrimary)

            TextField(examplePlaceholder(for: nutrient), text: nutrientFieldBinding(for: nutrient.key))
                .keyboardType(.numberPad)
                .focused($focusedField, equals: .nutrient(nutrient.key))
                .inputStyle(surface: surfaceSecondary, text: textPrimary, secondary: textSecondary)
                .id(manualEntryScrollID(for: .nutrient(nutrient.key)))
        }
    }

    func addEntry() {
        guard
            let calories = parsedEntryCalories,
            let nutrientMap = parsedNutrientInputs,
            calories + nutrientMap.values.reduce(0, +) > 0
        else {
            Haptics.notification(.warning)
            return
        }

        let newEntry = MealEntry(
            id: UUID(),
            name: entryNameText,
            calories: calories,
            nutrientValues: nutrientMap,
            createdAt: Date(),
            mealGroup: mealGroup(for: Date(), source: .manual)
        )

        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            entries.append(newEntry)
        }
        showAddConfirmation()

        entryNameText = ""
        entryCaloriesText = ""
        barcodeLookupError = nil
        for nutrient in activeNutrients {
            nutrientInputTexts[nutrient.key] = ""
        }
        focusedField = nil
        dismissKeyboard()
    }


}
