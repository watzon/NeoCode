import Foundation

struct PersistedWorkspaceSelectionStore {
    struct Selection: Codable, Hashable {
        enum Kind: String, Codable, Hashable {
            case dashboard
            case session
        }

        let kind: Kind
        let projectID: UUID?
        let sessionID: String?

        init(kind: Kind, projectID: UUID?, sessionID: String? = nil) {
            self.kind = kind
            self.projectID = projectID
            self.sessionID = sessionID
        }
    }

    private let defaults: UserDefaults
    private let key: String

    init(
        defaults: UserDefaults = .standard,
        key: String = "tech.watzon.NeoCode.workspaceSelection"
    ) {
        self.defaults = defaults
        self.key = key
    }

    func loadSelection() -> Selection? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Selection.self, from: data)
    }

    func saveSelection(_ selection: Selection) {
        guard let data = try? JSONEncoder().encode(selection) else { return }
        defaults.set(data, forKey: key)
    }
}
