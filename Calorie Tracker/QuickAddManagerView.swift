import SwiftUI
import UIKit

struct QuickAddManagerView: View {
    private struct EditorContext: Identifiable {
        let id = UUID()
        let item: QuickAddFood?
    }

    private struct QuickAddSectionGroup: Identifiable {
        let section: QuickAddSectionClassifier.Section
        let items: [QuickAddFood]

        var id: String { section.rawValue }
    }

    @Binding var quickAddFoods: [QuickAddFood]
    let trackedNutrientKeys: [String]
    let storedVenueMenus: [DiningVenue: [NutrisliceMenuService.MenuType: NutrisliceMenu]]
    let surfacePrimary: Color
    let surfaceSecondary: Color
    let textPrimary: Color
    let textSecondary: Color
    let accent: Color

    @Environment(\.dismiss) private var dismiss
    @AppStorage("quickAddSectionOverridesData") private var sectionOverridesData: String = ""
    @State private var searchText = ""
    @State private var editorContext: EditorContext?
    @State private var isReordering = false
    @State private var isSearchKeyboardVisible = false
    @State private var sectionOverridesByID: [UUID: QuickAddSectionClassifier.Section] = [:]
    @State private var effectiveSectionByID: [UUID: QuickAddSectionClassifier.Section] = [:]

    private var filteredFoods: [QuickAddFood] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return quickAddFoods }
        return quickAddFoods.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }

    private var groupedSections: [QuickAddSectionGroup] {
        var grouped: [QuickAddSectionClassifier.Section: [QuickAddFood]] = [:]
        for item in filteredFoods {
            let section = section(for: item)
            grouped[section, default: []].append(item)
        }

        return QuickAddSectionClassifier.Section.allCases.compactMap { section in
            let items = grouped[section, default: []]
            guard !items.isEmpty else { return nil }
            return QuickAddSectionGroup(section: section, items: items)
        }
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

                // One scroll surface: header + rows + empty state all move together (List swipe still works).
                List {
                    Group {
                        VStack(alignment: .leading, spacing: 18) {
                            HStack {
                                Button {
                                    dismiss()
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "chevron.left")
                                            .font(.caption.weight(.bold))
                                        Text("Close")
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

                                if !groupedSections.isEmpty {
                                    Button {
                                        isReordering.toggle()
                                        Haptics.selection()
                                    } label: {
                                        Text(isReordering ? "Done" : "Reorder")
                                            .font(.subheadline.weight(.semibold))
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
                                }
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Manage Quick Add Foods")
                                    .font(.system(size: 32, weight: .bold, design: .default))
                                    .foregroundStyle(textPrimary)
                                Text("Create and edit reusable foods.")
                                    .font(.subheadline)
                                    .foregroundStyle(textSecondary)
                            }

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
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)

                    if filteredFoods.isEmpty {
                        Group {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(quickAddFoods.isEmpty ? "No quick add foods yet." : "No quick add foods match your search.")
                                    .font(.headline.weight(.semibold))
                                    .foregroundStyle(textPrimary)
                                Text(quickAddFoods.isEmpty ? "Create foods you use often and add them in one tap." : "Try a broader search term.")
                                    .font(.subheadline)
                                    .foregroundStyle(textSecondary)
                            }
                            .padding(18)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .cardStyle(surface: surfacePrimary.opacity(0.95), stroke: textSecondary.opacity(0.18))
                        }
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 12, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    } else {
                        ForEach(groupedSections) { group in
                            Section {
                                ForEach(group.items) { item in
                                    quickAddRow(item)
                                        .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16))
                                        .listRowSeparator(.hidden)
                                        .listRowBackground(Color.clear)
                                }
                                .onMove { source, destination in
                                    moveItems(in: group.section, from: source, to: destination)
                                }
                                .moveDisabled(!isReordering || !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            } header: {
                                HStack(spacing: 8) {
                                    Text(group.section.title)
                                        .font(.headline.weight(.semibold))
                                        .foregroundStyle(textPrimary)
                                    Text("\(group.items.count)")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(textSecondary)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(
                                            Capsule(style: .continuous)
                                                .fill(surfaceSecondary.opacity(0.9))
                                        )
                                }
                                .textCase(nil)
                                .padding(.top, 2)
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .listSectionSpacing(4)
                .scrollDismissesKeyboard(.interactively)
                .scrollIndicators(.hidden)
                .scrollContentBackground(.hidden)
                .contentMargins(.bottom, 12, for: .scrollContent)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .environment(\.editMode, .constant(isReordering ? .active : .inactive))
                .onAppear {
                    loadSectionOverrides()
                    pruneSectionOverrides()
                    refreshEffectiveSections()
                }
                .onChange(of: quickAddFoods) { _, _ in
                    pruneSectionOverrides()
                    refreshEffectiveSections()
                }
                .onChange(of: sectionOverridesByID) { _, _ in
                    refreshEffectiveSections()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in
                    isSearchKeyboardVisible = true
                }
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                    isSearchKeyboardVisible = false
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    editorContext = EditorContext(item: nil)
                    Haptics.impact(.light)
                } label: {
                    Text("New Quick Add Food")
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
            .sheet(item: $editorContext) { context in
                QuickAddEditorView(
                    item: context.item,
                    trackedNutrientKeys: trackedNutrientKeys,
                    storedVenueMenus: storedVenueMenus,
                    surfacePrimary: surfacePrimary,
                    surfaceSecondary: surfaceSecondary,
                    textPrimary: textPrimary,
                    textSecondary: textSecondary,
                    accent: accent
                ) { savedItem in
                    if let index = quickAddFoods.firstIndex(where: { $0.id == savedItem.id }) {
                        quickAddFoods[index] = savedItem
                    } else {
                        quickAddFoods.insert(savedItem, at: 0)
                    }
                    pruneSectionOverrides()
                }
            }
        }
        .interactiveDismissDisabled(isSearchKeyboardVisible)
    }

    private func quickAddRow(_ item: QuickAddFood) -> some View {
        Group {
            if isReordering {
                quickAddRowContent(item)
            } else {
                Button {
                    editorContext = EditorContext(item: item)
                    Haptics.selection()
                } label: {
                    quickAddRowContent(item)
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        deleteQuickAddFood(item)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .tint(.red)
                }
                .contextMenu {
                    let destinations = destinationSections(for: item)
                    if !destinations.isEmpty {
                        Menu("Move To Section") {
                            ForEach(destinations, id: \.self) { section in
                                Button(section.title) {
                                    assign(item: item, to: section)
                                }
                            }
                        }
                    }
                    Button {
                        editorContext = EditorContext(item: item)
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        deleteQuickAddFood(item)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
    }

    private func quickAddRowContent(_ item: QuickAddFood) -> some View {
            HStack(alignment: .center, spacing: 10) {
                FoodLogIconView(token: FoodIconMLMapper.icon(for: item.name), accent: accent, size: 26)
                    .frame(width: 26, height: 26, alignment: .center)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(textPrimary)
                }
                Spacer()
                if isReordering {
                    let destinations = destinationSections(for: item)
                    Menu {
                        ForEach(destinations, id: \.self) { section in
                            Button(section.title) {
                                assign(item: item, to: section)
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.left.arrow.right.circle")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(textSecondary)
                    }
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(textSecondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(surfacePrimary.opacity(0.95))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(textSecondary.opacity(0.12), lineWidth: 1)
            )
    }

    private func deleteQuickAddFood(_ item: QuickAddFood) {
        quickAddFoods.removeAll { $0.id == item.id }
        sectionOverridesByID.removeValue(forKey: item.id)
        saveSectionOverrides()
        Haptics.selection()
    }

    private func moveItems(in sourceSection: QuickAddSectionClassifier.Section, from source: IndexSet, to destination: Int) {
        let allInSection = quickAddFoods.filter { section(for: $0) == sourceSection }
        guard !allInSection.isEmpty else { return }

        var movedInSection = allInSection
        movedInSection.move(fromOffsets: source, toOffset: destination)
        let movedIDs = Set(movedInSection.map { $0.id })

        var rebuilt: [QuickAddFood] = []
        rebuilt.reserveCapacity(quickAddFoods.count)

        var sectionIterator = movedInSection.makeIterator()
        for item in quickAddFoods {
            if movedIDs.contains(item.id) {
                if let next = sectionIterator.next() {
                    rebuilt.append(next)
                }
            } else {
                rebuilt.append(item)
            }
        }

        withAnimation(.easeInOut(duration: 0.18)) {
            quickAddFoods = rebuilt
        }
        Haptics.selection()
    }

    private func assign(item: QuickAddFood, to targetSection: QuickAddSectionClassifier.Section) {
        let currentSection = section(for: item)
        guard currentSection != targetSection else { return }

        let predictedSection = QuickAddSectionClassifier.shared.classify(item)
        var updatedOverrides = sectionOverridesByID
        if predictedSection == targetSection {
            updatedOverrides.removeValue(forKey: item.id)
        } else {
            updatedOverrides[item.id] = targetSection
        }

        let reordered = reorderItemsAfterCategoryChange(
            movingItemID: item.id,
            targetSection: targetSection,
            overrides: updatedOverrides
        )

        withAnimation(.easeInOut(duration: 0.2)) {
            sectionOverridesByID = updatedOverrides
            quickAddFoods = reordered
            effectiveSectionByID = computeEffectiveSections(for: reordered, overrides: updatedOverrides)
        }
        saveSectionOverrides()
        Haptics.selection()
    }

    private func section(for item: QuickAddFood) -> QuickAddSectionClassifier.Section {
        if let resolved = effectiveSectionByID[item.id] {
            return resolved
        }
        return sectionOverridesByID[item.id] ?? QuickAddSectionClassifier.shared.classify(item)
    }

    private func loadSectionOverrides() {
        guard let data = sectionOverridesData.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            sectionOverridesByID = [:]
            return
        }
        var mapped: [UUID: QuickAddSectionClassifier.Section] = [:]
        for (idString, sectionRaw) in decoded {
            guard let id = UUID(uuidString: idString),
                  let section = QuickAddSectionClassifier.Section(rawValue: sectionRaw) else { continue }
            mapped[id] = section
        }
        sectionOverridesByID = mapped
    }

    private func saveSectionOverrides() {
        let payload = sectionOverridesByID.reduce(into: [String: String]()) { partialResult, entry in
            partialResult[entry.key.uuidString] = entry.value.rawValue
        }
        guard let data = try? JSONEncoder().encode(payload) else { return }
        sectionOverridesData = String(decoding: data, as: UTF8.self)
    }

    private func pruneSectionOverrides() {
        let validIDs = Set(quickAddFoods.map(\.id))
        let pruned = sectionOverridesByID.filter { validIDs.contains($0.key) }
        if pruned != sectionOverridesByID {
            sectionOverridesByID = pruned
            saveSectionOverrides()
        }
    }

    private func refreshEffectiveSections() {
        effectiveSectionByID = computeEffectiveSections(for: quickAddFoods, overrides: sectionOverridesByID)
    }

    private func computeEffectiveSections(
        for foods: [QuickAddFood],
        overrides: [UUID: QuickAddSectionClassifier.Section]
    ) -> [UUID: QuickAddSectionClassifier.Section] {
        var map: [UUID: QuickAddSectionClassifier.Section] = [:]
        map.reserveCapacity(foods.count)
        for item in foods {
            if let overridden = overrides[item.id] {
                map[item.id] = overridden
            } else {
                map[item.id] = QuickAddSectionClassifier.shared.classify(item)
            }
        }
        return map
    }

    private func destinationSections(for item: QuickAddFood) -> [QuickAddSectionClassifier.Section] {
        let current = section(for: item)
        return QuickAddSectionClassifier.Section.allCases.filter { $0 != current }
    }

    private func reorderItemsAfterCategoryChange(
        movingItemID: UUID,
        targetSection: QuickAddSectionClassifier.Section,
        overrides: [UUID: QuickAddSectionClassifier.Section]
    ) -> [QuickAddFood] {
        guard let fromIndex = quickAddFoods.firstIndex(where: { $0.id == movingItemID }) else {
            return quickAddFoods
        }
        var updated = quickAddFoods
        let movingItem = updated.remove(at: fromIndex)

        func resolvedSection(for item: QuickAddFood) -> QuickAddSectionClassifier.Section {
            if let override = overrides[item.id] {
                return override
            }
            if let cached = effectiveSectionByID[item.id] {
                return cached
            }
            return QuickAddSectionClassifier.shared.classify(item)
        }

        if let lastTargetIndex = updated.lastIndex(where: { resolvedSection(for: $0) == targetSection }) {
            updated.insert(movingItem, at: lastTargetIndex + 1)
            return updated
        }

        let allSections = QuickAddSectionClassifier.Section.allCases
        let targetRank = allSections.firstIndex(of: targetSection) ?? allSections.count
        let boundary = updated.firstIndex {
            let rank = allSections.firstIndex(of: resolvedSection(for: $0)) ?? allSections.count
            return rank > targetRank
        } ?? updated.endIndex
        updated.insert(movingItem, at: boundary)
        return updated
    }
}
