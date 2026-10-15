import SwiftUI

/// Hoofdscherm: tabbladen Kiezen / Toestellen / Historie / Account (zoals MainActivity), en het belscherm
/// over alles heen zolang er een gesprek is.
struct ContentView: View {
    @Environment(Session.self) private var session
    private let sip = SipManager.shared

    var body: some View {
        if session.loggedIn {
            TabView {
                DialerView()
                    .tabItem { Label("Kiezen", systemImage: "circle.grid.3x3.fill") }
                ContactsView()
                    .tabItem { Label("Toestellen", systemImage: "person.2.fill") }
                HistoryView()
                    .tabItem { Label("Historie", systemImage: "clock.fill") }
                    .badge(missedBadge)
                NavigationStack { StatusView() }
                    .tabItem { Label("Account", systemImage: "person.crop.circle") }
            }
            .fullScreenCover(isPresented: .constant(sip.call != nil)) {
                if let info = sip.call { CallView(info: info, held: sip.heldCall, waiting: sip.waitingCall) }
            }
        } else {
            LoginView()
        }
    }

    /// Gemiste gesprekken sinds het laatste uitgaande of opgenomen gesprek.
    private var missedBadge: Int {
        History.shared.entries.prefix { $0.kind == .missed }.count
    }
}

struct StatusView: View {
    @Environment(Session.self) private var session
    private let sip = SipManager.shared

    var body: some View {
        List {
            Section("Centrale") {
                HStack(spacing: 12) {
                    Circle().fill(color).frame(width: 12, height: 12)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.headline)
                        if let detail { Text(detail).font(.subheadline).foregroundStyle(Theme.grey) }
                    }
                }
                .accessibilityIdentifier("status")
                Button("Opnieuw aanmelden") { sip.refresh() }
            }
            Section("Weergave") {
                Picker("Thema", selection: Binding(
                    get: { ThemeStore.shared.current.kind },
                    set: { ThemeStore.shared.current = AppTheme.of($0) })) {
                    ForEach(AppTheme.Kind.allCases) { Text(AppTheme.of($0).name).tag($0) }
                }
            }
            Section("Beheerserver") {
                Text(session.beheerRole.map { "Verbonden (\($0))" } ?? "Niet verbonden: collegastatus volgt later")
                    .foregroundStyle(session.beheerRole == nil ? Theme.grey : .primary)
            }
            Section {
                NavigationLink("Logboek en verbinding testen") { LogView() }
                NavigationLink("Over deze app") { AboutView() }
                Button("Uitloggen", role: .destructive) { Task { await session.logout() } }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bgAlt)
        .navigationTitle("Softphone")
    }

    private var title: String {
        switch sip.status {
        case .ok: "Aangemeld als \(sip.account?.address ?? "")"
        case .progress: "Bezig met aanmelden…"
        case .failed: "Niet aangemeld"
        case .none: "Offline"
        }
    }

    private var detail: String? {
        switch sip.status {
        case .failed(let code, let text): "SIP \(code) \(text)" + SipManager.explain(code, text)
        case .ok, .progress: sip.account.map { "via \($0.server) (\($0.transport.rawValue))" }
        case .none: nil
        }
    }

    private var color: Color {
        switch sip.status {
        case .ok: Theme.ok
        case .progress: Theme.accent
        case .failed: Theme.error
        case .none: Theme.grey
        }
    }
}

/// Logboek met delen (zoals LogActivity op Android): wat de app deed, en het SIP-log van Linphone.
struct LogView: View {
    private let store = LogStore.shared
    @State private var showSip = false
    @State private var sipText = ""
    @State private var testing = false

    var body: some View {
        VStack(spacing: 0) {
            Button {
                testing = true
                showSip = false
                Task {
                    await Diagnostics.run()
                    testing = false
                }
            } label: {
                if testing {
                    HStack(spacing: 8) { ProgressView().tint(.white); Text("Bezig met testen…") }
                } else {
                    Label("Verbinding testen", systemImage: "stethoscope")
                }
            }
            .buttonStyle(PillButtonStyle())
            .disabled(testing)
            .padding([.horizontal, .top])

            Picker("Logboek", selection: $showSip) {
                Text("App").tag(false)
                Text("SIP").tag(true)
            }
            .pickerStyle(.segmented)
            .padding()

            ScrollViewReader { proxy in
                if showSip {
                    ScrollView {
                        Text(sipText.suffix(60_000))
                            .font(.system(size: 10, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                        Color.clear.frame(height: 1).id("end")
                    }
                    .onAppear { proxy.scrollTo("end", anchor: .bottom) }
                } else {
                    List(store.entries) { e in
                        Text(e.text)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(e.kind == .error ? Theme.error : .primary)
                            .id(e.id)
                    }
                    .listStyle(.plain)
                    .onAppear { if let last = store.entries.last { proxy.scrollTo(last.id, anchor: .bottom) } }
                    .onChange(of: store.entries.count) { if let last = store.entries.last { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }
        }
        .navigationTitle("Logboek")
        .toolbar { ShareLink(item: "\(store.text)\n\n=== SIP ===\n\(sipText)") }
        .onAppear { sipText = LogStore.sipLogText() }
        .onChange(of: showSip) { if showSip { sipText = LogStore.sipLogText() } }
    }
}
