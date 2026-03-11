import SwiftUI

struct QuickAddManagerView: View {
    private struct EditorContext: Identifiable {
        let id = UUID()
        let item: QuickAddFood?
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
    @State private var searchText = ""
    @State private var editorContext: EditorContext?

    private var filteredFoods: [QuickAddFood] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return quickAddFoods }
        return quickAddFoods.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
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
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Manage quick add foods")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
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
                    .cardStyle(surface: surfacePrimary.opacity(0.95), stroke: textSecondary.opacity(0.15))

                    if filteredFoods.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(quickAddFoods.isEmpty ? "No quick add foods yet." : "No quick add foods match your search.")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(textPrimary)
                            Text(quickAddFoods.isEmpty ? "Create foods you use often and add them in one tap." : "Try a broader search term.")
                                .font(.subheadline)
                                .foregroundStyle(textSecondary)
                        }
                        .padding(18)
                        .cardStyle(surface: surfacePrimary.opacity(0.95), stroke: textSecondary.opacity(0.15))
                    } else {
                        List {
                            ForEach(filteredFoods) { item in
                                quickAddRow(item)
                                    .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(Color.clear)
                            }
                        }
                        .listStyle(.plain)
                        .scrollIndicators(.hidden)
                        .scrollContentBackground(.hidden)
                        .contentMargins(.bottom, 12, for: .scrollContent)
                        .background(Color.clear)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 12)
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
                    quickAddFoods.sort { $0.createdAt > $1.createdAt }
                }
            }
        }
    }

    private func quickAddRow(_ item: QuickAddFood) -> some View {
        Button {
            editorContext = EditorContext(item: item)
            Haptics.selection()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.name)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(textPrimary)
                    Text("\(item.calories) cal • \(servingSummary(for: item))" + quickAddSummary(for: item))
                        .font(.caption)
                        .foregroundStyle(textSecondary)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(textSecondary)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(surfacePrimary.opacity(0.95))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(textSecondary.opacity(0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                deleteQuickAddFood(item)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .contextMenu {
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

    private func quickAddSummary(for item: QuickAddFood) -> String {
        let summary = item.nutrientValues
            .filter { $0.value > 0 }
            .sorted { lhs, rhs in
                let lhsRank = NutrientCatalog.preferredOrder.firstIndex(of: lhs.key) ?? Int.max
                let rhsRank = NutrientCatalog.preferredOrder.firstIndex(of: rhs.key) ?? Int.max
                return lhsRank < rhsRank
            }
            .prefix(2)
            .map { nutrient in
                let definition = NutrientCatalog.definition(for: nutrient.key)
                return "\(nutrient.value)\(definition.unit) \(definition.name)"
            }
            .joined(separator: " • ")

        return summary.isEmpty ? "" : " • \(summary)"
    }

    private func servingSummary(for item: QuickAddFood) -> String {
        let amount = formatServingSelectorAmount(item.servingAmount)
        let unit = inflectServingUnitToken(item.servingUnit, quantity: item.servingAmount)
        return "\(amount) \(unit)"
    }

    private func deleteQuickAddFood(_ item: QuickAddFood) {
        quickAddFoods.removeAll { $0.id == item.id }
        Haptics.selection()
    }
}
