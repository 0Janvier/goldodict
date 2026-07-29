import Foundation

/// Écriture de temps déposée dans la boîte d'envoi de Goldocab.
///
/// Goldodict n'écrit jamais dans la base de Goldocab : il dépose un fichier JSON
/// dans l'outbox du mécanisme compagnon (`goldocab-mobile/outbox/`), que Goldocab
/// ingère avec ses propres validations, sa déduplication (nom de fichier) et un
/// passage obligatoire en revue avant facturation.
public struct OutboxEntry: Codable, Equatable, Sendable {

    public struct Payload: Codable, Equatable, Sendable {
        public let kind: String
        public let content: String
        public let startedAt: Int
        public let durationMin: Int
        public let dossierId: Int64
        public let billable: Int

        enum CodingKeys: String, CodingKey {
            case kind, content, billable
            case startedAt = "started_at"
            case durationMin = "duration_min"
            case dossierId = "dossier_id"
        }
    }

    public let schemaVersion: Int
    public let type: String
    public let payload: Payload

    enum CodingKeys: String, CodingKey {
        case type, payload
        case schemaVersion = "schema_version"
    }

    /// Temps de dictée d'une session sur un dossier. La durée est arrondie à la
    /// minute supérieure : une session imputée ne peut pas peser zéro minute.
    public static func dictation(
        dossier: DossierContext,
        startedAt: Date,
        duration: TimeInterval
    ) -> OutboxEntry {
        OutboxEntry(
            schemaVersion: 1,
            type: "entry",
            payload: Payload(
                kind: "work",
                content: "[Dictée] \(dossier.code) — \(dossier.titre)",
                startedAt: Int(startedAt.timeIntervalSince1970),
                durationMin: max(1, Int((duration / 60).rounded(.up))),
                dossierId: dossier.id,
                billable: 1
            )
        )
    }

    /// JSON tel qu'attendu par l'ingestion de Goldocab, clés triées pour rester
    /// stable d'une exécution à l'autre.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return try encoder.encode(self)
    }
}
