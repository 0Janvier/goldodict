import Foundation

/// Nombres énoncés en toutes lettres, chiffres romains et lettres d'ordre.
///
/// Le mode document n'a besoin que de petits nombres : un plan juridique qui
/// dépasse vingt titres de même niveau a un problème que Goldodict ne réglera pas.
public enum NumberWords {

    private static let words: [String: Int] = [
        "un": 1, "une": 1, "deux": 2, "trois": 3, "quatre": 4, "cinq": 5,
        "six": 6, "sept": 7, "huit": 8, "neuf": 9, "dix": 10,
        "onze": 11, "douze": 12, "treize": 13, "quatorze": 14, "quinze": 15,
        "seize": 16, "dix-sept": 17, "dix-huit": 18, "dix-neuf": 19, "vingt": 20,
    ]

    /// « un »…« vingt », ou le chiffre « 1 »…« 20 ». `nil` sinon.
    public static func value(of word: String) -> Int? {
        let cleaned = word
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
            .trimmingCharacters(in: .whitespaces)
        if let direct = words[cleaned] { return direct }
        if let numeric = Int(cleaned), (1...20).contains(numeric) { return numeric }
        return nil
    }

    public static func romanNumeral(_ value: Int) -> String {
        let table: [(Int, String)] = [
            (10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I"),
        ]
        var remainder = value
        var result = ""
        for (weight, symbol) in table {
            while remainder >= weight {
                result += symbol
                remainder -= weight
            }
        }
        return result
    }

    /// 1 → « A », 26 → « Z ». `nil` au-delà : un plan n'épuise pas l'alphabet.
    public static func letter(_ value: Int) -> String? {
        guard (1...26).contains(value) else { return nil }
        let scalar = UnicodeScalar(64 + value)!
        return String(Character(scalar))
    }
}
