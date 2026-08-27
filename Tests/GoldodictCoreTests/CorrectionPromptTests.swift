import Testing
@testable import GoldodictCore

@Suite("Consigne de correction")
struct CorrectionPromptTests {

    @Test("Les ornements de modèle sont retirés")
    func stripsDecoration() {
        #expect(CorrectionPrompt.stripDecoration(from: "« la requête est tardive »") == "la requête est tardive")
        #expect(CorrectionPrompt.stripDecoration(from: "Voici le texte corrigé :\n\nla requête est tardive") == "la requête est tardive")
        #expect(CorrectionPrompt.stripDecoration(from: "<think>raisonnement</think>\nla requête est tardive") == "la requête est tardive")
    }

    @Test("Une trace d'outil Apple est retirée")
    func stripsAppleToolTrace() {
        #expect(CorrectionPrompt.stripDecoration(from: "Tool : text_correction") == "")
        #expect(CorrectionPrompt.stripDecoration(from: "Tool: text_correction") == "")
        #expect(
            CorrectionPrompt.stripDecoration(from: "Tool : text_correction\nLa requête est tardive.")
                == "La requête est tardive."
        )
        #expect(
            CorrectionPrompt.stripDecoration(from: "Tool : text_correction La requête est tardive.")
                == "La requête est tardive."
        )
        // Espace insécable française devant les deux-points, telle que le modèle
        // Apple l'émet parfois.
        let withNbsp = "Tool\u{00A0}: text_correction\nla requête est tardive"
        #expect(CorrectionPrompt.stripDecoration(from: withNbsp) == "la requête est tardive")
        #expect(CorrectionPrompt.containsToolTrace("Tool : text_correction\nla requête"))
        #expect(!CorrectionPrompt.containsToolTrace("le délai : expiré"))
        #expect(CorrectionPrompt.stripDecoration(from: "le délai : expiré") == "le délai : expiré")
    }

    @Test("Les règles de style s'ajoutent à la consigne")
    func appendsStyleNotes() {
        let text = CorrectionPrompt.instructions(styleNotes: ["Tu écris « CAA » plutôt que « cage »."])
        #expect(text.contains(CorrectionPrompt.instructions))
        #expect(text.contains("Tu écris « CAA » plutôt que « cage »."))
    }
}
