import Foundation

/// Contrôle de fidélité d'une correction automatique.
///
/// Un modèle de langue chargé de « corriger » peut glisser vers la reformulation
/// sans que rien ne le signale : « le délai était expiré » devient « le délai
/// semblait expiré », et la nuance échappe à une relecture rapide. Dans un écrit
/// judiciaire, la conséquence n'est pas stylistique.
///
/// Trois mesures, dans cet ordre :
///
/// 1. La part des mots du corrigé déjà présents dans le brut (sac de mots).
/// 2. Le rapport des longueurs.
/// 3. L'alignement : une substitution d'un mot porteur — « était » / « semblait » —
///    est refusée même si le sac de mots reste dans les bornes. Les accords
///    (« était » / « étaient ») et les mots-outils courts (« le » / « la ») passent.
///
/// Les mots sont normalisés sans casse ni diacritiques : rétablir les accents
/// fait partie du travail attendu et ne doit pas compter comme une altération.
public struct CorrectionGuard: Sendable {

    public struct Thresholds: Equatable, Sendable {
        /// Part minimale des mots du corrigé déjà présents dans le brut.
        public var retention: Double
        /// Bornes du rapport entre le nombre de mots du corrigé et celui du brut.
        public var lengthRange: ClosedRange<Double>

        public init(retention: Double = 0.75, lengthRange: ClosedRange<Double> = 0.6...1.4) {
            self.retention = retention
            self.lengthRange = lengthRange
        }

        public static let `default` = Thresholds()
    }

    public struct Verdict: Equatable, Sendable {
        public let accepted: Bool
        public let retention: Double
        public let lengthRatio: Double
        public let reason: String?

        public var summary: String {
            String(
                format: "conservation %.0f %%, longueur %.0f %%",
                retention * 100,
                lengthRatio * 100
            )
        }
    }

    public var thresholds: Thresholds

    public init(thresholds: Thresholds = .default) {
        self.thresholds = thresholds
    }

    public func evaluate(raw: String, corrected: String) -> Verdict {
        let rawWords = Self.words(of: raw)
        let correctedWords = Self.words(of: corrected)

        guard !rawWords.isEmpty else {
            return Verdict(accepted: false, retention: 0, lengthRatio: 0, reason: "texte brut vide")
        }
        guard !correctedWords.isEmpty else {
            return Verdict(accepted: false, retention: 0, lengthRatio: 0, reason: "correction vide")
        }

        // Un sac de mots plutôt qu'un ensemble : un modèle qui répète un mot dix fois
        // ne doit pas passer pour fidèle sous prétexte que ce mot existait au brut.
        var available = Dictionary(rawWords.map { ($0, 1) }, uniquingKeysWith: +)
        var kept = 0
        for word in correctedWords {
            if let count = available[word], count > 0 {
                available[word] = count - 1
                kept += 1
            }
        }

        let retention = Double(kept) / Double(correctedWords.count)
        let lengthRatio = Double(correctedWords.count) / Double(rawWords.count)

        if retention < thresholds.retention {
            return Verdict(
                accepted: false,
                retention: retention,
                lengthRatio: lengthRatio,
                reason: "trop de mots nouveaux"
            )
        }
        if !thresholds.lengthRange.contains(lengthRatio) {
            return Verdict(
                accepted: false,
                retention: retention,
                lengthRatio: lengthRatio,
                reason: lengthRatio < thresholds.lengthRange.lowerBound
                    ? "texte tronqué"
                    : "texte allongé"
            )
        }

        if let substitution = Self.meaningSubstitution(raw: rawWords, corrected: correctedWords) {
            return Verdict(
                accepted: false,
                retention: retention,
                lengthRatio: lengthRatio,
                reason: "substitution de sens (\(substitution))"
            )
        }

        return Verdict(accepted: true, retention: retention, lengthRatio: lengthRatio, reason: nil)
    }

    /// Découpe en mots comparables : minuscules, sans diacritiques, sans ponctuation.
    /// La correction rétablit précisément accents et ponctuation, ils ne peuvent
    /// donc pas servir à mesurer sa fidélité.
    static func words(of text: String) -> [String] {
        text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    /// Première substitution de mot porteur relevée par alignement, ou `nil`.
    static func meaningSubstitution(raw: [String], corrected: [String]) -> String? {
        let anchors = longestCommonSubsequence(raw, corrected)
        var i = 0, j = 0
        for (ai, aj) in anchors + [(raw.count, corrected.count)] {
            let removed = Array(raw[i..<ai])
            let inserted = Array(corrected[j..<aj])
            if let pair = zip(removed, inserted).first(where: { !isAgreementOrInflection($0, $1) }) {
                return "« \(pair.0) » → « \(pair.1) »"
            }
            i = ai + 1
            j = aj + 1
        }
        return nil
    }

    /// Accords et flexions du même mot : « était / étaient », « expire / expires ».
    /// Les mots-outils de trois lettres ou moins (« le / la ») passent aussi —
    /// ce sont des accords, pas des glissements de sens.
    static func isAgreementOrInflection(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        if a.count <= 3, b.count <= 3 { return true }
        let shorter = a.count <= b.count ? a : b
        let longer = a.count <= b.count ? b : a
        if longer.hasPrefix(shorter), longer.count - shorter.count <= 3 { return true }
        return commonPrefixLength(a, b) >= 4
    }

    private static func commonPrefixLength(_ a: String, _ b: String) -> Int {
        zip(a, b).prefix(while: { $0 == $1 }).count
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
