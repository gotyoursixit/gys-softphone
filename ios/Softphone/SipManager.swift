import AudioToolbox
import Foundation
import Observation
@preconcurrency import linphonesw

/// Eén Linphone-core voor de hele app (zoals Sip.kt op Android): account instellen, registreren, status.
@Observable
final class SipManager {
    static let shared = SipManager()

    enum Status: Equatable {
        case none
        case progress
        case ok
        /// code = SIP-statuscode (0 = geen antwoord / netwerkfout).
        case failed(code: Int, text: String)
    }

    private(set) var status: Status = .none
    private(set) var account: Account?
    /// Het gesprek op het belscherm; nil = geen gesprek. Tijdens overleg is dit het overleggesprek.
    private(set) var call: CallInfo?

    private var core: Core?
    private var current: Call?
    private var coreDelegate: CoreDelegateStub?

    private init() {}

    var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?" }

    func start() {
        guard core == nil else { return }
        let log = LogStore.shared
        log.app("App gestart, versie \(version)")

        // SIP-log van Linphone naar bestanden (LogStore.sipLogText). Géén LoggingServiceDelegate: Linphone
        // roept die ook vanaf zijn audiothread aan en de Swift-koppeling crasht daar (14 okt 2026, na ophangen).
        LoggingService.Instance.logLevel = .Message
        Core.setLogCollectionPath(path: LogStore.sipLogDirectory.path)
        Core.setLogCollectionPrefix(prefix: LogStore.sipLogPrefix)
        Core.setLogCollectionMaxFileSize(size: 2_000_000)
        Core.enableLogCollection(state: .Enabled)

        do {
            let c = try Factory.Instance.createCore(configPath: nil, factoryConfigPath: nil, systemContext: nil)
            c.setUserAgent(name: "GYS Softphone iOS", version: version)
            c.keepAliveEnabled = true
            let cd = CoreDelegateStub(
                onCallStateChanged: { [weak self] _, call, state, message in
                    self?.callChanged(call, state, message)
                },
                onTransferStateChanged: { [weak self] _, call, state in
                    self?.transferChanged(call, state)
                },
                onAccountRegistrationStateChanged: { [weak self] _, account, state, message in
                    self?.registrationChanged(account, state, message)
                })
            c.addDelegate(delegate: cd)
            coreDelegate = cd
            try c.start()
            core = c
        } catch {
            log.appError("Linphone starten mislukt: \(error)")
        }
    }

    /// (Her)configureert het SIP-account en start de registratie (zoals Sip.applySettings()).
    func register(_ acc: Account, password: String) {
        guard let core else { return }
        core.clearAccounts()
        core.clearAllAuthInfo()
        LogStore.shared.app("Account instellen: \(acc.address) via \(acc.server)\(acc.port.isEmpty ? "" : ":\(acc.port)") (\(acc.transport.rawValue))")
        do {
            let f = Factory.Instance
            core.addAuthInfo(info: try f.createAuthInfo(username: acc.user, userid: nil, passwd: password, ha1: nil, realm: nil, domain: acc.domain))

            let identity = try f.createAddress(addr: "sip:\(acc.user)@\(acc.domain)")
            let server = try f.createAddress(addr: "sip:\(acc.server)\(acc.port.isEmpty ? "" : ":\(acc.port)")")
            try server.setTransport(newValue: acc.transport.linphone)

            let params = try core.createAccountParams()
            try params.setIdentityaddress(newValue: identity)
            try params.setServeraddress(newValue: server)
            params.registerEnabled = true
            params.expires = 600
            // Domein wijkt af van de server: al het verkeer via de server routeren.
            params.outboundProxyEnabled = acc.domain != acc.server

            let account = try core.createAccount(params: params)
            try core.addAccount(account: account)
            core.defaultAccount = account
            self.account = acc
            status = .progress
            core.refreshRegisters()
        } catch {
            status = .failed(code: 0, text: "Account instellen mislukt")
            LogStore.shared.appError("Account instellen mislukt: \(error)")
        }
    }

    /// Wacht tot de centrale de registratie accepteert of weigert (max. `seconds`); nil = geen antwoord.
    func waitForRegistration(seconds: Double = 15) async -> Status? {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            switch status {
            case .ok, .failed: return status
            default: try? await Task.sleep(for: .milliseconds(100))
            }
        }
        return nil
    }

    /// Opnieuw aanmelden, bijv. na terugkomen in de app (iOS verbreekt verbindingen op de achtergrond).
    func refresh() {
        guard let core, core.defaultAccount != nil else { return }
        core.refreshRegisters()
    }

    /// Account weghalen. Niet aangemeld: eerst registreren uitzetten, zodat Linphone niet opnieuw probeert
    /// en geen (geweigerde) afmelding stuurt; die telt anders ook mee voor Event Guard (zie CLAUDE.md).
    func clear() {
        guard let core else { return }
        if status != .ok, let acc = core.defaultAccount, let p = acc.params?.clone() {
            p.registerEnabled = false
            acc.params = p
        }
        core.clearAccounts()
        core.clearAllAuthInfo()
        account = nil
        status = .none
    }

    // MARK: Bellen

    /// Belt een nummer of toestel; geeft een foutmelding terug als dat niet kan.
    func dial(_ number: String) async -> String? {
        guard call == nil else { return "Er loopt al een gesprek." }
        return await invite(number)
    }

    private func invite(_ number: String) async -> String? {
        let n = Account.clean(number)
        guard !n.isEmpty, let core else { return nil }
        guard await AudioPermission.request() else {
            return "Geen toegang tot de microfoon. Zet die aan in Instellingen → Privacy → Microfoon."
        }
        guard let addr = core.interpretUrl(url: n, applyInternationalPrefix: false) else { return "Ongeldig nummer." }
        if status != .ok { LogStore.shared.app("Bellen terwijl niet aangemeld: \(status)") }
        do {
            let params = try core.createCallParams(call: nil)
            guard core.inviteAddressWithParams(addr: addr, params: params) != nil else { return "Bellen mislukt." }
            LogStore.shared.app("Bellen naar \(n)")
            return nil
        } catch {
            LogStore.shared.appError("Bellen mislukt: \(error)")
            return "Bellen mislukt."
        }
    }

    /// Ophangen van het gesprek op het scherm. Tijdens overleg: alleen het overleggesprek; de beller komt terug.
    func hangup() {
        guard let c = current else { return }
        do {
            if c.state == .IncomingReceived { try c.decline(reason: .Declined) } else { try c.terminate() }
        } catch {
            LogStore.shared.appError("Ophangen mislukt: \(error)")
        }
    }

    func answer() {
        Task {
            guard await AudioPermission.request() else {
                LogStore.shared.appError("Opnemen: geen toegang tot de microfoon")
                return
            }
            do { try current?.accept() } catch { LogStore.shared.appError("Opnemen mislukt: \(error)") }
        }
    }

    func toggleMute() {
        guard let c = current else { return }
        c.microphoneMuted.toggle()
        call?.muted = c.microphoneMuted
    }

    func toggleSpeaker() {
        guard let c = current, let core else { return }
        let wanted: AudioDevice.Kind = call?.speaker == true ? .Earpiece : .Speaker
        if let device = core.audioDevices.first(where: { $0.type == wanted && $0.hasCapability(capability: .CapabilityPlay) }) {
            c.outputAudioDevice = device
        }
        call?.speaker = c.outputAudioDevice?.type == .Speaker
    }

    func sendDtmf(_ digit: Character) {
        guard let c = current, let ascii = digit.asciiValue else { return }
        do { try c.sendDtmf(dtmf: CChar(ascii)) } catch { LogStore.shared.appError("DTMF mislukt: \(error)") }
    }

    // MARK: Wacht en doorverbinden (zoals CallActivity.kt en phone.consult() in web/src/store.ts)

    /// Het gesprek dat in de wacht staat tijdens overleg; nil = geen overleg.
    private(set) var heldCall: CallInfo?
    private var held: Call?
    /// Tekst voor het einde van een doorverbonden gesprek; voorkomt ook dat de beller wordt hervat.
    private var transferNote: String?

    func toggleHold() {
        guard let c = current, held == nil else { return }
        do {
            if c.state == .Paused { try c.resume() } else { try c.pause() }
        } catch {
            LogStore.shared.appError("Wacht mislukt: \(error)")
        }
    }

    /// Direct (blind) doorverbinden: de beller gaat meteen naar het andere toestel.
    func transferDirect(to target: String) {
        let n = Account.clean(target)
        guard let c = current, let core, !n.isEmpty,
              let addr = core.interpretUrl(url: n, applyInternationalPrefix: false) else { return }
        let to = label(addr).name
        LogStore.shared.app("Direct doorverbinden: \(call?.name ?? "?") → \(n)")
        transferNote = "Doorverbonden met \(to)"
        do {
            try c.transferTo(referTo: addr)
        } catch {
            transferNote = nil
            LogStore.shared.appError("Doorverbinden mislukt: \(error)")
        }
    }

    /// Overleg: eerst de beller echt in de wacht (pas na bevestiging), dan zelf het andere toestel bellen.
    /// Lukt bellen niet, dan komt de beller meteen terug.
    func consult(_ target: String) async -> String? {
        guard let c = current, held == nil else { return nil }
        if c.state != .Paused {
            do { try c.pause() } catch { return "De beller kon niet in de wacht worden gezet." }
        }
        for _ in 0..<50 where c.state != .Paused { try? await Task.sleep(for: .milliseconds(100)) }
        guard c.state == .Paused else {
            LogStore.shared.appError("Overleg: beller staat na 5 s nog niet in de wacht (\(c.state))")
            try? c.resume()
            return "De beller kon niet in de wacht worden gezet."
        }
        LogStore.shared.app("Overleg gestart: \(call?.name ?? "?") in de wacht, bellen naar \(target)")
        held = c
        heldCall = call
        current = nil
        if let error = await invite(target) {
            current = c
            held = nil
            call = heldCall
            heldCall = nil
            try? c.resume()
            return error
        }
        return nil
    }

    /// Na overleg: de wachtende beller doorverbinden met het overleggesprek.
    func completeTransfer() {
        guard let h = held, let c = current else { return }
        LogStore.shared.app("Doorverbinden (na overleg): \(heldCall?.name ?? "?") → \(call?.name ?? "?")")
        transferNote = "Doorverbonden met \(call?.name ?? "collega")"
        do {
            try h.transferToAnother(dest: c)
        } catch {
            transferNote = nil
            LogStore.shared.appError("Doorverbinden mislukt: \(error)")
        }
    }

    /// Wisselen tussen het overleggesprek en de wachtende beller.
    func swap() {
        guard let h = held, let c = current else { return }
        try? c.pause()
        try? h.resume()
        held = c
        current = h
        let info = call
        call = heldCall
        heldCall = info
    }

    /// Naam bij een adres (zoals Sip.label() op Android): collegalijst, contacten van de iPhone,
    /// wat de centrale meestuurt, en anders het nummer.
    func label(_ address: linphonesw.Address?) -> (name: String, number: String) {
        let number = address?.username ?? address?.asStringUriOnly() ?? "?"
        let name = Colleagues.shared.name(for: number) ?? PhoneContacts.shared.name(for: number)
            ?? address?.displayName?.nilIfEmpty ?? number
        return (name, number)
    }

    private func callChanged(_ c: Call, _ state: Call.State, _ message: String) {
        LogStore.shared.app("Gesprek: \(state) \"\(message)\"")
        if c === held {
            heldChanged(c, state)
            return
        }
        let isNew = current == nil
        if isNew {
            current = c
        } else if current !== c {
            waitingChanged(c, state)
            return
        }

        let (name, number) = label(c.remoteAddress)
        var info = (!isNew ? call : nil) ?? CallInfo(name: name, number: number, incoming: c.dir == .Incoming)
        switch state {
        case .IncomingReceived: info.phase = .incoming
        case .OutgoingInit, .OutgoingProgress: info.phase = .dialing
        case .OutgoingRinging, .OutgoingEarlyMedia: info.phase = .ringing
        case .Connected, .StreamsRunning:
            info.phase = .active
            info.onHold = false
            if info.connectedAt == nil { info.connectedAt = Date() }
        case .Paused:
            info.onHold = true
        case .Error, .End:
            info.phase = .ended(transferNote ?? Self.endText(c, state))
        case .Released:
            record(c, name: info.name, number: info.number)
            current = nil
            if held == nil, let w = waiting {
                // Gesprek voorbij terwijl er een wisselgesprek overgaat: dat wordt nu het gewone inkomende gesprek.
                current = w
                call = waitingCall
                waiting = nil
                waitingCall = nil
                return
            }
            if let h = held {
                // Overleg voorbij: terug naar de beller (behalve als die net is doorverbonden).
                held = nil
                current = h
                call = heldCall
                heldCall = nil
                if transferNote == nil, h.state == .Paused {
                    LogStore.shared.app("Overleg beëindigd: beller hervat")
                    try? h.resume()
                }
                return
            }
            // Belscherm nog even laten staan met de reden ("In gesprek", "Doorverbonden met …").
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                if self.current == nil {
                    self.call = nil
                    self.transferNote = nil
                }
            }
            return
        default: break
        }
        info.muted = c.microphoneMuted
        info.speaker = c.outputAudioDevice?.type == .Speaker
        call = info
    }

    // MARK: Wisselgesprek (tweede inkomend gesprek tijdens een gesprek)

    /// Het wisselgesprek dat overgaat; nil = geen.
    private(set) var waitingCall: CallInfo?
    private var waiting: Call?

    /// Opnemen: het huidige gesprek eerst echt in de wacht (zoals bij overleg), dan het wisselgesprek aannemen.
    /// Daarna werkt de overlegbalk: Wissel, Verbind door, of ophangen (dan komt de eerste beller terug).
    func answerWaiting() async {
        guard let w = waiting, let c = current, held == nil else { return }
        guard await AudioPermission.request() else { return }
        if c.state != .Paused { try? c.pause() }
        for _ in 0..<50 where c.state != .Paused { try? await Task.sleep(for: .milliseconds(100)) }
        guard c.state == .Paused, waiting === w else {
            LogStore.shared.appError("Wisselgesprek: huidige gesprek kon niet in de wacht")
            try? c.resume()
            return
        }
        LogStore.shared.app("Wisselgesprek aangenomen: \(call?.name ?? "?") in de wacht")
        held = c
        heldCall = call
        current = w
        call = waitingCall
        waiting = nil
        waitingCall = nil
        do { try w.accept() } catch { LogStore.shared.appError("Opnemen mislukt: \(error)") }
    }

    func declineWaiting() {
        guard let w = waiting else { return }
        do { try w.decline(reason: .Declined) } catch { LogStore.shared.appError("Weigeren mislukt: \(error)") }
    }

    private func waitingChanged(_ c: Call, _ state: Call.State) {
        if state == .IncomingReceived {
            // Eén wisselgesprek tegelijk, en niet tijdens overleg: anders bezet.
            guard waiting == nil, held == nil else {
                try? c.decline(reason: .Busy)
                return
            }
            let (name, number) = label(c.remoteAddress)
            waiting = c
            waitingCall = CallInfo(name: name, number: number, incoming: true, phase: .incoming)
            LogStore.shared.app("Wisselgesprek van \(number)")
            // Geen tweede beltoon, alleen een korte tril (zoals op Android).
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
            return
        }
        guard c === waiting else { return }
        switch state {
        case .End, .Error:
            waitingCall?.phase = .ended("Wisselgesprek gemist")
        case .Released:
            if let info = waitingCall { record(c, name: info.name, number: info.number) }
            waiting = nil
            waitingCall = nil
        default: break
        }
    }

    /// Uitkomst van een doorverbinding (REFER). Mislukt: melding, en de beller blijft gewoon verbonden.
    private func transferChanged(_ c: Call, _ state: Call.State) {
        switch state {
        case .Connected:
            LogStore.shared.app("Doorverbinden gelukt")
        case .Error:
            LogStore.shared.appError("Doorverbinden mislukt")
            transferNote = nil
            if c === current { call?.notice = "Doorverbinden mislukt" } else { heldCall?.notice = "Doorverbinden mislukt" }
        default: break
        }
    }

    /// De wachtende beller tijdens overleg: hangt die op, dan verdwijnt de wachtbalk.
    private func heldChanged(_ c: Call, _ state: Call.State) {
        switch state {
        case .Paused: heldCall?.onHold = true
        case .StreamsRunning: heldCall?.onHold = false
        case .Error, .End:
            if transferNote == nil { LogStore.shared.app("Beller in de wacht heeft opgehangen") }
        case .Released:
            if let info = heldCall { record(c, name: info.name, number: info.number) }
            held = nil
            heldCall = nil
        default: break
        }
    }

    private func record(_ c: Call, name: String, number: String) {
        guard let log = c.callLog else { return }
        let kind: History.Entry.Kind
        switch (log.dir, log.status) {
        case (.Outgoing, _): kind = .outgoing
        case (.Incoming, .Success): kind = .incoming
        case (.Incoming, .AcceptedElsewhere): kind = .elsewhere
        case (.Incoming, .Declined), (.Incoming, .DeclinedElsewhere): kind = .declined
        default: kind = .missed
        }
        History.shared.add(.init(number: number, name: name, kind: kind,
                                 date: Date(timeIntervalSince1970: TimeInterval(log.startDate)), duration: log.duration))
    }

    private static func endText(_ c: Call, _ state: Call.State) -> String {
        guard state == .Error || c.duration == 0, let e = c.errorInfo, e.protocolCode >= 400 else { return "Gesprek beëindigd" }
        switch e.protocolCode {
        case 486, 600: return "In gesprek"
        case 404, 484: return "Nummer niet gevonden"
        case 480: return "Niet bereikbaar"
        case 603: return "Geweigerd"
        default: return "Mislukt: \(e.protocolCode) \(e.phrase ?? "")"
        }
    }

    private func registrationChanged(_ account: linphonesw.Account, _ state: RegistrationState, _ message: String) {
        guard account === core?.defaultAccount else { return }
        let log = LogStore.shared
        switch state {
        case .Ok:
            status = .ok
            log.app("Registratie: aangemeld (\(message))")
        case .Progress, .Refreshing:
            if status != .ok { status = .progress }
        case .Failed:
            let code = account.errorInfo?.protocolCode ?? 0
            let phrase = account.errorInfo?.phrase ?? message
            status = .failed(code: code, text: phrase)
            log.appError("Registratie mislukt: SIP \(code) \(phrase)" + Self.explain(code, message))
        case .Cleared, .None:
            status = .none
            log.app("Registratie: afgemeld")
        }
    }

    /// Uitleg in gewone taal bij de meest voorkomende registratiefouten (zoals Sip.explain() op Android).
    static func explain(_ code: Int, _ message: String) -> String {
        switch code {
        case 401, 407: return " → Wachtwoord of toestel wordt niet geaccepteerd."
        case 403: return " → Geweigerd: verkeerd wachtwoord, of dit IP-adres is niet toegestaan."
        case 404: return " → Toestel bestaat niet in dit domein."
        case 408: return " → Geen antwoord van de server: verkeerd transport/poort, of firewall."
        case 503: return " → Server niet beschikbaar of niet bereikbaar."
        case 0: return " → Geen verbinding met de server (adres, netwerk, transport of poort)."
        default: return ""
        }
    }
}

extension Transport {
    var linphone: TransportType {
        switch self {
        case .udp: .Udp
        case .tcp: .Tcp
        case .tls: .Tls
        }
    }
}
