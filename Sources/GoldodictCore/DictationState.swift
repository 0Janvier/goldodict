import Foundation

/// Manière dont la dictée en cours a été déclenchée.
public enum TriggerMode: Equatable, Sendable {
    /// Le raccourci est maintenu enfoncé, la dictée s'arrête au relâchement.
    case pushToTalk
    /// Un appui bref a démarré la dictée, un second appui l'arrêtera.
    case toggle
}

/// Compte rendu d'une insertion réussie.
///
/// L'utilisateur ne voit pas le texte partir : il regarde son document, pas la
/// pastille. Le compte de signes et le nom de l'application lui confirment que la
/// dictée est arrivée là où il l'attendait, et non dans la fenêtre d'à côté.
public struct Insertion: Equatable, Sendable {
    public let characters: Int
    /// Nom de l'application visée, tel que le Finder l'affiche.
    public let application: String?
    /// Renseigné quand la correction n'a pas été appliquée. Le texte est inséré
    /// quand même, mais l'avocat doit savoir qu'il n'a pas été relu.
    public let note: String?

    public init(characters: Int, application: String? = nil, note: String? = nil) {
        self.characters = characters
        self.application = application
        self.note = note
    }

    /// « 312 signes · Pages », ou « 312 signes » si l'application est inconnue.
    public var summary: String {
        let count = "\(characters) signe\(characters > 1 ? "s" : "")"
        guard let application, !application.isEmpty else { return count }
        return "\(count) · \(application)"
    }
}

/// État de la machine de dictée. Une seule dictée peut être active à la fois.
public enum DictationState: Equatable, Sendable {
    case idle
    case recording(TriggerMode)
    case transcribing
    /// Le texte transcrit passe au correcteur local.
    case correcting
    case injecting
    /// Le texte est arrivé dans l'application visée.
    case inserted(Insertion)
    case failed(String)

    public var isBusy: Bool {
        switch self {
        case .idle, .inserted, .failed: return false
        case .recording, .transcribing, .correcting, .injecting: return true
        }
    }

    /// L'état mérite-t-il de rester affiché quelques secondes ?
    public var isTransient: Bool {
        switch self {
        case .inserted, .failed: return true
        default: return false
        }
    }

    /// L'utilisateur parle-t-il en ce moment ? Seul cas où le niveau sonore et le
    /// chronomètre ont un sens.
    public var isRecording: Bool {
        if case .recording = self { return true }
        return false
    }

    /// Symbole SF de repli, quand l'icône dessinée n'est pas disponible.
    public var symbolName: String {
        switch self {
        case .idle: return "mic"
        case .recording: return "mic.fill"
        case .transcribing: return "waveform"
        case .correcting: return "wand.and.sparkles"
        case .injecting: return "text.cursor"
        case .inserted: return "checkmark.circle"
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
        case .correcting: return "Relecture…"
        case .injecting: return "Insertion…"
        case .inserted(let insertion): return "\(insertion.summary) inséré"
        case .failed(let message): return "Erreur : \(message)"
        }
    }

    /// Libellé de la pastille, qui tient sur une seule ligne : ce qui dépasse est de
    /// l'information que l'utilisateur n'a pas le temps de lire.
    public var pillTitle: String {
        switch self {
        case .idle: return "Prêt"
        case .recording: return "J'écoute"
        case .transcribing: return "Transcription"
        case .correcting: return "Relecture"
        case .injecting: return "Insertion"
        case .inserted(let insertion): return insertion.note ?? insertion.summary
        case .failed(let message): return message
        }
    }
}
