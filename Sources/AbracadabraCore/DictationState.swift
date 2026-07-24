import Foundation

/// Manière dont la dictée en cours a été déclenchée.
public enum TriggerMode: Equatable, Sendable {
    /// Le raccourci est maintenu enfoncé, la dictée s'arrête au relâchement.
    case pushToTalk
    /// Un appui bref a démarré la dictée, un second appui l'arrêtera.
    case toggle
}

/// État de la machine de dictée. Une seule dictée peut être active à la fois.
public enum DictationState: Equatable, Sendable {
    case idle
    case recording(TriggerMode)
    case transcribing
    case injecting
    case failed(String)

    public var isBusy: Bool {
        switch self {
        case .idle, .failed: return false
        case .recording, .transcribing, .injecting: return true
        }
    }

    /// Symbole SF affiché dans la barre des menus.
    public var symbolName: String {
        switch self {
        case .idle: return "mic"
        case .recording: return "mic.fill"
        case .transcribing: return "waveform"
        case .injecting: return "text.cursor"
        case .failed: return "exclamationmark.triangle"
        }
    }

    /// Libellé affiché en tête du menu.
    public var label: String {
        switch self {
        case .idle: return "Prêt"
        case .recording(.pushToTalk): return "Dictée en cours (maintenu)"
        case .recording(.toggle): return "Dictée en cours"
        case .transcribing: return "Transcription…"
        case .injecting: return "Insertion…"
        case .failed(let message): return "Erreur : \(message)"
        }
    }
}
