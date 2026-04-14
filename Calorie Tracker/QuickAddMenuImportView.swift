import SwiftUI
import UIKit

struct QuickAddMenuImportView: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var menu: NutrisliceMenu
    let sourceTitle: String
    let mealTitle: String
    @Binding var isLoading: Bool
    @Binding var errorMessage: String?
    let surfacePrimary: Color
    let surfaceSecondary: Color
    let textPrimary: Color
    let textSecondary: Color
    let accent: Color
    let onRetry: () async -> Void
    let onSelect: (MenuItem) -> Void

    @State private var searchText = ""
    @State private var isRetrying = false
    @State private var expandedLineIDs: Set<String> = []
    @State private var isKeyboardVisible = false
    @FocusState private var isSearchFieldFocused: Bool

    private var filteredLines: [MenuLine] {
        guard !trimmedSearchText.isEmpty else { return menu.lines }
        return menu.lines.compactMap { line in
            let items = line.items.filter { $0.name.localizedCaseInsensitiveContains(trimmedSearchText) }
            guard !items.isEmpty else { return nil }
            return MenuLine(id: line.id, name: line.name, items: items)
        }
    }

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
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

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(alignment: .top, spacing: 14) {
                            Button {
                                dismiss()
                            } label: {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(textPrimary)
                                    .frame(width: 42, height: 42)
                                    .background(
                                        Circle()
                                            .fill(surfacePrimary.opacity(0.94))
                                    )
                                    .overlay(
                                        Circle()
                                            .stroke(textSecondary.opacity(0.16), lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Menu")
                                    .font(.system(size: 36, weight: .bold, design: .default))
                                    .foregroundStyle(textPrimary)
                                    .padding(.top, -4)

                                HStack(spacing: 6) {
                                    Text(mealTitle)
                                        .font(.caption.weight(.semibold))
                                }
                                .foregroundStyle(textPrimary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(.ultraThinMaterial)
                                )
                                .overlay(
                                    Capsule(style: .continuous)
                                        .stroke(textSecondary.opacity(0.16), lineWidth: 1)
                                )
                            }

                            Spacer()
                        }

                        Text(sourceTitle)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(textSecondary)

                        HStack(spacing: 10) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(textSecondary)
                            TextField(
                                "",
                                text: $searchText,
                                prompt: Text("Search menu")
                                    .foregroundStyle(textSecondary)
                            )
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .submitLabel(.done)
                                .focused($isSearchFieldFocused)
                                .onSubmit {
                                    isSearchFieldFocused = false
                                }
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

                        if isLoading {
                            statusCard(title: "Loading menu", message: "Pulling today's dining options.") {
                                ProgressView().tint(accent)
                            }
                        } else if let errorMessage {
                            statusCard(title: "Could not load menu", message: errorMessage) {
                                Button {
                                    Task {
                                        isRetrying = true
                                        await onRetry()
                                        isRetrying = false
                                    }
                                } label: {
                                    if isRetrying {
                                        ProgressView()
                                            .tint(.white)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 12)
                                    } else {
                                        Text("Retry")
                                            .font(.headline.weight(.semibold))
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 12)
                                    }
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.white)
                                .background(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(accent)
                                )
                            }
                        } else if !trimmedSearchText.isEmpty && filteredLines.isEmpty {
                            statusCard(title: "No results found", message: "Try a broader search term or check spelling.") {
                                EmptyView()
                            }
                        } else if filteredLines.isEmpty {
                            statusCard(title: "Menu not available yet", message: "Today's menu hasn't been published yet for this venue.") {
                                EmptyView()
                            }
                        } else if !trimmedSearchText.isEmpty {
                            searchResultsContent
                        } else {
                            LazyVStack(alignment: .leading, spacing: 18) {
                                ForEach(filteredLines) { line in
                                    lineCard(for: line)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 28)
                    .padding(.bottom, 32)
                }
                .scrollDismissesKeyboard(.immediately)
            }
            .onAppear {
                expandedLineIDs = []
            }
            .onChange(of: searchText) { _, newValue in
                if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    expandedLineIDs = []
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
            let endFrame = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect) ?? .zero
            let visibleHeight = max(0, UIScreen.main.bounds.maxY - endFrame.minY)
            isKeyboardVisible = visibleHeight > 20
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isKeyboardVisible = false
        }
        .onDisappear {
            isKeyboardVisible = false
        }
        .interactiveDismissDisabled(isKeyboardVisible)
    }

    private var searchResultsContent: some View {
        LazyVStack(alignment: .leading, spacing: 18) {
            ForEach(filteredLines) { line in
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        FoodLogIconView(
                            token: FoodIconMLMapper.icon(for: line.name),
                            accent: accent,
                            size: 30
                        )
                        .frame(width: 36, height: 36)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(line.name)
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(textPrimary)
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 4)
                    .padding(.top, 2)
                    .padding(.bottom, 8)

                    Divider()
                        .overlay(textSecondary.opacity(0.10))

                    VStack(spacing: 8) {
                        ForEach(line.items) { item in
                            selectableMenuItemRow(item)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                }
            }
        }
    }

    private func lineCard(for line: MenuLine) -> some View {
        let isExpanded = expandedLineIDs.contains(line.id)

        return VStack(spacing: 0) {
            Button {
                toggleLine(line.id)
            } label: {
                HStack(spacing: 12) {
                    FoodLogIconView(
                        token: FoodIconMLMapper.icon(for: line.name),
                        accent: accent,
                        size: 30
                    )
                    .frame(width: 36, height: 36)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(line.name)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(textPrimary)
                        Text("\(line.items.count) options")
                            .font(.caption)
                            .foregroundStyle(textSecondary)
                    }

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(textSecondary.opacity(0.95))
                }
                .padding(18)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
                    .overlay(textSecondary.opacity(0.10))
                    .padding(.horizontal, 18)

                VStack(spacing: 8) {
                    ForEach(line.items) { item in
                        selectableMenuItemRow(item)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 14)
            }
        }
        .cardStyle(surface: surfacePrimary.opacity(0.95), stroke: textSecondary.opacity(0.15))
    }

    private func selectableMenuItemRow(_ item: MenuItem) -> some View {
        Button {
            onSelect(item)
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(textPrimary)
                    Text("\(item.calories) cal • \(item.protein)g protein")
                        .font(.caption)
                        .foregroundStyle(textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white.opacity(0.96))
                        .frame(width: 26, height: 26)
                        .background(
                            Circle()
                                .fill(accent)
                        )
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .background(
                    Capsule(style: .continuous).fill(Color.white.opacity(0.04))
                )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(surfaceSecondary.opacity(0.92))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(textSecondary.opacity(0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func toggleLine(_ lineID: String) {
        if expandedLineIDs.contains(lineID) {
            expandedLineIDs.remove(lineID)
        } else {
            expandedLineIDs.insert(lineID)
        }
        Haptics.selection()
    }

    private func statusCard<Accessory: View>(title: String, message: String, @ViewBuilder accessory: () -> Accessory) -> some View {
        VStack(spacing: 16) {
            VStack(spacing: 6) {
                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(textPrimary)
                Text(message)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(textSecondary)
            }
            accessory()
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .cardStyle(surface: surfacePrimary.opacity(0.95), stroke: textSecondary.opacity(0.18))
    }
}
