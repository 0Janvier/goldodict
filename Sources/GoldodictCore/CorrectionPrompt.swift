import Foundation

/// Consigne unique, partagée par les deux correcteurs.
///
/// Elle est volontairement restrictive. L'utilisateur a demandé une correction, pas
/// une réécriture : le modèle rétablit ce que l'oral perd — ponctuation, accents,
/// accords — et ne touche à rien d'autre. Le `CorrectionGuard` vérifie ensuite que
/// la consigne a été suivie, car une consigne ne garantit rien.
public enum CorrectionPrompt {

    public static let instructions = """
    Tu corriges une dictée vocale rédigée en français juridique.

    Tu rétablis la ponctuation, les accents et les accords grammaticaux. Tu \
    supprimes les hésitations (« euh », « alors »), les faux départs et les \
    répétitions involontaires.

    Tu ne reformules jamais. Tu ne remplaces aucun mot porteur de sens par un \
    synonyme. Tu n'ajoutes ni ne retires aucune idée, aucune nuance, aucune \
    réserve. Tu ne commentes pas.

    Tu réponds uniquement par le texte corrigé, sans préambule ni guillemets. \
    Tu n'annonces aucun outil, aucune fonction, aucune balise du type \
    « Tool : text_correction ».
    """

    /// La consigne de base, complétée des règles apprises du profil courant.
    public static func instructions(styleNotes: [String]) -> String {
        guard !styleNotes.isEmpty else { return instructions }
        let rules = styleNotes.map { "- \($0)" }.joined(separator: "\n")
        return instructions + "\n\nRègles supplémentaires, propres à ce contexte :\n" + rules
    }

    public static func prompt(for text: String) -> String {
        "Texte dicté à corriger :\n\n\(text)"
    }

    /// Retire les ornements que les modèles ajoutent malgré la consigne : guillemets
    /// d'encadrement, préambule, blocs de raisonnement résiduels.
    public static func stripDecoration(from response: String) -> String {
        var text = response.trimmingCharacters(in: .whitespacesAndNewlines)

        if let range = text.range(of: "</think>") {
            text = String(text[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let prefixes = [
            "Texte dicté à corriger :",
            "Texte corrigé :",
            "Voici le texte corrigé :",
            "Voici la correction :",
        ]
        for prefix in prefixes {
            if let range = text.range(of: prefix, options: [.caseInsensitive, .anchored]) {
                text = String(text[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        let pairs: [(Character, Character)] = [("\"", "\""), ("«", "»"), ("“", "”")]
        for (open, close) in pairs where text.first == open && text.last == close && text.count > 2 {
            text = String(text.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return stripToolTraces(from: text)
    }

    /// Le modèle Apple, surtout, préfixe parfois sa réponse d'une trace d'outil
    /// interne (`Tool : text_correction`), avec ou sans espace insécable devant
    /// les deux-points. Ce n'est pas du texte dicté.
    public static func containsToolTrace(_ text: String) -> Bool {
        text.split(whereSeparator: \.isNewline).contains { toolTraceRemainder(of: String($0)) != nil }
    }

    static func stripToolTraces(from text: String) -> String {
        let kept = text
            .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .compactMap { line -> String? in
                let raw = String(line)
                guard let remainder = toolTraceRemainder(of: raw) else { return raw }
                return remainder.isEmpty ? nil : remainder
            }
        return kept.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Si la ligne est une trace d'outil, rend le reste (vide si la ligne n'était
    /// que ça). `nil` si ce n'est pas une trace — « le délai : expiré » passe.
    static func toolTraceRemainder(of line: String) -> String? {
        let folded = normalizeSpaces(line)
        guard let colon = folded.firstIndex(of: ":") else { return nil }
        let head = folded[..<colon].trimmingCharacters(in: .whitespaces)
        guard head.caseInsensitiveCompare("tool") == .orderedSame
            || head.caseInsensitiveCompare("tools") == .orderedSame else { return nil }

        let tail = folded[folded.index(after: colon)...]
            .trimmingCharacters(in: .whitespaces)
        guard let nameEnd = tail.firstIndex(where: {
            !$0.isLetter && !$0.isNumber && $0 != "_" && $0 != "-" && $0 != "."
        }) else {
            return tail.isEmpty ? nil : ""
        }
        let name = tail[..<nameEnd]
        guard !name.isEmpty else { return nil }
        return tail[nameEnd...].trimmingCharacters(in: .whitespaces)
    }

    private static func normalizeSpaces(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{202F}", with: " ")
            .replacingOccurrences(of: "\u{2009}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
