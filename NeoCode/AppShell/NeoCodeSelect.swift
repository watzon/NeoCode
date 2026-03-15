import SwiftUI

struct NeoCodeSelect<Item: Identifiable, RowContent: View>: View where Item.ID: Hashable {
    let title: String
    let selectedID: Item.ID?
    let items: [Item]
    let emptyMessage: String
    let placeholder: String
    let isSearchable: Bool
    let direction: FloatingPanelDirection
    let menuWidth: CGFloat
    let menuMaxHeight: CGFloat
    @ViewBuilder let rowContent: (Item) -> RowContent
    let searchableText: (Item) -> [String]
    let onSelect: (Item) -> Void
    let footer: (() -> AnyView)?

    @State private var isPresented = false
    @State private var query = ""
    @FocusState private var isSearchFieldFocused: Bool

    private let rowSpacing: CGFloat = 2
    private let estimatedRowHeight: CGFloat = 38
    private let minimumListHeight: CGFloat = 44

    init(
        title: String,
        selectedID: Item.ID? = nil,
        items: [Item],
        emptyMessage: String,
        placeholder: String,
        isSearchable: Bool,
        direction: FloatingPanelDirection = .down,
        menuWidth: CGFloat = 280,
        menuMaxHeight: CGFloat = 260,
        @ViewBuilder rowContent: @escaping (Item) -> RowContent,
        searchableText: @escaping (Item) -> [String],
        onSelect: @escaping (Item) -> Void,
        footer: (() -> AnyView)? = nil
    ) {
        self.title = title
        self.selectedID = selectedID
        self.items = items
        self.emptyMessage = emptyMessage
        self.placeholder = placeholder
        self.isSearchable = isSearchable
        self.direction = direction
        self.menuWidth = menuWidth
        self.menuMaxHeight = menuMaxHeight
        self.rowContent = rowContent
        self.searchableText = searchableText
        self.onSelect = onSelect
        self.footer = footer
    }

    var body: some View {
        Button(action: toggleMenu) {
            NeoCodeDropdownTriggerLabel(title: title, isPresented: isPresented)
        }
        .buttonStyle(.plain)
        .background {
            AnchoredFloatingPanelPresenter(isPresented: isPresented, direction: direction, onDismiss: closeMenu) {
                panelContent
            }
        }
        .zIndex(isPresented ? 10 : 0)
        .onChange(of: isPresented) { _, newValue in
            guard newValue else {
                query = ""
                isSearchFieldFocused = false
                return
            }

            guard isSearchable else { return }
            DispatchQueue.main.async {
                isSearchFieldFocused = true
            }
        }
    }

    private var panelContent: some View {
        DropdownMenuSurface(width: menuWidth) {
            VStack(alignment: .leading, spacing: 10) {
                if isSearchable {
                    TextField(placeholder, text: $query)
                        .textFieldStyle(.plain)
                        .font(.neoBody)
                        .foregroundStyle(NeoCodeTheme.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(NeoCodeTheme.panelSoft)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(NeoCodeTheme.line, lineWidth: 1)
                                )
                        )
                        .focused($isSearchFieldFocused)
                }

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: rowSpacing) {
                        if filteredItems.isEmpty {
                            Text(emptyMessage)
                                .font(.neoBody)
                                .foregroundStyle(NeoCodeTheme.textMuted)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 10)
                        } else {
                            ForEach(filteredItems) { item in
                                DropdownMenuRow(isSelected: selectedID == item.id, action: {
                                    onSelect(item)
                                    closeMenu()
                                }) {
                                    rowContent(item)
                                }
                            }
                        }
                    }
                }
                .frame(height: listHeight)

                if let footer {
                    footer()
                }
            }
            .padding(4)
        }
    }

    private var filteredItems: [Item] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return items }

        return items.filter { item in
            searchableText(item).contains { value in
                value.localizedCaseInsensitiveContains(trimmed)
            }
        }
    }

    private var listHeight: CGFloat {
        let visibleCount = max(filteredItems.isEmpty ? 1 : filteredItems.count, 1)
        let estimatedHeight = CGFloat(visibleCount) * estimatedRowHeight
        let spacingHeight = CGFloat(max(visibleCount - 1, 0)) * rowSpacing
        return min(max(minimumListHeight, estimatedHeight + spacingHeight), menuMaxHeight)
    }

    private func toggleMenu() {
        isPresented.toggle()
    }

    private func closeMenu() {
        isPresented = false
        query = ""
        isSearchFieldFocused = false
    }
}
