import SwiftUI

struct DropdownMenuSurface<Content: View>: View {
    let width: CGFloat
    @ViewBuilder let content: () -> Content

    init(width: CGFloat = 220, @ViewBuilder content: @escaping () -> Content) {
        self.width = width
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            content()
        }
        .padding(8)
        .frame(width: width, alignment: .leading)
        .background(NeoCodeTheme.panelRaised)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(NeoCodeTheme.lineStrong, lineWidth: 1)
        )
        .shadow(color: NeoCodeTheme.canvas.opacity(0.34), radius: 18, x: 0, y: 10)
    }
}

struct DropdownMenuRow<Content: View>: View {
    @State private var isHovering = false

    let isSelected: Bool
    let isDisabled: Bool
    let action: () -> Void
    @ViewBuilder let content: () -> Content

    init(
        isSelected: Bool = false,
        isDisabled: Bool = false,
        action: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.isSelected = isSelected
        self.isDisabled = isDisabled
        self.action = action
        self.content = content
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                content()

                Spacer(minLength: 8)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(NeoCodeTheme.accent)
                }
            }
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isHovering ? NeoCodeTheme.panelSoft : .clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .onHover { isHovering = $0 }
    }

    private var foregroundColor: Color {
        isDisabled ? NeoCodeTheme.textMuted : NeoCodeTheme.textPrimary
    }
}

struct NeoCodeDropdownTriggerLabel<Leading: View>: View {
    let title: String
    let isPresented: Bool
    @ViewBuilder let leading: () -> Leading

    init(
        title: String,
        isPresented: Bool,
        @ViewBuilder leading: @escaping () -> Leading
    ) {
        self.title = title
        self.isPresented = isPresented
        self.leading = leading
    }

    var body: some View {
        HStack(spacing: 8) {
            leading()

            Text(title)
                .font(.neoAction)
                .foregroundStyle(NeoCodeTheme.textPrimary)
                .lineLimit(1)

            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(NeoCodeTheme.textSecondary)
                .rotationEffect(.degrees(isPresented ? 180 : 0))
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isPresented ? NeoCodeTheme.panelSoft : NeoCodeTheme.panelRaised)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(isPresented ? NeoCodeTheme.lineStrong : NeoCodeTheme.line, lineWidth: 1)
                )
        )
        .animation(.easeOut(duration: 0.16), value: isPresented)
    }
}

extension NeoCodeDropdownTriggerLabel where Leading == EmptyView {
    init(title: String, isPresented: Bool) {
        self.init(title: title, isPresented: isPresented) {
            EmptyView()
        }
    }
}

struct NeoCodeMenuButton<Label: View, MenuContent: View>: View {
    let direction: FloatingPanelDirection
    @ViewBuilder let label: (Bool) -> Label
    let menuContent: (@escaping () -> Void) -> MenuContent

    @State private var isPresented = false

    init(
        direction: FloatingPanelDirection = .down,
        @ViewBuilder label: @escaping (Bool) -> Label,
        @ViewBuilder menuContent: @escaping (@escaping () -> Void) -> MenuContent
    ) {
        self.direction = direction
        self.label = label
        self.menuContent = menuContent
    }

    var body: some View {
        Button(action: toggleMenu) {
            label(isPresented)
        }
        .buttonStyle(.plain)
        .background {
            AnchoredFloatingPanelPresenter(
                isPresented: isPresented,
                direction: direction,
                onDismiss: closeMenu
            ) {
                menuContent(closeMenu)
            }
        }
        .zIndex(isPresented ? 10 : 0)
    }

    private func toggleMenu() {
        isPresented.toggle()
    }

    private func closeMenu() {
        isPresented = false
    }
}
