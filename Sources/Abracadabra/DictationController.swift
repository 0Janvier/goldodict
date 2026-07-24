import AbracadabraCore
import Foundation
import Observation

/// Chef d'orchestre de la dictée. Les couches concrètes (raccourci, audio, moteur,
/// insertion) seront branchées dans les lots suivants ; ce contrôleur ne connaîtra
/// jamais qu'un protocole de moteur, jamais un moteur particulier.
@Observable
@MainActor
final class DictationController {
    private(set) var state: DictationState = .idle
    private(set) var lastTranscript: String = ""

    /// Les vingt dernières dictées, en mémoire seule. Rien n'est écrit sur disque :
    /// ni l'audio, ni le texte, ce qui ferme la question du secret professionnel.
    private(set) var history: [String] = []
    private let historyLimit = 20

    func transition(to newState: DictationState) {
        state = newState
    }

    func record(transcript: String) {
        guard !transcript.isEmpty else { return }
        lastTranscript = transcript
        history.insert(transcript, at: 0)
        if history.count > historyLimit {
            history.removeLast(history.count - historyLimit)
        }
    }

    func clearHistory() {
        history.removeAll()
        lastTranscript = ""
    }
}
