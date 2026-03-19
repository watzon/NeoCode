import SwiftUI

struct ComposerTodoBadgeButton: View {
    @Environment(\.locale) private var locale

    let count: Int
    @Binding var isPresented: Bool

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(alignment: .center, spacing: 6) {
                Image(systemName: "checklist")
                    .font(.system(size: 11, weight: .semibold))

                Text(String(count))
                    .font(.neoMonoSmall)
                    .monospacedDigit()
            }
            .foregroundStyle(isPresented ? NeoCodeTheme.textPrimary : NeoCodeTheme.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isPresented ? NeoCodeTheme.panelSoft : NeoCodeTheme.panelRaised)
                    .overlay(
                        Capsule()
                            .stroke(isPresented ? NeoCodeTheme.lineStrong : NeoCodeTheme.line, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .neoTooltip(localized("Show To-Dos", locale: locale))
        .accessibilityLabel(
            String(format: localized("Show %@ remaining To-Dos", locale: locale), String(count))
        )
    }
}

struct ComposerTodoPanel: View {
    @Environment(\.locale) private var locale

    let items: [SessionTodoItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "checklist")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(NeoCodeTheme.accent)

                Text(localized("To-Dos", locale: locale))
                    .font(.neoMonoSmall)
                    .foregroundStyle(NeoCodeTheme.textSecondary)

                Spacer(minLength: 0)

                Text(String(items.filter(\.status.isActive).count))
                    .font(.neoMonoSmall)
                    .foregroundStyle(NeoCodeTheme.textMuted)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider()

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { entry in
                    ComposerTodoPanelRow(item: entry.element)

                    if entry.offset < items.count - 1 {
                        Divider()
                            .padding(.leading, 36)
                    }
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(NeoCodeTheme.panelRaised)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(NeoCodeTheme.line, lineWidth: 1)
                )
        )
        .shadow(color: NeoCodeTheme.canvas.opacity(0.14), radius: 12, x: 0, y: 8)
    }
}

private struct ComposerTodoPanelRow: View {
    @Environment(\.locale) private var locale

    let item: SessionTodoItem

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: statusSymbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(statusTint)
                .frame(width: 12, height: 12)
                .padding(.top, 3)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.content)
                    .font(.neoBody)
                    .foregroundStyle(item.status.isActive ? NeoCodeTheme.textPrimary : NeoCodeTheme.textMuted)
                    .strikethrough(!item.status.isActive, color: NeoCodeTheme.textMuted.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)

                if let priorityText {
                    Text(priorityText)
                        .font(.neoMonoSmall)
                        .foregroundStyle(priorityTint)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var priorityText: String? {
        guard let priority = item.priority else { return nil }
        switch priority {
        case .high:
            return localized("High priority", locale: locale)
        case .medium:
            return localized("Medium priority", locale: locale)
        case .low:
            return localized("Low priority", locale: locale)
        }
    }

    private var statusSymbol: String {
        switch item.status {
        case .pending:
            return "circle.dotted"
        case .inProgress:
            return "arrow.trianglehead.2.clockwise"
        case .completed:
            return "checkmark.circle.fill"
        case .cancelled:
            return "xmark.circle.fill"
        }
    }

    private var statusTint: Color {
        switch item.status {
        case .pending:
            return NeoCodeTheme.warning
        case .inProgress:
            return NeoCodeTheme.accent
        case .completed:
            return NeoCodeTheme.success
        case .cancelled:
            return NeoCodeTheme.textMuted
        }
    }

    private var priorityTint: Color {
        switch item.priority {
        case .high:
            return NeoCodeTheme.warning
        case .medium:
            return NeoCodeTheme.accent
        case .low:
            return NeoCodeTheme.textMuted
        case nil:
            return NeoCodeTheme.textMuted
        }
    }
}
