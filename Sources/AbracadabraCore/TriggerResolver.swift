import Foundation

/// Traduit une suite d'appuis et de relâchements du raccourci en décisions de dictée.
///
/// Le geste est ambigu au moment de l'enfoncement : on ne sait pas encore si
/// l'utilisateur fait un appui bref (bascule) ou un appui maintenu (push-to-talk).
/// La capture démarre donc dès l'enfoncement, sans quoi le début de la phrase
/// serait perdu ; l'ambiguïté se lève au relâchement.
public struct TriggerResolver {

    public enum Decision: Equatable, Sendable {
        /// Démarrer la capture audio.
        case start(TriggerMode)
        /// La capture continue, mais elle est désormais en mode bascule.
        case switchToToggle
        /// Arrêter la capture et transcrire.
        case stop
        case none
    }

    private enum Phase: Equatable {
        case idle
        /// Touche enfoncée depuis le repos, geste encore indéterminé.
        case pressedFromIdle(since: TimeInterval)
        /// Dictée en cours en mode bascule, touche relâchée.
        case toggling
        /// Dictée en mode bascule, touche enfoncée pour l'arrêter.
        case pressedFromToggle
    }

    /// En deçà de ce seuil, l'appui est considéré comme bref.
    public let holdThreshold: TimeInterval

    private var phase: Phase = .idle

    public init(holdThreshold: TimeInterval = 0.25) {
        self.holdThreshold = holdThreshold
    }

    public var isDictating: Bool {
        phase != .idle
    }

    public mutating func keyDown(at time: TimeInterval) -> Decision {
        switch phase {
        case .idle:
            phase = .pressedFromIdle(since: time)
            return .start(.pushToTalk)
        case .toggling:
            phase = .pressedFromToggle
            return .stop
        case .pressedFromIdle, .pressedFromToggle:
            return .none
        }
    }

    public mutating func keyUp(at time: TimeInterval) -> Decision {
        switch phase {
        case .pressedFromIdle(let since):
            if time - since < holdThreshold {
                phase = .toggling
                return .switchToToggle
            }
            phase = .idle
            return .stop
        case .pressedFromToggle:
            phase = .idle
            return .none
        case .idle, .toggling:
            return .none
        }
    }

    /// Abandon d'une dictée en cours (perte de focus, erreur du moteur, arrêt manuel).
    public mutating func reset() {
        phase = .idle
    }
}
