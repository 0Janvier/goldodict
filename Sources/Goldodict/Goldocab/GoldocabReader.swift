import Foundation
import GoldodictCore
import SQLite3

/// Pont de lecture vers la base Goldocab.
///
/// La base appartient à Goldocab, Goldodict n'y écrit jamais rien : ouverture en
/// lecture seule doublée d'un `PRAGMA query_only`, la même ceinture-bretelles que
/// le serveur ring-mcp. Toute défaillance (Goldocab absent, base déplacée) rend
/// simplement une liste vide — la dictée fonctionne sans dossier.
struct GoldocabReader {

    static let defaultDatabasePath = NSString(
        string: "~/Library/Application Support/fr.sztulman.goldocab/goldocab.sqlite"
    ).expandingTildeInPath

    var databasePath: String

    init(databasePath: String = ProcessInfo.processInfo.environment["GOLDOCAB_DB"]
            ?? GoldocabReader.defaultDatabasePath) {
        self.databasePath = databasePath
    }

    /// Les dossiers ouverts, avec le vocabulaire déjà construit. Les plus récents
    /// d'abord, pour que le Picker montre en tête ce qui occupe le cabinet.
    func activeDossiers() -> [DossierContext] {
        guard FileManager.default.fileExists(atPath: databasePath) else { return [] }

        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY
        guard sqlite3_open_v2(databasePath, &db, flags, nil) == SQLITE_OK, let db else {
            Log.goldocab.error("ouverture de la base refusée")
            sqlite3_close(db)
            return []
        }
        defer { sqlite3_close(db) }
        sqlite3_exec(db, "PRAGMA query_only = ON", nil, nil, nil)

        let sql = """
            SELECT d.id, d.code, d.titre, c.nom, d.juridiction, d.numero_rg,
                   d.partie_adverse, d.avocat_adverse
            FROM dossiers d
            LEFT JOIN clients c ON c.id = d.client_id
            WHERE d.etat IN ('brouillon', 'en_cours', 'en_attente')
            ORDER BY d.id DESC
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            Log.goldocab.error("requête dossiers refusée : \(String(cString: sqlite3_errmsg(db)), privacy: .public)")
            return []
        }
        defer { sqlite3_finalize(statement) }

        var dossiers: [DossierContext] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = sqlite3_column_int64(statement, 0)
            guard let code = text(statement, 1), let titre = text(statement, 2) else { continue }

            var fields: [String?] = [
                text(statement, 3),      // client
                text(statement, 6),      // partie adverse
                text(statement, 7),      // avocat adverse
                text(statement, 4),      // juridiction
                text(statement, 5),      // numéro RG
                titre,
            ]
            fields.append(contentsOf: parties(of: id, in: db))

            dossiers.append(DossierContext(
                id: id,
                code: code,
                titre: titre,
                terms: DossierVocabulary.terms(from: fields)
            ))
        }
        return dossiers
    }

    private func parties(of dossierID: Int64, in db: OpaquePointer) -> [String?] {
        let sql = "SELECT nom, conseil FROM dossier_parties WHERE dossier_id = ?"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, dossierID)

        var values: [String?] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            values.append(text(statement, 0))
            values.append(text(statement, 1))
        }
        return values
    }

    private func text(_ statement: OpaquePointer?, _ column: Int32) -> String? {
        guard let pointer = sqlite3_column_text(statement, column) else { return nil }
        let value = String(cString: pointer).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
