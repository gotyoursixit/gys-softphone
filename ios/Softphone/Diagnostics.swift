import Foundation
import Network
import Security

/// "Verbinding testen" (zoals Diagnostics.kt): controleert stap voor stap of de centrale bereikbaar is
/// en schrijft de uitkomst in gewone taal naar het logboek. Stuurt per transport één SIP OPTIONS, zonder
/// wachtwoord, zodat een fout hier niet meetelt voor Event Guard; daarna ook de beheerserver.
enum Diagnostics {
    nonisolated static let timeout: TimeInterval = 4

    enum Kind: String, Sendable { case udp = "UDP", tcp = "TCP", tls = "TLS" }

    static func run() async {
        let log = LogStore.shared
        guard let acc = SipManager.shared.account ?? Settings.account else {
            log.appError("Verbindingstest: geen account ingesteld.")
            return
        }
        log.app("════════ VERBINDINGSTEST ════════")
        log.app("Server: '\(acc.server)'  poort: '\(acc.port.isEmpty ? "standaard" : acc.port)'  transport: \(acc.transport.rawValue)")
        log.app("Toestel: '\(acc.user)'  domein: '\(acc.domain)'")

        // 1. Netwerk van de iPhone
        log.app("1. iPhone zit op: \(await network())")

        // 2. Adres opzoeken
        let addrs = await resolve(acc.server)
        guard let target = addrs.first else {
            log.appError("2. Adres '\(acc.server)' NIET gevonden (DNS). Controleer de spelling of gebruik het IP-adres.")
            return
        }
        log.app("2. Adres gevonden: \(addrs.joined(separator: ", "))")

        // 3. Elk transport proberen, zodat zichtbaar is wat de centrale wel/niet aanbiedt.
        let port = Int(acc.port)
        let udpTcpPort = acc.transport != .tls ? (port ?? 5060) : 5060
        let tlsPort = acc.transport == .tls ? (port ?? 5061) : 5061
        var results: [(Kind, String)] = []
        for (kind, p) in [(Kind.udp, udpTcpPort), (.tcp, udpTcpPort), (.tls, tlsPort)] {
            results.append((kind, await probe(host: target, sniName: acc.server, port: p, kind: kind, user: acc.user, domain: acc.domain)))
        }
        log.app("3. Resultaat per transport:")
        for (kind, r) in results { log.app("   \(kind.rawValue): \(r)") }

        // 4. Conclusie
        let chosen = results.first { $0.0.rawValue == acc.transport.rawValue }?.1 ?? ""
        let working = results.filter { $0.1.hasPrefix("OK") }.map(\.0.rawValue)
        if chosen.hasPrefix("OK") {
            log.app("4. Conclusie: centrale bereikbaar via \(acc.transport.rawValue). Zie hieronder de aanmelding zelf (401/403 = toestel/wachtwoord).")
        } else if let first = working.first {
            log.appError("4. Conclusie: \(acc.transport.rawValue) werkt NIET, maar \(working.joined(separator: ", ")) wel. Log uit en kies onder Serverinstellingen transport \(first).")
        } else {
            log.appError("4. Conclusie: de centrale reageert op geen enkel transport. Mogelijke oorzaken: verkeerd adres, firewall, of het IP-adres is geblokkeerd (Event Guard).")
        }

        // 5. Beheerserver (collegalijst, inloggen zonder SIP)
        log.app("5. Beheerserver: \(await beheerHealth())")

        log.app("Aanmelden opnieuw proberen…")
        SipManager.shared.refresh()
    }

    // MARK: Onderdelen

    private static func network() async -> String {
        await withCheckedContinuation { (cont: CheckedContinuation<String, Never>) in
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { path in
                monitor.cancel()
                let kind: String
                if path.status != .satisfied { kind = "GEEN netwerk" }
                else if path.usesInterfaceType(.wifi) { kind = "wifi" }
                else if path.usesInterfaceType(.cellular) { kind = "mobiel (4G/5G)" }
                else if path.usesInterfaceType(.wiredEthernet) { kind = "kabel" }
                else { kind = "anders" }
                let extra = path.isExpensive ? " (beperkt/duur netwerk)" : ""
                cont.resume(returning: kind + extra)
            }
            monitor.start(queue: DispatchQueue(label: "diagnose.pad"))
        }
    }

    private static func resolve(_ host: String) async -> [String] {
        await Task.detached {
            var hints = addrinfo(ai_flags: 0, ai_family: AF_UNSPEC, ai_socktype: SOCK_DGRAM, ai_protocol: 0,
                                 ai_addrlen: 0, ai_canonname: nil, ai_addr: nil, ai_next: nil)
            var res: UnsafeMutablePointer<addrinfo>?
            guard getaddrinfo(host, nil, &hints, &res) == 0, let first = res else { return [String]() }
            defer { freeaddrinfo(first) }
            var out: [String] = []
            var p: UnsafeMutablePointer<addrinfo>? = first
            while let a = p {
                var buf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(a.pointee.ai_addr, a.pointee.ai_addrlen, &buf, socklen_t(buf.count), nil, 0, NI_NUMERICHOST) == 0 {
                    let s = String(cString: buf)
                    if !out.contains(s) { out.append(s) }
                }
                p = a.pointee.ai_next
            }
            // IPv4 eerst: de centrale is via IPv4 ingericht.
            return out.sorted { !$0.contains(":") && $1.contains(":") }
        }.value
    }

    /// Eén SIP OPTIONS via het gekozen transport; geeft "OK …" of een uitleg terug.
    private nonisolated static func probe(host: String, sniName: String, port: Int, kind: Kind, user: String, domain: String) async -> String {
        let params: NWParameters
        let cert = CertNote()
        switch kind {
        case .udp: params = .udp
        case .tcp: params = .tcp
        case .tls:
            // Alleen voor de diagnose: certificaat accepteren en apart rapporteren.
            let tls = NWProtocolTLS.Options()
            sec_protocol_options_set_tls_server_name(tls.securityProtocolOptions, sniName)
            sec_protocol_options_set_verify_block(tls.securityProtocolOptions, { _, trust, done in
                let t = sec_trust_copy_ref(trust).takeRetainedValue()
                if let chain = SecTrustCopyCertificateChain(t) as? [SecCertificate], let leaf = chain.first {
                    cert.text = SecCertificateCopySubjectSummary(leaf) as String? ?? "?"
                }
                done(true)
            }, DispatchQueue(label: "diagnose.tls"))
            params = NWParameters(tls: tls)
        }
        let conn = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(integerLiteral: UInt16(port)), using: params)
        let queue = DispatchQueue(label: "diagnose.\(kind.rawValue)")
        let once = Once()

        let result: String = await withCheckedContinuation { cont in
            let finish: @Sendable (String) -> Void = { s in
                guard once.claim() else { return }
                conn.cancel()
                cont.resume(returning: s)
            }
            queue.asyncAfter(deadline: .now() + timeout) {
                switch kind {
                case .udp: finish("GEEN antwoord op poort \(port) binnen \(Int(timeout)) s (UDP dicht, firewall, of geblokkeerd)")
                default:
                    finish(once.connected
                           ? "OK verbinding op poort \(port), maar geen SIP-antwoord\(cert.suffix)"
                           : "TIME-OUT op poort \(port) (geblokkeerd door firewall of server onbereikbaar)")
                }
            }
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    once.connected = true
                    let local = conn.currentPath?.localEndpoint
                    let (ip, lport): (String, Int) = {
                        if case .hostPort(let h, let p) = local { return ("\(h)".components(separatedBy: "%")[0], Int(p.rawValue)) }
                        return ("0.0.0.0", 0)
                    }()
                    let msg = options(host: host, transport: kind.rawValue, localIp: ip, localPort: lport, user: user, domain: domain)
                    conn.send(content: Data(msg.utf8), completion: .contentProcessed { error in
                        if let error { finish("FOUT bij versturen op poort \(port): \(error.localizedDescription)") }
                    })
                    conn.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, error in
                        if let data, let text = String(data: data, encoding: .utf8), !text.isEmpty {
                            finish("OK op poort \(port) – antwoord: \(text.components(separatedBy: "\r\n").first ?? "?")\(cert.suffix)")
                        } else if let error {
                            finish(kind == .udp
                                   ? "GEEN antwoord op poort \(port) (\(error.localizedDescription))"
                                   : "OK verbinding op poort \(port), maar geen SIP-antwoord\(cert.suffix)")
                        }
                    }
                case .failed(let error), .waiting(let error):
                    if case .posix(let code) = error, code == .ECONNREFUSED {
                        finish("GEWEIGERD op poort \(port) (de centrale luistert hier niet op \(kind.rawValue))")
                    } else if kind == .tls, case .tls = error {
                        finish("FOUT bij TLS op poort \(port): \(error.localizedDescription)")
                    } else if case .failed = state {
                        finish("FOUT op poort \(port): \(error.localizedDescription)")
                    }
                default: break
                }
            }
            conn.start(queue: queue)
        }
        return result
    }

    private nonisolated static func options(host: String, transport: String, localIp: String, localPort: Int, user: String, domain: String) -> String {
        let branch = "z9hG4bK" + String(UInt64.random(in: 1...UInt64.max), radix: 16)
        let tag = String(UInt32.random(in: 1...UInt32.max), radix: 16)
        let callId = String(UInt64.random(in: 1...UInt64.max), radix: 16) + "@softphone-ios"
        return "OPTIONS sip:\(host) SIP/2.0\r\n" +
            "Via: SIP/2.0/\(transport) \(localIp):\(localPort);branch=\(branch);rport\r\n" +
            "Max-Forwards: 70\r\n" +
            "From: <sip:\(user)@\(domain)>;tag=\(tag)\r\n" +
            "To: <sip:\(host)>\r\n" +
            "Call-ID: \(callId)\r\n" +
            "CSeq: 1 OPTIONS\r\n" +
            "Contact: <sip:\(user)@\(localIp):\(localPort);transport=\(transport.lowercased())>\r\n" +
            "User-Agent: Softphone-diagnose\r\n" +
            "Content-Length: 0\r\n\r\n"
    }

    private static func beheerHealth() async -> String {
        var req = URLRequest(url: BeheerClient.baseURL.appending(path: "health"))
        req.timeoutInterval = 6
        req.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, res) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "NIET bereikbaar (geen internet naar api.gys-voip.nl, of de server ligt eruit)"
        }
        let code = (res as? HTTPURLResponse)?.statusCode ?? 0
        let esl = json["esl"] as? Bool ?? false
        if code == 200 && esl { return "OK, en verbonden met de centrale" }
        if code == 200 { return "bereikbaar, maar NIET verbonden met de centrale (collegastatus onbekend)" }
        return "bereikbaar, maar meldt een storing (database of Redis, HTTP \(code))"
    }
}

/// Zorgt dat een continuation precies één keer wordt afgerond (time-out en antwoord kunnen tegelijk komen).
private nonisolated final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    private var _connected = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }

    var connected: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _connected }
        set { lock.lock(); _connected = newValue; lock.unlock() }
    }
}

/// Onderwerp van het TLS-certificaat, gevuld vanuit het verify-blok.
private nonisolated final class CertNote: @unchecked Sendable {
    private let lock = NSLock()
    private var _text: String?

    var text: String? {
        get { lock.lock(); defer { lock.unlock() }; return _text }
        set { lock.lock(); _text = newValue; lock.unlock() }
    }

    var suffix: String { text.map { " (certificaat: \($0))" } ?? "" }
}
