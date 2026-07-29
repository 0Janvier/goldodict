import Foundation
import Testing
@testable import GoldodictCore

@Suite("Moteur de diff de style")
struct StyleDiffEngineTests {

    @Test("Deux textes identiques ne produisent rien")
    func identicalTexts() {
        #expect(StyleDiffEngine.diff(original: "la requête est recevable", corrected: "la requête est recevable").isEmpty)
    }

    @Test("Une substitution d'un mot est détectée et classée lexique")
    func singleWordSubstitution() {
        let pairs = StyleDiffEngine.diff(
            original: "la requête de rive rel est recevable",
            corrected: "la requête de Riverel est recevable"
        )
        // « rive rel » vs « Riverel » : deux mots remplacés par un seul.
        #expect(pairs == [CorrectionPair(before: "rive rel", after: "Riverel")])
        #expect(StyleDiffEngine.classify(CorrectionPair(before: "smavd", after: "SMAVD")) == .lexicon)
    }

    @Test("Une substitution de plusieurs mots est classée style")
    func multiWordSubstitution() {
        let pairs = StyleDiffEngine.diff(
            original: "le conseil de état a jugé",
            corrected: "le Conseil d'État a jugé"
        )
        #expect(pairs == [CorrectionPair(before: "conseil de état", after: "Conseil d'État")])
        #expect(StyleDiffEngine.classify(pairs[0]) == .style)
        #expect(StyleDiffEngine.classify(CorrectionPair(before: "suite à", after: "à la suite de")) == .style)
    }

    @Test("L'alignement est sensible à la casse et aux accents")
    func caseSensitiveAlignment() {
        let pairs = StyleDiffEngine.diff(
            original: "la métropole a conclu",
            corrected: "la Métropole a conclu"
        )
        #expect(pairs == [CorrectionPair(before: "métropole", after: "Métropole")])
    }

    @Test("Une réécriture longue est écartée")
    func longRewriteDiscarded() {
        let pairs = StyleDiffEngine.diff(
            original: "aaa bbb ccc ddd eee fff ggg hhh",
            corrected: "aaa un deux trois quatre cinq six sept huit neuf hhh"
        )
        #expect(pairs.isEmpty)
    }

    @Test("Une insertion pure ou une suppression pure n'apprend rien")
    func pureInsertionIgnored() {
        #expect(StyleDiffEngine.diff(
            original: "la requête est recevable",
            corrected: "la requête est parfaitement recevable"
        ).isEmpty)
        #expect(StyleDiffEngine.diff(
            original: "la requête est parfaitement recevable",
            corrected: "la requête est recevable"
        ).isEmpty)
    }

    @Test("La règle de style produite est stable")
    func instructionText() {
        #expect(
            StyleDiffEngine.styleInstruction(before: "suite à", after: "à la suite de")
            == "Tu écris « à la suite de » plutôt que « suite à »."
        )
    }

    @Test("Une paire déjà couverte par le lexique est filtrée")
    func lexiconHandledFiltered() {
        var lexicon = Lexicon()
        lexicon.upsert(LexiconEntry(entendu: "smavd", corrige: "SMAVD"))
        let pairs = [
            CorrectionPair(before: "smavd", after: "SMAVD"),
            CorrectionPair(before: "riverl", after: "Riverel"),
        ]
        let kept = StyleDiffEngine.discardingAlreadyHandled(pairs, lexicon: lexicon)
        #expect(kept == [CorrectionPair(before: "riverl", after: "Riverel")])
    }
}

@Suite("Registre des observations de style")
struct StyleObservationsTests {

    @Test("Un premier signalement crée une entrée en attente")
    func firstRecord() {
        var observations = StyleObservations()
        let entry = observations.record(before: "smavd", after: "SMAVD", profileName: "Rédaction", kind: .lexicon)
        #expect(entry.occurrences == 1)
        #expect(entry.status == .pending)
    }

    @Test("Les variantes de casse et d'accent s'agrègent sur la même clé")
    func normalizedAggregation() {
        var observations = StyleObservations()
        observations.record(before: "Méralis", after: "Meralis", profileName: "Rédaction", kind: .lexicon)
        observations.record(before: "meralis", after: "Meralis", profileName: "Rédaction", kind: .lexicon)
        observations.record(before: "MERALIS", after: "meralis", profileName: "Rédaction", kind: .lexicon)
        #expect(observations.entries.count == 1)
        #expect(observations.entries[0].occurrences == 3)
    }

    @Test("Le seuil filtre les propositions, les plus fréquentes d'abord")
    func thresholdAndOrder() {
        var observations = StyleObservations()
        for _ in 1...5 { observations.record(before: "a1", after: "b1", profileName: "P", kind: .lexicon) }
        for _ in 1...3 { observations.record(before: "a2", after: "b2", profileName: "P", kind: .lexicon) }
        observations.record(before: "a3", after: "b3", profileName: "P", kind: .lexicon)

        let proposals = observations.proposals(threshold: 3)
        #expect(proposals.map(\.before) == ["a1", "a2"])
    }

    @Test("Une observation écartée continue de compter mais ne repropose jamais")
    func dismissedNeverNags() {
        var observations = StyleObservations()
        for _ in 1...3 { observations.record(before: "a", after: "b", profileName: "P", kind: .lexicon) }
        let id = observations.entries[0].id
        observations.setStatus(.dismissed, id: id)
        for _ in 1...5 { observations.record(before: "a", after: "b", profileName: "P", kind: .lexicon) }

        #expect(observations.entries[0].occurrences == 8)
        #expect(observations.proposals(threshold: 3).isEmpty)
    }

    @Test("Une observation acceptée reste au journal, hors des propositions")
    func acceptedStaysInJournal() {
        var observations = StyleObservations()
        for _ in 1...3 { observations.record(before: "a", after: "b", profileName: "P", kind: .style) }
        observations.setStatus(.accepted, id: observations.entries[0].id)
        #expect(observations.entries.count == 1)
        #expect(observations.proposals(threshold: 3).isEmpty)
    }

    @Test("Deux profils font deux observations distinctes")
    func profileScoping() {
        var observations = StyleObservations()
        observations.record(before: "a", after: "b", profileName: "Rédaction", kind: .lexicon)
        observations.record(before: "a", after: "b", profileName: "Messagerie", kind: .lexicon)
        #expect(observations.entries.count == 2)
    }

    @Test("Le registre survit à un aller-retour disque")
    func persistenceRoundTrip() throws {
        var observations = StyleObservations()
        // Date ronde : l'encodage ISO 8601 ne conserve pas les fractions de seconde.
        observations.record(
            before: "smavd", after: "SMAVD", profileName: "Rédaction", kind: .lexicon,
            at: Date(timeIntervalSince1970: 1_753_000_000)
        )
        observations.setStatus(.accepted, id: observations.entries[0].id)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("style-observations-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        try observations.save(to: url)
        let reloaded = try StyleObservations.load(from: url)
        #expect(reloaded == observations)
    }
}

@Suite("Profil — règles de style")
struct AppProfileStyleNotesTests {

    @Test("Un profil sans la clé styleNotes se décode avec une liste vide")
    func backwardCompatibleDecoding() throws {
        let json = """
        {"name":"Test","bundleIdentifiers":[],"correctText":true,"punctuationCommands":true,
         "capitalizeSentences":true,"frenchTypography":true}
        """
        let profile = try JSONDecoder().decode(AppProfile.self, from: Data(json.utf8))
        #expect(profile.styleNotes.isEmpty)
        #expect(profile.applyLexicon == true)
    }

    @Test("Les règles de style survivent à un aller-retour Codable")
    func styleNotesRoundTrip() throws {
        var profile = AppProfile.redaction
        profile.styleNotes = ["Tu écris « à la suite de » plutôt que « suite à »."]
        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(AppProfile.self, from: data)
        #expect(decoded.styleNotes == profile.styleNotes)
    }
}
