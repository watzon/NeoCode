import SwiftUI

struct InlineStatusView: View {
    enum Tone {
        case neutral
        case warning
    }

    let text: String
    let tone: Tone

    var body: some View {
        Text(text)
            .font(.neoMonoSmall)
            .foregroundStyle(foreground)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(background)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(NeoCodeTheme.line, lineWidth: 1)
                    )
            )
    }

    private var foreground: Color {
        switch tone {
        case .neutral: NeoCodeTheme.textSecondary
        case .warning: NeoCodeTheme.warning
        }
    }

    private var background: Color {
        switch tone {
        case .neutral: NeoCodeTheme.panel
        case .warning: NeoCodeTheme.warning.opacity(0.12)
        }
    }
}

struct EmptyConversationView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.locale) private var locale

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 20) {
                DraftReactiveMetaballOrb(
                    size: 88,
                    text: store.draft,
                    renderScale: 1.0,
                    internalResolutionScale: 1.15,
                    animationInterval: 1.0 / 20.0
                )
                .frame(width: 106, height: 100)

                VStack(spacing: 10) {
                    Text(store.projects.isEmpty ? localized("Add your first project", locale: locale) : localized("Start a thread", locale: locale))
                        .font(.system(size: 22, weight: .semibold, design: .default))
                        .foregroundStyle(NeoCodeTheme.textPrimary)

                    Text(store.projects.isEmpty
                         ? localized("Use the project button in the Threads sidebar to add a folder. NeoCode will only show threads for projects you explicitly add.", locale: locale)
                         : localized("Create a new thread or select one from the sidebar to begin chatting with the NeoCode daemon.", locale: locale))
                        .font(.neoBody)
                        .foregroundStyle(NeoCodeTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

            WindowDragRegion()
                .frame(height: 52)
        }
    }
}

struct ErrorToast: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(NeoCodeTheme.warning)

            Text(message)
                .font(.neoBody)
                .foregroundStyle(NeoCodeTheme.textPrimary)
                .lineLimit(2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(NeoCodeTheme.panelRaised)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(NeoCodeTheme.warning.opacity(0.45), lineWidth: 1)
                )
        )
        .frame(maxWidth: 360, alignment: .trailing)
        .shadow(color: Color.black.opacity(0.25), radius: 18, x: 0, y: 6)
    }
}

struct StatusToast: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)

            Text(message)
                .font(.neoBody)
                .foregroundStyle(NeoCodeTheme.textPrimary)
                .lineLimit(2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(NeoCodeTheme.panelRaised)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(NeoCodeTheme.lineStrong.opacity(0.45), lineWidth: 1)
                )
        )
        .frame(maxWidth: 360, alignment: .trailing)
        .shadow(color: Color.black.opacity(0.25), radius: 18, x: 0, y: 6)
    }
}
