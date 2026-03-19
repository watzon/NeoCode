import AppKit
import SwiftUI

struct ComposerAttachmentChip: View {
    let attachment: ComposerAttachment
    let onRemove: () -> Void

    var body: some View {
        Group {
            if attachment.isImage {
                ComposerImageAttachmentChip(attachment: attachment, onRemove: onRemove)
            } else {
                ComposerFileAttachmentChip(attachment: attachment, onRemove: onRemove)
            }
        }
    }
}

private struct ComposerFileAttachmentChip: View {
    let attachment: ComposerAttachment
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "paperclip")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(NeoCodeTheme.textMuted)

            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.name)
                    .font(.neoMonoSmall)
                    .foregroundStyle(NeoCodeTheme.textSecondary)
                    .lineLimit(1)

                Text(attachment.mimeType)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(NeoCodeTheme.textMuted)
                    .lineLimit(1)
            }

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(NeoCodeTheme.textMuted)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            Capsule()
                .fill(NeoCodeTheme.panelSoft)
                .overlay(Capsule().stroke(NeoCodeTheme.line, lineWidth: 1))
        )
    }
}

private struct ComposerImageAttachmentChip: View {
    let attachment: ComposerAttachment
    let onRemove: () -> Void

    @State private var isHovering = false
    @Environment(\.locale) private var locale

    private let previewWidth: CGFloat = 80
    private let previewHeight: CGFloat = 64

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                Group {
                    if let image = composerAttachmentImage(for: attachment) {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Rectangle()
                            .fill(NeoCodeTheme.panelSoft)
                            .overlay {
                                Image(systemName: "photo")
                                    .foregroundStyle(NeoCodeTheme.textMuted)
                            }
                    }
                }
                .frame(width: previewWidth, height: previewHeight)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                if isHovering {
                    Button(action: onRemove) {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.red.opacity(0.88))
                            .overlay {
                                VStack(spacing: 6) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 18, weight: .semibold))
                                    Text(localized("Remove", locale: locale))
                                        .font(.system(size: 11, weight: .semibold))
                                }
                                .foregroundStyle(Color.white)
                            }
                    }
                    .buttonStyle(.plain)
                    .frame(width: previewWidth, height: previewHeight)
                    .neoTooltip(localized("Remove attachment", locale: locale))
                    .accessibilityLabel(localized("Remove attachment", locale: locale))
                    .transition(.opacity)
                }
            }
            .onHover { isHovering = $0 }
            .animation(.easeOut(duration: 0.14), value: isHovering)

            Text(attachment.name)
                .font(.neoMonoSmall)
                .foregroundStyle(NeoCodeTheme.textSecondary)
                .lineLimit(1)
                .frame(width: previewWidth, alignment: .leading)
        }
        .padding(7)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(NeoCodeTheme.panelSoft)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(NeoCodeTheme.line, lineWidth: 1)
                )
        )
    }
}

private func composerAttachmentImage(for attachment: ComposerAttachment) -> NSImage? {
    ComposerAttachmentImageCache.image(for: attachment) {
        switch attachment.content {
        case .file(let path):
            return NSImage(contentsOfFile: path)
        case .dataURL(let dataURL):
            guard let data = data(fromDataURL: dataURL) else { return nil }
            return NSImage(data: data)
        }
    }
}

private func data(fromDataURL dataURL: String) -> Data? {
    guard let commaIndex = dataURL.firstIndex(of: ",") else { return nil }
    let encoded = String(dataURL[dataURL.index(after: commaIndex)...])
    return Data(base64Encoded: encoded)
}

private enum ComposerAttachmentImageCache {
    private static let imageCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 32
        return cache
    }()

    private static let failedLookupCache: NSCache<NSString, NSNumber> = {
        let cache = NSCache<NSString, NSNumber>()
        cache.countLimit = 128
        return cache
    }()

    static func image(for attachment: ComposerAttachment, loader: () -> NSImage?) -> NSImage? {
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

    private static func cacheKey(for attachment: ComposerAttachment) -> NSString {
        var hasher = Hasher()
        hasher.combine(attachment.name)
        hasher.combine(attachment.mimeType)
        hasher.combine(attachment.deduplicationKey)
        return NSString(string: String(hasher.finalize()))
    }
}
