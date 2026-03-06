import SwiftUI

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

    private var filteredLines: [MenuLine] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return menu.lines }
        return menu.lines.compactMap { line in
            let items = line.items.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
            guard !items.isEmpty else { return nil }
            return MenuLine(id: line.id, name: line.name, items: items)
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

                ScrollView {
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
                            Text("PCC Menu")
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .foregroundStyle(textPrimary)
                            Text("\(sourceTitle) • \(mealTitle)")
                                .font(.subheadline)
                                .foregroundStyle(textSecondary)
                        }

                        HStack(spacing: 10) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(textSecondary)
                            TextField("Search menu", text: $searchText)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .foregroundStyle(textPrimary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .cardStyle(surface: surfacePrimary.opacity(0.95), stroke: textSecondary.opacity(0.15))

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
                        } else if filteredLines.isEmpty {
                            statusCard(title: "Menu not available yet", message: "Today's menu hasn't been published yet for this venue.") {
                                EmptyView()
                            }
                        } else {
                            LazyVStack(alignment: .leading, spacing: 14) {
                                ForEach(filteredLines) { line in
                                    lineCard(for: line)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                    .padding(.bottom, 32)
                }
            }
            .onAppear {
                expandedLineIDs = []
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
                        .font(.caption.weight(.bold))
                        .foregroundStyle(textSecondary)
                }
                .padding(18)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 10) {
                    ForEach(line.items) { item in
                        Button {
                            onSelect(item)
                            dismiss()
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.name)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(textPrimary)
                                    Text("\(item.calories) cal • \(item.protein)g protein")
                                        .font(.caption)
                                        .foregroundStyle(textSecondary)
                                }
                                Spacer()
                            }
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(surfaceSecondary.opacity(0.92))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(textSecondary.opacity(0.10), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 18)
            }
        }
        .cardStyle(surface: surfacePrimary.opacity(0.95), stroke: textSecondary.opacity(0.15))
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
        .cardStyle(surface: surfacePrimary.opacity(0.95), stroke: textSecondary.opacity(0.15))
    }
}
