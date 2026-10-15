import Foundation
import Observation

/// Collegalijst met live status van de beheerserver (zoals BeheerLink in web/src/beheer.ts): eerst /presence,
/// dan gebeurtenissen via de WebSocket /realtime. Valt die weg, dan opnieuw (1, 2, 5, 10, 20, daarna elke 30 s).
/// BLF via SIP wordt niet gebruikt: FreeSWITCH stuurt de NOTIFY's niet betrouwbaar (zie CLAUDE.md).
@Observable
final class Colleagues {
    static let shared = Colleagues()

    struct Colleague: Identifiable, Decodable {
        let ext: String
        let name: String
        /// idle / ringing / busy
        var state: String
        /// nil = onbekend (de centrale gaf geen lijst met aanmeldingen).
        var registered: Bool?
        var dnd: Bool?
        var id: String { ext }

        enum Status { case available, ringing, busy, dnd, offline, unknown }
    }

    private struct Presence: Decodable {
        let live: Bool
        let extensions: [Colleague]
    }

    private struct Ticket: Decodable { let ticket: String }

    private(set) var list: [Colleague] = []
    /// false = de beheerserver heeft (even) geen verbinding met de centrale: status onbekend.
    private(set) var live = true
    /// true zolang de WebSocket open is.
    private(set) var online = false
    /// Waarom er geen lijst is (beheerserver niet gebruikt, domein niet aangesloten, ...).
    private(set) var unavailable: String?

    private var loop: Task<Void, Never>?
    private var socket: URLSessionWebSocketTask?
    private let log = LogStore.shared

    func start() {
        guard loop == nil else { return }
        guard Settings.beheerToken != nil else {
            unavailable = "De beheerserver is niet verbonden, daarom is er geen collegalijst."
            return
        }
        unavailable = nil
        loop = Task { await run() }
    }

    func stop() {
        loop?.cancel()
        loop = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        list = []
        online = false
    }

    /// Bij terugkomen in de app: iOS heeft de WebSocket op de achtergrond vaak al gesloten.
    func wake() {
        guard loop != nil, !online else { return }
        stop()
        start()
    }

    func status(_ c: Colleague) -> Colleague.Status {
        if !live { return .unknown }
        // Een gesprek gaat voor op offline (zelfde volgorde als de webapp).
        switch c.state {
        case "busy": return .busy
        case "ringing": return .ringing
        default: break
        }
        if c.registered == false { return .offline }
        if c.dnd == true { return .dnd }
        return .available
    }

    func name(for number: String) -> String? {
        list.first { $0.ext == number }?.name.nilIfEmpty
    }

    private func run() async {
        let delays: [UInt64] = [1, 2, 5, 10, 20, 30]
        var retry = 0
        while !Task.isCancelled {
            let opened = Date()
            do {
                let p = try await BeheerClient.authed("presence", as: Presence.self)
                live = p.live
                list = p.extensions.sorted { $0.ext.localizedStandardCompare($1.ext) == .orderedAscending }
                let t = try await BeheerClient.authed("realtime/ticket", method: "POST", as: Ticket.self)
                try await listen(ticket: t.ticket)
            } catch let f as BeheerClient.Failure where f.status == 403 || f.status == 401 {
                // Domein niet aangesloten of niet (meer) ingelogd: opnieuw proberen heeft geen zin.
                log.app("Collegalijst: \(f.message)")
                unavailable = f.message
                online = false
                loop = nil
                return
            } catch {
                if !Task.isCancelled { log.app("Collegalijst: verbinding weg (\(error.localizedDescription))") }
            }
            online = false
            if Date().timeIntervalSince(opened) >= 30 { retry = 0 }
            try? await Task.sleep(for: .seconds(Double(delays[min(retry, delays.count - 1)])))
            retry += 1
        }
    }

    private func listen(ticket: String) async throws {
        var url = URLComponents(url: BeheerClient.baseURL.appending(path: "realtime"), resolvingAgainstBaseURL: false)!
        url.scheme = "wss"
        url.queryItems = [URLQueryItem(name: "ticket", value: ticket)]
        let ws = URLSession.shared.webSocketTask(with: url.url!)
        socket = ws
        ws.resume()
        while !Task.isCancelled {
            let message = try await ws.receive()
            online = true
            if case .string(let text) = message { handle(text) }
        }
    }

    /// Gebeurtenissen uit server/src/realtime.ts en server/src/pbx/calls.ts.
    private func handle(_ text: String) {
        guard let e = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any],
              let type = e["type"] as? String else { return }
        let ext = e["ext"] as? String
        switch type {
        case "hello":
            live = e["live"] as? Bool ?? true
            let states = Dictionary((e["states"] as? [[String: String]] ?? []).compactMap { s in
                s["ext"].flatMap { ext in s["state"].map { (ext, $0) } }
            }, uniquingKeysWith: { a, _ in a })
            let registered = (e["registered"] as? [String]).map(Set.init)
            let dnd = Set(e["dnd"] as? [String] ?? [])
            for i in list.indices {
                list[i].state = states[list[i].ext] ?? "idle"
                list[i].registered = registered.map { $0.contains(list[i].ext) }
                list[i].dnd = dnd.contains(list[i].ext)
            }
        case "extension.state":
            update(ext) { $0.state = e["state"] as? String ?? "idle" }
        case "extension.registered":
            update(ext) { $0.registered = e["registered"] as? Bool }
        case "extension.registrations":
            let registered = Set(e["registered"] as? [String] ?? [])
            for i in list.indices { list[i].registered = registered.contains(list[i].ext) }
        case "extension.dnd":
            update(ext) { $0.dnd = e["dnd"] as? Bool }
        default:
            break
        }
    }

    private func update(_ ext: String?, _ change: (inout Colleague) -> Void) {
        guard let ext, let i = list.firstIndex(where: { $0.ext == ext }) else { return }
        change(&list[i])
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
