import CoreText
import Observation
import SwiftUI
import UIKit

/// Thema's zoals op Android (Themes.kt, res/values/themes.xml): Zakelijk (Got Your Six, standaard),
/// LCARS (Star Trek) en Star Wars-stijl. Kleuren, lettertypes, hoeken en hoofdletters zijn variabelen;
/// schermen gebruiken altijd `Theme.x`, nooit vaste kleuren. Geen officiële Star Wars-logo's of -lettertypes.
struct AppTheme: Identifiable, Equatable {
    enum Kind: String, CaseIterable, Identifiable {
        case gys, lcars, starwars
        var id: String { rawValue }
    }

    let kind: Kind
    let name: String
    let accent, accentDark, accentSoft, onAccent: Color
    let bg, bgAlt, surface, line: Color
    let ink, inkSoft, muted: Color
    let ok, okSoft, danger, dangerSoft: Color
    let callBg, callSurface, callButton, callText, callTextDim: Color
    /// PostScript-namen van de lettertypes (in Fonts/, OFL-licentie).
    let fontMedium, fontSemibold, fontBold: String
    /// 999 = pilvorm.
    let buttonCorner: CGFloat
    /// Hoek van de toetsen; nil = rond (zoals de iPhone).
    let keyCorner: CGFloat?
    let caps: Bool
    /// nil = volgt licht/donker van de iPhone.
    let scheme: ColorScheme?

    var id: Kind { kind }

    static func == (a: AppTheme, b: AppTheme) -> Bool { a.kind == b.kind }

    static func of(_ kind: Kind) -> AppTheme {
        switch kind {
        case .gys: gys
        case .lcars: lcars
        case .starwars: starWars
        }
    }

    /// Huisstijl gotyoursix.nl (CLAUDE.md); licht en donker zoals values/ en values-night/ op Android.
    static let gys = AppTheme(
        kind: .gys, name: "Zakelijk (Got Your Six)",
        accent: hex(0xF39200), accentDark: hex(0xD97E00), accentSoft: dyn(0xFFF4E3, 0x3A2A12), onAccent: .white,
        bg: dyn(0xFFFFFF, 0x1C1C1C), bgAlt: dyn(0xF6F7F9, 0x262626), surface: dyn(0xFFFFFF, 0x232323), line: dyn(0xE7E9EE, 0x363636),
        ink: dyn(0x2B2B2B, 0xF3F4F6), inkSoft: dyn(0x4A4A4A, 0xD1D5DB), muted: dyn(0x6B7280, 0x9CA3AF),
        ok: hex(0x1F9D55), okSoft: dyn(0xE6F6EC, 0x15301F), danger: hex(0xDC2626), dangerSoft: dyn(0xFDECEC, 0x3A1717),
        callBg: hex(0x262626), callSurface: hex(0x333333), callButton: hex(0x3D3D3D), callText: .white, callTextDim: hex(0xB9BCC4),
        fontMedium: "Poppins-Medium", fontSemibold: "Poppins-SemiBold", fontBold: "Poppins-Bold",
        buttonCorner: 999, keyCorner: nil, caps: false, scheme: nil)

    static let lcars = AppTheme(
        kind: .lcars, name: "LCARS (Star Trek)",
        accent: hex(0xFF9C00), accentDark: hex(0xFFCC99), accentSoft: hex(0x3D2A0F), onAccent: .black,
        bg: hex(0x000000), bgAlt: hex(0x15151C), surface: hex(0x0D0D12), line: hex(0x34343F),
        ink: hex(0xF5EBDD), inkSoft: hex(0xCC99CC), muted: hex(0x9C948A),
        ok: hex(0x66CC99), okSoft: hex(0x10261C), danger: hex(0xE05555), dangerSoft: hex(0x2E1212),
        callBg: hex(0x000000), callSurface: hex(0x1A1A22), callButton: hex(0x2B2336), callText: hex(0xFFCC99), callTextDim: hex(0xCC99CC),
        fontMedium: "Antonio-Regular", fontSemibold: "Antonio-SemiBold", fontBold: "Antonio-Bold",
        buttonCorner: 999, keyCorner: 22, caps: true, scheme: .dark)

    static let starWars = AppTheme(
        kind: .starwars, name: "Star Wars-stijl",
        accent: hex(0xFFE81F), accentDark: hex(0xFFE81F), accentSoft: hex(0x2A2608), onAccent: .black,
        bg: hex(0x04060A), bgAlt: hex(0x0D121A), surface: hex(0x0A0E14), line: hex(0x1E2A38),
        ink: hex(0xE8EEF5), inkSoft: hex(0x9FB3C8), muted: hex(0x6E7F91),
        ok: hex(0x2FE07A), okSoft: hex(0x0C2A18), danger: hex(0xFF3B3B), dangerSoft: hex(0x2E0D0D),
        callBg: hex(0x000000), callSurface: hex(0x0F1620), callButton: hex(0x18222E), callText: hex(0xE8EEF5), callTextDim: hex(0x4FA8FF),
        fontMedium: "Exo2-Regular_Medium", fontSemibold: "Orbitron-SemiBold", fontBold: "Orbitron-ExtraBold",
        buttonCorner: 4, keyCorner: 4, caps: true, scheme: .dark)

    private static func hex(_ v: UInt32) -> Color { Color(uiColor: ui(v)) }

    /// Kleur die meeschakelt met licht/donker van de iPhone.
    private static func dyn(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? ui(dark) : ui(light) })
    }

    private static func ui(_ v: UInt32) -> UIColor {
        UIColor(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
}

/// Het gekozen thema (bewaard in UserDefaults, zoals Prefs.theme op Android).
@Observable
final class ThemeStore {
    static let shared = ThemeStore()

    var current: AppTheme {
        didSet {
            UserDefaults.standard.set(current.kind.rawValue, forKey: "theme")
            applyUIKit()
        }
    }

    private init() {
        Self.registerFonts()
        current = AppTheme.of(AppTheme.Kind(rawValue: UserDefaults.standard.string(forKey: "theme") ?? "") ?? .gys)
        applyUIKit()
    }

    /// Lettertypes uit de app registreren (geen UIAppFonts nodig in de gegenereerde Info.plist).
    private static func registerFonts() {
        let urls = (Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? [])
            + (Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: "Fonts") ?? [])
        for url in urls { CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil) }
    }

    /// Titels van navigatie- en tabbalken: die tekent UIKit, dus daar het lettertype zetten.
    private func applyUIKit() {
        let t = current
        let large = UIFont(name: t.fontBold, size: 32) ?? .systemFont(ofSize: 32, weight: .bold)
        let small = UIFont(name: t.fontSemibold, size: 17) ?? .systemFont(ofSize: 17, weight: .semibold)
        let tab = UIFont(name: t.fontMedium, size: 10) ?? .systemFont(ofSize: 10, weight: .medium)
        let nav = UINavigationBar.appearance()
        nav.largeTitleTextAttributes = [.font: large]
        nav.titleTextAttributes = [.font: small]
        UITabBarItem.appearance().setTitleTextAttributes([.font: tab], for: .normal)
    }
}

/// Korte namen voor het huidige thema, zodat schermen `Theme.accent` enz. kunnen gebruiken.
/// SwiftUI tekent opnieuw zodra het thema wijzigt (ThemeStore is @Observable).
enum Theme {
    private static var t: AppTheme { ThemeStore.shared.current }

    static var accent: Color { t.accent }
    static var accentDark: Color { t.accentDark }
    static var accentSoft: Color { t.accentSoft }
    static var onAccent: Color { t.onAccent }
    static var bg: Color { t.bg }
    static var bgAlt: Color { t.bgAlt }
    static var line: Color { t.line }
    static var ink: Color { t.ink }
    static var grey: Color { t.muted }
    static var ok: Color { t.ok }
    static var error: Color { t.danger }
    static var callBg: Color { t.callBg }
    static var callButton: Color { t.callButton }
    static var callText: Color { t.callText }
    static var callTextDim: Color { t.callTextDim }
    static let radius: CGFloat = 14
    static var caps: Bool { t.caps }
    static var keyCorner: CGFloat? { t.keyCorner }

    enum Weight { case medium, semibold, bold }

    /// Lettertype van het thema dat meeschaalt met de tekstgrootte van de iPhone.
    static func font(_ weight: Weight, size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        let name = switch weight {
        case .medium: t.fontMedium
        case .semibold: t.fontSemibold
        case .bold: t.fontBold
        }
        return .custom(name, size: size, relativeTo: style)
    }

    /// Hoofdletters op knoppen en kopjes (LCARS, Star Wars-stijl).
    static func label(_ text: String) -> String { caps ? text.uppercased() : text }
}

/// Knop in de vorm van het thema (pil, of hoekig bij Star Wars-stijl) met tekst in de themakleur.
struct PillButtonStyle: ButtonStyle {
    var color: Color?

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.font(.semibold, size: 17, relativeTo: .headline))
            .textCase(Theme.caps ? .uppercase : nil)
            .foregroundStyle(color == nil ? Theme.onAccent : .white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: min(ThemeStore.shared.current.buttonCorner, 28), style: .continuous)
                    .fill(configuration.isPressed ? Theme.accentDark : (color ?? Theme.accent))
            )
    }
}
