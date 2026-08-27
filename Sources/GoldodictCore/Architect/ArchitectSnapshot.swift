import Foundation

/// Image persistée d'une session de document. Suffit à reprendre le plan après
/// un crash : le constructeur retrouve le nœud ouvert, les segments déjà
/// transcrits restent à l'écran.
public struct ArchitectSnapshot: Codable, Equatable, Sendable {
    public var outline: DocumentOutline
    public var segmentCount: Int
    public var startedAt: Date?

    public init(outline: DocumentOutline, segmentCount: Int, startedAt: Date? = nil) {
        self.outline = outline
        self.segmentCount = segmentCount
        self.startedAt = startedAt
    }

    /// Relit un fichier de reprise. Les anciennes versions n'écrivaient que le
    /// plan : on les accepte encore, le compteur de segments vaut alors zéro.
    public static func decode(from data: Data) throws -> ArchitectSnapshot {
        if let snapshot = try? JSONDecoder().decode(ArchitectSnapshot.self, from: data) {
            return snapshot
        }
        let outline = try JSONDecoder().decode(DocumentOutline.self, from: data)
        return ArchitectSnapshot(outline: outline, segmentCount: 0)
    }
}
