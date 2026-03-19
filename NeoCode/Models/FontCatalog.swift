import AppKit

struct NeoCodeFontOption: Identifiable, Hashable {
    let id: String
    let title: String
}

enum NeoCodeFontCatalog {
    static let defaultUIFontName = "SF Pro"
    static let defaultCodeFontName = "SF Mono"

    static let uiOptions: [NeoCodeFontOption] = buildUIOptions()
    static let codeOptions: [NeoCodeFontOption] = buildCodeOptions()

    static func postScriptName(for storedName: String, preferFixedPitch: Bool) -> String? {
        guard !storedName.isEmpty,
              storedName != defaultUIFontName,
              storedName != defaultCodeFontName,
              !usesSystemMonospaceStack(storedName)
        else {
            return nil
        }

        if NSFont(name: storedName, size: 13) != nil {
            return storedName
        }

        return preferredMember(forFamily: storedName, preferFixedPitch: preferFixedPitch)?.postScriptName
    }

    static func displayName(for storedName: String, preferFixedPitch: Bool) -> String {
        let fallback = preferFixedPitch ? defaultCodeFontName : defaultUIFontName
        let trimmed = storedName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            return fallback
        }

        if usesSystemMonospaceStack(trimmed) {
            return "System Monospace"
        }

        return trimmed
    }

    static func uiOptions(includingSelected storedName: String) -> [NeoCodeFontOption] {
        options(includingSelected: storedName, in: uiOptions, preferFixedPitch: false)
    }

    static func codeOptions(includingSelected storedName: String) -> [NeoCodeFontOption] {
        options(includingSelected: storedName, in: codeOptions, preferFixedPitch: true)
    }

    static func usesSystemMonospaceStack(_ storedName: String) -> Bool {
        storedName.localizedCaseInsensitiveContains("ui-monospace")
    }

    private static func buildUIOptions() -> [NeoCodeFontOption] {
        [NeoCodeFontOption(id: defaultUIFontName, title: defaultUIFontName)]
            + availableFamilyNames().map { NeoCodeFontOption(id: $0, title: $0) }
    }

    private static func buildCodeOptions() -> [NeoCodeFontOption] {
        [NeoCodeFontOption(id: defaultCodeFontName, title: defaultCodeFontName)]
            + availableFamilyNames().filter { family in
                guard let member = preferredMember(forFamily: family, preferFixedPitch: true),
                      let font = NSFont(name: member.postScriptName, size: 13)
                else {
                    return false
                }

                return font.isFixedPitch
            }
            .map { NeoCodeFontOption(id: $0, title: $0) }
    }

    private static func availableFamilyNames() -> [String] {
        NSFontManager.shared.availableFontFamilies
            .filter { !$0.hasPrefix(".") }
            .filter { $0 != defaultUIFontName && $0 != defaultCodeFontName }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private static func preferredMember(forFamily family: String, preferFixedPitch: Bool) -> FontMember? {
        let members = fontMembers(forFamily: family)
        let filteredMembers: [FontMember]
        if preferFixedPitch {
            filteredMembers = members.filter { member in
                guard let font = NSFont(name: member.postScriptName, size: 13) else { return false }
                return font.isFixedPitch
            }
        } else {
            filteredMembers = members
        }

        let candidates = filteredMembers.isEmpty ? members : filteredMembers
        return candidates.first(where: \.isRegularLike) ?? candidates.first
    }

    private static func fontMembers(forFamily family: String) -> [FontMember] {
        guard let rawMembers = NSFontManager.shared.availableMembers(ofFontFamily: family) else {
            return []
        }

        return rawMembers.compactMap { member in
            guard member.count >= 2,
                  let postScriptName = member[0] as? String,
                  let displayName = member[1] as? String
            else {
                return nil
            }

            return FontMember(postScriptName: postScriptName, displayName: displayName)
        }
    }

    private static func options(
        includingSelected storedName: String,
        in baseOptions: [NeoCodeFontOption],
        preferFixedPitch: Bool
    ) -> [NeoCodeFontOption] {
        guard !storedName.isEmpty,
              !baseOptions.contains(where: { $0.id == storedName })
        else {
            return baseOptions
        }

        return [NeoCodeFontOption(id: storedName, title: displayName(for: storedName, preferFixedPitch: preferFixedPitch))] + baseOptions
    }

    private struct FontMember {
        let postScriptName: String
        let displayName: String

        var isRegularLike: Bool {
            let lowered = displayName.lowercased()
            return !lowered.contains("bold")
                && !lowered.contains("italic")
                && !lowered.contains("oblique")
                && !lowered.contains("black")
                && !lowered.contains("heavy")
        }
    }
}
