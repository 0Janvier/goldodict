import Foundation
import Testing
@testable import GoldodictCore

@Suite("Vocabulaire de dossier")
struct DossierVocabularyTests {

    @Test("Les champs du dossier deviennent des termes, dans l'ordre")
    func fieldsBecomeTerms() {
        let terms = DossierVocabulary.terms(from: [
            "Riverel", "SMAVD", "TA Toulouse", "2601234-5",
        ])
        #expect(terms == ["Riverel", "SMAVD", "TA Toulouse", "2601234-5"])
    }

    @Test("Les doublons sont éliminés sans tenir compte de la casse ni des accents")
    func duplicatesFold() {
        let terms = DossierVocabulary.terms(from: [
            "Méralis", "meralis", "MERALIS", "Octave Méralis",
        ])
        #expect(terms == ["Méralis", "Octave Méralis"])
    }

    @Test("Les champs nuls ou vides sont ignorés")
    func nilAndEmptySkipped() {
        let terms = DossierVocabulary.terms(from: [nil, "", "  ", "Verdillon"])
        #expect(terms == ["Verdillon"])
    }

    @Test("Un champ énumératif est découpé sur ses séparateurs")
    func enumerationsSplit() {
        let terms = DossierVocabulary.terms(from: ["Martin, Durand ; Commune de Blagnac"])
        #expect(terms == ["Martin", "Durand", "Commune de Blagnac"])
    }

    @Test("Les termes trop courts sont écartés")
    func shortTermsDropped() {
        let terms = DossierVocabulary.terms(from: ["SA", "de", "CAA de Bordeaux"])
        #expect(terms == ["CAA de Bordeaux"])
    }

    @Test("La liste est plafonnée")
    func capped() {
        let many = (1...60).map { "Partie numéro \($0)" }
        let terms = DossierVocabulary.terms(from: many)
        #expect(terms.count == DossierVocabulary.maxTerms)
        #expect(terms.first == "Partie numéro 1")
    }
}
