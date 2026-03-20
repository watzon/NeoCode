import Foundation

enum NeoCodeRelease {
    nonisolated static var marketingVersion: String {
        let version = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (version?.isEmpty == false) ? version! : "0.0.0"
    }

    nonisolated static var buildVersion: String {
        let version = (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (version?.isEmpty == false) ? version! : "0"
    }
}
