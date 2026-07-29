import Foundation

/// Commande de structure énoncée pendant une dictée de document.
public enum StructureCommand: Equatable, Sendable {
    /// `level` 1 → « I. », 2 → « A. », 3 → « 1. ».
    case title(level: Int, marker: String)
    case beginQuote
    case endQuote
    case newParagraph
}

/// Le texte d'un segment, découpé en commandes et en fragments de prose,
/// dans l'ordre d'énonciation.
public enum DocumentToken: Equatable, Sendable {
    case command(StructureCommand)
    case prose(String)
}

/// Reconnaissance déterministe des commandes de structure.
///
/// Même philosophie que `PunctuationCommands` : des mots entiers, insensibles à
/// la casse et aux diacritiques, les correspondances longues avant les courtes
/// (« fin de citation » avant « citation »). Le correcteur LLM ne voit jamais ces
/// mots — seule la prose lui est soumise, il ne peut donc ni les paraphraser ni
/// les avaler.
public enum DocumentOutlineParser {

    public static func tokenize(_ text: String) -> [DocumentToken] {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        var tokens: [DocumentToken] = []
        var prose: [String] = []
        var index = 0

        func flushProse() {
            let joined = prose.joined(separator: " ")
                .trimmingCharacters(in: CharacterSet(charactersIn: " ,;"))
            if !joined.isEmpty { tokens.append(.prose(joined)) }
            prose = []
        }

        while index < words.count {
            if let (command, consumed) = match(words, at: index) {
                flushProse()
                tokens.append(.command(command))
                index += consumed
            } else {
                prose.append(words[index])
                index += 1
            }
        }
        flushProse()
        return tokens
    }

    /// Essaie chaque motif à la position donnée, les plus longs d'abord.
    private static func match(_ words: [String], at index: Int) -> (StructureCommand, Int)? {
        // « fin de citation » — trois mots, avant « citation » seule.
        if clean(words, index) == "fin", clean(words, index + 1) == "de", clean(words, index + 2) == "citation" {
            return (.endQuote, 3)
        }
        // « nouvel alinéa » / « nouvel alinea ».
        if clean(words, index) == "nouvel", clean(words, index + 1) == "alinea" {
            return (.newParagraph, 2)
        }
        // « titre <nombre> » → niveau 1, chiffre romain.
        if clean(words, index) == "titre", let word = word(words, index + 1),
           let value = NumberWords.value(of: word) {
            return (.title(level: 1, marker: NumberWords.romanNumeral(value) + "."), 2)
        }
        // « grand <lettre> » → niveau 2. La lettre s'énonce seule (« grand a »).
        if clean(words, index) == "grand", let letter = singleLetter(words, index + 1) {
            return (.title(level: 2, marker: letter + "."), 2)
        }
        // « petit <nombre> » → niveau 3.
        if clean(words, index) == "petit", let word = word(words, index + 1),
           let value = NumberWords.value(of: word) {
            return (.title(level: 3, marker: "\(value)."), 2)
        }
        // « citation » seule.
        if clean(words, index) == "citation" {
            return (.beginQuote, 1)
        }
        return nil
    }

    private static func word(_ words: [String], _ index: Int) -> String? {
        guard words.indices.contains(index) else { return nil }
        return stripPunctuation(words[index])
    }

    /// Le mot, dépouillé de sa ponctuation et normalisé pour comparaison.
    private static func clean(_ words: [String], _ index: Int) -> String? {
        guard let stripped = word(words, index) else { return nil }
        return stripped.folding(
            options: [.diacriticInsensitive, .caseInsensitive],
            locale: Locale(identifier: "fr_FR")
        )
    }

    private static func singleLetter(_ words: [String], _ index: Int) -> String? {
        guard let cleaned = clean(words, index), cleaned.count == 1,
              let character = cleaned.first, character.isLetter else { return nil }
        return cleaned.uppercased()
    }

    private static func stripPunctuation(_ word: String) -> String {
        word.trimmingCharacters(in: CharacterSet.punctuationCharacters)
    }
}
