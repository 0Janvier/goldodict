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

/// Consigne unique, partagée par les deux correcteurs.
///
/// Elle est volontairement restrictive. L'utilisateur a demandé une correction, pas
/// une réécriture : le modèle rétablit ce que l'oral perd — ponctuation, accents,
/// accords — et ne touche à rien d'autre. Le `CorrectionGuard` vérifie ensuite que
/// la consigne a été suivie, car une consigne ne garantit rien.
enum CorrectionPrompt {

    static let instructions = """
    Tu corriges une dictée vocale rédigée en français juridique.

    Tu rétablis la ponctuation, les accents et les accords grammaticaux. Tu \
    supprimes les hésitations (« euh », « alors »), les faux départs et les \
    répétitions involontaires.

    Tu ne reformules jamais. Tu ne remplaces aucun mot porteur de sens par un \
    synonyme. Tu n'ajoutes ni ne retires aucune idée, aucune nuance, aucune \
    réserve. Tu ne commentes pas.

    Tu réponds uniquement par le texte corrigé, sans préambule ni guillemets.
    """

    /// La consigne de base, complétée des règles apprises du profil courant.
    static func instructions(styleNotes: [String]) -> String {
        guard !styleNotes.isEmpty else { return instructions }
        let rules = styleNotes.map { "- \($0)" }.joined(separator: "\n")
        return instructions + "\n\nRègles supplémentaires, propres à ce contexte :\n" + rules
    }

    static func prompt(for text: String) -> String {
        "Texte dicté à corriger :\n\n\(text)"
    }
}
