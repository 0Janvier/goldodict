import Foundation

/// Surveille l'absence prolongée de signal pendant une capture.
///
/// Un blanc de deux secondes au milieu d'une phrase est ordinaire, trois secondes
/// sans rien du tout ne le sont plus. La distinction ne se lit pas dans le niveau,
/// qui ne dit jamais depuis combien de temps il est nul, mais dans une horloge.
///
/// Le temps est passé par l'appelant plutôt que lu ici. La montre devient testable
/// sans rien attendre, et chaque surface qui l'utilise garde sa propre cadence.
public struct SilenceWatch {

    /// Seuil d'audibilité, appliqué au niveau lissé et normalisé que rend `AudioLevel`.
    /// En dessous, la barre est à plat et rien n'a été entendu.
    public static let defaultAudibleLevel: Float = 0.05

    /// Passé ce délai sans rien, l'enregistrement n'est plus une pause dans la phrase
    /// mais un micro muet, et il faut le dire.
    public static let defaultAlertDelay: TimeInterval = 3

    public let audibleLevel: Float
    public let alertDelay: TimeInterval

    public private(set) var isSilent = false

    private var lastAudibleAt: TimeInterval = 0

    public init(
        audibleLevel: Float = SilenceWatch.defaultAudibleLevel,
        alertDelay: TimeInterval = SilenceWatch.defaultAlertDelay
    ) {
        self.audibleLevel = audibleLevel
        self.alertDelay = alertDelay
    }

    /// Réarme la montre au début d'une capture.
    public mutating func begin(at time: TimeInterval) {
        lastAudibleAt = time
        isSilent = false
    }

    /// Absorbe un relevé de niveau.
    ///
    /// - Returns: `true` au seul instant où le silence est déclaré, une fois par
    ///   épisode. Ce front vaut mieux que l'état pour qui ne doit réagir qu'une fois,
    ///   comme relire le nom du périphérique d'entrée, trop coûteux à chaque image.
    @discardableResult
    public mutating func absorb(level: Float, at time: TimeInterval) -> Bool {
        if level > audibleLevel { lastAudibleAt = time }
        let wasSilent = isSilent
        isSilent = time - lastAudibleAt > alertDelay
        return isSilent && !wasSilent
    }
}
