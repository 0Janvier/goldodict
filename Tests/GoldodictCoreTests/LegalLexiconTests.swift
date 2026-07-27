import Foundation
import Testing
@testable import GoldodictCore

/// Le lexique livré est une donnée, pas du code, et rien ne le compile : une virgule
/// de trop ou une entrée qui frappe un mot courant ne se voient qu'à l'usage. Ces
/// tests le traitent donc comme une dépendance à valider.
@Suite("Lexique juridique livré")
struct LegalLexiconTests {

    /// `Resources/` vit à côté de `Tests/`, deux crans au-dessus de ce fichier.
    private static var defaultLexiconURL: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()   // GoldodictCoreTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // racine
            .appending(path: "Resources/lexique.default.json")
    }

    private static let lexicon = try! Lexicon.load(from: defaultLexiconURL)

    // MARK: - Intégrité du fichier

    @Test("Le fichier livré se décode")
    func decodes() {
        #expect(!Self.lexicon.entries.isEmpty)
    }

    @Test("Aucun entendu en double")
    func noDuplicateKeys() {
        let ids = Self.lexicon.entries.map(\.id)
        #expect(ids.count == Set(ids).count)
    }

    @Test("Aucune entrée vide")
    func noEmptyEntry() {
        #expect(Self.lexicon.entries.allSatisfy { !$0.entendu.isEmpty && !$0.corrige.isEmpty })
    }

    /// Le prompt Whisper est plafonné à 223 tokens côté Python, et ce sont les
    /// PREMIERS termes qui sautent en cas de dépassement. Un biais de trop ne se
    /// signale pas, il évince silencieusement le terme d'à côté. Quatre caractères
    /// par token est une estimation prudente pour du français.
    @Test("Le biais tient dans le prompt Whisper")
    func contextualPromptFitsWhisperWindow() {
        let prompt = Self.lexicon.contextualStrings.joined(separator: ", ")
        #expect(prompt.count < 700)
    }

    @Test("Le biais est réservé à ce que le moteur ne devine pas")
    func biasStaysScarce() {
        let biased = Self.lexicon.entries.filter(\.biaiser)
        #expect(biased.count <= 40)
    }

    // MARK: - Corrections attendues

    @Test(
        "Les sigles sont rétablis en capitales",
        arguments: [
            ("le moyen tiré de la qpc est sérieux", "le moyen tiré de la QPC est sérieux"),
            ("article L. 2121-1 du cgct", "article L. 2121-1 du CGCT"),
            ("saisine de la cada", "saisine de la CADA"),
            ("le plui de la métropole", "le PLUi de la métropole"),
            ("compatibilité avec le scot", "compatibilité avec le SCoT"),
        ]
    )
    func acronymsAreCapitalized(input: String, expected: String) {
        #expect(Self.lexicon.correct(input) == expected)
    }

    @Test(
        "Les toponymes reprennent leurs traits d'union",
        arguments: [
            ("le préfet de la Haute Garonne", "le préfet de la Haute-Garonne"),
            ("commune de Castanet Tolosan", "commune de Castanet-Tolosan"),
            ("département de Tarn et Garonne", "département de Tarn-et-Garonne"),
        ]
    )
    func placeNamesRegainHyphens(input: String, expected: String) {
        #expect(Self.lexicon.correct(input) == expected)
    }

    /// La recherche est insensible aux diacritiques : une entrée dont l'`entendu`
    /// égale le `corrige` n'est pas inerte, elle efface l'accent parasite que le
    /// français colle spontanément sur le latin.
    @Test(
        "Le latin perd ses accents parasites",
        arguments: [
            ("le juge a statué ultra pétita", "le juge a statué ultra petita"),
            ("incompétence ratione matériae", "incompétence ratione materiae"),
            ("soulevé à fortiori", "soulevé a fortiori"),
        ]
    )
    func latinLosesStrayAccents(input: String, expected: String) {
        #expect(Self.lexicon.correct(input) == expected)
    }

    @Test(
        "Les fautes de forme du vocabulaire juridique sont reprises",
        arguments: [
            ("un conflit d'intérêt manifeste", "un conflit d'intérêts manifeste"),
            ("poursuivi pour prise illégale d'intérêt", "poursuivi pour prise illégale d'intérêts"),
            ("une ordonnance de non lieu", "une ordonnance de non-lieu"),
            ("le procès verbal de séance", "le procès-verbal de séance"),
            ("un référé provision", "un référé-provision"),
        ]
    )
    func commonMistakesAreFixed(input: String, expected: String) {
        #expect(Self.lexicon.correct(input) == expected)
    }

    @Test("La CAA de Toulouse est connue")
    func toulouseAppealCourt() {
        #expect(Self.lexicon.correct("appel devant la caa de toulouse") == "appel devant la CAA de Toulouse")
        #expect(Self.lexicon.contextualStrings.contains("CAA de Toulouse"))
    }

    // MARK: - Absence d'effets de bord

    /// L'entrée « partant » → « Partant » capitalisait le participe présent partout,
    /// la recherche ignorant la casse et le contexte. Elle a été retirée.
    @Test("Le participe présent n'est plus capitalisé")
    func gerundIsLeftAlone() {
        #expect(Self.lexicon.correct("en partant de là") == "en partant de là")
    }

    /// Les sigles sont des mots entiers : « scot » ne doit pas ronger « scotch ».
    @Test(
        "Les sigles courts ne mordent pas sur les mots",
        arguments: ["un rouleau de scotch", "la ville de Dupuy", "il a du cran"]
    )
    func shortAcronymsRespectWordBounds(input: String) {
        #expect(Self.lexicon.correct(input) == input)
    }

    /// Le lexique tourne avant le correcteur, donc sur les apostrophes brutes du
    /// moteur. Une entrée écrite avec l'apostrophe courbe ne matcherait jamais.
    @Test("Les entendu n'emploient que l'apostrophe droite")
    func heardFormsUseStraightApostrophe() {
        #expect(Self.lexicon.entries.allSatisfy { !$0.entendu.contains("\u{2019}") })
    }
}
