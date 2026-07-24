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
    /// Le texte transcrit passe au correcteur local.
    case correcting
    case injecting
    /// Le texte a bien été inséré, mais un fait mérite d'être signalé : correction
    /// écartée, repli sur un autre modèle. Ce n'est pas une erreur.
    case notice(String)
    case failed(String)

    public var isBusy: Bool {
        switch self {
        case .idle, .notice, .failed: return false
        case .recording, .transcribing, .correcting, .injecting: return true
        }
    }

    /// L'état mérite-t-il de rester affiché quelques secondes ?
    public var isTransient: Bool {
        switch self {
        case .notice, .failed: return true
        default: return false
        }
    }

    /// Symbole SF affiché dans la barre des menus.
    public var symbolName: String {
        switch self {
        case .idle: return "mic"
        case .recording: return "mic.fill"
        case .transcribing: return "waveform"
        case .correcting: return "wand.and.sparkles"
        case .injecting: return "text.cursor"
        case .notice: return "info.circle"
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
        case .correcting: return "Correction…"
        case .injecting: return "Insertion…"
        case .notice(let message): return message
        case .failed(let message): return "Erreur : \(message)"
        }
    }
}
