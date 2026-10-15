import SwiftUI

/// Belscherm (zoals CallActivity.kt, donker): naam, status/timer, dempen, toetsen, luidspreker, wacht,
/// doorverbinden (direct of overleg) en ophangen. Vanaf stap 3 neemt CallKit het binnenkomende scherm over.
struct CallView: View {
    let info: CallInfo
    /// De beller in de wacht tijdens overleg; nil = geen overleg.
    let held: CallInfo?
    /// Wisselgesprek dat overgaat; nil = geen.
    var waiting: CallInfo?
    private let sip = SipManager.shared
    @State private var showKeypad = false
    @State private var showTransfer = false
    @State private var dtmf = ""

    var body: some View {
        VStack(spacing: 20) {
            if let waiting { WaitingBanner(waiting: waiting, current: info) }
            if let held { ConsultBar(held: held, consult: info) }

            VStack(spacing: 6) {
                Text(info.name)
                    .font(Theme.font(.semibold, size: 34, relativeTo: .largeTitle))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                if info.name != info.number {
                    Text(info.number).font(.title3).foregroundStyle(Theme.callTextDim)
                }
                statusText
                    .font(Theme.font(.medium, size: 17, relativeTo: .headline))
                    .foregroundStyle(Theme.accent)
                    .accessibilityIdentifier("callStatus")
                if let notice = info.notice {
                    Text(notice).font(.subheadline).foregroundStyle(Theme.error)
                }
            }
            .padding(.top, held == nil && waiting == nil ? 60 : 12)

            Spacer()

            if showKeypad {
                Text(dtmf.isEmpty ? " " : dtmf).font(.title2.monospaced())
                DialpadView(dark: true) { key in
                    dtmf.append(key)
                    sip.sendDtmf(key)
                }
            } else if info.phase != .incoming {
                Grid(horizontalSpacing: 28, verticalSpacing: 24) {
                    GridRow {
                        RoundButton(icon: info.muted ? "mic.slash.fill" : "mic.fill", label: "Dempen", on: info.muted) { sip.toggleMute() }
                        RoundButton(icon: "circle.grid.3x3.fill", label: "Toetsen", on: false) { showKeypad = true }
                        RoundButton(icon: "speaker.wave.2.fill", label: "Luidspreker", on: info.speaker) { sip.toggleSpeaker() }
                    }
                    GridRow {
                        RoundButton(icon: "pause.fill", label: info.onHold ? "Hervatten" : "Wacht", on: info.onHold) { sip.toggleHold() }
                            .disabled(info.phase != .active || held != nil)
                        RoundButton(icon: "arrow.turn.up.right", label: "Doorverbinden", on: false) { showTransfer = true }
                            .disabled(info.phase != .active || held != nil)
                        Color.clear.frame(width: 72, height: 72)
                    }
                }
                .disabled(isEnded)
            }

            Spacer()

            if info.phase == .incoming {
                HStack(spacing: 80) {
                    CallButton(icon: "phone.down.fill", color: Theme.error, label: "Weigeren") { sip.hangup() }
                    CallButton(icon: "phone.fill", color: Theme.ok, label: "Opnemen") { sip.answer() }
                }
            } else {
                ZStack {
                    CallButton(icon: "phone.down.fill", color: Theme.error, label: "Ophangen") { sip.hangup() }
                    if showKeypad {
                        HStack {
                            Spacer()
                            Button(Theme.label("Verberg")) { showKeypad = false }.foregroundStyle(Theme.callText)
                        }
                        .frame(maxWidth: 300)
                    }
                }
                .opacity(isEnded ? 0.3 : 1)
                .disabled(isEnded)
            }
        }
        .padding(.bottom, 40)
        .padding(.horizontal)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(Theme.callText)
        .background(Theme.callBg.ignoresSafeArea())
        .sheet(isPresented: $showTransfer) { TransferSheet(caller: info) }
    }

    private var isEnded: Bool { if case .ended = info.phase { true } else { false } }

    @ViewBuilder private var statusText: some View {
        switch info.phase {
        case .incoming: Text("Inkomend gesprek")
        case .dialing: Text(held == nil ? "Bellen…" : "Overleg: bellen…")
        case .ringing: Text("Gaat over…")
        case .ended(let reason): Text(reason)
        case .active:
            if info.onHold {
                Text("In de wacht")
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text((held == nil ? "" : "Overleg · ") + Self.duration(from: info.connectedAt ?? context.date, to: context.date))
                        .monospacedDigit()
                }
            }
        }
    }

    static func duration(from start: Date, to now: Date) -> String {
        let s = max(0, Int(now.timeIntervalSince(start)))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// Wisselgesprek: wie er belt, en Weigeren / Opnemen (het huidige gesprek gaat dan in de wacht).
private struct WaitingBanner: View {
    let waiting: CallInfo
    let current: CallInfo
    private let sip = SipManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "phone.arrow.down.left.fill").foregroundStyle(Theme.ok)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Wisselgesprek: \(waiting.name)").font(Theme.font(.semibold, size: 15, relativeTo: .subheadline))
                    if case .ended(let reason) = waiting.phase {
                        Text(reason).font(.footnote).foregroundStyle(Theme.callTextDim)
                    } else if waiting.name != waiting.number {
                        Text(waiting.number).font(.footnote).foregroundStyle(Theme.callTextDim)
                    }
                }
                Spacer()
            }
            if waiting.phase == .incoming {
                HStack(spacing: 8) {
                    SmallPill(title: "Weigeren", color: Theme.error) { sip.declineWaiting() }
                    SmallPill(title: "Opnemen", color: Theme.ok) { Task { await sip.answerWaiting() } }
                        .disabled(current.phase != .active)
                }
                Text("Bij opnemen gaat \(current.name) in de wacht.").font(.footnote).foregroundStyle(Theme.callTextDim)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.callButton.opacity(0.6)))
        .padding(.top, 8)
    }
}

/// Balk tijdens overleg (zoals de overleg-balk in de webapp): wie er in de wacht staat, en Annuleer / Wissel / Verbind door.
private struct ConsultBar: View {
    let held: CallInfo
    let consult: CallInfo
    private let sip = SipManager.shared

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "pause.circle.fill").foregroundStyle(Theme.accent)
                Text("In de wacht: \(held.name)").font(Theme.font(.semibold, size: 15, relativeTo: .subheadline))
                Spacer()
            }
            HStack(spacing: 8) {
                SmallPill(title: "Annuleer", color: Theme.callButton) { sip.hangup() }
                SmallPill(title: "Wissel", color: Theme.callButton) { sip.swap() }
                    .disabled(consult.phase != .active)
                SmallPill(title: "Verbind door", color: Theme.ok) { sip.completeTransfer() }
                    .disabled(consult.phase != .active && consult.phase != .ringing)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.callButton.opacity(0.6)))
        .padding(.top, 8)
    }
}

private struct SmallPill: View {
    let title: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(Theme.label(title))
                .font(Theme.font(.semibold, size: 15, relativeTo: .subheadline))
                .foregroundStyle(Theme.callText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: min(ThemeStore.shared.current.buttonCorner, 22), style: .continuous).fill(color))
        }
    }
}

/// Doorverbinden: nummer intypen of een collega kiezen, en dan Direct of Overleg (zoals sheet_transfer op Android).
private struct TransferSheet: View {
    let caller: CallInfo
    private let sip = SipManager.shared
    private let colleagues = Colleagues.shared
    @Environment(\.dismiss) private var dismiss
    @State private var number = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Toestel of nummer", text: $number)
                        .keyboardType(.phonePad)
                    HStack {
                        Button("Direct") { direct(number) }
                            .buttonStyle(PillButtonStyle())
                        Button("Overleg") { consult(number) }
                            .buttonStyle(PillButtonStyle(color: Theme.grey))
                    }
                    .disabled(Account.clean(number).isEmpty)
                    .listRowSeparator(.hidden)
                } footer: {
                    Text("Direct: \(caller.name) gaat meteen door. Overleg: \(caller.name) gaat in de wacht en u spreekt eerst zelf met de collega.")
                }
                if let error {
                    Text(error).foregroundStyle(Theme.error)
                }
                Section("Collega's") {
                    if colleagues.list.isEmpty {
                        Text(colleagues.unavailable ?? "Geen collegalijst.").foregroundStyle(Theme.grey)
                    }
                    ForEach(colleagues.list.filter { $0.ext != sip.account?.user && $0.ext != caller.number }) { c in
                        HStack {
                            RowView(name: c.name.nilIfEmpty ?? c.ext, detail: c.ext, status: colleagues.status(c))
                            Button("Direct") { direct(c.ext) }
                                .buttonStyle(.bordered)
                            Button("Overleg") { consult(c.ext) }
                                .buttonStyle(.bordered)
                        }
                    }
                }
            }
            .navigationTitle("Doorverbinden")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Sluiten") { dismiss() } }
        }
        .tint(Theme.accent)
    }

    private func direct(_ target: String) {
        sip.transferDirect(to: target)
        dismiss()
    }

    private func consult(_ target: String) {
        Task {
            if let e = await sip.consult(target) {
                error = e
            } else {
                dismiss()
            }
        }
    }
}

private struct RoundButton: View {
    let icon: String
    let label: String
    let on: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(on ? Theme.callBg : Theme.callText)
                    .frame(width: 72, height: 72)
                    .background(RoundedRectangle(cornerRadius: Theme.keyCorner ?? 36, style: .continuous)
                        .fill(on ? Theme.callText : Theme.callButton))
                Text(Theme.label(label)).font(Theme.font(.medium, size: 12, relativeTo: .caption))
                    .foregroundStyle(Theme.callTextDim).lineLimit(1).fixedSize()
            }
        }
        .accessibilityLabel(label)
    }
}

private struct CallButton: View {
    let icon: String
    let color: Color
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title)
                .foregroundStyle(.white)
                .frame(width: 76, height: 76)
                .background(Circle().fill(color))
        }
        .accessibilityLabel(label)
    }
}
