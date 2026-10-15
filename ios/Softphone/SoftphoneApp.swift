import SwiftUI

/// Wortel van de app: thema toepassen (kleur, licht/donker); bij een ander thema alles opnieuw opbouwen,
/// zodat ook de navigatie- en tabbalken van UIKit het nieuwe lettertype krijgen.
struct ThemedRoot: View {
    private let themes = ThemeStore.shared

    var body: some View {
        ContentView()
            .tint(Theme.accent)
            .preferredColorScheme(themes.current.scheme)
            .id(themes.current.kind)
    }
}

@main
struct SoftphoneApp: App {
    @State private var session = Session()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        SipManager.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            ThemedRoot()
                .environment(session)
                .task { session.resume() }
        }
        .onChange(of: scenePhase) { _, phase in
            // iOS verbreekt de verbinding op de achtergrond: bij terugkomen opnieuw aanmelden.
            if phase == .active {
                SipManager.shared.refresh()
                Colleagues.shared.wake()
            }
        }
    }
}
