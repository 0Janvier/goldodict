import Testing
@testable import GoldodictCore

@Suite("Garde-fou de correction")
struct CorrectionGuardTests {

    private let guardRail = CorrectionGuard()

    @Test("Une correction légitime est acceptée")
    func acceptsGenuineCorrection() {
        // Cas réel mesuré avec qwen3:8b : accents rétablis, ponctuation posée,
        // hésitation supprimée, aucun mot porteur de sens modifié.
        let raw = "alors la requete est irrecevable euh parce que le delai de deux mois etait expire a la date de la saisine"
        let corrected = "Alors la requête est irrecevable, parce que le délai de deux mois était expiré à la date de la saisine."

        let verdict = guardRail.evaluate(raw: raw, corrected: corrected)
        #expect(verdict.accepted)
        #expect(verdict.retention == 1.0)
    }

    @Test("Une reformulation complète est refusée")
    func rejectsRewriting() {
        let raw = "la requete est irrecevable parce que le delai etait expire"
        let corrected = "Le recours ne saurait prospérer, dès lors que les conditions temporelles posées par les textes ne se trouvaient plus réunies au jour de son introduction."

        let verdict = guardRail.evaluate(raw: raw, corrected: corrected)
        #expect(!verdict.accepted)
        #expect(verdict.reason == "trop de mots nouveaux")
    }

    @Test("Une troncature est refusée")
    func rejectsTruncation() {
        let raw = "la requete est irrecevable parce que le delai de deux mois etait expire a la date de la saisine du tribunal"
        let corrected = "La requête est irrecevable."

        let verdict = guardRail.evaluate(raw: raw, corrected: corrected)
        #expect(!verdict.accepted)
        #expect(verdict.reason == "texte tronqué")
    }

    @Test("Un ajout substantiel est refusé")
    func rejectsPadding() {
        let raw = "la requete est irrecevable"
        let corrected = "La requête est irrecevable, et il convient de préciser que cette irrecevabilité procède de la tardiveté manifeste de la saisine opérée par le requérant devant la juridiction compétente."

        let verdict = guardRail.evaluate(raw: raw, corrected: corrected)
        #expect(!verdict.accepted)
    }

    @Test("La répétition d'un mot ne passe pas pour de la fidélité")
    func repetitionIsNotRetention() {
        let raw = "la requete est irrecevable"
        let corrected = "requête requête requête requête requête requête"

        let verdict = guardRail.evaluate(raw: raw, corrected: corrected)
        #expect(!verdict.accepted)
    }

    @Test("Les accents seuls ne comptent pas comme des mots nouveaux")
    func accentsAreNotChanges() {
        let raw = "le delai etait expire a la date consideree"
        let corrected = "Le délai était expiré à la date considérée."

        let verdict = guardRail.evaluate(raw: raw, corrected: corrected)
        #expect(verdict.accepted)
        #expect(verdict.retention == 1.0)
    }

    @Test("Un mot de sens substitué fait chuter la conservation")
    func meaningSubstitutionIsCaught() {
        // « était expiré » devient « semblait expiré » : glissement typique et
        // lourd de conséquences, invisible à la relecture rapide.
        let raw = "le delai etait expire"
        let corrected = "le délai semblait expiré"

        let verdict = guardRail.evaluate(raw: raw, corrected: corrected)
        #expect(verdict.retention < 1.0)
    }

    @Test("Un texte brut vide est refusé")
    func emptyRawIsRejected() {
        #expect(!guardRail.evaluate(raw: "   ", corrected: "quelque chose").accepted)
    }

    @Test("Une correction vide est refusée")
    func emptyCorrectionIsRejected() {
        #expect(!guardRail.evaluate(raw: "la requête est tardive", corrected: "").accepted)
    }

    @Test("Les seuils sont ajustables")
    func thresholdsAreConfigurable() {
        let permissive = CorrectionGuard(
            thresholds: .init(retention: 0.05, lengthRange: 0.1...5.0)
        )
        let raw = "la requete est irrecevable"
        let corrected = "Le recours ne prospérera pas devant la juridiction saisie."

        #expect(permissive.evaluate(raw: raw, corrected: corrected).accepted)
        #expect(!guardRail.evaluate(raw: raw, corrected: corrected).accepted)
    }
}
