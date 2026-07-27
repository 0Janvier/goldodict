import Foundation

/// Une réplique de cinéma affichée dans la pastille pendant la dictée.
///
/// Le texte reste en version originale : traduire « You talkin' to me? » revient à
/// perdre ce qui fait qu'on la reconnaît.
public struct MovieLine: Codable, Equatable, Sendable, Identifiable {
    public var id: String { replique.lowercased() }

    /// La réplique, en version originale.
    public var replique: String
    /// Le titre du film, en version originale lui aussi.
    public var film: String
    /// Année de sortie.
    public var annee: Int

    public init(replique: String, film: String, annee: Int) {
        self.replique = replique
        self.film = film
        self.annee = annee
    }

    /// Rendu de la réplique selon le format retenu dans les réglages.
    public func rendered(_ format: MovieLineFormat) -> String {
        switch format {
        case .repliqueSeule:
            return replique
        case .repliqueEtFilm:
            return "\(replique)  —  \(film)"
        case .repliqueFilmAnnee:
            return "\(replique)\n\(film), \(annee)"
        }
    }
}

/// Mise en forme de la réplique dans la pastille.
public enum MovieLineFormat: String, Codable, CaseIterable, Sendable, Identifiable {
    /// « You talkin' to me? »
    case repliqueSeule
    /// « You talkin' to me?  —  Taxi Driver »
    case repliqueEtFilm
    /// La réplique, puis « Taxi Driver, 1976 » sur une seconde ligne.
    case repliqueFilmAnnee

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .repliqueSeule: return "Réplique seule"
        case .repliqueEtFilm: return "Réplique et film"
        case .repliqueFilmAnnee: return "Réplique, film et année"
        }
    }

    /// Nombre de lignes que la pastille doit réserver.
    public var lineCount: Int {
        self == .repliqueFilmAnnee ? 2 : 1
    }
}

/// Le recueil des répliques, tiré au sort à chaque dictée.
public struct MovieLineBook: Equatable, Sendable {

    public private(set) var lines: [MovieLine]

    public init(lines: [MovieLine] = []) {
        self.lines = lines
    }

    public var isEmpty: Bool { lines.isEmpty }

    // MARK: - Chargement

    public static func load(from url: URL) throws -> MovieLineBook {
        let data = try Data(contentsOf: url)
        let lines = try JSONDecoder().decode([MovieLine].self, from: data)
        return MovieLineBook(lines: lines)
    }

    public func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(lines).write(to: url, options: .atomic)
    }

    public mutating func upsert(_ line: MovieLine) {
        if let index = lines.firstIndex(where: { $0.id == line.id }) {
            lines[index] = line
        } else {
            lines.append(line)
        }
    }

    public mutating func remove(id: String) {
        lines.removeAll { $0.id == id }
    }

    // MARK: - Tirage

    /// Tire une réplique au hasard, en évitant celle qui vient d'être affichée.
    ///
    /// Sans cette exclusion, deux dictées consécutives tomberaient tôt ou tard sur
    /// la même réplique, et le hasard passerait pour une panne. Le tireur est
    /// injectable pour que le test n'ait pas à composer avec l'aléa.
    public func draw(
        after previous: MovieLine? = nil,
        pick: (Int) -> Int = { Int.random(in: 0..<$0) }
    ) -> MovieLine? {
        guard !lines.isEmpty else { return nil }

        var candidates = lines
        if let previous, candidates.count > 1 {
            candidates.removeAll { $0.id == previous.id }
        }

        let index = pick(candidates.count)
        guard candidates.indices.contains(index) else { return candidates.first }
        return candidates[index]
    }
}
