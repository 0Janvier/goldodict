import Foundation
import Testing
@testable import GoldodictCore

@Suite("Nombres et marqueurs")
struct NumberWordsTests {

    @Test("Les nombres en toutes lettres et en chiffres sont reconnus")
    func values() {
        #expect(NumberWords.value(of: "un") == 1)
        #expect(NumberWords.value(of: "Deux") == 2)
        #expect(NumberWords.value(of: "dix-sept") == 17)
        #expect(NumberWords.value(of: "3") == 3)
        #expect(NumberWords.value(of: "vingt") == 20)
        #expect(NumberWords.value(of: "trente") == nil)
        #expect(NumberWords.value(of: "21") == nil)
        #expect(NumberWords.value(of: "recevabilité") == nil)
    }

    @Test("Les chiffres romains sont corrects")
    func romans() {
        #expect(NumberWords.romanNumeral(1) == "I")
        #expect(NumberWords.romanNumeral(4) == "IV")
        #expect(NumberWords.romanNumeral(9) == "IX")
        #expect(NumberWords.romanNumeral(14) == "XIV")
        #expect(NumberWords.romanNumeral(20) == "XX")
    }

    @Test("Les lettres d'ordre suivent l'alphabet")
    func letters() {
        #expect(NumberWords.letter(1) == "A")
        #expect(NumberWords.letter(26) == "Z")
        #expect(NumberWords.letter(27) == nil)
        #expect(NumberWords.letter(0) == nil)
    }
}

@Suite("Grammaire de structure")
struct DocumentOutlineParserTests {

    @Test("Un titre de niveau un est reconnu avec son intitulé en prose")
    func titleLevelOne() {
        let tokens = DocumentOutlineParser.tokenize("titre un, sur la recevabilité.")
        #expect(tokens == [
            .command(.title(level: 1, marker: "I.")),
            .prose("sur la recevabilité."),
        ])
    }

    @Test("Les trois niveaux s'énoncent titre, grand, petit")
    func threeLevels() {
        let tokens = DocumentOutlineParser.tokenize("titre deux grand a petit trois")
        #expect(tokens == [
            .command(.title(level: 1, marker: "II.")),
            .command(.title(level: 2, marker: "A.")),
            .command(.title(level: 3, marker: "3.")),
        ])
    }

    @Test("Fin de citation est reconnue avant citation")
    func quoteBoundaries() {
        let tokens = DocumentOutlineParser.tokenize(
            "citation le délai court à compter de la notification, fin de citation."
        )
        #expect(tokens == [
            .command(.beginQuote),
            .prose("le délai court à compter de la notification"),
            .command(.endQuote),
        ])
    }

    @Test("La casse et les accents n'empêchent pas la reconnaissance")
    func caseAndDiacritics() {
        let tokens = DocumentOutlineParser.tokenize("Nouvel alinéa, la requête est fondée.")
        #expect(tokens.first == .command(.newParagraph))
        #expect(tokens == [
            .command(.newParagraph),
            .prose("la requête est fondée."),
        ])
    }

    @Test("Un mot englobant ne déclenche rien")
    func containingWordsDoNotTrigger() {
        let tokens = DocumentOutlineParser.tokenize("la citations directes et le grand avocat")
        #expect(tokens == [.prose("la citations directes et le grand avocat")])
    }

    @Test("Grand suivi d'un mot ordinaire reste de la prose")
    func grandWithoutLetter() {
        let tokens = DocumentOutlineParser.tokenize("un grand tribunal a jugé")
        #expect(tokens == [.prose("un grand tribunal a jugé")])
    }

    @Test("Titre sans nombre valide reste de la prose")
    func titleWithoutNumber() {
        let tokens = DocumentOutlineParser.tokenize("le titre exécutoire est contesté")
        #expect(tokens == [.prose("le titre exécutoire est contesté")])
    }
}
