import Foundation
import Security

/// SIP-transport, zoals in de Android-instellingen.
enum Transport: String, Codable, CaseIterable, Identifiable {
    case udp = "UDP", tcp = "TCP", tls = "TLS"
    var id: String { rawValue }
}

/// Accountinstellingen (zoals Prefs.kt). Inloggen gaat als toestel@domein; het domein bepaalt de klant.
struct Account: Codable, Equatable {
    /// Alle klanten registreren via dezelfde host (zie CLAUDE.md, "De centrale").
    static let defaultServer = "pbx01.gys-voip.nl"

    var user: String
    var domain: String
    var server: String = Account.defaultServer
    var port: String = ""
    var transport: Transport = .udp

    var address: String { "\(user)@\(domain)" }

    /// Onzichtbare tekens en spaties weg (zoals SettingsActivity.clean() op Android).
    static func clean(_ text: String) -> String {
        String(text.unicodeScalars.filter {
            !CharacterSet.whitespacesAndNewlines.contains($0) && !CharacterSet.controlCharacters.contains($0)
                && $0 != "\u{200B}" && $0 != "\u{200C}" && $0 != "\u{200D}" && $0 != "\u{FEFF}"
        })
    }

    /// "102@test.gys-voip.nl" (ook met sip:-voorvoegsel) → toestel en domein; nil als een van beide ontbreekt.
    static func parse(_ input: String) -> (user: String, domain: String)? {
        var s = clean(input)
        if s.lowercased().hasPrefix("sip:") { s.removeFirst(4) }
        let parts = s.split(separator: "@", maxSplits: 1).map(String.init)
        guard parts.count == 2, !parts[0].isEmpty, parts[1].contains(".") else { return nil }
        return (parts[0], parts[1].lowercased())
    }
}

/// Opslag: het account in UserDefaults, wachtwoord en token van de beheerserver in de Keychain.
enum Settings {
    private static let accountKey = "account"

    static var account: Account? {
        get {
            guard let data = UserDefaults.standard.data(forKey: accountKey) else { return nil }
            return try? JSONDecoder().decode(Account.self, from: data)
        }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: accountKey)
            } else {
                UserDefaults.standard.removeObject(forKey: accountKey)
            }
        }
    }

    static var password: String? {
        get { Keychain.get("password") }
        set { Keychain.set("password", newValue) }
    }

    static var beheerToken: String? {
        get { Keychain.get("beheerToken") }
        set { Keychain.set("beheerToken", newValue) }
    }

    /// Rol bij de beheerserver (gebruiker / klantbeheerder); nil = niet ingelogd bij de beheerserver.
    static var beheerRole: String? {
        get { UserDefaults.standard.string(forKey: "beheerRole") }
        set { UserDefaults.standard.set(newValue, forKey: "beheerRole") }
    }

    /// Laatst gebruikte serverinstellingen, ook na uitloggen (vult het inlogscherm).
    static var lastLogin: Account? {
        get {
            guard let data = UserDefaults.standard.data(forKey: "lastLogin") else { return nil }
            return try? JSONDecoder().decode(Account.self, from: data)
        }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: "lastLogin") }
    }
}

/// Minimale Keychain-toegang voor tekst (alleen op dit toestel, na de eerste ontgrendeling).
enum Keychain {
    private static let service = "nl.gotyoursix.softphone"

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ key: String, _ value: String?) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(base as CFDictionary)
        guard let value else { return }
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }
}

/// Rem op foute logins (zoals LOGIN_MAX_FAILURES in web/src/store.ts): Event Guard/fail2ban op de centrale
/// blokkeert anders het IP-adres van het hele kantoor. Na 3 fouten binnen 15 minuten niets meer naar de centrale.
enum LoginThrottle {
    static let maxFailures = 3
    static let lockMinutes = 15.0
    private static let key = "loginFailures"

    private static var recent: [Date] {
        let since = Date().addingTimeInterval(-lockMinutes * 60)
        return (UserDefaults.standard.array(forKey: key) as? [Date] ?? []).filter { $0 > since }
    }

    /// Minuten tot er weer geprobeerd mag worden; 0 = mag nu.
    static var minutesLeft: Int {
        let list = recent
        guard list.count >= maxFailures, let first = list.first else { return 0 }
        return max(1, Int((first.addingTimeInterval(lockMinutes * 60).timeIntervalSinceNow / 60).rounded(.up)))
    }

    static func noteFailure() { UserDefaults.standard.set(recent + [Date()], forKey: key) }
    static func clear() { UserDefaults.standard.removeObject(forKey: key) }
}
