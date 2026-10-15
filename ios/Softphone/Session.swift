import Foundation
import Observation

/// Inloggen en uitloggen. Volgorde zoals in docs/iOS-start.md: eerst de beheerserver (geen SIP-verkeer),
/// pas daarna registreren bij de centrale. Opgeslagen wordt alleen wat de centrale heeft geaccepteerd.
@Observable
final class Session {
    private(set) var loggedIn = Settings.account != nil && Settings.password != nil
    private(set) var busy = false
    /// Rol bij de beheerserver; nil = niet ingelogd bij de beheerserver (alleen de centrale).
    private(set) var beheerRole = Settings.beheerRole
    var error: String?

    private let sip = SipManager.shared
    private let log = LogStore.shared

    /// Bij het starten: met het opgeslagen account meteen de app tonen en op de achtergrond aanmelden.
    func resume() {
        guard let acc = Settings.account, let password = Settings.password else { return }
        sip.register(acc, password: password)
        Colleagues.shared.start()
        Task {
            if case .failed(let code, _) = await sip.waitForRegistration(), [401, 403, 407].contains(code) {
                LoginThrottle.noteFailure()
                await logout(message: "Aanmelden geweigerd door de centrale. Is het wachtwoord gewijzigd?")
            }
        }
    }

    func login(input: String, password: String, server: String, port: String, transport: Transport) async {
        error = nil
        guard let (user, domain) = Account.parse(input) else {
            error = "Vul in als toestel@domein, bijvoorbeeld 102@test.gys-voip.nl."
            return
        }
        guard !password.isEmpty else {
            error = "Vul het wachtwoord in."
            return
        }
        let wait = LoginThrottle.minutesLeft
        guard wait == 0 else {
            error = "Te vaak een fout wachtwoord. Wacht \(wait) min voor je het opnieuw probeert."
            return
        }
        let srv = Account.clean(server)
        let acc = Account(user: user, domain: domain, server: srv.isEmpty ? Account.defaultServer : srv,
                          port: Account.clean(port), transport: transport)
        Settings.lastLogin = acc
        busy = true
        defer { busy = false }

        switch await BeheerClient.login(user: user, domain: domain, password: password) {
        case .ok(let token, let role):
            Settings.beheerToken = token
            Settings.beheerRole = role
            beheerRole = role
            log.app("Beheerserver: ingelogd als \(acc.address) (\(role))")
        case .rejected(let message):
            log.appError("Beheerserver: \(message)")
            error = message
            return
        case .unavailable(let message):
            Settings.beheerToken = nil
            Settings.beheerRole = nil
            beheerRole = nil
            log.app("Beheerserver: \(message). Verder met alleen de centrale.")
        }

        sip.register(acc, password: password)
        switch await sip.waitForRegistration() {
        case .ok:
            LoginThrottle.clear()
            Settings.account = acc
            Settings.password = password
            loggedIn = true
            Colleagues.shared.start()
        case .failed(let code, let text) where [401, 403, 407].contains(code):
            sip.clear()
            LoginThrottle.noteFailure()
            error = "Toestel of wachtwoord onjuist (SIP \(code) \(text))."
        case .failed(let code, let text):
            sip.clear()
            error = "Kan de centrale niet bereiken (SIP \(code) \(text))."
        default:
            sip.clear()
            error = "Geen antwoord van de centrale binnen 15 seconden. Probeer een ander transport onder Serverinstellingen."
        }
    }

    func logout(message: String? = nil) async {
        sip.clear()
        Colleagues.shared.stop()
        if let token = Settings.beheerToken { await BeheerClient.logout(token: token) }
        Settings.beheerToken = nil
        Settings.beheerRole = nil
        Settings.account = nil
        Settings.password = nil
        beheerRole = nil
        loggedIn = false
        error = message
        log.app("Uitgelogd")
    }
}
