import AVFAudio
import Foundation

/// Wat het belscherm van het lopende gesprek laat zien (los van de Linphone-objecten).
struct CallInfo: Equatable {
    enum Phase: Equatable {
        case incoming
        case dialing
        case ringing
        case active
        case ended(String)
    }

    var name: String
    var number: String
    var incoming: Bool
    var phase: Phase = .dialing
    var connectedAt: Date?
    var onHold = false
    /// Korte melding op het belscherm, bijv. "Doorverbinden mislukt".
    var notice: String?
    var muted = false
    var speaker = false
}

/// Microfoontoestemming: pas vragen als er gebeld wordt (zoals de Android-app).
enum AudioPermission {
    static func request() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: true
        case .denied: false
        default: await AVAudioApplication.requestRecordPermission()
        }
    }
}
