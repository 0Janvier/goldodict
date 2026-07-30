import Foundation
import Testing
@testable import GoldodictCore

@Suite("Localisation de l'insertion dans le champ")
struct InsertionLocatorTests {

    private let inserted = "la requête de Riverel est recevable en tous ses moyens"

    @Test("Une insertion intacte ne rend rien")
    func untouchedInsertion() {
        let field = "Introduction. \(inserted) Conclusion."
        #expect(InsertionLocator.modifiedPassage(of: inserted, in: field) == nil)
    }

    @Test("Un mot retouché rend le passage modifié")
    func singleWordEdit() {
        let field = "Introduction. la requête de Riverel est parfaitement en tous ses moyens Conclusion."
        let passage = InsertionLocator.modifiedPassage(of: inserted, in: field)
        #expect(passage == "la requête de Riverel est parfaitement en tous ses moyens")
    }

    @Test("Des mots ajoutés sont couverts par la fenêtre élargie")
    func insertedWordsFound() {
        let field = "la requête de M. Riverel est recevable en tous ses moyens et conclusions"
        let passage = InsertionLocator.modifiedPassage(of: inserted, in: field)
        #expect(passage != nil)
        #expect(passage?.contains("M. Riverel") == true)
    }

    @Test("Un champ sans rapport ne rend rien")
    func unrelatedField() {
        let field = "bordereau des pièces communiquées au greffe le douze janvier"
        #expect(InsertionLocator.modifiedPassage(of: inserted, in: field) == nil)
    }

    @Test("Champ vide ou insertion vide ne rendent rien")
    func emptyInputs() {
        #expect(InsertionLocator.modifiedPassage(of: "", in: "du texte") == nil)
        #expect(InsertionLocator.modifiedPassage(of: "du texte", in: "") == nil)
        #expect(InsertionLocator.modifiedPassage(of: "long texte inséré ici", in: "court") == nil)
    }

    @Test("Le passage retenu est le plus ressemblant du champ")
    func bestWindowWins() {
        let field = "la requête de Riverel est recevable en tous ses points "
            + "sans rapport aucun "
            + "la requête est irrecevable en la forme"
        let passage = InsertionLocator.modifiedPassage(of: inserted, in: field)
        #expect(passage == "la requête de Riverel est recevable en tous ses points")
    }
}
