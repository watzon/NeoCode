import SwiftUI

struct ComposerSuggestionPopover<Item: Identifiable, RowContent: View>: View where Item.ID: Hashable {
    let title: String
    let emptyMessage: String
    let items: [Item]
    let selectedIndex: Int
    let scrollTargetID: Item.ID?
    let onHoverIndex: (Int) -> Void
    let onSelect: (Item) -> Void
    @ViewBuilder let rowContent: (Item, Bool) -> RowContent

    private let cornerRadius: CGFloat = 20
    private let visibleRowLimit = 5
    private let estimatedRowHeight: CGFloat = 56
    private let rowSpacing: CGFloat = 4
    private let listVerticalPadding: CGFloat = 16

    var body: some View {
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.neoMonoSmall)
                    .foregroundStyle(NeoCodeTheme.textMuted)
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: rowSpacing) {
                        if items.isEmpty {
                            Text(emptyMessage)
                                .font(.neoBody)
                                .foregroundStyle(NeoCodeTheme.textMuted)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                        } else {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                rowContent(item, index == selectedIndex)
                                    .id(item.id)
                                    .contentShape(RoundedRectangle(cornerRadius: 14))
                                    .onHover { hovering in
                                        if hovering {
                                            onHoverIndex(index)
                                        }
                                    }
                                    .onTapGesture {
                                        onSelect(item)
                                    }
                            }
                        }
                    }
                    .padding(8)
                }
                .frame(height: listHeight)
                .clipped()
            }
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(NeoCodeTheme.panelRaised)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(NeoCodeTheme.lineStrong, lineWidth: 1)
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .shadow(color: NeoCodeTheme.canvas.opacity(0.34), radius: 24, x: 0, y: 12)
            .onChange(of: scrollTargetID) { _, _ in
                scrollSelectionIfNeeded(using: proxy)
            }
        }
    }

    private func scrollSelectionIfNeeded(using proxy: ScrollViewProxy) {
        guard let scrollTargetID,
              items.contains(where: { $0.id == scrollTargetID })
        else {
            return
        }

        withAnimation(.easeOut(duration: 0.12)) {
            proxy.scrollTo(scrollTargetID, anchor: .center)
        }
    }

    private var listHeight: CGFloat {
        let visibleCount = max(1, min(items.count, visibleRowLimit))
        let spacingTotal = CGFloat(max(visibleCount - 1, 0)) * rowSpacing
        return CGFloat(visibleCount) * estimatedRowHeight + spacingTotal + listVerticalPadding
    }
}

struct ComposerSlashCommandsPopover: View {
    let commands: [ComposerSlashCommand]
    let selectedIndex: Int
    let scrollTargetID: String?
    let onHoverIndex: (Int) -> Void
    let onSelect: (ComposerSlashCommand) -> Void
    @Environment(\.locale) private var locale

    var body: some View {
        ComposerSuggestionPopover(
            title: localized("Slash Commands", locale: locale),
            emptyMessage: localized("No matching slash commands.", locale: locale),
            items: commands,
            selectedIndex: selectedIndex,
            scrollTargetID: scrollTargetID,
            onHoverIndex: onHoverIndex,
            onSelect: onSelect
        ) { command, isSelected in
            ComposerSlashCommandRow(command: command, isSelected: isSelected)
        }
    }
}

struct ComposerFileMentionsPopover: View {
    let files: [ProjectFileSearchResult]
    let selectedIndex: Int
    let scrollTargetID: String?
    let onHoverIndex: (Int) -> Void
    let onSelect: (ProjectFileSearchResult) -> Void
    @Environment(\.locale) private var locale

    var body: some View {
        ComposerSuggestionPopover(
            title: localized("Files", locale: locale),
            emptyMessage: localized("No matching files.", locale: locale),
            items: files,
            selectedIndex: selectedIndex,
            scrollTargetID: scrollTargetID,
            onHoverIndex: onHoverIndex,
            onSelect: onSelect
        ) { file, isSelected in
            ComposerFileMentionRow(file: file, isSelected: isSelected)
        }
    }
}

private struct ComposerSlashCommandRow: View {
    let command: ComposerSlashCommand
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("/\(command.name)")
                        .font(.neoBody)
                        .foregroundStyle(NeoCodeTheme.textPrimary)

                    if let badgeTitle = command.badgeTitle {
                        Text(badgeTitle)
                            .font(.neoMonoSmall)
                            .foregroundStyle(NeoCodeTheme.textMuted)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(NeoCodeTheme.panelSoft)
                                    .overlay(
                                        Capsule()
                                            .stroke(NeoCodeTheme.line, lineWidth: 1)
                                    )
                            )
                    }
                }

                if let description = command.description {
                    Text(description)
                        .font(.neoMonoSmall)
                        .foregroundStyle(NeoCodeTheme.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 12)

            if command.title.caseInsensitiveCompare(command.name) != .orderedSame {
                Text(command.title)
                    .font(.neoMonoSmall)
                    .foregroundStyle(NeoCodeTheme.textMuted)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(ComposerSuggestionRowBackground(isSelected: isSelected))
    }
}

private struct ComposerFileMentionRow: View {
    let file: ProjectFileSearchResult
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(file.displayName)
                    .font(.neoBody)
                    .foregroundStyle(NeoCodeTheme.textPrimary)
                    .lineLimit(1)

                Text(file.relativePath)
                    .font(.neoMonoSmall)
                    .foregroundStyle(NeoCodeTheme.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            if let directoryPath {
                Text(directoryPath)
                    .font(.neoMonoSmall)
                    .foregroundStyle(NeoCodeTheme.textMuted)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(ComposerSuggestionRowBackground(isSelected: isSelected))
    }

    private var directoryPath: String? {
        file.directoryPath
    }
}

private struct ComposerSuggestionRowBackground: View {
    let isSelected: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(isSelected ? NeoCodeTheme.panelSoft : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? NeoCodeTheme.lineStrong : Color.clear, lineWidth: 1)
            )
    }
}
