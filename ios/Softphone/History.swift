import Foundation
import Observation

/// Gesprekshistorie, bewaard als JSON op het toestel. Zelf bijgehouden (niet de database van Linphone):
/// die werkt alleen met een configuratiebestand, en daarin zou Linphone ook het wachtwoord opslaan.
@Observable
final class History {
    static let shared = History()

    struct Entry: Codable, Identifiable {
        enum Kind: String, Codable {
            case outgoing, incoming, missed, declined
            /// Belgroep: een collega nam op (zoals "Aangenomen door een collega" in de webapp).
            case elsewhere
        }

        var id = UUID()
        let number: String
        let name: String
        let kind: Kind
        let date: Date
        /// Gespreksduur in seconden.
        let duration: Int
    }

    private(set) var entries: [Entry] = []
    private let max = 300

    private static var file: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "historie.json")
    }

    private init() {
        if let data = try? Data(contentsOf: Self.file), let list = try? JSONDecoder().decode([Entry].self, from: data) {
            entries = list
        }
    }

    func add(_ entry: Entry) {
        entries.insert(entry, at: 0)
        if entries.count > max { entries.removeLast(entries.count - max) }
        save()
    }

    func clear() {
        entries = []
        save()
    }

    private func save() {
        try? JSONEncoder().encode(entries).write(to: Self.file, options: [.atomic, .completeFileProtection])
    }
}
