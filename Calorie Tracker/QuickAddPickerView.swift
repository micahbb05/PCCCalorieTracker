import SwiftUI

struct QuickAddPickerView: View {
    let quickAddFoods: [QuickAddFood]
    let surfacePrimary: Color
    let surfaceSecondary: Color
    let textPrimary: Color
    let textSecondary: Color
    let accent: Color
    let onSelect: (QuickAddFood) -> Void
    let onClose: (() -> Void)?
    let showsStandaloneChrome: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filteredFoods: [QuickAddFood] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return quickAddFoods }
        return quickAddFoods.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
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
    }

    private var scrollContent: some View {
        ScrollView {
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

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Quick Add")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(textPrimary)
                        Text("Pick a saved food to add instantly.")
                            .font(.subheadline)
                            .foregroundStyle(textSecondary)
                    }
                }

                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(textSecondary)
                    TextField("Search quick add foods", text: $searchText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .foregroundStyle(textPrimary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .cardStyle(surface: surfacePrimary.opacity(0.95), stroke: textSecondary.opacity(0.15))

                if filteredFoods.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(quickAddFoods.isEmpty ? "No quick add foods yet." : "No quick add foods match your search.")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(textPrimary)
                        Text(quickAddFoods.isEmpty ? "Create them from Profile." : "Try a broader search term.")
                            .font(.subheadline)
                            .foregroundStyle(textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .cardStyle(surface: surfacePrimary.opacity(0.95), stroke: textSecondary.opacity(0.15))
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredFoods) { item in
                            Button {
                                onSelect(item)
                            } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(item.name)
                                            .font(.headline.weight(.semibold))
                                            .foregroundStyle(textPrimary)
                                        Text("\(item.calories) cal")
                                            .font(.caption)
                                            .foregroundStyle(textSecondary)
                                    }
                                    Spacer()
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
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, showsStandaloneChrome ? 18 : 8)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
    }
}
