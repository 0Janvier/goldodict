import Foundation
import Testing
@testable import GoldodictCore

@Suite("Détection du code de dossier")
struct DossierCodeDetectorTests {

    @Test("Un code dans un titre de fenêtre est trouvé")
    func codeInWindowTitle() {
        let codes = DossierCodeDetector.codes(in: "Riverel-26-812-note-defense.docx — Word")
        #expect(codes == ["26-812"])
    }

    @Test("Plusieurs codes sortent dans l'ordre, sans doublon")
    func multipleCodes() {
        let codes = DossierCodeDetector.codes(in: "26-812 vs 26-807, encore 26-812")
        #expect(codes == ["26-812", "26-807"])
    }

    @Test("Un nombre plus long n'est pas un code")
    func longerNumbersRejected() {
        #expect(DossierCodeDetector.codes(in: "requête n° 2601234-5").isEmpty)
        #expect(DossierCodeDetector.codes(in: "126-8121").isEmpty)
        #expect(DossierCodeDetector.codes(in: "le 26-40 et le 6-400").isEmpty)
    }

    @Test("Un code en bord de chaîne est accepté")
    func codeAtBoundaries() {
        #expect(DossierCodeDetector.codes(in: "26-812") == ["26-812"])
        #expect(DossierCodeDetector.codes(in: "dossier 26-812") == ["26-812"])
    }

    @Test("Le premier code correspondant à un dossier connu l'emporte")
    func matchAgainstKnownDossiers() {
        let dossiers = [
            DossierContext(id: 1, code: "26-807", titre: "Delcourt", terms: []),
            DossierContext(id: 2, code: "26-812", titre: "Riverel", terms: []),
        ]
        let match = DossierCodeDetector.match(
            in: "99-999 puis 26-812 puis 26-807",
            among: dossiers
        )
        #expect(match?.id == 2)
        #expect(DossierCodeDetector.match(in: "aucun code ici", among: dossiers) == nil)
    }
}
