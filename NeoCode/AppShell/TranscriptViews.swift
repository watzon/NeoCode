import Foundation
import SwiftUI

enum DisplayMessageGroup: Identifiable, Hashable {
    case message(ChatMessage)
    case userTurn([ChatMessage])
    case assistantTurn([ChatMessage])

    var id: String {
        switch self {
        case .message(let message):
            return message.id
        case .userTurn(let messages), .assistantTurn(let messages):
            return messages.map(\.id).joined(separator: "-")
        }
    }
}

struct UserTurnView: View {
    private let attachmentThumbnailWidth: CGFloat = 220
    private let attachmentGridSpacing: CGFloat = 12
    private let attachmentGridMaxWidth: CGFloat = 680

    let sessionID: String
    let messages: [ChatMessage]
    @Binding var editingText: String
    let editingMessageID: String?
    let onBeginEdit: (ChatMessage) -> Void
    let onCancelEdit: () -> Void
    let onFinishEdit: () -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            MessageMetadataHeaderView(
                roleLabel: "user",
                timestamp: messages.first?.timestamp,
                roleColor: NeoCodeTheme.textSecondary,
                isTrailingAligned: true
            )

            VStack(alignment: .trailing, spacing: 10) {
                if !attachmentMessages.isEmpty {
                    // A single image should sit flush right like the user's text
                    // bubble. Once there are multiple attachments, switch to a
                    // fixed-width wrapping grid so rows grow like a flex-wrap layout.
                    if attachmentMessages.count == 1,
                       let attachment = attachmentMessages.first?.attachment {
                        AttachmentMessageView(
                            attachment: attachment,
                            isUser: true,
                            imageWidth: attachmentThumbnailWidth
                        )
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    } else {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: attachmentThumbnailWidth, maximum: attachmentThumbnailWidth), spacing: attachmentGridSpacing)],
                            alignment: .trailing,
                            spacing: attachmentGridSpacing
                        ) {
                            ForEach(attachmentMessages) { message in
                                if let attachment = message.attachment {
                                    AttachmentMessageView(
                                        attachment: attachment,
                                        isUser: true,
                                        imageWidth: attachmentThumbnailWidth
                                    )
                                }
                            }
                        }
                        .frame(maxWidth: attachmentGridMaxWidth, alignment: .trailing)
                    }
                }

                ForEach(textMessages) { message in
                    MessageRowView(
                        sessionID: sessionID,
                        message: message,
                        editingText: $editingText,
                        isEditing: editingMessageID == message.id,
                        showsMetadataHeader: false,
                        onBeginEdit: {
                            onBeginEdit(message)
                        },
                        onCancelEdit: onCancelEdit,
                        onFinishEdit: onFinishEdit
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var attachmentMessages: [ChatMessage] {
        messages.filter { $0.attachment != nil }
    }

    private var textMessages: [ChatMessage] {
        messages.filter { $0.attachment == nil }
    }
}

struct AssistantTurnView: View {
    let messages: [ChatMessage]
    private let contentWidth = ConversationLayout.assistantContentWidth

    var body: some View {
        let turnBlocks = blocks

        VStack(alignment: .leading, spacing: 10) {
            MessageMetadataHeaderView(
                roleLabel: "assistant",
                timestamp: messages.first?.timestamp,
                roleColor: NeoCodeTheme.accent,
                isTrailingAligned: false
            )

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(turnBlocks.enumerated()), id: \.element.id) { index, block in
                    VStack(alignment: .leading, spacing: 0) {
                        switch block {
                        case .thinking(let message):
                            ThinkingRowView(message: message, showsLabel: showsThinkingLabel(at: index, in: turnBlocks))
                        case .toolCluster(let toolMessages):
                            ToolCallClusterRowView(messages: toolMessages, contentWidth: contentWidth)
                        case .output(let message):
                            AssistantOutputView(message: message)
                        }
                    }
                    .padding(.top, topSpacing(at: index, in: turnBlocks))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var blocks: [AssistantTurnBlock] {
        var result: [AssistantTurnBlock] = []
        var currentTools: [ChatMessage] = []

        func flushTools() {
            guard !currentTools.isEmpty else { return }
            result.append(.toolCluster(currentTools))
            currentTools.removeAll(keepingCapacity: true)
        }

        for message in messages {
            if message.role == .tool {
                currentTools.append(message)
                continue
            }

            flushTools()

            if message.emphasis == .strong {
                result.append(.thinking(message))
            } else {
                result.append(.output(message))
            }
        }

        flushTools()
        return result
    }

    private func topSpacing(at index: Int, in blocks: [AssistantTurnBlock]) -> CGFloat {
        guard index > 0 else { return 0 }
        let block = blocks[index]
        let previous = blocks[index - 1]

        if previous.isCompactSibling(of: block) {
            return 8
        }

        return 18
    }

    private func showsThinkingLabel(at index: Int, in blocks: [AssistantTurnBlock]) -> Bool {
        guard case .thinking = blocks[index] else { return false }
        guard index > 0 else { return true }

        if case .thinking = blocks[index - 1] {
            return false
        }

        return true
    }
}

private struct MessageMetadataHeaderView: View {
    let roleLabel: String
    let timestamp: Date?
    let roleColor: Color
    let isTrailingAligned: Bool

    var body: some View {
        HStack(spacing: 10) {
            if isTrailingAligned {
                Spacer(minLength: 0)
            }

            if isTrailingAligned {
                timestampView
                divider
                roleView
            } else {
                roleView
                divider
                timestampView
            }
        }
        .frame(maxWidth: .infinity, alignment: isTrailingAligned ? .trailing : .leading)
    }

    @ViewBuilder
    private var timestampView: some View {
        if let timestamp {
            Text(timestamp, style: .time)
                .font(.neoMonoSmall)
                .foregroundStyle(NeoCodeTheme.textMuted)
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(NeoCodeTheme.lineSoft)
            .frame(width: 20, height: 1)
    }

    private var roleView: some View {
        Text(roleLabel)
            .font(.neoMonoSmall)
            .foregroundStyle(roleColor)
    }
}

enum AssistantTurnBlock: Identifiable, Hashable {
    case thinking(ChatMessage)
    case toolCluster([ChatMessage])
    case output(ChatMessage)

    var id: String {
        switch self {
        case .thinking(let message), .output(let message):
            return message.id
        case .toolCluster(let messages):
            return messages.map(\.id).joined(separator: "-")
        }
    }

    func isCompactSibling(of other: AssistantTurnBlock) -> Bool {
        switch (self, other) {
        case (.thinking, .thinking), (.toolCluster, .toolCluster):
            return true
        default:
            return false
        }
    }
}

struct ToolCallRowView: View {
    let contentWidth: CGFloat
    let toolCall: ChatMessage.ToolCall
    let presentation: ToolCallPresentation

    init(message: ChatMessage, contentWidth: CGFloat) {
        self.contentWidth = contentWidth
        let resolvedToolCall: ChatMessage.ToolCall
        if let toolCall = message.kind.toolCall {
            resolvedToolCall = toolCall
        } else {
            resolvedToolCall = ChatMessage.ToolCall(name: "tool", status: .running, detail: message.text)
        }
        self.toolCall = resolvedToolCall
        self.presentation = ToolCallPresentation(toolCall: resolvedToolCall)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(presentation.items) { item in
                ToolCallItemCardView(item: item, toolStatus: toolCall.status, contentWidth: contentWidth)
            }
        }
    }

}

struct ToolCallClusterRowView: View {
    let messages: [ChatMessage]
    let contentWidth: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(messages) { message in
                ToolCallRowView(message: message, contentWidth: contentWidth)
            }
        }
    }
}

struct MessageRowView: View {
    @Environment(AppStore.self) private var store
    @Environment(OpenCodeRuntime.self) private var runtime
    @State private var isHovering = false
    @State private var isHoveringActions = false
    @State private var didCopy = false
    @State private var editorHeight: CGFloat = 36

    let sessionID: String
    let message: ChatMessage
    @Binding var editingText: String
    let isEditing: Bool
    let showsMetadataHeader: Bool
    let onBeginEdit: () -> Void
    let onCancelEdit: () -> Void
    let onFinishEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsMetadataHeader, message.role != .tool {
                MessageMetadataHeaderView(
                    roleLabel: roleLabel,
                    timestamp: message.timestamp,
                    roleColor: roleColor,
                    isTrailingAligned: message.role == .user
                )
            }

            if message.role == .tool {
                EmptyView()
            } else if isThinking {
                ThinkingRowView(message: message)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if let attachment = message.attachment {
                AttachmentMessageView(attachment: attachment, isUser: message.role == .user)
                    .frame(maxWidth: .infinity, alignment: alignment)
            } else if message.role == .user {
                userMessageBody
            } else {
                MarkdownMessageView(
                    markdown: message.text,
                    baseFont: message.role == .assistant ? .neoBody : .neoMono,
                    textColor: textColor
                )
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, message.role == .assistant ? 0 : 14)
                    .padding(.vertical, message.role == .assistant ? 0 : 12)
                    .background(bubbleBackground)
                    .frame(maxWidth: .infinity, alignment: alignment)
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment)
    }

    private var userMessageBody: some View {
        VStack(alignment: .trailing, spacing: 10) {
            if isEditing {
                InlineMessageEditor(
                    text: $editingText,
                    measuredHeight: $editorHeight,
                    isSending: store.isSending,
                    onCancel: onCancelEdit,
                    onSubmit: resendEditedMessage
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                MarkdownMessageView(markdown: message.text, baseFont: .neoMono, textColor: textColor)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(bubbleBackground)
                    .overlay(alignment: .bottomTrailing) {
                        if isHovering || isHoveringActions || didCopy {
                            HStack(spacing: 6) {
                                MessageHoverActionButton(systemImage: "pencil", isDisabled: !canEditMessage) {
                                    onBeginEdit()
                                }

                                MessageHoverActionButton(systemImage: didCopy ? "checkmark" : "doc.on.doc") {
                                    copyMessageText()
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(Color.clear)
                            .contentShape(Rectangle())
                            .onHover { isHoveringActions = $0 }
                            .offset(x: 6, y: 36)
                            .transition(.scale(scale: 0.9).combined(with: .opacity))
                        }
                    }
            }
        }
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.16), value: isHovering)
        .animation(.easeOut(duration: 0.16), value: didCopy)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var alignment: Alignment {
        message.role == .user ? .trailing : .leading
    }

    private var isThinking: Bool {
        message.role == .assistant && message.emphasis == .strong
    }

    private var roleLabel: String {
        switch message.role {
        case .user: "user"
        case .assistant: "assistant"
        case .tool: "tool"
        case .system: "system"
        }
    }

    private var roleColor: Color {
        switch message.role {
        case .user: NeoCodeTheme.textSecondary
        case .assistant: NeoCodeTheme.accent
        case .tool: NeoCodeTheme.success
        case .system: NeoCodeTheme.textMuted
        }
    }

    private var backgroundColor: Color {
        switch message.role {
        case .user: NeoCodeTheme.panel
            case .assistant: NeoCodeTheme.panelRaised
        case .tool: NeoCodeTheme.success.opacity(0.08)
        case .system: NeoCodeTheme.panel.opacity(0.7)
        }
    }

    @ViewBuilder
    private var bubbleBackground: some View {
        if message.role == .assistant {
            EmptyView()
        } else {
            RoundedRectangle(cornerRadius: 16)
                .fill(backgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(NeoCodeTheme.line, lineWidth: 1)
                )
        }
    }

    private var textColor: Color {
        switch message.emphasis {
        case .normal: NeoCodeTheme.textPrimary
        case .subtle: NeoCodeTheme.textSecondary
        case .strong: NeoCodeTheme.accent
        }
    }

    private var canEditMessage: Bool {
        store.selectedSession?.status != .running && !store.isSending
    }

    private func copyMessageText() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(message.text, forType: .string)
        didCopy = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            didCopy = false
        }
    }

    private func resendEditedMessage() {
        Task {
            let didSend = await store.resendEditedMessage(messageID: message.id, newText: editingText, in: sessionID, using: runtime)
            if didSend {
                onFinishEdit()
            }
        }
    }
}

private struct AttachmentMessageView: View {
    let attachment: ChatAttachment
    let isUser: Bool
    let imageWidth: CGFloat?
    @State private var isHoveringImage = false

    init(attachment: ChatAttachment, isUser: Bool, imageWidth: CGFloat? = nil) {
        self.attachment = attachment
        self.isUser = isUser
        self.imageWidth = imageWidth
    }

    var body: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 10) {
            if attachment.isImage, let image = transcriptAttachmentImage(for: attachment) {
                imagePreview(for: image)
                .onHover { isHoveringImage = $0 }
                .animation(.easeOut(duration: 0.14), value: isHoveringImage)
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "paperclip")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(NeoCodeTheme.textMuted)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(attachment.displayTitle)
                            .font(.neoMonoSmall)
                            .foregroundStyle(NeoCodeTheme.textPrimary)
                            .lineLimit(2)

                        if let subtitle = attachment.displaySubtitle {
                            Text(subtitle)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(NeoCodeTheme.textMuted)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(isUser ? NeoCodeTheme.panel : NeoCodeTheme.panelRaised)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(NeoCodeTheme.line, lineWidth: 1)
                        )
                )
            }
        }
    }

    @ViewBuilder
    private func imagePreview(for image: NSImage) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14)

        Group {
            if let imageWidth {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: imageWidth)
                    .frame(maxHeight: min(180, imageWidth * 0.82))
            } else {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 280, maxHeight: 220)
            }
        }
        .clipShape(shape)
        .overlay {
            if isHoveringImage {
                LinearGradient(
                    stops: [
                        .init(color: Color.black.opacity(0.18), location: 0),
                        .init(color: Color.black.opacity(0.34), location: 0.52),
                        .init(color: Color.black.opacity(0.92), location: 0.7),
                        .init(color: Color.black.opacity(0.92), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                    .clipShape(shape)
                    .overlay(alignment: .bottomLeading) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(attachment.displayTitle)
                                .font(.neoMonoSmall)
                                .foregroundStyle(Color.white)
                                .lineLimit(2)

                            if let subtitle = attachment.displaySubtitle {
                                Text(subtitle)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(Color.white.opacity(0.72))
                                    .lineLimit(1)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                    }
                    .transition(.opacity)
            }
        }
    }
}

private func transcriptAttachmentImage(for attachment: ChatAttachment) -> NSImage? {
    TranscriptAttachmentImageCache.image(for: attachment) {
        guard attachment.isImage else { return nil }

        if attachment.url.hasPrefix("data:"),
           let data = transcriptAttachmentData(from: attachment.url) {
            return NSImage(data: data)
        }

        if let url = URL(string: attachment.url), url.isFileURL {
            return NSImage(contentsOf: url)
        }

        return nil
    }
}

private func transcriptAttachmentData(from dataURL: String) -> Data? {
    guard let commaIndex = dataURL.firstIndex(of: ",") else { return nil }
    let encoded = String(dataURL[dataURL.index(after: commaIndex)...])
    return Data(base64Encoded: encoded)
}

private enum TranscriptAttachmentImageCache {
    private static let imageCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 96
        return cache
    }()

    private static let failedLookupCache: NSCache<NSString, NSNumber> = {
        let cache = NSCache<NSString, NSNumber>()
        cache.countLimit = 256
        return cache
    }()

    static func image(for attachment: ChatAttachment, loader: () -> NSImage?) -> NSImage? {
        let key = cacheKey(for: attachment)

        if let cached = imageCache.object(forKey: key) {
            return cached
        }

        if failedLookupCache.object(forKey: key) != nil {
            return nil
        }

        guard let image = loader() else {
            failedLookupCache.setObject(NSNumber(value: true), forKey: key)
            return nil
        }

        imageCache.setObject(image, forKey: key)
        return image
    }

    private static func cacheKey(for attachment: ChatAttachment) -> NSString {
        var hasher = Hasher()
        hasher.combine(attachment.filename)
        hasher.combine(attachment.mimeType)
        hasher.combine(attachment.url)
        hasher.combine(attachment.sourcePath)
        return NSString(string: String(hasher.finalize()))
    }
}

private struct MessageHoverActionButton: View {
    let systemImage: String
    let isDisabled: Bool
    let action: () -> Void

    init(systemImage: String, isDisabled: Bool = false, action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.isDisabled = isDisabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(isDisabled ? NeoCodeTheme.textMuted : NeoCodeTheme.textSecondary)
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(NeoCodeTheme.panelRaised)
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .stroke(NeoCodeTheme.line, lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}

private struct InlineMessageEditor: View {
    @Binding var text: String
    @Binding var measuredHeight: CGFloat

    let isSending: Bool
    let onCancel: () -> Void
    let onSubmit: () -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 12) {
            GrowingTextView(
                text: $text,
                measuredHeight: $measuredHeight,
                selectionRequest: .constant(nil),
                onPrimaryAction: onSubmit,
                onConfirmAuxiliarySelection: { false },
                onMoveAuxiliarySelection: { _ in false },
                onCancelAuxiliaryUI: { false },
                allowsEmptyPrimaryAction: false,
                onImportAttachments: { _ in }
            )
            .frame(height: measuredHeight)

            HStack(spacing: 8) {
                Button("Cancel", action: onCancel)
                    .buttonStyle(.plain)
                    .font(.neoMonoSmall)
                    .foregroundStyle(NeoCodeTheme.textMuted)

                Button(action: onSubmit) {
                    Label(isSending ? "Sending..." : "Resend", systemImage: "arrow.up")
                        .font(.neoMonoSmall)
                        .foregroundStyle(NeoCodeTheme.canvas)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(canSubmit ? NeoCodeTheme.textPrimary : NeoCodeTheme.accentDim))
                }
                .buttonStyle(.plain)
                .disabled(!canSubmit)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(NeoCodeTheme.panel)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(NeoCodeTheme.line, lineWidth: 1)
                )
        )
    }

    private var canSubmit: Bool {
        !isSending && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
