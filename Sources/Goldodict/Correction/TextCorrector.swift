import Foundation

/// Correcteur de dictée. Deux implémentations : le modèle embarqué d'Apple et,
/// en repli, un modèle servi par Ollama.
protocol TextCorrector: Sendable {
    var identifier: String { get }
    var displayName: String { get }

    /// Le correcteur est-il utilisable maintenant ?
    func isAvailable() async -> Bool

    /// Prépare le correcteur pour que la première correction ne soit pas la plus
    /// lente. Sans effet si le modèle est déjà prêt.
    func warmUp() async

    func correct(_ text: String, styleNotes: [String]) async throws -> String
}

enum CorrectionError: LocalizedError {
    case unavailable(String)
    /// Le modèle a refusé de traiter le contenu. Cas réel en matière pénale.
    case contentRefused(String)
    case timedOut
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let name): return "correcteur \(name) indisponible"
        case .contentRefused(let name): return "\(name) a refusé de traiter ce contenu"
        case .timedOut: return "correction trop lente"
        case .failed(let detail): return detail
        }
    }
}
