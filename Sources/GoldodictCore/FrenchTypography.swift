import Foundation

/// Met le texte aux normes typographiques françaises.
///
/// Nécessaire parce que la substitution des commandes vocales laisse la ponctuation
/// entourée d'espaces (« bonjour , ceci ») : c'est ici qu'elle est recollée au mot
/// qui précède, et que les espaces insécables sont posées.
public enum FrenchTypography {

    /// U+00A0. Devant `; : ! ?` et à l'intérieur des guillemets.
    public static let nonBreakingSpace: Character = "\u{00A0}"

    /// Ponctuation qui se colle au mot précédent et appelle une espace après.
    private static let lowMarks: Set<Character> = [",", ".", "…"]

    /// Ponctuation haute, précédée d'une espace insécable en français.
    private static let highMarks: Set<Character> = [";", ":", "!", "?"]

    public static func normalize(_ text: String) -> String {
        var result = collapseSpaces(text)
        result = tightenBeforeMarks(result)
        result = spaceAfterMarks(result)
        result = normalizeQuotes(result)
        result = normalizeParentheses(result)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Réduit les suites d'espaces, sans toucher aux sauts de ligne.
    private static func collapseSpaces(_ text: String) -> String {
        var result = ""
        var previousWasSpace = false
        for character in text {
            let isSpace = character == " " || character == nonBreakingSpace
            if isSpace {
                if !previousWasSpace { result.append(" ") }
                previousWasSpace = true
            } else {
                result.append(character)
                previousWasSpace = false
            }
        }
        return result
    }

    /// Supprime l'espace avant la ponctuation basse, la remplace par une insécable
    /// avant la ponctuation haute.
    private static func tightenBeforeMarks(_ text: String) -> String {
        var result = ""
        for character in text {
            if lowMarks.contains(character) || highMarks.contains(character) {
                while result.last == " " || result.last == nonBreakingSpace {
                    result.removeLast()
                }
                if highMarks.contains(character), !result.isEmpty {
                    result.append(nonBreakingSpace)
                }
            }
            result.append(character)
        }
        return result
    }

    /// Garantit une espace après la ponctuation lorsqu'un mot suit.
    private static func spaceAfterMarks(_ text: String) -> String {
        var result = ""
        var iterator = Array(text)
        for index in iterator.indices {
            let character = iterator[index]
            result.append(character)
            guard lowMarks.contains(character) || highMarks.contains(character) else { continue }
            guard index + 1 < iterator.count else { continue }
            let next = iterator[index + 1]
            // Une ponctuation suivie d'une autre, d'un guillemet fermant ou d'une
            // fin de ligne ne réclame pas d'espace.
            if next.isLetter || next.isNumber || next == "«" || next == "(" {
                result.append(" ")
            }
        }
        iterator.removeAll()
        return result
    }

    /// Guillemets français : espace insécable à l'intérieur, ordinaire à l'extérieur.
    private static func normalizeQuotes(_ text: String) -> String {
        var result = ""
        for character in text {
            switch character {
            case "«":
                if let last = result.last, last != " ", last != "\n", !result.isEmpty {
                    result.append(" ")
                }
                result.append("«")
                result.append(nonBreakingSpace)
            case "»":
                while result.last == " " || result.last == nonBreakingSpace {
                    result.removeLast()
                }
                result.append(nonBreakingSpace)
                result.append("»")
            default:
                result.append(character)
            }
        }
        return result
    }

    /// Parenthèses : collées à leur contenu, espacées de l'extérieur.
    private static func normalizeParentheses(_ text: String) -> String {
        var result = ""
        var iterator = Array(text)
        for index in iterator.indices {
            let character = iterator[index]
            switch character {
            case "(":
                if let last = result.last, last != " ", last != "\n" {
                    result.append(" ")
                }
                result.append("(")
            case ")":
                while result.last == " " || result.last == nonBreakingSpace {
                    result.removeLast()
                }
                result.append(")")
                if index + 1 < iterator.count {
                    let next = iterator[index + 1]
                    if next.isLetter || next.isNumber { result.append(" ") }
                }
            default:
                if result.last == "(" , character == " " { continue }
                result.append(character)
            }
        }
        iterator.removeAll()
        return result
    }

    /// Majuscule en tête de texte et après un point, un point d'interrogation ou
    /// d'exclamation.
    public static func capitalizeSentences(_ text: String) -> String {
        var result = ""
        var startOfSentence = true

        for character in text {
            if startOfSentence, character.isLetter {
                result.append(contentsOf: String(character).uppercased())
                startOfSentence = false
            } else {
                result.append(character)
            }

            if character == "." || character == "?" || character == "!" || character == "\n" {
                startOfSentence = true
            }
        }
        return result
    }
}
