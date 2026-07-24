import Foundation

/// Chaîne de traitement appliquée au texte brut du moteur.
///
/// Elle se déroule en deux temps parce qu'une étape extérieure — la correction par
/// un modèle de langue — vient s'intercaler au milieu :
///
/// ```
/// prepare()  : commandes de ponctuation → lexique
///              ↓  correction locale, hors de cette cible
/// finalize() : typographie française → majuscules
/// ```
///
/// L'ordre n'est pas indifférent. La ponctuation passe avant le lexique pour qu'une
/// entrée de lexique puisse contenir des signes. La typographie vient en dernier
/// parce qu'un modèle de langue ne pose pas les espaces insécables de façon fiable :
/// elle doit avoir le dernier mot.
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

    /// Premier temps : ce qui doit précéder la correction.
    public func prepare(_ raw: String, profile: AppProfile = .redaction) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        var result = trimmed
        if profile.punctuationCommands {
            result = punctuation.apply(to: result)
        }
        if profile.applyLexicon {
            result = lexicon.correct(result)
        }
        return result
    }

    /// Second temps : mise en forme finale, après correction éventuelle.
    public func finalize(_ text: String, profile: AppProfile = .redaction) -> String {
        guard !text.isEmpty else { return "" }

        var result = text
        if profile.frenchTypography {
            result = FrenchTypography.normalize(result)
        } else {
            result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // Les deux doivent consentir : le profil dit que ce contexte accepte les
        // majuscules, le réglage dit qu'on les souhaite.
        if profile.capitalizeSentences, punctuation.options.capitalizeSentences {
            result = FrenchTypography.capitalizeSentences(result)
        }
        return result
    }

    /// Chaîne complète sans correction — comportement d'origine, conservé pour les
    /// profils qui s'en dispensent et pour les tests.
    public func process(_ raw: String, profile: AppProfile = .redaction) -> String {
        finalize(prepare(raw, profile: profile), profile: profile)
    }
}
