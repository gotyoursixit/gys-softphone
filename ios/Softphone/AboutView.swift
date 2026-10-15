import SwiftUI

/// "Over deze app": versie, waar de broncode staat en de licenties (GPLv3-voorwaarde: broncode aanbieden en
/// de licentie vermelden). Adressen staan hier op één plek.
enum AppLinks {
    /// Openbare repository met alleen de apps (app/ en ios/), zie tools/publish-apps.sh.
    static let source = URL(string: "https://github.com/gotyoursixit/gys-softphone")!
    static let privacy = URL(string: "https://bellen.gys-voip.nl/privacy.html")!
    static let support = URL(string: "mailto:support@gotyoursix.nl")!
    static let gpl = URL(string: "https://www.gnu.org/licenses/gpl-3.0.html")!
}

struct AboutView: View {
    private let sip = SipManager.shared
    @State private var showFonts = false

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Theme.label("Softphone")).font(Theme.font(.bold, size: 28, relativeTo: .title))
                    Text("Got Your Six · versie \(sip.version) (\(build))").foregroundStyle(Theme.grey)
                }
                .padding(.vertical, 4)
            }

            Section {
                Link(destination: AppLinks.source) { Label("Broncode op GitHub", systemImage: "chevron.left.forwardslash.chevron.right") }
                Link(destination: AppLinks.privacy) { Label("Privacyverklaring", systemImage: "hand.raised") }
                Link(destination: AppLinks.support) { Label("support@gotyoursix.nl", systemImage: "envelope") }
            }

            Section {
                Text("Deze app is vrije software: u mag hem gebruiken, bestuderen, aanpassen en doorgeven onder de voorwaarden van de GNU General Public License versie 3 (GPLv3). De app komt zonder enige garantie. De volledige broncode staat op GitHub (zie hierboven).")
                    .font(.footnote)
                Link("Tekst van de GPLv3", destination: AppLinks.gpl).font(.footnote)
            } header: {
                Text("Licentie")
            }

            Section("Gebruikte onderdelen") {
                credit("Linphone SDK", "Belledonne Communications · GPLv3", url: "https://www.linphone.org")
                credit("Lettertypes Poppins, Antonio, Orbitron en Exo 2", "SIL Open Font License 1.1") { showFonts = true }
                credit("Iconen (app-icoon)", "Material Icons, Google · Apache 2.0", url: "https://fonts.google.com/icons")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bgAlt)
        .navigationTitle("Over deze app")
        .sheet(isPresented: $showFonts) { LicenseText(title: "Lettertypes (OFL)", file: "OFL") }
    }

    private var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?" }

    @ViewBuilder
    private func credit(_ name: String, _ detail: String, url: String? = nil, action: (() -> Void)? = nil) -> some View {
        let label = VStack(alignment: .leading, spacing: 2) {
            Text(name).foregroundStyle(Theme.ink)
            Text(detail).font(.footnote).foregroundStyle(Theme.grey)
        }
        if let url, let u = URL(string: url) {
            Link(destination: u) { label }
        } else if let action {
            Button(action: action) { label }
        } else {
            label
        }
    }
}

/// Licentietekst uit de app (bijv. Fonts/OFL.txt), zodat die ook zonder internet te lezen is.
private struct LicenseText: View {
    let title: String
    let file: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(text)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding()
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Sluiten") { dismiss() } }
        }
    }

    private var text: String {
        let url = Bundle.main.url(forResource: file, withExtension: "txt")
            ?? Bundle.main.url(forResource: file, withExtension: "txt", subdirectory: "Fonts")
        return url.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? "Licentietekst niet gevonden."
    }
}
