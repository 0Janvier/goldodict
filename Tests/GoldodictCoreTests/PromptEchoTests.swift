import Testing
@testable import GoldodictCore

@Suite("Écho du prompt Whisper")
struct PromptEchoTests {

    private let prompt = "CAA de Bordeaux, CAA de Toulouse, Conseil d'État, CJA, QPC"

    @Test("Sans prompt, le texte est intact")
    func noPrompt() {
        #expect(PromptEcho.strip("la requête est tardive", prompt: nil) == "la requête est tardive")
        #expect(PromptEcho.strip("la requête est tardive", prompt: "") == "la requête est tardive")
    }

    @Test("Le prompt entier en tête est retiré")
    func fullPromptEcho() {
        let text = "\(prompt), la requête est irrecevable"
        #expect(PromptEcho.strip(text, prompt: prompt) == "la requête est irrecevable")
    }

    @Test("Un préfixe d'au moins trois termes est retiré")
    func partialPromptEcho() {
        let text = "CAA de Bordeaux, CAA de Toulouse, Conseil d'État la requête est irrecevable"
        #expect(PromptEcho.strip(text, prompt: prompt) == "la requête est irrecevable")
    }

    @Test("Un seul terme du lexique en tête n'est pas mangé")
    func singleLexiconTermSurvives() {
        let text = "CAA de Bordeaux a jugé que la requête est tardive"
        #expect(PromptEcho.strip(text, prompt: prompt) == text)
    }

    @Test("La casse et les accents n'empêchent pas la détection")
    func caseAndDiacritics() {
        let text = "caa de bordeaux, caa de toulouse, conseil d'etat — la requête est tardive"
        #expect(PromptEcho.strip(text, prompt: prompt) == "la requête est tardive")
    }

    @Test("Un texte sans écho reste intact")
    func noEcho() {
        let text = "la requête est irrecevable parce que le délai était expiré"
        #expect(PromptEcho.strip(text, prompt: prompt) == text)
    }
}
