import SwiftUI

private struct BottomCTAHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct MenuSheetView: View {
    private struct MultiplierSheetContext: Identifiable {
        let id = UUID()
        let item: MenuItem
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let menu: NutrisliceMenu
    let venue: DiningVenue
    let sourceTitle: String
    let mealTitle: String
    let selectedMenuType: NutrisliceMenuService.MenuType
    let availableMenuTypes: [NutrisliceMenuService.MenuType]
    let trackedNutrientKeys: [String]
    @Binding var selectedItemQuantities: [String: Int]
    @Binding var selectedItemMultipliers: [String: Double]
    let isLoading: Bool
    let errorMessage: String?
    let onRetry: () async -> Void
    let onAddSelected: () -> Void
    let onPhotoPlate: (([MenuItem], Data) -> Void)?
    @Binding var plateEstimateItems: [MenuItem]?
    @Binding var plateEstimateOzByItemId: [String: Double]
    let plateEstimateBaseOzByItemId: [String: Double]
    let mealGroup: MealGroup
    let onPlateEstimateConfirm: ([(MenuItem, oz: Double, baseOz: Double)]) -> Void
    let onPlateEstimateDismiss: () -> Void
    let onVenueChange: (DiningVenue) -> Void
    let onMenuTypeChange: (NutrisliceMenuService.MenuType) -> Void
    let onClose: (() -> Void)?
    let bottomOverlayClearance: CGFloat
    let onRequestExternalAIPopup: (() -> Void)?
    let requestedExternalAIPickerSource: PlateImagePickerView.Source?
    let clearRequestedExternalAIPickerSource: () -> Void

    @State private var isRetrying = false
    @State private var showImagePickerSource = false
    @State private var requestedImagePickerSource: PlateImagePickerView.Source?
    @State private var expandedLineIDs: Set<String> = []
    @State private var searchText = ""
    @State private var multiplierSheetContext: MultiplierSheetContext?
    @State private var selectedMultiplierValue = 1.0
    @State private var bottomCTAHeight: CGFloat = 0
    @FocusState private var isSearchFieldFocused: Bool
    private let minMultiplier = 0.25
    private let maxMultiplier = 2.0
    private let multiplierStep = 0.25
    private let minimumBottomLineClearance: CGFloat = 96

    private var surfacePrimary: Color {
        colorScheme == .dark ? Color(red: 0.13, green: 0.15, blue: 0.20) : Color.white
    }

    private var surfaceSecondary: Color {
        colorScheme == .dark ? Color(red: 0.17, green: 0.19, blue: 0.25) : Color(red: 0.97, green: 0.98, blue: 1.00)
    }

    private var textPrimary: Color {
        colorScheme == .dark ? Color(red: 0.95, green: 0.96, blue: 0.98) : Color(red: 0.12, green: 0.14, blue: 0.18)
    }

    private var textSecondary: Color {
        colorScheme == .dark ? Color(red: 0.78, green: 0.81, blue: 0.86) : Color(red: 0.43, green: 0.47, blue: 0.54)
    }

    private var accent: Color { AppTheme.accent }

    private var backgroundTop: Color {
        colorScheme == .dark ? Color(red: 0.07, green: 0.08, blue: 0.12) : Color(red: 0.95, green: 0.97, blue: 0.99)
    }

    private var backgroundBottom: Color {
        colorScheme == .dark ? Color(red: 0.10, green: 0.11, blue: 0.17) : Color(red: 0.91, green: 0.94, blue: 0.98)
    }

    private var scrollContentBottomPadding: CGFloat {
        if onClose == nil {
            return bottomOverlayClearance + 24
        }
        return bottomCTAHeight + minimumBottomLineClearance
    }

    private var selectedCount: Int {
        selectedItemQuantities.values.reduce(0, +)
    }

    private var isSelectionActionEnabled: Bool {
        selectedCount > 0 && !isLoading && errorMessage == nil
    }

    private var selectedMenuItems: [MenuItem] {
        let ids = Set(selectedItemQuantities.filter { $0.value > 0 }.map(\.key))
        let allSelected = menu.lines.flatMap(\.items).filter { ids.contains($0.id) }

        // Only one card per food name on the plate estimate screen.
        var seenNames = Set<String>()
        return allSelected.filter { item in
            let key = item.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if seenNames.contains(key) { return false }
            seenNames.insert(key)
            return true
        }
    }

    private var filteredLines: [MenuLine] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return menu.lines
        }

        return menu.lines.compactMap { line in
            let items = line.items.filter { item in
                item.name.localizedCaseInsensitiveContains(trimmed)
            }
            guard !items.isEmpty else {
                return nil
            }
            return MenuLine(id: line.id, name: line.name, items: items)
        }
    }

    var body: some View {
        ZStack {
            ZStack {
                LinearGradient(
                    colors: [backgroundTop, backgroundBottom],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        venuePicker
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 28)

                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 18) {
                                searchCard
                                content
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, scrollContentBottomPadding)
                        }
                        .accessibilityIdentifier("pccMenu.scrollView")
                        .scrollBounceBehavior(.basedOnSize)
                        .scrollIndicators(.hidden)
                        .scrollDismissesKeyboard(.immediately)
                        .ignoresSafeArea(.keyboard, edges: .bottom)
                    }
                }
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .overlay(alignment: .bottom) {
                bottomCTA
            }
            .overlay {
                if showImagePickerSource && onRequestExternalAIPopup == nil {
                    Color.black.opacity(0.28)
                        .ignoresSafeArea()
                }
            }
            .allowsHitTesting(!showImagePickerSource)
        }
        .overlay {
            if showImagePickerSource && onRequestExternalAIPopup == nil {
                aiPortionDialog
            }
        }
        .onChange(of: requestedExternalAIPickerSource) { _, newValue in
            guard let newValue else { return }
            requestedImagePickerSource = newValue
            clearRequestedExternalAIPickerSource()
        }
        .sheet(item: $multiplierSheetContext, onDismiss: {
            multiplierSheetContext = nil
        }) { context in
            multiplierSheet(item: context.item)
        }
        .fullScreenCover(item: $requestedImagePickerSource) { source in
            PlateImagePickerView(source: source, onPicked: { data in
                requestedImagePickerSource = nil
                let items = selectedMenuItems
                if !items.isEmpty {
                    onPhotoPlate?(items, data)
                }
            }, onCancel: {
                requestedImagePickerSource = nil
            })
        }
        .fullScreenCover(isPresented: Binding(
            get: { plateEstimateItems != nil },
            set: { if !$0 { onPlateEstimateDismiss() } }
        )) {
            if let items = plateEstimateItems {
                PlateEstimateResultView(
                    items: items,
                    ozByItemId: $plateEstimateOzByItemId,
                    baseOzByItemId: plateEstimateBaseOzByItemId,
                    mealGroup: mealGroup,
                    onConfirm: onPlateEstimateConfirm,
                    onDismiss: onPlateEstimateDismiss
                )
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            statusCard(
                systemImage: "fork.knife.circle",
                title: "Loading menu",
                message: "Pulling today's dining options and nutrition data."
            ) {
                ProgressView()
                    .tint(accent)
            }
        } else if let errorMessage {
            statusCard(
                systemImage: "exclamationmark.triangle.fill",
                title: "Could not load menu",
                message: errorMessage
            ) {
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
                            .padding(.vertical, 14)
                    } else {
                        Text("Retry")
                            .font(.headline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(accent)
                )
                .disabled(isRetrying)
            }
        } else if filteredLines.isEmpty {
            statusCard(
                systemImage: searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "fork.knife" : "magnifyingglass",
                title: searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No menu items available" : "No matches found",
                message: searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Today's menu has not been published yet." : "Try a broader search term."
            )
        } else if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            searchResultsContent
        } else {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(filteredLines) { line in
                    lineCard(for: line)
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            if let onClose {
                Button {
                    Haptics.selection()
                    onClose()
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
            } else {
                EmptyView()
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Menu")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(textPrimary)
                    .padding(.top, -4)
                Menu {
                    ForEach(availableMenuTypes, id: \.self) { menuType in
                        Button {
                            guard menuType != selectedMenuType else { return }
                            Haptics.selection()
                            onMenuTypeChange(menuType)
                        } label: {
                            if menuType == selectedMenuType {
                                Label(menuType.title, systemImage: "checkmark")
                            } else {
                                Text(menuType.title)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(mealTitle)
                            .font(.caption.weight(.semibold))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
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
                .buttonStyle(.plain)
            }

            Spacer()

            if onClose == nil {
                HStack(spacing: 10) {
                    if onPhotoPlate != nil && venue != .grabNGo {
                        compactAIButton
                    }

                    compactAddSelectedButton
                }
            } else {
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(selectedCount)")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(textPrimary)
                        .monospacedDigit()
                    Text("selected")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(textSecondary)
                }
            }
        }
    }

    private var venuePicker: some View {
        HStack(spacing: 8) {
            ForEach(DiningVenue.allCases) { v in
                let isSelected = v == venue
                Button {
                    if !isSelected {
                        Haptics.selection()
                        onVenueChange(v)
                    }
                } label: {
                    Text(v.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .foregroundStyle(isSelected ? .white : textSecondary)
                .background(
                    Capsule(style: .continuous)
                        .fill(isSelected ? accent : surfacePrimary.opacity(0.6))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(isSelected ? Color.clear : textSecondary.opacity(0.2), lineWidth: 1)
                )
            }
        }
    }

    private var searchCard: some View {
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
            .frame(maxWidth: .infinity)
            .frame(height: 22)
            .accessibilityIdentifier("pccMenu.searchField")

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    Haptics.selection()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("pccMenu.clearSearchButton")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .cardStyle(surface: surfacePrimary.opacity(0.95), stroke: textSecondary.opacity(0.15))
        .accessibilityIdentifier("pccMenu.searchCard")
    }

    private var searchResultsContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(filteredLines) { line in
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(line.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(textPrimary)
                            Text("\(line.items.count) result\(line.items.count == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundStyle(textSecondary)
                        }

                        Spacer()
                    }

                    VStack(spacing: 10) {
                        if venue == .grabNGo {
                            grabNGoSelectAllRow(for: line)
                        }
                        ForEach(line.items) { item in
                            menuItemRow(item)
                        }
                    }
                }
                .padding(16)
                .cardStyle(surface: surfacePrimary.opacity(0.95), stroke: textSecondary.opacity(0.15))
            }
        }
        .accessibilityIdentifier("pccMenu.searchResults")
    }

    private func lineCard(for line: MenuLine) -> some View {
        let expanded = isLineExpandedBinding(for: line.id)

        return VStack(spacing: 0) {
            Button {
                expanded.wrappedValue.toggle()
                Haptics.selection()
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

                    Text("\(line.items.count)")
                        .font(.caption.monospacedDigit().weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule(style: .continuous)
                                .fill(accent.opacity(0.95))
                        )

                    Image(systemName: expanded.wrappedValue ? "chevron.up" : "chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(textSecondary)
                }
                .padding(18)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("pccMenu.line.\(line.id)")

            if expanded.wrappedValue {
                Divider()
                    .overlay(textSecondary.opacity(0.10))
                    .padding(.horizontal, 18)

                VStack(spacing: 10) {
                    if venue == .grabNGo {
                        grabNGoSelectAllRow(for: line)
                    }
                    ForEach(line.items) { item in
                        menuItemRow(item)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 14)
                .id("pccMenu.lineContent.\(line.id)")
                .accessibilityIdentifier("pccMenu.lineContent.\(line.id)")
            }
        }
        .cardStyle(surface: surfacePrimary.opacity(0.95), stroke: textSecondary.opacity(0.15))
    }

    private func grabNGoSelectAllRow(for line: MenuLine) -> some View {
        let allSelected = areAllItemsSelected(in: line)

        return Button {
            selectAllItems(in: line)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: allSelected ? "checkmark.circle.fill" : "checkmark.circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(allSelected ? accent : textSecondary)

                VStack(alignment: .leading, spacing: 3) {
                    Text(allSelected ? "All items selected" : "Select all")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(textPrimary)
                    Text("\(line.items.count) item\(line.items.count == 1 ? "" : "s") in this section")
                        .font(.caption)
                        .foregroundStyle(textSecondary)
                }

                Spacer()

                Text(allSelected ? "Done" : "Add All")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule(style: .continuous)
                            .fill(accent.opacity(0.12))
                    )
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(surfaceSecondary.opacity(0.82))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(textSecondary.opacity(0.10), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(allSelected)
    }

    private func statusCard<Accessory: View>(systemImage: String, title: String, message: String, @ViewBuilder accessory: () -> Accessory) -> some View {
        VStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(systemImage.contains("exclamationmark") ? Color.orange : accent)

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

    private func statusCard(systemImage: String, title: String, message: String) -> some View {
        statusCard(systemImage: systemImage, title: title, message: message) {
            EmptyView()
        }
    }

    private var bottomCTA: some View {
        guard onClose != nil else {
            return AnyView(EmptyView())
        }

        return AnyView(VStack(spacing: 0) {
            GeometryReader { geo in
                let spacing: CGFloat = 12
                let aiButtonWidth: CGFloat = 56
                HStack(spacing: spacing) {
                    Button {
                    dismissKeyboard()
                    guard selectedCount > 0 else {
                        Haptics.notification(.warning)
                        return
                    }
                    Haptics.impact(.medium)
                    onAddSelected()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Add Selected")
                                .font(.headline.weight(.semibold))
                            Text("\(selectedCount) item\(selectedCount == 1 ? "" : "s") ready")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.78))
                        }

                        Spacer()

                        Text("\(selectedCount)")
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(.white.opacity(0.14))
                            )
                    }
                    .foregroundStyle(.white)
                    .frame(height: 52)
                    .padding(.horizontal, 18)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(isSelectionActionEnabled ? accent : surfaceSecondary.opacity(0.98))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(
                                isSelectionActionEnabled ? accent.opacity(0.0) : textSecondary.opacity(0.18),
                                lineWidth: 1
                            )
                    )
                }
                .buttonStyle(.plain)
                .disabled(!isSelectionActionEnabled)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("pccMenu.addSelectedButton")
                .transaction { txn in
                    txn.animation = nil
                }

                    // Show AI plate photo capture only for Four Winds and Varsity, not Grab N Go. Placed to the right of Add Selected.
                    if onPhotoPlate != nil && venue != .grabNGo {
                        Button {
                            dismissKeyboard()
                            guard selectedCount > 0 else {
                                Haptics.notification(.warning)
                                return
                            }
                            Haptics.impact(.light)
                            if let onRequestExternalAIPopup {
                                onRequestExternalAIPopup()
                            } else {
                                showImagePickerSource = true
                            }
                        } label: {
                            Image(systemName: "sparkles")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(isSelectionActionEnabled ? .white : textSecondary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(
                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                        .fill(isSelectionActionEnabled ? accent : surfaceSecondary.opacity(0.98))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                        .stroke(
                                            isSelectionActionEnabled ? Color.clear : textSecondary.opacity(0.18),
                                            lineWidth: 1
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(!isSelectionActionEnabled)
                        .frame(width: aiButtonWidth)
                        .transaction { txn in
                            txn.animation = nil
                        }
                    }
                }
            }
            .frame(height: 60)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(
            GeometryReader { geo in
                Color.clear
                    .preference(key: BottomCTAHeightPreferenceKey.self, value: geo.size.height)
            }
        )
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
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onPreferenceChange(BottomCTAHeightPreferenceKey.self) { height in
            bottomCTAHeight = height
        }
        .accessibilityIdentifier("pccMenu.bottomCTA"))
    }

    private var compactAddSelectedButton: some View {
        Button {
            dismissKeyboard()
            guard selectedCount > 0 else {
                Haptics.notification(.warning)
                return
            }
            Haptics.impact(.medium)
            onAddSelected()
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
        .disabled(!isSelectionActionEnabled)
        .transaction { txn in
            txn.animation = nil
        }
    }

    private var compactAIButton: some View {
        Button {
            dismissKeyboard()
            guard selectedCount > 0 else {
                Haptics.notification(.warning)
                return
            }
            Haptics.impact(.light)
            if let onRequestExternalAIPopup {
                onRequestExternalAIPopup()
            } else {
                showImagePickerSource = true
            }
        } label: {
            Image(systemName: "sparkles")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isSelectionActionEnabled ? .white : textSecondary)
                .frame(width: 40, height: 40)
                .background(
                    Circle()
                        .fill(isSelectionActionEnabled ? accent : surfaceSecondary.opacity(0.98))
                )
                .overlay(
                    Circle()
                        .stroke(
                            isSelectionActionEnabled ? Color.clear : textSecondary.opacity(0.18),
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
        .disabled(!isSelectionActionEnabled)
        .transaction { txn in
            txn.animation = nil
        }
    }

    private var aiPortionDialog: some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .ignoresSafeArea()
                .onTapGesture {
                    showImagePickerSource = false
                }

            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("AI portion estimation")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(textPrimary)
                    Text("Add a plate photo from camera or library.")
                        .font(.body)
                        .foregroundStyle(textSecondary)
                }

                VStack(spacing: 12) {
                    aiPortionDialogButton(title: "Use camera") {
                        showImagePickerSource = false
                        requestedImagePickerSource = .camera
                    }

                    aiPortionDialogButton(title: "Choose from library") {
                        showImagePickerSource = false
                        requestedImagePickerSource = .photoLibrary
                    }
                }
            }
            .padding(22)
            .frame(maxWidth: 340)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(surfacePrimary.opacity(0.98))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(textSecondary.opacity(0.14), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.22), radius: 24, y: 10)
            .padding(.horizontal, 24)
        }
    }

    private func aiPortionDialogButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    Capsule(style: .continuous)
                        .fill(surfaceSecondary.opacity(0.96))
                )
        }
        .buttonStyle(.plain)
    }

    private func quantity(for id: String) -> Int {
        selectedItemQuantities[id] ?? 0
    }

    private func multiplier(for id: String) -> Double {
        selectedItemMultipliers[id] ?? 1.0
    }

    private func increment(_ id: String) {
        selectedItemQuantities[id] = quantity(for: id) + 1
        Haptics.selection()
    }

    private func decrement(_ id: String) {
        let next = quantity(for: id) - 1
        if next <= 0 {
            var updatedQuantities = selectedItemQuantities
            var updatedMultipliers = selectedItemMultipliers
            updatedQuantities.removeValue(forKey: id)
            updatedMultipliers.removeValue(forKey: id)
            selectedItemQuantities = updatedQuantities
            selectedItemMultipliers = updatedMultipliers
        } else {
            selectedItemQuantities[id] = next
        }
        Haptics.selection()
    }

    private func openMultiplierSheet(for item: MenuItem) {
        selectedMultiplierValue = snappedMultiplier(multiplier(for: item.id))
        dismissKeyboard()
        multiplierSheetContext = nil
        Haptics.impact(.light)
        DispatchQueue.main.async {
            multiplierSheetContext = MultiplierSheetContext(item: item)
        }
    }

    private func applySelectedMultiplier() {
        guard let item = multiplierSheetContext?.item else { return }
        selectedItemMultipliers[item.id] = snappedMultiplier(selectedMultiplierValue)
        if quantity(for: item.id) == 0 {
            selectedItemQuantities[item.id] = 1
        }
        Haptics.notification(.success)
        multiplierSheetContext = nil
    }

    private func areAllItemsSelected(in line: MenuLine) -> Bool {
        !line.items.isEmpty && line.items.allSatisfy { quantity(for: $0.id) > 0 }
    }

    private func selectAllItems(in line: MenuLine) {
        var changed = false

        for item in line.items where quantity(for: item.id) == 0 {
            selectedItemQuantities[item.id] = 1
            if selectedItemMultipliers[item.id] == nil {
                selectedItemMultipliers[item.id] = 1.0
            }
            changed = true
        }

        if changed {
            Haptics.notification(.success)
        } else {
            Haptics.selection()
        }
    }

    private func isLineExpandedBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: {
                return expandedLineIDs.contains(id)
            },
            set: { expanded in
                if expanded {
                    expandedLineIDs.insert(id)
                } else {
                    expandedLineIDs.remove(id)
                }
            }
        )
    }

    private func menuItemRow(_ item: MenuItem) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(textPrimary)
                HStack(spacing: 6) {
                    Text("\(item.calories) cal • \(item.protein)g protein")
                    if multiplier(for: item.id) != 1 {
                        Text("\(formattedDisplayServingAmount(item.servingAmount * multiplier(for: item.id), unit: item.servingUnit)) \(displayServingUnit(for: item.servingUnit)) (\(multiplier(for: item.id), specifier: "%.2f")x)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.cyan)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule(style: .continuous).fill(.cyan.opacity(0.14))
                            )
                    }
                }
                .font(.caption)
                .foregroundStyle(textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                openMultiplierSheet(for: item)
            }

            Spacer()
            HStack(spacing: 10) {
                Button {
                    decrement(item.id)
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white.opacity(quantity(for: item.id) > 0 ? 0.92 : 0.35))
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(Color.white.opacity(quantity(for: item.id) > 0 ? 0.10 : 0.05))
                        )
                }
                .buttonStyle(.plain)
                .disabled(quantity(for: item.id) == 0)

                Text("\(quantity(for: item.id))")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .frame(minWidth: 28)
                    .foregroundStyle(textPrimary)

                Button {
                    increment(item.id)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white.opacity(0.96))
                        .frame(width: 28, height: 28)
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
                Capsule(style: .continuous).fill(Color.white.opacity(0.05))
            )
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
        .accessibilityIdentifier("pccMenu.item.\(item.id)")
    }

    private func multiplierSheet(item: MenuItem) -> some View {
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
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundStyle(textPrimary)
                                .lineLimit(3)
                                .fixedSize(horizontal: false, vertical: true)

                            Text("Base serve: \(formattedDisplayServingAmount(item.servingAmount, unit: item.servingUnit)) \(displayServingUnit(for: item.servingUnit))")
                                .font(.subheadline)
                                .foregroundStyle(textSecondary)
                        }

                        HStack(alignment: .center, spacing: 22) {
                            VerticalServeSlider(
                                value: $selectedMultiplierValue,
                                range: minMultiplier...maxMultiplier,
                                step: multiplierStep
                            ) {
                                Haptics.selection()
                            }
                            .frame(width: 104, height: 336)

                            VStack(alignment: .leading, spacing: 14) {
                                multiplierStatCard(
                                    title: "Serve",
                                    value: "\(formattedDisplayServingAmount(item.servingAmount * selectedMultiplierValue, unit: item.servingUnit)) \(displayServingUnit(for: item.servingUnit))"
                                )

                                multiplierStatCard(
                                    title: "Multiplier",
                                    value: String(format: "%.2fx", selectedMultiplierValue)
                                )

                                Text("Move up for more, down for less")
                                    .font(.caption)
                                    .foregroundStyle(textSecondary)
                                    .padding(.top, 2)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        ServingNutrientGridCard(
                            title: "Nutrients Per Selected Serving",
                            calories: item.calories,
                            nutrientValues: item.nutrientValues,
                            multiplier: selectedMultiplierValue,
                            trackedNutrientKeys: trackedNutrientKeys,
                            displayedNutrientKeys: nil,
                            surface: surfacePrimary.opacity(0.95),
                            stroke: textSecondary.opacity(0.15),
                            titleColor: textPrimary,
                            labelColor: textSecondary,
                            valueColor: textPrimary
                        )
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 120)
                }
                .scrollIndicators(.hidden)
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    applySelectedMultiplier()
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
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        multiplierSheetContext = nil
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .foregroundStyle(textPrimary)
                }
            }
        }
    }

    private func multiplierStatCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(textSecondary)
            Text(value)
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(textPrimary)
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

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func snappedMultiplier(_ value: Double) -> Double {
        let clamped = min(max(value, minMultiplier), maxMultiplier)
        let steps = (clamped / multiplierStep).rounded()
        return min(max(steps * multiplierStep, minMultiplier), maxMultiplier)
    }

    private func formattedServingAmount(_ amount: Double) -> String {
        if abs(amount.rounded() - amount) < 0.001 {
            return String(format: "%.0f", amount)
        }
        if abs((amount * 10).rounded() - (amount * 10)) < 0.001 {
            return String(format: "%.1f", amount)
        }
        return String(format: "%.2f", amount)
    }

    private func formattedDisplayServingAmount(_ amount: Double, unit: String) -> String {
        formattedServingAmount(convertedServingAmount(amount, unit: unit))
    }

    private func displayServingUnit(for unit: String) -> String {
        isGramUnit(unit) ? "oz" : unit
    }

    private func convertedServingAmount(_ amount: Double, unit: String) -> Double {
        if isGramUnit(unit) {
            return amount / 28.3495
        }
        return amount
    }

    private func isGramUnit(_ unit: String) -> Bool {
        let normalized = unit.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "g" || normalized == "gram" || normalized == "grams"
    }
}
