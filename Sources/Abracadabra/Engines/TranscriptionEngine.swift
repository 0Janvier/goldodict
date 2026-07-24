import AVFoundation
import Foundation

/// Contrat auquel se plient tous les moteurs de transcription.
///
/// La différence de nature entre les moteurs est absorbée ici plutôt que chez
/// l'appelant : Apple diffuse ses résultats au fil de l'eau et ignore l'audio
/// accumulé, Whisper accumule et ne produit son texte qu'à la fin. Dans les deux
/// cas le contrôleur voit la même séquence — `start`, une suite de `feed`, `finish`.
protocol TranscriptionEngine: AnyObject, Sendable {

    /// Identifiant stable, utilisé pour la persistance du choix de l'utilisateur.
    var identifier: String { get }

    /// Nom affiché dans le menu et les réglages.
    var displayName: String { get }

    /// Format audio réclamé par le moteur.
    func preferredAudioFormat() async -> AVAudioFormat

    /// Prépare une session de transcription.
    /// - Parameter contextualStrings: vocabulaire dont le moteur doit tenir compte
    ///   en amont — noms propres, termes de procédure — afin de ne pas avoir à
    ///   corriger après coup ce qu'il pouvait reconnaître correctement.
    func start(locale: Locale, contextualStrings: [String]) async throws

    /// Livre un tampon au format rendu par `preferredAudioFormat()`.
    func feed(_ buffer: AVAudioPCMBuffer) async

    /// Clôt la session et rend le texte transcrit.
    func finish() async throws -> String

    /// Abandonne la session en cours sans produire de texte.
    func cancel() async
}

enum TranscriptionEngineError: LocalizedError {
    case unavailable(String)
    case localeUnsupported(String)
    case assetsMissing(String)
    case notStarted
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let engine):
            return "moteur \(engine) indisponible sur cet ordinateur"
        case .localeUnsupported(let locale):
            return "langue non prise en charge : \(locale)"
        case .assetsMissing(let locale):
            return "modèle de reconnaissance \(locale) non installé"
        case .notStarted:
            return "aucune session de transcription en cours"
        case .failed(let detail):
            return detail
        }
    }
}
