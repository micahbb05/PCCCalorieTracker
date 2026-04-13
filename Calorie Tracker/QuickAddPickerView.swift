import SwiftUI

struct QuickAddPickerView: View {
    private struct ServingSheetContext: Identifiable {
        let id = UUID()
        let item: QuickAddFood
    }

    private struct QuickAddStatusState {
        let systemImage: String
        let title: String
        let message: String
    }

    private struct QuickAddSectionLine: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let iconSeed: String
        let systemIconName: String?
        let foods: [QuickAddFood]
    }

    let quickAddFoods: [QuickAddFood]
    let surfacePrimary: Color
    let surfaceSecondary: Color
    let textPrimary: Color
    let textSecondary: Color
    let accent: Color
    let trackedNutrientKeys: [String]
    let onAddSelected: ([(item: QuickAddFood, quantity: Int, multiplier: Double)]) -> Void
    let onManage: (() -> Void)?
    let onClose: (() -> Void)?
    let showsStandaloneChrome: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("quickAddSectionOverridesData") private var sectionOverridesData: String = ""
    @State private var searchText = ""
    @State private var selectedQuantitiesByID: [UUID: Int] = [:]
    @State private var selectedServingMultiplierByID: [UUID: Double] = [:]

    @State private var servingSheetContext: ServingSheetContext?
    @State private var servingSliderBaselineByItemId: [UUID: Double] = [:]
    @State private var servingSliderValueByItemId: [UUID: Double] = [:]
    @State private var expandedSectionIDs: Set<String> = []

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var usesSectionedLayout: Bool {
        quickAddFoods.count > 8
    }

    private var flatFilteredFoods: [QuickAddFood] {
        guard !trimmedSearchText.isEmpty else { return quickAddFoods }
        return quickAddFoods.filter { $0.name.localizedCaseInsensitiveContains(trimmedSearchText) }
    }

    private var recentFoods: [QuickAddFood] {
        Array(quickAddFoods.sorted { $0.lastUsedAt > $1.lastUsedAt }.prefix(5))
    }

    private var sectionOverridesByID: [UUID: QuickAddSectionClassifier.Section] {
        guard let data = sectionOverridesData.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        var mapped: [UUID: QuickAddSectionClassifier.Section] = [:]
        for (idString, sectionRaw) in decoded {
            guard let id = UUID(uuidString: idString),
                  let section = QuickAddSectionClassifier.Section(rawValue: sectionRaw) else { continue }
            mapped[id] = section
        }
        return mapped
    }

    private var foodsBySection: [QuickAddSectionClassifier.Section: [QuickAddFood]] {
        var grouped: [QuickAddSectionClassifier.Section: [QuickAddFood]] = [:]
        for item in quickAddFoods {
            let section = section(for: item)
            grouped[section, default: []].append(item)
        }
        return grouped
    }

    private var browsingLines: [QuickAddSectionLine] {
        var lines: [QuickAddSectionLine] = []

        if !recentFoods.isEmpty {
            lines.append(
                QuickAddSectionLine(
                    id: "recent",
                    title: "Recent",
                    subtitle: "Last 5 used",
                    iconSeed: "recent meals",
                    systemIconName: "clock.arrow.circlepath",
                    foods: recentFoods
                )
            )
        }

        for section in QuickAddSectionClassifier.Section.allCases {
            let items = foodsBySection[section, default: []]
            guard !items.isEmpty else { continue }
            lines.append(
                QuickAddSectionLine(
                    id: section.rawValue,
                    title: section.title,
                    subtitle: "\(items.count) saved",
                    iconSeed: section.iconSeed,
                    systemIconName: nil,
                    foods: items
                )
            )
        }

        return lines
    }

    private var searchLines: [QuickAddSectionLine] {
        guard usesSectionedLayout else { return [] }
        guard !trimmedSearchText.isEmpty else { return [] }

        var grouped: [QuickAddSectionClassifier.Section: [QuickAddFood]] = [:]
        for item in quickAddFoods where item.name.localizedCaseInsensitiveContains(trimmedSearchText) {
            let section = section(for: item)
            grouped[section, default: []].append(item)
        }

        var lines: [QuickAddSectionLine] = []
        for section in QuickAddSectionClassifier.Section.allCases {
            let items = grouped[section, default: []]
            guard !items.isEmpty else { continue }
            lines.append(
                QuickAddSectionLine(
                    id: section.rawValue,
                    title: section.title,
                    subtitle: "\(items.count) match\(items.count == 1 ? "" : "es")",
                    iconSeed: section.iconSeed,
                    systemIconName: nil,
                    foods: items
                )
            )
        }
        return lines
    }

    private var browsingStatusState: QuickAddStatusState? {
        guard trimmedSearchText.isEmpty else { return nil }
        if quickAddFoods.isEmpty {
            return QuickAddStatusState(
                systemImage: "fork.knife",
                title: "No quick add foods yet.",
                message: "Tap settings to create your first quick add food."
            )
        }
        return nil
    }

    private var searchStatusState: QuickAddStatusState? {
        guard usesSectionedLayout else { return nil }
        guard !trimmedSearchText.isEmpty else { return nil }
        if quickAddFoods.isEmpty {
            return QuickAddStatusState(
                systemImage: "fork.knife",
                title: "No quick add foods yet.",
                message: "Tap settings to create your first quick add food."
            )
        }
        if searchLines.isEmpty {
            return QuickAddStatusState(
                systemImage: "magnifyingglass",
                title: "No results found",
                message: "Try a broader search term or check spelling."
            )
        }
        return nil
    }

    private var selectedCount: Int {
        selectedQuantitiesByID.values.reduce(0, +)
    }

    private var isSelectionActionEnabled: Bool {
        selectedCount > 0
    }

    private var selectedFoodsAndQuantities: [(item: QuickAddFood, quantity: Int, multiplier: Double)] {
        quickAddFoods.compactMap { item in
            let quantity = selectedQuantitiesByID[item.id] ?? 0
            guard quantity > 0 else { return nil }
            return (item, quantity, multiplier(for: item.id))
        }
    }

    private var backgroundTop: Color {
        colorScheme == .dark ? Color(red: 0.059, green: 0.051, blue: 0.039) : Color(red: 0.97, green: 0.95, blue: 0.92)
    }

    private var backgroundBottom: Color {
        colorScheme == .dark ? Color(red: 0.078, green: 0.063, blue: 0.039) : Color(red: 0.93, green: 0.90, blue: 0.86)
    }

    var body: some View {
        Group {
            if showsStandaloneChrome {
                NavigationStack {
                    ZStack {
                        LinearGradient(
                            colors: AppTheme.sheetBackgroundGradient,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .ignoresSafeArea()

                        scrollContent
                    }
                }
            } else {
                scrollContent
            }
        }
        .sheet(item: $servingSheetContext, onDismiss: {
            servingSheetContext = nil
        }) { context in
            QuickAddServingSheetView(
                item: context.item,
                initialBaseline: servingSliderBaselineByItemId[context.item.id],
                initialSlider: servingSliderValueByItemId[context.item.id],
                initialMultiplier: selectedServingMultiplierByID[context.item.id] ?? 1.0,
                trackedNutrientKeys: trackedNutrientKeys,
                surfacePrimary: surfacePrimary,
                surfaceSecondary: surfaceSecondary,
                textPrimary: textPrimary,
                textSecondary: textSecondary,
                accent: accent
            ) { effectiveMultiplier, baseline, sliderValue in
                applyServingSelection(
                    for: context.item.id,
                    effectiveMultiplier: effectiveMultiplier,
                    baseline: baseline,
                    sliderValue: sliderValue
                )
            } onDismiss: {
                servingSheetContext = nil
            }
        }
    }

    /// Title, caption, actions, and search stay fixed; only the food list scrolls.
    private var scrollContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                if showsStandaloneChrome {
                    HStack {
                        Button {
                            if let onClose {
                                onClose()
                            } else {
                                dismiss()
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "chevron.left")
                                    .font(.caption.weight(.bold))
                                Text(onClose == nil ? "Close" : "Back")
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
                }
                headerRow

                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(textSecondary)
                    TextField("Search quick add foods", text: $searchText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .foregroundStyle(textPrimary)
                    Button {
                        guard !searchText.isEmpty else { return }
                        searchText = ""
                        Haptics.selection()
                    } label: {
                        Label("Clear search", systemImage: "xmark.circle.fill")
                            .labelStyle(.iconOnly)
                            .foregroundStyle(textSecondary)
                            .opacity(searchText.isEmpty ? 0.35 : 1)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .disabled(searchText.isEmpty)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .cardStyle(surface: surfacePrimary.opacity(0.95), stroke: textSecondary.opacity(0.18))
            }
            .padding(.horizontal, 16)
            .padding(.top, showsStandaloneChrome ? 18 : 12)
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(backgroundTop)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    content
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: quickAddFoods) { _, _ in
            pruneUnavailableSelections()
        }
    }

    @ViewBuilder
    private var content: some View {
        if usesSectionedLayout {
            if !trimmedSearchText.isEmpty {
                searchContent
            } else {
                browseContent
            }
        } else {
            flatContent
        }
    }

    @ViewBuilder
    private var browseContent: some View {
        if let state = browsingStatusState {
            statusCard(state)
        } else {
            LazyVStack(alignment: .leading, spacing: 14) {
                ForEach(browsingLines) { line in
                    browsingLineCard(line)
                }
            }
        }
    }

    @ViewBuilder
    private var searchContent: some View {
        if let state = searchStatusState {
            statusCard(state)
        } else {
            LazyVStack(alignment: .leading, spacing: 18) {
                ForEach(searchLines) { line in
                    searchLineCard(line)
                }
            }
        }
    }

    @ViewBuilder
    private var flatContent: some View {
        if flatFilteredFoods.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(quickAddFoods.isEmpty ? "No quick add foods yet." : "No quick add foods match your search.")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(textPrimary)
                Text(quickAddFoods.isEmpty ? "Tap settings to create your first quick add food." : "Try a broader search term.")
                    .font(.subheadline)
                    .foregroundStyle(textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .cardStyle(surface: surfacePrimary.opacity(0.95), stroke: textSecondary.opacity(0.18))
        } else {
            LazyVStack(spacing: 12) {
                ForEach(flatFilteredFoods) { item in
                    quickAddItemRow(item)
                }
            }
        }
    }

    private func browsingLineCard(_ line: QuickAddSectionLine) -> some View {
        let expanded = isSectionExpandedBinding(for: line.id)

        return VStack(spacing: 0) {
            Button {
                expanded.wrappedValue.toggle()
                Haptics.selection()
            } label: {
                HStack(spacing: 12) {
                    sectionHeaderIcon(for: line)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(line.title)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(textPrimary)
                        Text(line.subtitle)
                            .font(.caption)
                            .foregroundStyle(textSecondary)
                    }

                    Spacer()

                    Image(systemName: expanded.wrappedValue ? "chevron.up" : "chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(textSecondary)
                }
                .padding(18)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded.wrappedValue {
                Divider()
                    .overlay(textSecondary.opacity(0.10))
                    .padding(.horizontal, 18)

                VStack(spacing: 10) {
                    ForEach(line.foods) { item in
                        quickAddItemRow(item)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 14)
            }
        }
        .cardStyle(surface: surfacePrimary.opacity(0.95), stroke: textSecondary.opacity(0.15))
    }

    private func searchLineCard(_ line: QuickAddSectionLine) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                sectionHeaderIcon(for: line)

                VStack(alignment: .leading, spacing: 5) {
                    Text(line.title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(textPrimary)
                    Text(line.subtitle)
                        .font(.caption)
                        .foregroundStyle(textSecondary)
                }

                Spacer()
            }
            .padding(.horizontal, 4)
            .padding(.top, 2)
            .padding(.bottom, 8)

            Divider()
                .overlay(textSecondary.opacity(0.10))

            VStack(spacing: 8) {
                ForEach(line.foods) { item in
                    quickAddItemRow(item, compact: true)
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .padding(.bottom, 4)
        }
    }

    private func statusCard(_ state: QuickAddStatusState) -> some View {
        VStack(spacing: 16) {
            Image(systemName: state.systemImage)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(accent)

            VStack(spacing: 6) {
                Text(state.title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(textPrimary)
                Text(state.message)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .cardStyle(surface: surfacePrimary.opacity(0.95), stroke: textSecondary.opacity(0.18))
    }

    @ViewBuilder
    private func sectionHeaderIcon(for line: QuickAddSectionLine) -> some View {
        if let systemIconName = line.systemIconName {
            Image(systemName: systemIconName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 36, height: 36)
        } else {
            FoodLogIconView(
                token: FoodIconMLMapper.icon(for: line.iconSeed),
                accent: accent,
                size: 30
            )
            .frame(width: 36, height: 36)
        }
    }

    private func isSectionExpandedBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: { expandedSectionIDs.contains(id) },
            set: { expanded in
                if expanded {
                    expandedSectionIDs.insert(id)
                } else {
                    expandedSectionIDs.remove(id)
                }
            }
        )
    }

    private var compactHeaderActions: some View {
        HStack(spacing: 10) {
            if let onManage {
                Button {
                    onManage()
                    Haptics.impact(.light)
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(textPrimary)
                        .frame(width: 40, height: 40)
                        .background(
                            Circle()
                                .fill(surfaceSecondary.opacity(0.98))
                        )
                        .overlay(
                            Circle()
                                .stroke(textSecondary.opacity(0.18), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }

            compactAddSelectedButton
        }
    }

    private var headerRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 14) {
                Text("Quick Add")
                    .font(.system(size: 32, weight: .bold, design: .default))
                    .foregroundStyle(textPrimary)

                Spacer(minLength: 8)

                compactHeaderActions
                    .padding(.top, 2)
            }

            Text("Add one of your saved foods.")
                .font(.subheadline)
                .foregroundStyle(textSecondary)
        }
    }

    private var compactAddSelectedButton: some View {
        Button {
            guard selectedCount > 0 else {
                Haptics.notification(.warning)
                return
            }
            Haptics.impact(.medium)
            onAddSelected(selectedFoodsAndQuantities)
            let selectedIDs = Set(selectedFoodsAndQuantities.map { $0.item.id })
            selectedQuantitiesByID.removeAll()
            for id in selectedIDs {
                selectedServingMultiplierByID.removeValue(forKey: id)
                servingSliderBaselineByItemId.removeValue(forKey: id)
                servingSliderValueByItemId.removeValue(forKey: id)
            }
        } label: {
            HStack(spacing: 8) {
                Text("Add")
                    .font(.subheadline.weight(.semibold))

                Text("\(selectedCount)")
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous)
                            .fill(.white.opacity(0.14))
                    )
            }
            .foregroundStyle(isSelectionActionEnabled ? .white : textSecondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelectionActionEnabled ? accent : surfaceSecondary.opacity(0.98))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(
                        isSelectionActionEnabled ? Color.clear : textSecondary.opacity(0.18),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func quickAddItemRow(_ item: QuickAddFood, compact: Bool = false) -> some View {
        let currentMultiplier = multiplier(for: item.id)
        let displayedCalories = Int((Double(item.calories) * currentMultiplier).rounded())
        let displayedProtein = Int((Double(item.nutrientValues["g_protein"] ?? 0) * currentMultiplier).rounded())
        let rowPadding: CGFloat = compact ? 12 : 16
        let cornerRadius: CGFloat = compact ? 14 : 18
        let controlSize: CGFloat = compact ? 26 : 28
        let iconFontSize: CGFloat = compact ? 13 : 14
        let quantityMinWidth: CGFloat = compact ? 24 : 28

        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(item.name)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(textPrimary)
                HStack(spacing: 6) {
                    Text("\(displayedCalories) cal • \(displayedProtein)g protein")
                    if abs(currentMultiplier - 1.0) > 0.001 {
                        Text(formattedDisplayServingWithUnit(item.servingAmount * currentMultiplier, unit: item.servingUnit))
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.cyan)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(.cyan.opacity(0.14))
                            )
                    }
                }
                .font(.caption)
                .foregroundStyle(textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                openServingSheet(for: item)
            }

            Spacer()

            HStack(spacing: 10) {
                Button {
                    decrement(item.id)
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: iconFontSize, weight: .bold))
                        .foregroundStyle(.white.opacity(quantity(for: item.id) > 0 ? 0.92 : 0.35))
                        .frame(width: controlSize, height: controlSize)
                        .background(
                            Circle()
                                .fill(Color.white.opacity(quantity(for: item.id) > 0 ? 0.10 : 0.05))
                        )
                }
                .buttonStyle(.plain)
                .disabled(quantity(for: item.id) == 0)

                Text("\(quantity(for: item.id))")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .frame(minWidth: quantityMinWidth)
                    .foregroundStyle(textPrimary)

                Button {
                    increment(item.id)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: iconFontSize, weight: .bold))
                        .foregroundStyle(.white.opacity(0.96))
                        .frame(width: controlSize, height: controlSize)
                        .background(
                            Circle()
                                .fill(accent)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )
        }
        .padding(rowPadding)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(compact ? surfacePrimary.opacity(0.90) : surfaceSecondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(textSecondary.opacity(0.12), lineWidth: 1)
        )
    }

    private func quantity(for id: UUID) -> Int {
        max(selectedQuantitiesByID[id] ?? 0, 0)
    }

    private func multiplier(for id: UUID) -> Double {
        selectedServingMultiplierByID[id] ?? 1.0
    }

    private func increment(_ id: UUID) {
        selectedQuantitiesByID[id] = min(quantity(for: id) + 1, 99)
        if selectedServingMultiplierByID[id] == nil {
            selectedServingMultiplierByID[id] = 1.0
        }
        Haptics.selection()
    }

    private func decrement(_ id: UUID) {
        let next = quantity(for: id) - 1
        if next <= 0 {
            selectedQuantitiesByID.removeValue(forKey: id)
            selectedServingMultiplierByID.removeValue(forKey: id)
            servingSliderBaselineByItemId.removeValue(forKey: id)
            servingSliderValueByItemId.removeValue(forKey: id)
        } else {
            selectedQuantitiesByID[id] = next
        }
        Haptics.selection()
    }

    private func openServingSheet(for item: QuickAddFood) {
        dismissKeyboard()
        servingSheetContext = nil
        Haptics.impact(.light)
        DispatchQueue.main.async {
            servingSheetContext = ServingSheetContext(item: item)
        }
    }

    private func applyServingSelection(
        for id: UUID,
        effectiveMultiplier: Double,
        baseline: Double,
        sliderValue: Double
    ) {
        // Close first so the dismissal animation is not competing with heavy list re-render work.
        servingSheetContext = nil
        DispatchQueue.main.async {
            selectedServingMultiplierByID[id] = effectiveMultiplier
            servingSliderBaselineByItemId[id] = baseline
            servingSliderValueByItemId[id] = sliderValue
            if selectedQuantitiesByID[id] == nil || selectedQuantitiesByID[id] == 0 {
                selectedQuantitiesByID[id] = 1
            }
        }
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func formattedDisplayServingWithUnit(_ amount: Double, unit: String) -> String {
        let formattedAmount = formatServingSelectorAmount(amount)
        let displayUnit = quickAddIsGramUnit(unit) ? "g" : unit
        let unitText = inflectServingUnitToken(displayUnit, quantity: amount)
        return "\(formattedAmount) \(unitText)"
    }

    private func quickAddIsGramUnit(_ unit: String) -> Bool {
        let n = unit.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return n == "g" || n == "gram" || n == "grams" || n == "grms"
    }

    private func section(for item: QuickAddFood) -> QuickAddSectionClassifier.Section {
        if let override = sectionOverridesByID[item.id] {
            return override
        }
        return QuickAddSectionClassifier.shared.classify(item)
    }

    private func pruneUnavailableSelections() {
        let availableIDs = Set(quickAddFoods.map(\.id))
        selectedQuantitiesByID = selectedQuantitiesByID.filter { availableIDs.contains($0.key) && $0.value > 0 }
        selectedServingMultiplierByID = selectedServingMultiplierByID.filter { availableIDs.contains($0.key) && $0.value > 0 }
        servingSliderBaselineByItemId = servingSliderBaselineByItemId.filter { availableIDs.contains($0.key) }
        servingSliderValueByItemId = servingSliderValueByItemId.filter { availableIDs.contains($0.key) }
    }
}

struct QuickAddSectionClassifier {
    enum Section: String, CaseIterable {
        case meal
        case snack
        case dessert

        var title: String {
            switch self {
            case .meal: return "Meals"
            case .snack: return "Snacks"
            case .dessert: return "Desserts"
            }
        }

        var iconSeed: String {
            switch self {
            case .meal: return "chicken rice bowl"
            case .snack: return "potato chips"
            case .dessert: return "chocolate cake dessert"
            }
        }
    }

    private struct TrainingSample {
        let name: String
        let calories: Int
        let sugar: Int
        let protein: Int
        let section: Section
    }

    private struct TrainedModel {
        let vocabulary: Set<String>
        let classCounts: [Section: Int]
        let tokenCountsByClass: [Section: [String: Int]]
        let totalTokenCountByClass: [Section: Int]
        let totalDocumentCount: Int

        func predict(features: [String: Int]) -> Section {
            let classCount = Section.allCases.count
            let vocabularyCount = max(vocabulary.count, 1)

            var bestSection: Section = .meal
            var bestScore = -Double.infinity

            for section in Section.allCases {
                let documentCount = classCounts[section, default: 0]
                let prior = log(Double(documentCount + 1) / Double(totalDocumentCount + classCount))
                let classTokenCounts = tokenCountsByClass[section, default: [:]]
                let classTotalTokens = totalTokenCountByClass[section, default: 0]
                let denominator = Double(classTotalTokens + vocabularyCount)

                var score = prior
                for (token, count) in features where count > 0 {
                    let tokenCount = classTokenCounts[token, default: 0]
                    let tokenProbability = Double(tokenCount + 1) / denominator
                    score += Double(count) * log(tokenProbability)
                }

                if score > bestScore {
                    bestScore = score
                    bestSection = section
                }
            }

            return bestSection
        }
    }

    static let shared = QuickAddSectionClassifier()

    private let model: TrainedModel

    private init() {
        model = Self.trainModel()
    }

    func classify(_ item: QuickAddFood) -> Section {
        let sugar = max(item.nutrientValues["g_sugar"] ?? 0, item.nutrientValues["g_added_sugar"] ?? 0)
        let protein = item.nutrientValues["g_protein"] ?? 0
        let features = Self.features(
            name: item.name,
            calories: item.calories,
            sugar: sugar,
            protein: protein
        )
        return model.predict(features: features)
    }

    private nonisolated static func trainModel() -> TrainedModel {
        let samples = trainingSamples
        var vocabulary = Set<String>()
        var classCounts: [Section: Int] = [:]
        var tokenCountsByClass: [Section: [String: Int]] = [:]
        var totalTokenCountByClass: [Section: Int] = [:]

        for sample in samples {
            let features = features(
                name: sample.name,
                calories: sample.calories,
                sugar: sample.sugar,
                protein: sample.protein
            )
            classCounts[sample.section, default: 0] += 1
            for (token, count) in features where count > 0 {
                vocabulary.insert(token)
                tokenCountsByClass[sample.section, default: [:]][token, default: 0] += count
                totalTokenCountByClass[sample.section, default: 0] += count
            }
        }

        return TrainedModel(
            vocabulary: vocabulary,
            classCounts: classCounts,
            tokenCountsByClass: tokenCountsByClass,
            totalTokenCountByClass: totalTokenCountByClass,
            totalDocumentCount: samples.count
        )
    }

    private nonisolated static func features(name: String, calories: Int, sugar: Int, protein: Int) -> [String: Int] {
        var features: [String: Int] = [:]
        let tokens = tokenize(name)
        let stemmedTokens = tokens.map(stemToken)
        let trigrams = characterTrigrams(name)

        for token in tokens {
            features["w:\(token)", default: 0] += 1
        }
        for token in stemmedTokens {
            features["s:\(token)", default: 0] += 1
        }
        if tokens.count > 1 {
            for index in 0..<(tokens.count - 1) {
                let bigram = "\(tokens[index])_\(tokens[index + 1])"
                features["bg:\(bigram)", default: 0] += 1
            }
        }
        if let first = stemmedTokens.first {
            features["first:\(first)", default: 0] += 1
        }
        if let last = stemmedTokens.last {
            features["last:\(last)", default: 0] += 1
        }
        for trigram in trigrams {
            features["cg:\(trigram)", default: 0] += 1
        }
        features["name_token_count:\(min(tokens.count, 6))", default: 0] += 1

        if calories <= 180 {
            features["cal:light", default: 0] += 1
        } else if calories >= 420 {
            features["cal:heavy", default: 0] += 1
        } else {
            features["cal:mid", default: 0] += 1
        }

        if sugar >= 20 {
            features["sugar:high", default: 0] += 1
        } else if sugar >= 10 {
            features["sugar:mid", default: 0] += 1
        } else {
            features["sugar:low", default: 0] += 1
        }

        if protein >= 20 {
            features["protein:high", default: 0] += 1
        } else if protein >= 8 {
            features["protein:mid", default: 0] += 1
        } else {
            features["protein:low", default: 0] += 1
        }

        return features
    }

    private nonisolated static func tokenize(_ text: String) -> [String] {
        text
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
    }

    private nonisolated static func stemToken(_ token: String) -> String {
        guard token.count >= 4 else { return token }
        if token.hasSuffix("ies"), token.count > 4 {
            return String(token.dropLast(3)) + "y"
        }
        if token.hasSuffix("es"), token.count > 4 {
            return String(token.dropLast(2))
        }
        if token.hasSuffix("s"), token.count > 4 {
            return String(token.dropLast())
        }
        return token
    }

    private nonisolated static func characterTrigrams(_ text: String) -> [String] {
        let joined = tokenize(text).joined(separator: "_")
        guard joined.count >= 3 else { return joined.isEmpty ? [] : [joined] }

        let chars = Array(joined)
        var grams: [String] = []
        grams.reserveCapacity(max(chars.count - 2, 1))
        for index in 0...(chars.count - 3) {
            grams.append(String(chars[index...index + 2]))
        }
        return grams
    }

    private nonisolated static let trainingSamples: [TrainingSample] = [
        TrainingSample(name: "Grilled Chicken Bowl", calories: 520, sugar: 4, protein: 38, section: .meal),
        TrainingSample(name: "Turkey Sandwich", calories: 430, sugar: 6, protein: 29, section: .meal),
        TrainingSample(name: "Beef Burrito Bowl", calories: 610, sugar: 5, protein: 35, section: .meal),
        TrainingSample(name: "Salmon Rice Plate", calories: 560, sugar: 3, protein: 34, section: .meal),
        TrainingSample(name: "Pasta with Meat Sauce", calories: 640, sugar: 8, protein: 28, section: .meal),
        TrainingSample(name: "Chicken Alfredo Pasta", calories: 690, sugar: 5, protein: 32, section: .meal),
        TrainingSample(name: "Veggie Stir Fry", calories: 430, sugar: 9, protein: 16, section: .meal),
        TrainingSample(name: "Tofu Rice Bowl", calories: 470, sugar: 7, protein: 22, section: .meal),
        TrainingSample(name: "Chicken Caesar Salad", calories: 390, sugar: 3, protein: 30, section: .meal),
        TrainingSample(name: "Cobb Salad", calories: 460, sugar: 5, protein: 27, section: .meal),
        TrainingSample(name: "Breakfast Burrito", calories: 520, sugar: 4, protein: 24, section: .meal),
        TrainingSample(name: "Scrambled Eggs and Toast", calories: 380, sugar: 3, protein: 21, section: .meal),
        TrainingSample(name: "Omelet with Cheese", calories: 410, sugar: 2, protein: 25, section: .meal),
        TrainingSample(name: "Pho Noodle Soup", calories: 480, sugar: 5, protein: 24, section: .meal),
        TrainingSample(name: "Ramen Bowl", calories: 520, sugar: 6, protein: 18, section: .meal),
        TrainingSample(name: "Sushi Roll Combo", calories: 500, sugar: 7, protein: 20, section: .meal),
        TrainingSample(name: "Burger and Fries", calories: 780, sugar: 9, protein: 29, section: .meal),
        TrainingSample(name: "Cheeseburger", calories: 620, sugar: 8, protein: 31, section: .meal),
        TrainingSample(name: "Quesadilla", calories: 510, sugar: 4, protein: 20, section: .meal),
        TrainingSample(name: "Chicken Tacos", calories: 450, sugar: 3, protein: 24, section: .meal),
        TrainingSample(name: "Protein Box", calories: 390, sugar: 5, protein: 22, section: .meal),
        TrainingSample(name: "Rice and Beans Plate", calories: 520, sugar: 3, protein: 17, section: .meal),
        TrainingSample(name: "Falafel Wrap", calories: 540, sugar: 6, protein: 18, section: .meal),
        TrainingSample(name: "Chicken Curry", calories: 560, sugar: 7, protein: 30, section: .meal),
        TrainingSample(name: "Greek Chicken Plate", calories: 580, sugar: 5, protein: 33, section: .meal),
        TrainingSample(name: "Burrito", calories: 560, sugar: 4, protein: 24, section: .meal),
        TrainingSample(name: "Bean Burrito", calories: 490, sugar: 3, protein: 20, section: .meal),
        TrainingSample(name: "Breakfast Sandwich", calories: 430, sugar: 5, protein: 20, section: .meal),
        TrainingSample(name: "Mashed Potatoes", calories: 210, sugar: 2, protein: 4, section: .meal),
        TrainingSample(name: "Garlic Mashed Potatoes", calories: 230, sugar: 2, protein: 5, section: .meal),
        TrainingSample(name: "Mac and Cheese", calories: 480, sugar: 6, protein: 17, section: .meal),
        TrainingSample(name: "Chicken and Rice", calories: 530, sugar: 3, protein: 34, section: .meal),
        TrainingSample(name: "Steak and Potatoes", calories: 650, sugar: 4, protein: 38, section: .meal),
        TrainingSample(name: "Roasted Turkey Plate", calories: 510, sugar: 4, protein: 32, section: .meal),
        TrainingSample(name: "Baked Potato", calories: 240, sugar: 3, protein: 6, section: .meal),
        TrainingSample(name: "Loaded Baked Potato", calories: 420, sugar: 4, protein: 14, section: .meal),
        TrainingSample(name: "Chili Bowl", calories: 430, sugar: 7, protein: 22, section: .meal),
        TrainingSample(name: "Chicken Noodle Soup", calories: 300, sugar: 4, protein: 18, section: .meal),
        TrainingSample(name: "Tomato Soup and Grilled Cheese", calories: 520, sugar: 9, protein: 19, section: .meal),
        TrainingSample(name: "Teriyaki Chicken Bowl", calories: 560, sugar: 12, protein: 31, section: .meal),
        TrainingSample(name: "Taco Plate", calories: 500, sugar: 4, protein: 23, section: .meal),
        TrainingSample(name: "Pork Carnitas Bowl", calories: 610, sugar: 4, protein: 30, section: .meal),
        TrainingSample(name: "Fried Rice", calories: 540, sugar: 5, protein: 14, section: .meal),
        TrainingSample(name: "Pad Thai", calories: 620, sugar: 15, protein: 20, section: .meal),
        TrainingSample(name: "Chicken Parmesan", calories: 680, sugar: 8, protein: 38, section: .meal),
        TrainingSample(name: "Lasagna", calories: 640, sugar: 9, protein: 30, section: .meal),
        TrainingSample(name: "Enchiladas", calories: 590, sugar: 6, protein: 27, section: .meal),
        TrainingSample(name: "Stuffed Peppers", calories: 450, sugar: 10, protein: 24, section: .meal),
        TrainingSample(name: "Rice Bowl", calories: 500, sugar: 4, protein: 16, section: .meal),
        TrainingSample(name: "Pot Roast Plate", calories: 620, sugar: 6, protein: 34, section: .meal),
        TrainingSample(name: "Chicken Wrap", calories: 470, sugar: 5, protein: 26, section: .meal),
        TrainingSample(name: "Tuna Melt", calories: 520, sugar: 5, protein: 30, section: .meal),
        TrainingSample(name: "Lentil Bowl", calories: 430, sugar: 6, protein: 20, section: .meal),
        TrainingSample(name: "Potato Wedges", calories: 240, sugar: 1, protein: 4, section: .meal),
        TrainingSample(name: "Seasoned Potato Wedges", calories: 260, sugar: 1, protein: 4, section: .meal),
        TrainingSample(name: "Peanut Butter Sandwich", calories: 380, sugar: 10, protein: 14, section: .meal),
        TrainingSample(name: "Turkey Club Sandwich", calories: 560, sugar: 6, protein: 30, section: .meal),
        TrainingSample(name: "Ham and Cheese Sandwich", calories: 490, sugar: 5, protein: 26, section: .meal),
        TrainingSample(name: "Oatmeal", calories: 250, sugar: 8, protein: 7, section: .meal),
        TrainingSample(name: "Overnight Oats", calories: 280, sugar: 11, protein: 8, section: .meal),
        TrainingSample(name: "Savory Oatmeal Bowl", calories: 300, sugar: 4, protein: 12, section: .meal),
        TrainingSample(name: "Chicken Nuggets", calories: 310, sugar: 1, protein: 18, section: .meal),
        TrainingSample(name: "Nuggets and Fries", calories: 520, sugar: 2, protein: 20, section: .meal),
        TrainingSample(name: "Sweet Potato Fries", calories: 260, sugar: 9, protein: 3, section: .meal),
        TrainingSample(name: "Rice and Chicken Plate", calories: 540, sugar: 4, protein: 31, section: .meal),
        TrainingSample(name: "Pesto Chicken Sandwich", calories: 520, sugar: 5, protein: 29, section: .meal),
        TrainingSample(name: "Pulled Pork Burrito", calories: 640, sugar: 6, protein: 31, section: .meal),
        TrainingSample(name: "Beef and Bean Burrito", calories: 590, sugar: 5, protein: 27, section: .meal),
        TrainingSample(name: "Mashed Potatoes and Gravy", calories: 260, sugar: 3, protein: 5, section: .meal),
        TrainingSample(name: "Chicken Pesto Sandwich", calories: 520, sugar: 5, protein: 29, section: .meal),
        TrainingSample(name: "Teriyaki Beef Plate", calories: 620, sugar: 14, protein: 30, section: .meal),
        TrainingSample(name: "Veggie Burrito", calories: 480, sugar: 5, protein: 14, section: .meal),
        TrainingSample(name: "Egg and Potato Breakfast Bowl", calories: 450, sugar: 4, protein: 20, section: .meal),

        TrainingSample(name: "Trail Mix", calories: 210, sugar: 8, protein: 7, section: .snack),
        TrainingSample(name: "Potato Chips", calories: 170, sugar: 1, protein: 2, section: .snack),
        TrainingSample(name: "Pretzels", calories: 150, sugar: 2, protein: 3, section: .snack),
        TrainingSample(name: "Popcorn", calories: 140, sugar: 1, protein: 3, section: .snack),
        TrainingSample(name: "Granola Bar", calories: 190, sugar: 9, protein: 4, section: .snack),
        TrainingSample(name: "Protein Bar", calories: 210, sugar: 6, protein: 18, section: .snack),
        TrainingSample(name: "Beef Jerky", calories: 120, sugar: 3, protein: 14, section: .snack),
        TrainingSample(name: "String Cheese", calories: 90, sugar: 1, protein: 7, section: .snack),
        TrainingSample(name: "Greek Yogurt Cup", calories: 140, sugar: 7, protein: 12, section: .snack),
        TrainingSample(name: "Apple Slices", calories: 95, sugar: 18, protein: 0, section: .snack),
        TrainingSample(name: "Banana", calories: 105, sugar: 14, protein: 1, section: .snack),
        TrainingSample(name: "Mixed Nuts", calories: 200, sugar: 3, protein: 6, section: .snack),
        TrainingSample(name: "Almonds", calories: 170, sugar: 1, protein: 6, section: .snack),
        TrainingSample(name: "Peanuts", calories: 180, sugar: 2, protein: 8, section: .snack),
        TrainingSample(name: "Hummus and Carrots", calories: 160, sugar: 5, protein: 5, section: .snack),
        TrainingSample(name: "Crackers", calories: 150, sugar: 2, protein: 3, section: .snack),
        TrainingSample(name: "Rice Cakes", calories: 110, sugar: 1, protein: 2, section: .snack),
        TrainingSample(name: "Fruit Cup", calories: 130, sugar: 19, protein: 1, section: .snack),
        TrainingSample(name: "Edamame", calories: 140, sugar: 3, protein: 12, section: .snack),
        TrainingSample(name: "Cottage Cheese Cup", calories: 120, sugar: 4, protein: 11, section: .snack),
        TrainingSample(name: "Veggie Sticks", calories: 150, sugar: 1, protein: 2, section: .snack),
        TrainingSample(name: "Chex Mix", calories: 180, sugar: 4, protein: 4, section: .snack),
        TrainingSample(name: "Pita Chips", calories: 170, sugar: 2, protein: 4, section: .snack),
        TrainingSample(name: "Roasted Chickpeas", calories: 160, sugar: 2, protein: 8, section: .snack),
        TrainingSample(name: "Seaweed Snack", calories: 45, sugar: 0, protein: 2, section: .snack),
        TrainingSample(name: "Rice Krispies Treat", calories: 90, sugar: 8, protein: 1, section: .snack),
        TrainingSample(name: "Fruit Snacks", calories: 80, sugar: 11, protein: 0, section: .snack),
        TrainingSample(name: "Goldfish Crackers", calories: 140, sugar: 1, protein: 3, section: .snack),
        TrainingSample(name: "Cheese Crackers", calories: 150, sugar: 2, protein: 4, section: .snack),
        TrainingSample(name: "Bag of Chips", calories: 160, sugar: 1, protein: 2, section: .snack),
        TrainingSample(name: "Celery and Peanut Butter", calories: 170, sugar: 5, protein: 6, section: .snack),
        TrainingSample(name: "Hard Boiled Egg", calories: 78, sugar: 0, protein: 6, section: .snack),
        TrainingSample(name: "Mini Pretzels", calories: 120, sugar: 2, protein: 3, section: .snack),
        TrainingSample(name: "Snack Mix", calories: 170, sugar: 4, protein: 4, section: .snack),
        TrainingSample(name: "Yogurt Parfait", calories: 190, sugar: 14, protein: 8, section: .snack),
        TrainingSample(name: "Pita and Hummus", calories: 260, sugar: 3, protein: 8, section: .snack),
        TrainingSample(name: "Corn Chips", calories: 150, sugar: 1, protein: 2, section: .snack),
        TrainingSample(name: "Mixed Seed Snack", calories: 190, sugar: 2, protein: 7, section: .snack),
        TrainingSample(name: "Sea Salt Popcorn", calories: 120, sugar: 1, protein: 3, section: .snack),
        TrainingSample(name: "Mini Cheese Crackers", calories: 140, sugar: 2, protein: 4, section: .snack),
        TrainingSample(name: "Veggie Chips", calories: 130, sugar: 3, protein: 2, section: .snack),
        TrainingSample(name: "Snack Pretzels", calories: 110, sugar: 1, protein: 2, section: .snack),
        TrainingSample(name: "Fruit and Yogurt", calories: 170, sugar: 18, protein: 8, section: .snack),
        TrainingSample(name: "Yogurt Bowl", calories: 260, sugar: 21, protein: 10, section: .snack),

        TrainingSample(name: "Chocolate Chip Cookie", calories: 260, sugar: 20, protein: 3, section: .dessert),
        TrainingSample(name: "Brownie", calories: 320, sugar: 29, protein: 4, section: .dessert),
        TrainingSample(name: "Cheesecake Slice", calories: 410, sugar: 26, protein: 7, section: .dessert),
        TrainingSample(name: "Vanilla Ice Cream", calories: 280, sugar: 23, protein: 5, section: .dessert),
        TrainingSample(name: "Chocolate Ice Cream", calories: 300, sugar: 25, protein: 5, section: .dessert),
        TrainingSample(name: "Donut", calories: 290, sugar: 18, protein: 4, section: .dessert),
        TrainingSample(name: "Cupcake", calories: 330, sugar: 30, protein: 3, section: .dessert),
        TrainingSample(name: "Apple Pie", calories: 360, sugar: 27, protein: 3, section: .dessert),
        TrainingSample(name: "Pumpkin Pie", calories: 340, sugar: 24, protein: 5, section: .dessert),
        TrainingSample(name: "Pudding", calories: 230, sugar: 22, protein: 4, section: .dessert),
        TrainingSample(name: "Flan", calories: 250, sugar: 24, protein: 5, section: .dessert),
        TrainingSample(name: "Tiramisu", calories: 390, sugar: 27, protein: 6, section: .dessert),
        TrainingSample(name: "Muffin", calories: 340, sugar: 24, protein: 5, section: .dessert),
        TrainingSample(name: "Cinnamon Roll", calories: 420, sugar: 31, protein: 6, section: .dessert),
        TrainingSample(name: "Candy Bar", calories: 240, sugar: 26, protein: 3, section: .dessert),
        TrainingSample(name: "Chocolate", calories: 210, sugar: 19, protein: 2, section: .dessert),
        TrainingSample(name: "Milkshake", calories: 510, sugar: 52, protein: 10, section: .dessert),
        TrainingSample(name: "Frozen Yogurt", calories: 230, sugar: 24, protein: 6, section: .dessert),
        TrainingSample(name: "Sweet Pastry", calories: 320, sugar: 22, protein: 5, section: .dessert),
        TrainingSample(name: "Churro", calories: 280, sugar: 20, protein: 3, section: .dessert),
        TrainingSample(name: "Baklava", calories: 310, sugar: 23, protein: 4, section: .dessert),
        TrainingSample(name: "Rice Pudding", calories: 260, sugar: 25, protein: 5, section: .dessert),
        TrainingSample(name: "Sorbet", calories: 180, sugar: 29, protein: 1, section: .dessert),
        TrainingSample(name: "Macaron", calories: 180, sugar: 17, protein: 3, section: .dessert),
        TrainingSample(name: "Carrot Cake", calories: 370, sugar: 31, protein: 5, section: .dessert),
        TrainingSample(name: "Fudge Popsicle", calories: 120, sugar: 16, protein: 2, section: .dessert),
        TrainingSample(name: "Fudge Pop", calories: 110, sugar: 15, protein: 2, section: .dessert),
        TrainingSample(name: "Drizzilicious Cookies and Cream", calories: 140, sugar: 9, protein: 1, section: .dessert),
        TrainingSample(name: "Cookies and Cream", calories: 260, sugar: 24, protein: 4, section: .dessert),
        TrainingSample(name: "Lowfat Ice Cream Sandwich", calories: 160, sugar: 16, protein: 3, section: .dessert),
        TrainingSample(name: "Ice Cream Sandwich", calories: 210, sugar: 20, protein: 4, section: .dessert),
        TrainingSample(name: "Popsicle", calories: 90, sugar: 18, protein: 0, section: .dessert),
        TrainingSample(name: "Frozen Dessert Bar", calories: 170, sugar: 17, protein: 2, section: .dessert),
        TrainingSample(name: "Oatmeal Cookie", calories: 190, sugar: 14, protein: 3, section: .dessert),
        TrainingSample(name: "Chocolate Pudding Cup", calories: 170, sugar: 21, protein: 3, section: .dessert),
        TrainingSample(name: "Ice Cream Bar", calories: 240, sugar: 22, protein: 4, section: .dessert),
        TrainingSample(name: "Frozen Custard", calories: 310, sugar: 26, protein: 6, section: .dessert),
        TrainingSample(name: "Shortcake", calories: 320, sugar: 27, protein: 4, section: .dessert),
        TrainingSample(name: "Cannoli", calories: 300, sugar: 22, protein: 5, section: .dessert),
        TrainingSample(name: "Creme Brulee", calories: 340, sugar: 28, protein: 5, section: .dessert),
        TrainingSample(name: "Sweet Cream Gelato", calories: 260, sugar: 24, protein: 5, section: .dessert),
        TrainingSample(name: "Fudge Bar", calories: 150, sugar: 18, protein: 2, section: .dessert),
        TrainingSample(name: "Cookies and Cream Bar", calories: 210, sugar: 21, protein: 3, section: .dessert),
        TrainingSample(name: "Low Fat Ice Cream Sandwiches", calories: 180, sugar: 17, protein: 3, section: .dessert),
        TrainingSample(name: "Drizzilicious Cinnamon Swirl", calories: 140, sugar: 8, protein: 1, section: .dessert),
        TrainingSample(name: "Chocolate Pudding", calories: 180, sugar: 19, protein: 3, section: .dessert),
        TrainingSample(name: "Frozen Fudge Pops", calories: 120, sugar: 14, protein: 2, section: .dessert),
        TrainingSample(name: "Vanilla Ice Cream Sandwich", calories: 220, sugar: 22, protein: 4, section: .dessert),
        TrainingSample(name: "Cookies n Cream Ice Cream", calories: 270, sugar: 24, protein: 4, section: .dessert),
        TrainingSample(name: "Chocolate Banana", calories: 210, sugar: 22, protein: 2, section: .dessert),
        TrainingSample(name: "Cookie Dough Bites", calories: 280, sugar: 24, protein: 3, section: .dessert),
        TrainingSample(name: "Pancake Bites", calories: 220, sugar: 12, protein: 4, section: .dessert),
        TrainingSample(name: "Cinnamon Apples", calories: 180, sugar: 20, protein: 0, section: .dessert),
        TrainingSample(name: "Ice Cream Cookie Sandwich", calories: 290, sugar: 27, protein: 4, section: .dessert)
    ]
}

// MARK: - Serving sheet (isolated so its state doesn't re-render the picker list)

struct QuickAddServingSheetView: View {
    let item: QuickAddFood
    let initialBaseline: Double?
    let initialSlider: Double?
    let initialMultiplier: Double
    let trackedNutrientKeys: [String]
    let surfacePrimary: Color
    let surfaceSecondary: Color
    let textPrimary: Color
    let textSecondary: Color
    let accent: Color
    let onConfirm: (_ effectiveMultiplier: Double, _ baseline: Double, _ sliderValue: Double) -> Void
    let onDismiss: () -> Void

    private let minMultiplier = 0.25
    private let maxMultiplier = 1.75
    private let multiplierStep = 0.25

    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedMultiplierValue = 1.0
    @State private var selectedServingBaselineAmount = 1.0
    @State private var selectedServingAmountText = ""
    @State private var isUpdatingServingTextFromSlider = false
    @State private var isServingKeyboardVisible = false
    @FocusState private var isServingAmountFieldFocused: Bool

    private var backgroundTop: Color {
        colorScheme == .dark ? Color(red: 0.059, green: 0.051, blue: 0.039) : Color(red: 0.97, green: 0.95, blue: 0.92)
    }

    private var backgroundBottom: Color {
        colorScheme == .dark ? Color(red: 0.078, green: 0.063, blue: 0.039) : Color(red: 0.93, green: 0.90, blue: 0.86)
    }

    private var effectiveMultiplier: Double {
        let baseAmount = item.servingAmount
        guard baseAmount > 0 else { return 1.0 }
        let selectedAmount = roundToServingSelectorIncrement(selectedServingBaselineAmount * selectedMultiplierValue)
        return max(selectedAmount / baseAmount, 0)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [backgroundTop, backgroundBottom],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Adjust Serving")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(accent)

                            Text(item.name)
                                .font(.system(size: 28, weight: .bold, design: .default))
                                .foregroundStyle(textPrimary)
                                .lineLimit(3)
                                .fixedSize(horizontal: false, vertical: true)

                            Text("Base serve: \(formattedDisplayServingWithUnit(item.servingAmount, unit: item.servingUnit))")
                                .font(.subheadline)
                                .foregroundStyle(textSecondary)
                        }

                        if isCountBased(item: item) {
                            countServingControl
                        } else {
                            sliderServingControl
                        }

                        ServingNutrientGridCard(
                            title: "Nutrition Info",
                            calories: item.calories,
                            nutrientValues: item.nutrientValues,
                            multiplier: effectiveMultiplier,
                            trackedNutrientKeys: trackedNutrientKeys,
                            displayedNutrientKeys: nil,
                            surface: surfacePrimary.opacity(0.95),
                            stroke: textSecondary.opacity(0.18),
                            titleColor: textPrimary,
                            labelColor: textSecondary,
                            valueColor: textPrimary
                        )
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 120)
                }
                .scrollBounceBehavior(.always)
                .scrollDismissesKeyboard(.interactively)
                .scrollIndicators(.hidden)
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    confirmServing()
                } label: {
                    Text("Set Serving Size")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 12)
                .background(
                    ZStack {
                        Rectangle().fill(.ultraThinMaterial)
                        LinearGradient(
                            colors: [surfacePrimary.opacity(0.24), surfacePrimary.opacity(0.96)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                    .ignoresSafeArea(edges: .bottom)
                )
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { onDismiss() } label: {
                        Image(systemName: "chevron.left")
                    }
                    .foregroundStyle(textPrimary)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
                let endFrame = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect) ?? .zero
                let visibleHeight = max(0, UIScreen.main.bounds.maxY - endFrame.minY)
                isServingKeyboardVisible = visibleHeight > 20
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                isServingKeyboardVisible = false
            }
            .onAppear {
                isServingKeyboardVisible = false
                isServingAmountFieldFocused = false
                initializeState()
            }
            .onDisappear {
                isServingKeyboardVisible = false
            }
            .onChange(of: selectedMultiplierValue) { _, _ in
                if !isServingAmountFieldFocused { syncAmountText() }
            }
            .onChange(of: selectedServingBaselineAmount) { _, _ in
                if !isServingAmountFieldFocused { syncAmountText() }
            }
            .onChange(of: selectedServingAmountText) { _, newValue in
                if isCountBased(item: item) {
                    applyTypedCountServing(newValue)
                } else {
                    applyTypedServing(text: newValue)
                }
            }
            .interactiveDismissDisabled(isServingKeyboardVisible)
        }
    }

    private var sliderServingControl: some View {
        VStack(alignment: .leading, spacing: 14) {
            let minAmt = formattedServingAmount(selectedServingBaselineAmount * minMultiplier)
            let maxAmt = formattedServingAmount(selectedServingBaselineAmount * maxMultiplier)
            let displayUnit = isGramUnit(item.servingUnit) ? "g" : item.servingUnit
            let minUnit = inflectServingUnitToken(displayUnit, quantity: selectedServingBaselineAmount * minMultiplier)
            let maxUnit = inflectServingUnitToken(displayUnit, quantity: selectedServingBaselineAmount * maxMultiplier)
            HStack {
                Text("\(minAmt) \(minUnit)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(textSecondary)
                Spacer()
                Text("\(maxAmt) \(maxUnit)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(textSecondary)
            }

            HorizontalServeSlider(
                value: $selectedMultiplierValue,
                range: minMultiplier...maxMultiplier,
                step: multiplierStep
            ) {
                Haptics.selection()
            }
            .frame(height: 52)

            VStack(alignment: .leading, spacing: 8) {
                Text("Serve")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(textSecondary)

                TextField("", text: $selectedServingAmountText)
                    .keyboardType(.decimalPad)
                    .focused($isServingAmountFieldFocused)
                    .padding(.trailing, 52)
                    .inputStyle(surface: surfaceSecondary, text: textPrimary, secondary: textSecondary)
                    .overlay(alignment: .trailing) {
                        Text(inflectedTextFieldUnit(for: item.servingUnit, amountText: selectedServingAmountText))
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(textSecondary)
                            .padding(.trailing, 14)
                            .allowsHitTesting(false)
                    }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(surfacePrimary.opacity(0.94))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(textSecondary.opacity(0.12), lineWidth: 1)
            )
        }
    }

    private var countServingControl: some View {
        let quantity = max(roundToServingSelectorIncrement(selectedServingBaselineAmount * selectedMultiplierValue), 0.25)
        let unit = inflectCountUnitToken(item.servingUnit, quantity: quantity)
        return VStack(alignment: .leading, spacing: 10) {
            Text("Quantity")
                .font(.caption.weight(.semibold))
                .foregroundStyle(textSecondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)

            HStack(spacing: 18) {
                Button {
                    setCountQuantity(nextDecrementCount(from: quantity))
                    Haptics.selection()
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.title2)
                }
                .foregroundStyle(quantity > 0.25 ? accent : textSecondary.opacity(0.5))
                .disabled(quantity <= 0.25)

                TextField("", text: $selectedServingAmountText)
                    .font(.headline.weight(.semibold))
                    .keyboardType(.decimalPad)
                    .focused($isServingAmountFieldFocused)
                    .multilineTextAlignment(.leading)
                    .frame(width: 102)
                    .padding(.leading, 10)
                    .padding(.vertical, 8)
                    .padding(.trailing, 56)
                    .foregroundStyle(textPrimary)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(surfacePrimary.opacity(0.95))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(textSecondary.opacity(0.18), lineWidth: 1)
                    )
                    .overlay(alignment: .trailing) {
                        Text(unit)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(textSecondary)
                            .padding(.trailing, 10)
                            .allowsHitTesting(false)
                    }

                Button {
                    setCountQuantity(nextIncrementCount(from: quantity))
                    Haptics.selection()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                }
                .foregroundStyle(accent)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(surfacePrimary.opacity(0.94))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(textSecondary.opacity(0.12), lineWidth: 1)
        )
    }

    private func initializeState() {
        let baseAmount = item.servingAmount
        if let savedBaseline = initialBaseline, let savedSlider = initialSlider {
            selectedServingBaselineAmount = max(roundToServingSelectorIncrement(savedBaseline), 0)
            selectedMultiplierValue = min(max(savedSlider, minMultiplier), maxMultiplier)
        } else {
            selectedServingBaselineAmount = max(roundToServingSelectorIncrement(baseAmount * initialMultiplier), 0)
            selectedMultiplierValue = 1.0
        }
        syncAmountText()
    }

    private func confirmServing() {
        let baseAmount = item.servingAmount
        let selectedAmount = roundToServingSelectorIncrement(selectedServingBaselineAmount * selectedMultiplierValue)
        let mult = baseAmount > 0 ? max(selectedAmount / baseAmount, 0) : 1.0
        let baseline = max(roundToServingSelectorIncrement(selectedServingBaselineAmount), 0)
        let slider = min(max(selectedMultiplierValue, minMultiplier), maxMultiplier)
        Haptics.notification(.success)
        onConfirm(mult, baseline, slider)
    }

    private func syncAmountText() {
        let amount = formattedServingAmount(selectedServingBaselineAmount * selectedMultiplierValue)
        if selectedServingAmountText != amount {
            isUpdatingServingTextFromSlider = true
            selectedServingAmountText = amount
        }
    }

    private func applyTypedServing(text: String) {
        if isUpdatingServingTextFromSlider { isUpdatingServingTextFromSlider = false; return }
        guard let typedAmount = parsedAmount(text), typedAmount >= 0 else { return }
        let rounded = roundToServingSelectorIncrement(typedAmount)
        let current = roundToServingSelectorIncrement(selectedServingBaselineAmount * selectedMultiplierValue)
        if abs(rounded - current) > 0.0005 {
            selectedServingBaselineAmount = rounded
            selectedMultiplierValue = 1.0
        }
    }

    private func applyTypedCountServing(_ text: String) {
        if isUpdatingServingTextFromSlider { isUpdatingServingTextFromSlider = false; return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        guard let parsed = Double(normalized), parsed >= 0.25 else { return }
        let rounded = roundToServingSelectorIncrement(parsed)
        let current = roundToServingSelectorIncrement(selectedServingBaselineAmount * selectedMultiplierValue)
        if abs(rounded - current) > 0.0005 { setCountQuantity(rounded) }
    }

    private func setCountQuantity(_ quantity: Double) {
        let clamped = min(max(roundToServingSelectorIncrement(quantity), 0.25), 99)
        selectedServingBaselineAmount = clamped
        selectedMultiplierValue = 1.0
        let amount = formattedServingAmount(clamped)
        if selectedServingAmountText != amount {
            isUpdatingServingTextFromSlider = true
            selectedServingAmountText = amount
        }
    }

    private func nextDecrementCount(from quantity: Double) -> Double {
        let n = min(max(roundToServingSelectorIncrement(quantity), 0.25), 99)
        return n > 1 ? max(1, n - 1) : max(0.25, n - 0.25)
    }

    private func nextIncrementCount(from quantity: Double) -> Double {
        let n = min(max(roundToServingSelectorIncrement(quantity), 0.25), 99)
        return n < 1 ? min(1, n + 0.25) : min(99, n + 1)
    }

    private func parsedAmount(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Double(trimmed.replacingOccurrences(of: ",", with: "."))
    }

    private func formattedServingAmount(_ amount: Double) -> String {
        formatServingSelectorAmount(amount)
    }

    private func formattedDisplayServingWithUnit(_ amount: Double, unit: String) -> String {
        let displayUnit = isGramUnit(unit) ? "g" : unit
        let unitText = inflectServingUnitToken(displayUnit, quantity: amount)
        return "\(formatServingSelectorAmount(amount)) \(unitText)"
    }

    private func inflectedTextFieldUnit(for unit: String, amountText: String) -> String {
        let displayUnit = isGramUnit(unit) ? "g" : unit
        guard let amount = parsedAmount(amountText) else { return displayUnit }
        return inflectServingUnitToken(displayUnit, quantity: amount)
    }

    private func isGramUnit(_ unit: String) -> Bool {
        let n = unit.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return n == "g" || n == "gram" || n == "grams" || n == "grms"
    }

    private func isCountBased(item: QuickAddFood) -> Bool {
        let unit = item.servingUnit.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if unit.contains("cup") || unit.contains("oz")
            || unit == "g" || unit == "gram" || unit == "grams" || unit == "grms"
            || unit.contains("tbsp") || unit.contains("tablespoon")
            || unit.contains("tsp") || unit.contains("teaspoon")
            || unit == "ml" || unit == "l" || unit == "lb" || unit == "lbs" {
            return false
        }

        if ["piece", "pieces", "slice", "slices", "nugget", "nuggets",
            "sandwich", "sandwiches", "burger", "burgers", "taco", "tacos",
            "burrito", "burritos", "wrap", "wraps",
            "quesadilla", "quesadillas"].contains(unit) { return true }

        if name.contains("nugget") || name.contains("quesadilla") { return true }
        if name.contains("cookie") || name.contains("chips") || name.hasSuffix(" chip") { return true }
        if name.contains("sandwich") || name.contains("burger") || name.contains("burrito")
            || name.contains("taco") || name.contains("wrap") { return true }

        let ambiguous: Set<String> = ["", "serving", "servings", "each", "ea", "item", "items", "portion", "portions"]
        if !ambiguous.contains(unit) {
            let letters = CharacterSet.letters
            let unitChars = CharacterSet(charactersIn: unit)
            if !unit.contains(" ") && !unit.isEmpty && letters.isSuperset(of: unitChars) { return true }
        }
        return false
    }
}
