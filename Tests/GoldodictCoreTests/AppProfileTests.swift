import Foundation
import Testing
@testable import GoldodictCore

@Suite("Profils par application")
struct AppProfileTests {

    @Test("Le profil Brut ne touche à rien")
    func rawProfileIsFullyPassive() {
        let raw = AppProfile.raw
        #expect(!raw.correctText)
        #expect(!raw.punctuationCommands)
        #expect(!raw.capitalizeSentences)
        #expect(!raw.frenchTypography)
        #expect(!raw.applyLexicon)
    }

    @Test("Le profil Rédaction applique tout")
    func redactionProfileIsFullyActive() {
        let redaction = AppProfile.redaction
        #expect(redaction.correctText)
        #expect(redaction.punctuationCommands)
        #expect(redaction.capitalizeSentences)
        #expect(redaction.frenchTypography)
        #expect(redaction.applyLexicon)
    }

    @Test("Le profil Messagerie ponctue sans corriger ni poser d'insécables")
    func messagingProfile() {
        let messaging = AppProfile.messaging
        #expect(!messaging.correctText)
        #expect(messaging.punctuationCommands)
        #expect(messaging.capitalizeSentences)
        #expect(!messaging.frenchTypography)
    }

    @Test("Un terminal reçoit le profil Brut")
    func terminalResolvesToRaw() {
        let set = ProfileSet()
        #expect(set.profile(for: "com.mitchellh.ghostty").name == "Brut")
        #expect(set.profile(for: "com.apple.Terminal").name == "Brut")
    }

    @Test("Word reçoit le profil Rédaction")
    func wordResolvesToRedaction() {
        #expect(ProfileSet().profile(for: "com.microsoft.Word").name == "Rédaction")
    }

    @Test("Une application inconnue reçoit le premier profil")
    func unknownFallsBackToFirst() {
        let set = ProfileSet()
        #expect(set.profile(for: "com.exemple.inconnu").name == "Rédaction")
        #expect(set.profile(for: nil).name == "Rédaction")
    }

    @Test("Un profil modifié remplace le précédent sans duplication")
    func replacementKeepsSetSize() {
        var set = ProfileSet()
        let count = set.profiles.count
        var raw = AppProfile.raw
        raw.correctText = true
        set.replace(raw)
        #expect(set.profiles.count == count)
        #expect(set.profile(for: "com.apple.Terminal").correctText)
    }

    @Test("Le codage puis décodage conserve chaque réglage")
    func codingRoundTripIsFaithful() throws {
        let encoded = try JSONEncoder().encode(AppProfile.defaults)
        let decoded = try JSONDecoder().decode([AppProfile].self, from: encoded)
        #expect(decoded == AppProfile.defaults)
    }

    @Test("Le profil Brut laisse le texte intact dans la chaîne de traitement")
    func rawProfileLeavesTextUntouched() {
        let pipeline = TranscriptPipeline(
            lexicon: Lexicon(entries: [LexiconEntry(entendu: "rapo", corrige: "RAPO")])
        )
        let source = "git commit virgule rapo"
        #expect(pipeline.process(source, profile: .raw) == source)
    }

    @Test("Le profil Rédaction met le même texte en forme")
    func redactionProfileFormats() {
        let pipeline = TranscriptPipeline(
            lexicon: Lexicon(entries: [LexiconEntry(entendu: "rapo", corrige: "RAPO")])
        )
        let result = pipeline.process("le recours virgule rapo", profile: .redaction)
        #expect(result.contains("RAPO"))
        #expect(result.contains(","))
        #expect(result.hasPrefix("Le"))
    }
}
