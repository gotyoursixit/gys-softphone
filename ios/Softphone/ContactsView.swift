import SwiftUI

/// Tabblad Toestellen: collega's met live status van de beheerserver, en de contacten van de iPhone
/// (zoals het tabblad Toestellen op Android). Tikken = bellen.
struct ContactsView: View {
    enum Source: String, CaseIterable, Identifiable {
        case colleagues = "Collega's"
        case phone = "Contacten"
        var id: String { rawValue }
    }

    private let colleagues = Colleagues.shared
    private let phone = PhoneContacts.shared
    private let sip = SipManager.shared
    @State private var source = Source.colleagues
    @State private var search = ""
    @State private var error: String?
    /// Contact met meerdere nummers: eerst kiezen welk.
    @State private var choose: PhoneContacts.Contact?

    var body: some View {
        NavigationStack {
            List {
                Picker("Bron", selection: $source) {
                    ForEach(Source.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowSeparator(.hidden)

                switch source {
                case .colleagues: colleagueRows
                case .phone: phoneRows
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .searchable(text: $search, prompt: source == .colleagues ? "Zoek op naam of toestel" : "Zoek op naam of nummer")
            .navigationTitle("Toestellen")
            .refreshable {
                if source == .colleagues { colleagues.wake() } else { await phone.load() }
            }
            .task(id: source) { if source == .phone { await phone.open() } }
            .confirmationDialog(choose?.name ?? "", isPresented: .constant(choose != nil), titleVisibility: .visible) {
                ForEach(choose?.numbers ?? [], id: \.self) { n in
                    Button("\(n.label.isEmpty ? "" : n.label + ": ")\(n.value)") { dial(n.value) }
                }
                Button("Annuleer", role: .cancel) { choose = nil }
            }
            .alert("Bellen", isPresented: .constant(error != nil)) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
        }
    }

    @ViewBuilder private var colleagueRows: some View {
        if let reason = colleagues.unavailable {
            Text(reason).foregroundStyle(Theme.grey)
        } else if colleagues.list.isEmpty {
            HStack { ProgressView(); Text("Collega's ophalen…").foregroundStyle(Theme.grey) }
        } else if !colleagues.live {
            Text("De beheerserver ziet de centrale even niet: status onbekend.").font(.footnote).foregroundStyle(Theme.grey)
        }
        ForEach(filteredColleagues) { c in
            Button { dial(c.ext) } label: {
                RowView(name: c.name.nilIfEmpty ?? c.ext, detail: c.ext, status: colleagues.status(c))
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder private var phoneRows: some View {
        switch phone.access {
        case .denied:
            Text("Geen toegang tot uw contacten. Zet dit aan in Instellingen → Apps → Softphone → Contacten.")
                .foregroundStyle(Theme.grey)
        case .unknown:
            HStack { ProgressView(); Text("Toestemming vragen…").foregroundStyle(Theme.grey) }
        case .granted:
            if phone.loading && phone.list.isEmpty {
                HStack { ProgressView(); Text("Contacten inlezen…").foregroundStyle(Theme.grey) }
            } else if phone.list.isEmpty {
                Text("Geen contacten met een telefoonnummer.").foregroundStyle(Theme.grey)
            }
            ForEach(filteredPhone) { c in
                Button {
                    if c.numbers.count == 1 { dial(c.numbers[0].value) } else { choose = c }
                } label: {
                    RowView(name: c.name, detail: detail(c))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func dial(_ number: String) {
        choose = nil
        Task { error = await sip.dial(PhoneContacts.dialable(number)) }
    }

    private func detail(_ c: PhoneContacts.Contact) -> String {
        let first = c.numbers.first.map(\.value) ?? ""
        let more = c.numbers.count > 1 ? " (+\(c.numbers.count - 1))" : ""
        return [c.company, first + more].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// Eigen toestel weglaten (zoals de webapp).
    private var filteredColleagues: [Colleagues.Colleague] {
        let own = sip.account?.user
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return colleagues.list.filter { c in
            c.ext != own && (q.isEmpty || c.ext.contains(q) || c.name.lowercased().contains(q))
        }
    }

    private var filteredPhone: [PhoneContacts.Contact] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return phone.list }
        let digits = q.filter(\.isNumber)
        return phone.list.filter { c in
            c.name.lowercased().contains(q) || c.company.lowercased().contains(q)
                || (!digits.isEmpty && c.numbers.contains { $0.value.filter(\.isNumber).contains(digits) })
        }
    }
}

/// Lijstregel met initialen-avatar (zoals RowAdapter.kt).
struct RowView: View {
    let name: String
    let detail: String
    var status: Colleagues.Colleague.Status?
    var nameColor: Color = .primary
    var trailing: String?

    var body: some View {
        HStack(spacing: 12) {
            Text(Self.initials(name))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accentDark)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Theme.accentSoft))
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.body.weight(.medium)).foregroundStyle(nameColor).lineLimit(1)
                HStack(spacing: 6) {
                    if let status {
                        Circle().fill(Self.color(status)).frame(width: 8, height: 8)
                        Text("\(detail) · \(Self.text(status))")
                    } else {
                        Text(detail)
                    }
                }
                .font(.footnote)
                .foregroundStyle(Theme.grey)
            }
            Spacer()
            if let trailing { Text(trailing).font(.footnote).foregroundStyle(Theme.grey) }
        }
        .contentShape(Rectangle())
    }

    static func initials(_ name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap(\.first).map(String.init).joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }

    static func text(_ s: Colleagues.Colleague.Status) -> String {
        switch s {
        case .available: "Beschikbaar"
        case .ringing: "Gaat over"
        case .busy: "In gesprek"
        case .dnd: "Niet storen"
        case .offline: "Offline"
        case .unknown: "Onbekend"
        }
    }

    static func color(_ s: Colleagues.Colleague.Status) -> Color {
        switch s {
        case .available: Theme.ok
        case .ringing: Theme.accent
        case .busy, .dnd: Theme.error
        case .offline, .unknown: Theme.grey
        }
    }
}
