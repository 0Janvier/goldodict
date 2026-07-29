import Foundation
import GoldodictCore

/// Dépose une écriture de temps dans la boîte d'envoi de Goldocab.
///
/// Le dépôt suit le contrat du mécanisme compagnon : écriture d'un fichier
/// temporaire puis renommage atomique, pour que l'ingestion ne voie jamais un
/// JSON à moitié écrit. Le nom du fichier sert de clé d'idempotence côté Goldocab.
enum OutboxWriter {

    static let defaultOutboxPath = NSString(
        string: "~/Documents/1_Avocat/90_Systeme/goldocab-mobile/outbox"
    ).expandingTildeInPath

    enum Failure: LocalizedError {
        case outboxMissing

        var errorDescription: String? {
            switch self {
            case .outboxMissing: return "boîte d'envoi Goldocab introuvable"
            }
        }
    }

    @discardableResult
    static func deposit(_ entry: OutboxEntry, outboxPath: String = defaultOutboxPath) throws -> URL {
        let outbox = URL(fileURLWithPath: outboxPath, isDirectory: true)
        guard FileManager.default.fileExists(atPath: outbox.path) else {
            throw Failure.outboxMissing
        }

        let name = "goldodict-\(UUID().uuidString.lowercased()).json"
        let temporary = outbox.appendingPathComponent(name + ".tmp")
        let final = outbox.appendingPathComponent(name)

        try entry.encoded().write(to: temporary, options: .atomic)
        try FileManager.default.moveItem(at: temporary, to: final)
        Log.goldocab.notice("temps déposé : \(name, privacy: .public)")
        return final
    }
}
