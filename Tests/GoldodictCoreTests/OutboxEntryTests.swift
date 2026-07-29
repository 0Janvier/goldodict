import Foundation
import Testing
@testable import GoldodictCore

@Suite("Écriture de temps vers l'outbox Goldocab")
struct OutboxEntryTests {

    private let dossier = DossierContext(
        id: 42, code: "26-812", titre: "Riverel c. SMAVD", terms: []
    )

    @Test("Le JSON respecte le schéma attendu par Goldocab")
    func schemaMatches() throws {
        let entry = OutboxEntry.dictation(
            dossier: dossier,
            startedAt: Date(timeIntervalSince1970: 1_753_000_000),
            duration: 12 * 60
        )
        let data = try entry.encoded()
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let root = try #require(object)

        #expect(root["schema_version"] as? Int == 1)
        #expect(root["type"] as? String == "entry")

        let payload = try #require(root["payload"] as? [String: Any])
        #expect(payload["kind"] as? String == "work")
        #expect(payload["content"] as? String == "[Dictée] 26-812 — Riverel c. SMAVD")
        #expect(payload["started_at"] as? Int == 1_753_000_000)
        #expect(payload["duration_min"] as? Int == 12)
        #expect(payload["dossier_id"] as? Int == 42)
        #expect(payload["billable"] as? Int == 1)
        #expect(payload.count == 6)
    }

    @Test("La durée est arrondie à la minute supérieure, jamais nulle")
    func durationRoundsUp() {
        let brief = OutboxEntry.dictation(dossier: dossier, startedAt: .init(timeIntervalSince1970: 0), duration: 20)
        #expect(brief.payload.durationMin == 1)

        let sevenAndHalf = OutboxEntry.dictation(dossier: dossier, startedAt: .init(timeIntervalSince1970: 0), duration: 7.5 * 60)
        #expect(sevenAndHalf.payload.durationMin == 8)
    }

    @Test("Le round-trip Codable est fidèle")
    func roundTrip() throws {
        let entry = OutboxEntry.dictation(
            dossier: dossier,
            startedAt: Date(timeIntervalSince1970: 1_753_000_000),
            duration: 300
        )
        let decoded = try JSONDecoder().decode(OutboxEntry.self, from: entry.encoded())
        #expect(decoded == entry)
    }
}
