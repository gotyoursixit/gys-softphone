import SwiftUI

/// Tabblad Historie: gemist / inkomend / uitgaand; tikken = terugbellen.
struct HistoryView: View {
    private let history = History.shared
    private let sip = SipManager.shared
    @State private var confirmClear = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                if history.entries.isEmpty {
                    Text("Nog geen gesprekken.").foregroundStyle(Theme.grey)
                }
                ForEach(history.entries) { e in
                    Button {
                        Task { error = await sip.dial(e.number) }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: Self.icon(e.kind))
                                .foregroundStyle(e.kind == .missed ? Theme.error : Theme.grey)
                                .frame(width: 20)
                            RowView(name: e.name, detail: Self.detail(e),
                                    nameColor: e.kind == .missed ? Theme.error : .primary,
                                    trailing: Self.when(e.date))
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle("Historie")
            .toolbar {
                if !history.entries.isEmpty {
                    Button("Wissen") { confirmClear = true }
                }
            }
            .confirmationDialog("Historie wissen?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Wissen", role: .destructive) { history.clear() }
            }
            .alert("Bellen", isPresented: .constant(error != nil)) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
        }
    }

    static func icon(_ kind: History.Entry.Kind) -> String {
        switch kind {
        case .outgoing: "phone.arrow.up.right"
        case .incoming, .elsewhere: "phone.arrow.down.left"
        case .missed: "phone.arrow.down.left.fill"
        case .declined: "phone.down"
        }
    }

    static func detail(_ e: History.Entry) -> String {
        let what: String = switch e.kind {
        case .outgoing: e.duration > 0 ? "Uitgaand" : "Uitgaand, niet opgenomen"
        case .incoming: "Inkomend"
        case .missed: "Gemist"
        case .declined: "Geweigerd"
        case .elsewhere: "Aangenomen door een collega"
        }
        let number = e.name == e.number ? "" : "\(e.number) · "
        let length = e.duration > 0 ? " · \(e.duration / 60):\(String(format: "%02d", e.duration % 60))" : ""
        return number + what + length
    }

    static func when(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return date.formatted(date: .omitted, time: .shortened) }
        if Calendar.current.isDateInYesterday(date) { return "gisteren" }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }
}
