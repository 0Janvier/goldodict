import Foundation

/// Contexte de dossier actif : le vocabulaire éphémère transmis aux moteurs de
/// reconnaissance pendant qu'un dossier est sélectionné.
///
/// Les termes viennent des données du dossier (parties, client, juridiction,
/// numéro RG, avocats). Ils ne sont jamais persistés côté Goldodict : le dossier
/// se désélectionne, le vocabulaire disparaît.
public struct DossierContext: Equatable, Sendable, Identifiable {
    public let id: Int64
    public let code: String
    public let titre: String
    public let terms: [String]

    public init(id: Int64, code: String, titre: String, terms: [String]) {
        self.id = id
        self.code = code
        self.titre = titre
        self.terms = terms
    }
}

public enum DossierVocabulary {

    /// Les moteurs reçoivent le vocabulaire sous forme d'amorce textuelle : au-delà
    /// d'une quarantaine de termes, Whisper dilue l'amorce et n'en tire plus rien.
    public static let maxTerms = 40

    /// Un terme plus court que trois caractères biaiserait la reconnaissance de
    /// mots courants (« de », « la ») plus qu'il n'aiderait un nom propre.
    public static let minTermLength = 3

    /// Construit la liste de termes d'un dossier. L'ordre d'entrée est préservé
    /// (les champs les plus discriminants d'abord), les doublons sont éliminés
    /// sans tenir compte de la casse ni des diacritiques.
    public static func terms(from rawValues: [String?]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for raw in rawValues {
            guard let raw else { continue }
            for candidate in split(raw) {
                guard candidate.count >= minTermLength else { continue }
                let key = normalize(candidate)
                guard !key.isEmpty, seen.insert(key).inserted else { continue }
                result.append(candidate)
                if result.count == maxTerms { return result }
            }
        }
        return result
    }

    /// Découpe un champ en termes présentables : les séparateurs d'énumération
    /// usuels des fiches (virgule, point-virgule, barre, « et ») délimitent,
    /// les espaces internes d'un nom composé sont conservés.
    static func split(_ field: String) -> [String] {
        field
            .components(separatedBy: CharacterSet(charactersIn: ",;|/\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func normalize(_ term: String) -> String {
        term.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
