import Foundation

/// Chaîne de traitement appliquée au texte brut du moteur.
///
/// L'ordre importe. La ponctuation passe avant le lexique pour qu'une entrée de
/// lexique puisse contenir des signes (« article L. 761-1 »), et la typographie
/// vient en dernier parce qu'elle rattrape les espaces laissées par les deux
/// étapes précédentes.
public struct TranscriptPipeline: Sendable {

    public var lexicon: Lexicon
    public var punctuation: PunctuationCommands

    public init(
        lexicon: Lexicon = Lexicon(),
        punctuation: PunctuationCommands = PunctuationCommands()
    ) {
        self.lexicon = lexicon
        self.punctuation = punctuation
    }

    public func process(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        var result = punctuation.apply(to: trimmed)
        result = lexicon.correct(result)
        result = FrenchTypography.normalize(result)

        if punctuation.options.capitalizeSentences {
            result = FrenchTypography.capitalizeSentences(result)
        }
        return result
    }
}
