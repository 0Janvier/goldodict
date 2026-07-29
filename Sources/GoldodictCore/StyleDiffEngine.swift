import Foundation

/// Une correction manuelle observée : ce que Goldodict avait écrit, ce que
/// l'utilisateur a mis à la place.
public struct CorrectionPair: Equatable, Sendable {
    public let before: String
    public let after: String

    public init(before: String, after: String) {
        self.before = before
        self.after = after
    }
}

public enum StyleSuggestionKind: String, Codable, Equatable, Sendable {
    /// Un mot pour un mot : un nom propre ou un sigle mal entendu, candidat au lexique.
    case lexicon
    /// Une tournure : candidate à une règle transmise au correcteur.
    case style
}

/// Extraction des corrections d'un texte retouché à la main.
///
/// L'alignement est un LCS sur les mots, en égalité stricte : c'est justement
/// l'écart littéral — casse, accent, trait d'union — qu'une retouche vient
/// réparer. Seules les substitutions courtes sont retenues ; une réécriture
/// longue est un changement d'avis, pas une correction.
public enum StyleDiffEngine {

    public static let maxSegmentLength = 4
    public static let maxTokensForDiff = 400

    public static func diff(original: String, corrected: String) -> [CorrectionPair] {
        let before = tokens(of: original)
        let after = tokens(of: corrected)
        guard before.count <= maxTokensForDiff, after.count <= maxTokensForDiff else { return [] }
        guard before != after else { return [] }

        let anchors = longestCommonSubsequence(before, after)
        var pairs: [CorrectionPair] = []

        var i = 0, j = 0
        for (ai, aj) in anchors + [(before.count, after.count)] {
            let removed = Array(before[i..<ai])
            let inserted = Array(after[j..<aj])
            // Substitution pure uniquement : un ajout ou un retrait sec n'apprend
            // rien sur la manière d'écrire ce qui a été dicté.
            if !removed.isEmpty, !inserted.isEmpty,
               removed.count <= maxSegmentLength, inserted.count <= maxSegmentLength {
                pairs.append(CorrectionPair(
                    before: removed.joined(separator: " "),
                    after: inserted.joined(separator: " ")
                ))
            }
            i = ai + 1
            j = aj + 1
        }
        return pairs
    }

    public static func classify(_ pair: CorrectionPair) -> StyleSuggestionKind {
        let single = !pair.before.contains(" ") && !pair.after.contains(" ")
        return single ? .lexicon : .style
    }

    /// La règle en français, telle qu'elle rejoindra les instructions du correcteur.
    public static func styleInstruction(before: String, after: String) -> String {
        "Tu écris « \(after) » plutôt que « \(before) »."
    }

    /// Une paire que le lexique corrige déjà n'a rien à apprendre : sans ce
    /// filtre, chaque acceptation reviendrait hanter le panneau.
    public static func discardingAlreadyHandled(_ pairs: [CorrectionPair], lexicon: Lexicon) -> [CorrectionPair] {
        pairs.filter { pair in
            normalize(lexicon.correct(pair.before)) != normalize(pair.after)
        }
    }

    // MARK: - Outils

    static func tokens(of text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    public static func normalize(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
            .replacingOccurrences(of: "’", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Indices appariés (i, j) de la plus longue sous-suite commune.
    private static func longestCommonSubsequence(_ a: [String], _ b: [String]) -> [(Int, Int)] {
        guard !a.isEmpty, !b.isEmpty else { return [] }
        var table = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                table[i][j] = a[i] == b[j]
                    ? table[i + 1][j + 1] + 1
                    : max(table[i + 1][j], table[i][j + 1])
            }
        }
        var result: [(Int, Int)] = []
        var i = 0, j = 0
        while i < a.count, j < b.count {
            if a[i] == b[j] {
                result.append((i, j))
                i += 1; j += 1
            } else if table[i + 1][j] >= table[i][j + 1] {
                i += 1
            } else {
                j += 1
            }
        }
        return result
    }
}
