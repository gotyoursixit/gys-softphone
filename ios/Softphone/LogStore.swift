import Foundation
import Observation

/// Logboek van de app en van Linphone (zoals LogBuffer.kt). Alleen in het geheugen; het laatste deel blijft bewaard.
@Observable
final class LogStore {
    static let shared = LogStore()

    enum Kind { case app, error, sip }

    struct Entry: Identifiable {
        let id = UUID()
        let time: Date
        let kind: Kind
        let text: String
    }

    private(set) var entries: [Entry] = []
    private let max = 1500

    func app(_ text: String) { add(.app, text) }
    func appError(_ text: String) { add(.error, text) }
    func sip(_ text: String) { add(.sip, text) }

    private func add(_ kind: Kind, _ text: String) {
        entries.append(Entry(time: Date(), kind: kind, text: text))
        if entries.count > max { entries.removeFirst(entries.count - max) }
    }

    /// Hele app-logboek als tekst, om te delen.
    var text: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return entries.map { "\(f.string(from: $0.time)) \($0.kind == .error ? "FOUT " : "")\($0.text)" }.joined(separator: "\n")
    }

    // MARK: SIP-log (Linphone schrijft zelf naar bestanden, zie SipManager.start())

    static let sipLogPrefix = "linphone"

    static var sipLogDirectory: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appending(path: "sip-log")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Laatste deel van het SIP-log (nieuwste bestand achteraan), max. `maxBytes`.
    static func sipLogText(maxBytes: Int = 300_000) -> String {
        let fm = FileManager.default
        let files = ((try? fm.contentsOfDirectory(at: sipLogDirectory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [])
            .filter { $0.lastPathComponent.hasPrefix(sipLogPrefix) && $0.pathExtension == "log" }
            .sorted {
                let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return a < b
            }
        var data = Data()
        for file in files { data.append((try? Data(contentsOf: file)) ?? Data()) }
        if data.count > maxBytes { data = data.suffix(maxBytes) }
        return String(decoding: data, as: UTF8.self)
    }
}
