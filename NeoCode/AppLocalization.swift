import Foundation
import SwiftUI

enum NeoCodeAppLanguage: String, Codable, CaseIterable, Hashable, Identifiable {
    case system
    case english
    case spanish
    case portuguese
    case french
    case italian

    var id: String { rawValue }

    var title: String {
        title(locale: .autoupdatingCurrent)
    }

    func title(locale: Locale) -> String {
        switch self {
        case .system:
            return localized("System", locale: locale)
        case .english:
            return localized("English", locale: locale)
        case .spanish:
            return localized("Spanish", locale: locale)
        case .portuguese:
            return localized("Portuguese", locale: locale)
        case .french:
            return localized("French", locale: locale)
        case .italian:
            return localized("Italian", locale: locale)
        }
    }

    var locale: Locale {
        switch self {
        case .system:
            return .autoupdatingCurrent
        case .english:
            return Locale(identifier: "en")
        case .spanish:
            return Locale(identifier: "es")
        case .portuguese:
            return Locale(identifier: "pt")
        case .french:
            return Locale(identifier: "fr")
        case .italian:
            return Locale(identifier: "it")
        }
    }
}

nonisolated func localized(_ key: String, locale: Locale) -> String {
    let bundle = localizationBundle(for: locale)
    let localizedValue = bundle.localizedString(forKey: key, value: nil, table: nil)

    if localizedValue != key || bundle == Bundle.main {
        return localizedValue
    }

    return Bundle.main.localizedString(forKey: key, value: key, table: nil)
}

private nonisolated func localizationBundle(for locale: Locale) -> Bundle {
    for identifier in localizationIdentifiers(for: locale) {
        if let path = Bundle.main.path(forResource: identifier, ofType: "lproj"),
           let bundle = Bundle(path: path)
        {
            return bundle
        }
    }

    return Bundle.main
}

private nonisolated func localizationIdentifiers(for locale: Locale) -> [String] {
    var identifiers: [String] = []
    let normalizedIdentifier = locale.identifier.replacingOccurrences(of: "_", with: "-")

    if !normalizedIdentifier.isEmpty {
        identifiers.append(normalizedIdentifier)
        if let languageIdentifier = normalizedIdentifier.split(separator: "-").first {
            identifiers.append(String(languageIdentifier))
        }
    }

    return Array(NSOrderedSet(array: identifiers)) as? [String] ?? identifiers
}
