import Foundation

/// Traduit les commandes vocales de ponctuation en signes.
///
/// Les substitutions portent sur le texte littéral : si le moteur de transcription
/// a déjà converti « virgule » en « , » de lui-même, le mot n'y figure plus et rien
/// n'est appliqué. Aucun double emploi n'est donc possible.
public struct PunctuationCommands {

    /// Les commandes ambiguës sont isolées parce que leurs mots ont un sens plein
    /// en français juridique — « le point de départ du délai », « la virgule du
    /// texte ». L'utilisateur peut les désactiver sans perdre les autres.
    public struct Options: Equatable, Sendable {
        /// « point », « virgule », « tiret », « apostrophe ».
        public var simpleMarks: Bool
        /// « à la ligne », « nouveau paragraphe ».
        public var lineBreaks: Bool
        /// Guillemets, parenthèses, « point d'interrogation », « deux points »…
        public var compoundMarks: Bool
        /// Majuscule après un point et en tête de texte.
        public var capitalizeSentences: Bool

        public init(
            simpleMarks: Bool = true,
            lineBreaks: Bool = true,
            compoundMarks: Bool = true,
            capitalizeSentences: Bool = true
        ) {
            self.simpleMarks = simpleMarks
            self.lineBreaks = lineBreaks
            self.compoundMarks = compoundMarks
            self.capitalizeSentences = capitalizeSentences
        }

        public static let `default` = Options()
    }

    public var options: Options

    public init(options: Options = .default) {
        self.options = options
    }

    /// Commandes composées, appliquées en premier : « point d'interrogation » doit
    /// être reconnu avant que « point » ne réduise l'expression à un simple point.
    private static let compound: [(patterns: [String], replacement: String)] = [
        (["point d'interrogation", "point dinterrogation"], "?"),
        (["point d'exclamation", "point dexclamation"], "!"),
        (["points de suspension", "point de suspension"], "…"),
        (["point-virgule", "point virgule"], ";"),
        (["deux points", "deux-points"], ":"),
        (["ouvrez les guillemets", "ouvre les guillemets", "ouvrir les guillemets"], "«"),
        (["fermez les guillemets", "ferme les guillemets", "fermer les guillemets"], "»"),
        (["ouvrez la parenthèse", "ouvre la parenthèse", "ouvrir la parenthèse"], "("),
        (["fermez la parenthèse", "ferme la parenthèse", "fermer la parenthèse"], ")"),
        (["tiret cadratin", "tiret long"], "—"),
    ]

    private static let lineBreaks: [(patterns: [String], replacement: String)] = [
        (["nouveau paragraphe", "à la ligne à la ligne"], "\n\n"),
        (["à la ligne", "nouvelle ligne", "retour à la ligne"], "\n"),
    ]

    private static let simple: [(patterns: [String], replacement: String)] = [
        (["virgule"], ","),
        (["point"], "."),
        (["apostrophe"], "’"),
        (["tiret"], "-"),
    ]

    public func apply(to text: String) -> String {
        var result = text

        if options.compoundMarks {
            result = Self.substitute(Self.compound, in: result)
        }
        if options.lineBreaks {
            result = Self.substitute(Self.lineBreaks, in: result)
        }
        if options.simpleMarks {
            result = Self.substitute(Self.simple, in: result)
        }
        return result
    }

    private static func substitute(
        _ table: [(patterns: [String], replacement: String)],
        in text: String
    ) -> String {
        var result = text
        for entry in table {
            for pattern in entry.patterns {
                result = replaceWholeWords(
                    pattern,
                    with: entry.replacement,
                    in: result
                )
            }
        }
        return result
    }

    /// Remplace une expression prise comme suite de mots entiers, sans égard à la
    /// casse ni aux accents — un moteur peut rendre « a la ligne » sans accent.
    ///
    /// `NSRegularExpression` ne sait pas ignorer les diacritiques ; `range(of:options:)`
    /// le fait nativement. Les bornes de mots sont donc vérifiées à la main, ce qui
    /// a l'avantage de traiter correctement l'apostrophe typographique, devant
    /// laquelle `\b` se comporte de façon inattendue.
    public static func replaceWholeWords(
        _ needle: String,
        with replacement: String,
        in text: String
    ) -> String {
        guard !needle.isEmpty else { return text }

        var result = text
        var searchFrom = result.startIndex

        while searchFrom < result.endIndex,
              let found = result.range(
                of: needle,
                options: [.caseInsensitive, .diacriticInsensitive],
                range: searchFrom..<result.endIndex,
                locale: Locale(identifier: "fr_FR")
              ) {

            let precededByWord = found.lowerBound > result.startIndex
                && isWordCharacter(result[result.index(before: found.lowerBound)])
            let followedByWord = found.upperBound < result.endIndex
                && isWordCharacter(result[found.upperBound])

            if precededByWord || followedByWord {
                searchFrom = result.index(after: found.lowerBound)
                continue
            }

            // Les indices sont invalidés par la mutation : on repart d'un décalage.
            let offset = result.distance(from: result.startIndex, to: found.lowerBound)
            result.replaceSubrange(found, with: replacement)
            searchFrom = result.index(result.startIndex, offsetBy: offset + replacement.count)
        }

        return result
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber
    }
}
