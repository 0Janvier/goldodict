import Foundation

/// Contrôle de fidélité d'une correction automatique.
///
/// Un modèle de langue chargé de « corriger » peut glisser vers la reformulation
/// sans que rien ne le signale : « le délai était expiré » devient « le délai
/// semblait expiré », et la nuance échappe à une relecture rapide. Dans un écrit
/// judiciaire, la conséquence n'est pas stylistique.
///
/// Deux mesures, calculées sur les mots normalisés (sans casse ni diacritiques) :
/// la part des mots du texte corrigé qui figuraient déjà dans le brut, et le
/// rapport des longueurs. Hors des bornes, la correction est refusée et le texte
/// brut conservé.
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
}
