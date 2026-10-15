import SwiftUI

/// Toetsenblok (zoals Dialpad.kt): lang op 0 = +. Gebruikt op het kiesscherm en voor DTMF in een gesprek.
struct DialpadView: View {
    var dark = false
    let onKey: (Character) -> Void

    private let keys: [(Character, String)] = [
        ("1", ""), ("2", "ABC"), ("3", "DEF"),
        ("4", "GHI"), ("5", "JKL"), ("6", "MNO"),
        ("7", "PQRS"), ("8", "TUV"), ("9", "WXYZ"),
        ("*", ""), ("0", "+"), ("#", ""),
    ]

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 20), count: 3), spacing: 16) {
            ForEach(keys, id: \.0) { key, letters in
                VStack(spacing: 0) {
                    Text(String(key)).font(Theme.font(.medium, size: 32, relativeTo: .largeTitle))
                    Text(letters).font(.caption2.weight(.semibold)).opacity(letters.isEmpty ? 0 : 0.6)
                }
                .foregroundStyle(dark ? Theme.callText : Theme.ink)
                .frame(width: 76, height: 76)
                .background(RoundedRectangle(cornerRadius: Theme.keyCorner ?? 38, style: .continuous)
                    .fill(dark ? Theme.callButton : Theme.bgAlt))
                .contentShape(Rectangle())
                .onTapGesture { onKey(key) }
                .onLongPressGesture(minimumDuration: 0.5) { onKey(key == "0" ? "+" : key) }
                .accessibilityLabel(String(key))
                .accessibilityAddTraits(.isButton)
            }
        }
        .frame(maxWidth: 300)
    }
}

/// Tabblad Kiezen: nummer intypen en bellen.
struct DialerView: View {
    private let sip = SipManager.shared
    @State private var number = ""
    @State private var error: String?

    var body: some View {
        VStack(spacing: 20) {
            StatusLine()
            Spacer()
            Text(number.isEmpty ? " " : number)
                .font(Theme.font(.medium, size: 36, relativeTo: .largeTitle))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.horizontal)
                .accessibilityIdentifier("number")
            if let error {
                Text(error).font(.footnote).foregroundStyle(Theme.error).multilineTextAlignment(.center)
            }
            DialpadView { key in
                number.append(key)
                error = nil
            }
            HStack {
                Color.clear.frame(width: 76, height: 76)
                Spacer()
                Button {
                    Task { error = await sip.dial(number) }
                } label: {
                    Image(systemName: "phone.fill")
                        .font(.title)
                        .foregroundStyle(.white)
                        .frame(width: 76, height: 76)
                        .background(Circle().fill(Theme.ok))
                }
                .disabled(number.isEmpty)
                .accessibilityLabel("Bellen")
                Spacer()
                Button {
                    if !number.isEmpty { number.removeLast() }
                } label: {
                    Image(systemName: "delete.left")
                        .font(.title2)
                        .foregroundStyle(Theme.grey)
                        .frame(width: 76, height: 76)
                }
                .opacity(number.isEmpty ? 0 : 1)
                .simultaneousGesture(LongPressGesture().onEnded { _ in number = "" })
                .accessibilityLabel("Wissen")
            }
            .frame(maxWidth: 300)
            Spacer(minLength: 12)
        }
        .padding()
        .background(Theme.bg.ignoresSafeArea())
    }
}

/// Kleine statusregel bovenaan (zoals het statuslabel in MainActivity).
struct StatusLine: View {
    private let sip = SipManager.shared

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).font(.footnote).foregroundStyle(Theme.grey)
        }
    }

    private var text: String {
        switch sip.status {
        case .ok: "Aangemeld als \(sip.account?.user ?? "")"
        case .progress: "Bezig met aanmelden…"
        case .failed: "Niet aangemeld"
        case .none: "Offline"
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
