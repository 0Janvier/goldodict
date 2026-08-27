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

    @Test("Un mot de sens substitué est refusé, même sur une phrase courte")
    func meaningSubstitutionIsRejected() {
        // « était expiré » devient « semblait expiré » : glissement typique et
        // lourd de conséquences. Sur quatre mots, la conservation vaut 0,75 —
        // pile le seuil du sac de mots. L'alignement doit quand même refuser.
        let raw = "le delai etait expire"
        let corrected = "le délai semblait expiré"

        let verdict = guardRail.evaluate(raw: raw, corrected: corrected)
        #expect(!verdict.accepted)
        #expect(verdict.reason?.contains("substitution de sens") == true)
    }

    @Test("Une substitution de sens au milieu d'une phrase longue est refusée")
    func meaningSubstitutionInLongSentenceIsRejected() {
        let raw = "la requete est irrecevable parce que le delai de deux mois etait expire a la date de la saisine"
        let corrected = "La requête est irrecevable parce que le délai de deux mois semblait expiré à la date de la saisine."

        let verdict = guardRail.evaluate(raw: raw, corrected: corrected)
        #expect(!verdict.accepted)
        #expect(verdict.reason?.contains("substitution de sens") == true)
    }

    @Test("Un accord de nombre n'est pas une substitution de sens")
    func agreementIsAccepted() {
        // Un seul mot change de nombre : le sac de mots reste à 0,75, pile le
        // seuil. Sans l'alignement, on ne saurait pas que c'est un accord.
        let raw = "le delai etait expire"
        let corrected = "le délai étaient expiré"

        let verdict = guardRail.evaluate(raw: raw, corrected: corrected)
        #expect(verdict.accepted)
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
        // Des mots ajoutés, sans substitution : le sac de mots tranche, pas l'alignement.
        let permissive = CorrectionGuard(
            thresholds: .init(retention: 0.05, lengthRange: 0.1...5.0)
        )
        let raw = "la requete est irrecevable"
        let corrected = "La requête est tout à fait irrecevable, cela va sans dire."

        #expect(permissive.evaluate(raw: raw, corrected: corrected).accepted)
        #expect(!guardRail.evaluate(raw: raw, corrected: corrected).accepted)
    }
}
