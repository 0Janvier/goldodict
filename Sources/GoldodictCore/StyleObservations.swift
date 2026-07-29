import Foundation

/// Une correction récurrente, en attente de devenir une entrée de lexique ou une
/// règle de style — ou déjà tranchée.
public struct StyleObservation: Codable, Equatable, Sendable, Identifiable {

    public enum Status: String, Codable, Sendable {
        case pending, accepted, dismissed
    }

    public let id: String
    public let before: String
    public let after: String
    public let profileName: String
    public let kind: StyleSuggestionKind
    public var occurrences: Int
    public let firstSeen: Date
    public var lastSeen: Date
    public var status: Status
}

/// Le registre des corrections observées.
///
/// Jamais le texte d'une dictée : seulement des paires courtes, agrégées sur une
/// clé normalisée. Une observation tranchée — acceptée ou écartée — continue de
/// compter ses occurrences (le fichier sert de journal) mais ne repasse jamais
/// dans les propositions : c'est l'anti-harcèlement.
public struct StyleObservations: Equatable, Sendable {

    public static let defaultThreshold = 3

    public private(set) var entries: [StyleObservation]

    public init(entries: [StyleObservation] = []) {
        self.entries = entries
    }

    @discardableResult
    public mutating func record(
        before: String,
        after: String,
        profileName: String,
        kind: StyleSuggestionKind,
        at date: Date = Date()
    ) -> StyleObservation {
        let key = Self.key(profileName: profileName, before: before, after: after)
        if let index = entries.firstIndex(where: { $0.id == key }) {
            entries[index].occurrences += 1
            entries[index].lastSeen = date
            return entries[index]
        }
        let observation = StyleObservation(
            id: key,
            before: before,
            after: after,
            profileName: profileName,
            kind: kind,
            occurrences: 1,
            firstSeen: date,
            lastSeen: date,
            status: .pending
        )
        entries.append(observation)
        return observation
    }

    public mutating func setStatus(_ status: StyleObservation.Status, id: String) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].status = status
    }

    /// Les corrections mûres : en attente et vues assez souvent, les plus
    /// fréquentes d'abord.
    public func proposals(threshold: Int = Self.defaultThreshold) -> [StyleObservation] {
        entries
            .filter { $0.status == .pending && $0.occurrences >= threshold }
            .sorted { $0.occurrences > $1.occurrences }
    }

    static func key(profileName: String, before: String, after: String) -> String {
        "\(profileName)|\(StyleDiffEngine.normalize(before))→\(StyleDiffEngine.normalize(after))"
    }

    // MARK: - Persistance

    public static func load(from url: URL) throws -> StyleObservations {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return StyleObservations(entries: try decoder.decode([StyleObservation].self, from: data))
    }

    public func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(entries).write(to: url, options: .atomic)
    }
}
