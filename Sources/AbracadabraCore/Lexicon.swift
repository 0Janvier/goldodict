import Foundation

/// Correspondance entre ce que le moteur entend et ce qu'il faut écrire.
public struct LexiconEntry: Codable, Equatable, Sendable, Identifiable {
    public var id: String { entendu.lowercased() }

    /// Ce que le moteur produit — souvent une déformation phonétique.
    public var entendu: String
    /// Ce qu'il faut écrire à la place.
    public var corrige: String
    /// Transmettre ce terme au moteur avant transcription plutôt que de le corriger
    /// après coup. Sans effet pour les déformations, utile pour les noms propres.
    public var biaiser: Bool

    public init(entendu: String, corrige: String, biaiser: Bool = true) {
        self.entendu = entendu
        self.corrige = corrige
        self.biaiser = biaiser
    }

    private enum CodingKeys: String, CodingKey {
        case entendu, corrige, biaiser
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        entendu = try container.decode(String.self, forKey: .entendu)
        corrige = try container.decode(String.self, forKey: .corrige)
        biaiser = try container.decodeIfPresent(Bool.self, forKey: .biaiser) ?? true
    }
}

/// Vocabulaire personnalisé, appliqué en correction après transcription et transmis
/// au moteur en amont sous forme de vocabulaire contextuel.
public struct Lexicon: Equatable, Sendable {

    public private(set) var entries: [LexiconEntry]

    public init(entries: [LexiconEntry] = []) {
        self.entries = entries
    }

    // MARK: - Chargement

    public static func load(from url: URL) throws -> Lexicon {
        let data = try Data(contentsOf: url)
        let entries = try JSONDecoder().decode([LexiconEntry].self, from: data)
        return Lexicon(entries: entries)
    }

    public func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(entries).write(to: url, options: .atomic)
    }

    public mutating func upsert(_ entry: LexiconEntry) {
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index] = entry
        } else {
            entries.append(entry)
        }
    }

    public mutating func remove(id: String) {
        entries.removeAll { $0.id == id }
    }

    // MARK: - Application

    /// Termes transmis au moteur avant transcription. C'est la voie la plus efficace :
    /// mieux vaut que le moteur reconnaisse « CAA de Bordeaux » que de rattraper
    /// après coup ce qu'il a mal entendu.
    public var contextualStrings: [String] {
        entries.filter(\.biaiser).map(\.corrige)
    }

    /// Applique les corrections, des expressions les plus longues aux plus courtes,
    /// afin qu'une entrée générale n'entame pas une entrée plus précise.
    public func correct(_ text: String) -> String {
        var result = text
        for entry in entries.sorted(by: { $0.entendu.count > $1.entendu.count }) {
            guard !entry.entendu.isEmpty else { continue }
            result = PunctuationCommands.replaceWholeWords(
                entry.entendu,
                with: entry.corrige,
                in: result
            )
        }
        return result
    }
}
