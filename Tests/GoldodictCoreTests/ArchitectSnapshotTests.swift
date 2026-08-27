import Foundation
import Testing
@testable import GoldodictCore

@Suite("Image de reprise du mode document")
struct ArchitectSnapshotTests {

    @Test("Un plan seul, format d'avant, se relit encore")
    func decodesLegacyOutline() throws {
        var builder = DocumentOutlineBuilder()
        builder.append(DocumentOutlineParser.tokenize("titre un, sur la recevabilité"))
        let data = try JSONEncoder().encode(builder.outline)

        let snapshot = try ArchitectSnapshot.decode(from: data)
        #expect(snapshot.outline.sections[0].marker == "I.")
        #expect(snapshot.segmentCount == 0)
        #expect(snapshot.startedAt == nil)
    }

    @Test("Une image complète aller-retour conserve le compteur")
    func roundTrip() throws {
        var builder = DocumentOutlineBuilder()
        builder.append(DocumentOutlineParser.tokenize("titre un, sur le fond"))
        let start = Date(timeIntervalSince1970: 1_777_000_000)
        let snapshot = ArchitectSnapshot(outline: builder.outline, segmentCount: 4, startedAt: start)
        let data = try JSONEncoder().encode(snapshot)

        let decoded = try ArchitectSnapshot.decode(from: data)
        #expect(decoded.segmentCount == 4)
        #expect(decoded.startedAt == start)
        #expect(decoded.outline.sections[0].heading == "sur le fond")
    }
}
