import Foundation

/// Reconnaissance du double appui sur une touche modificatrice.
///
/// La fenêtre est fixée à trois cents millisecondes : en deçà le geste échoue chez
/// qui ne tape pas vite, au-delà deux appuis sans rapport finissent par se
/// rejoindre — enfoncer ⌘ pour ⌘C puis pour ⌘V lancerait une dictée.
public struct DoubleTapDetector: Equatable, Sendable {

    public static let defaultWindow: TimeInterval = 0.3

    public let window: TimeInterval

    private var lastPressAt: TimeInterval?

    public init(window: TimeInterval = DoubleTapDetector.defaultWindow) {
        self.window = window
    }

    /// Enregistre un appui et dit s'il complète un doublé.
    ///
    /// Le second appui d'un doublé n'ouvre jamais le suivant : sans cette remise à
    /// zéro, trois appuis rapides vaudraient deux déclenchements.
    public mutating func press(at time: TimeInterval) -> Bool {
        guard let previous = lastPressAt, time - previous <= window else {
            lastPressAt = time
            return false
        }
        lastPressAt = nil
        return true
    }

    /// Oublie l'appui en attente. À appeler dès qu'un autre geste s'intercale.
    public mutating func reset() {
        lastPressAt = nil
    }
}
