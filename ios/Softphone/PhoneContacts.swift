import Contacts
import Foundation
import Observation

/// Contacten van de iPhone (zoals PhoneContacts.kt): lijst om te bellen en naam bij een nummer.
/// Toestemming wordt pas gevraagd als de gebruiker de contacten opent.
@Observable
final class PhoneContacts {
    static let shared = PhoneContacts()

    struct Contact: Identifiable, Sendable {
        let id: String
        let name: String
        let company: String
        /// (label, nummer), bijv. ("mobiel", "06 1234 5678").
        let numbers: [Number]

        struct Number: Hashable, Sendable {
            let label: String
            let value: String
        }
    }

    enum Access { case unknown, granted, denied }

    private(set) var access: Access = PhoneContacts.currentAccess
    private(set) var list: [Contact] = []
    private(set) var loading = false
    /// Laatste 9 cijfers → naam, voor naamherkenning van bellers.
    private var byNumber: [String: String] = [:]

    private static var currentAccess: Access {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized, .limited: .granted
        case .denied, .restricted: .denied
        default: .unknown
        }
    }

    private init() {
        if access == .granted { Task { await load() } }
    }

    /// Bij het openen van de contacten: zo nodig toestemming vragen, dan inlezen.
    func open() async {
        if access == .unknown {
            let ok = (try? await CNContactStore().requestAccess(for: .contacts)) ?? false
            access = ok ? .granted : .denied
            LogStore.shared.app("Contacten: toestemming \(ok ? "gegeven" : "geweigerd")")
        }
        if access == .granted, list.isEmpty { await load() }
    }

    func load() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        // Inlezen kan even duren bij veel contacten: niet op de hoofdthread.
        let contacts = await Task.detached(priority: .userInitiated) { Self.fetch() }.value
        list = contacts
        var map: [String: String] = [:]
        for c in contacts {
            for n in c.numbers {
                let key = Self.key(n.value)
                if key.count >= 6, map[key] == nil { map[key] = c.name }
            }
        }
        byNumber = map
    }

    /// Naam bij een nummer, of nil. Korte interne toestelnummers worden niet opgezocht.
    func name(for number: String) -> String? {
        let key = Self.key(number)
        guard key.count >= 6 else { return nil }
        return byNumber[key]
    }

    /// Vergelijken op de laatste 9 cijfers (zoals sameNumber() in de webapp): 06…, +316… en 00316… zijn dan gelijk.
    static func key(_ number: String) -> String {
        String(dialable(number).filter(\.isNumber).suffix(9))
    }

    /// "06 - 1234 5678" → "0612345678"; een + aan het begin blijft staan.
    static func dialable(_ number: String) -> String {
        let t = number.trimmingCharacters(in: .whitespaces)
        let digits = t.filter { $0.isNumber || $0 == "*" || $0 == "#" }
        return t.hasPrefix("+") ? "+" + digits : digits
    }

    private nonisolated static func fetch() -> [Contact] {
        let keys: [CNKeyDescriptor] = [
            CNContactGivenNameKey, CNContactFamilyNameKey, CNContactOrganizationNameKey, CNContactPhoneNumbersKey,
        ].map { $0 as CNKeyDescriptor }
        let request = CNContactFetchRequest(keysToFetch: keys)
        request.sortOrder = .userDefault
        var out: [Contact] = []
        try? CNContactStore().enumerateContacts(with: request) { c, _ in
            guard !c.phoneNumbers.isEmpty else { return }
            let full = [c.givenName, c.familyName].filter { !$0.isEmpty }.joined(separator: " ")
            let name = full.isEmpty ? c.organizationName : full
            guard !name.isEmpty else { return }
            let numbers = c.phoneNumbers.map {
                Contact.Number(label: CNLabeledValue<CNPhoneNumber>.localizedString(forLabel: $0.label ?? ""),
                               value: $0.value.stringValue)
            }
            out.append(Contact(id: c.identifier, name: name, company: full.isEmpty ? "" : c.organizationName, numbers: numbers))
        }
        return out
    }
}
