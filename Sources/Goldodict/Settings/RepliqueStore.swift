import GoldodictCore
import Foundation
import Observation

/// Persistance des répliques dans un fichier JSON éditable à la main.
///
/// Même parti pris que le lexique : ajouter une réplique ne doit pas exiger
/// d'ouvrir l'application, et le catalogue livré ne doit jamais écraser celui de
/// l'utilisateur.
/// Observable, à la différence du lexique : la table des réglages doit refléter
/// l'ajout d'une réplique sans qu'on ait à refermer la fenêtre.
@Observable
@MainActor
final class RepliqueStore {

    /// `~/Library/Application Support/Goldodict/repliques.json`
    static var fileURL: URL { SupportDirectory.url(for: "repliques.json") }

    private(set) var book = MovieLineBook()

    /// Dernière réplique tirée, pour ne pas la retirer deux fois de suite. Hors
    /// observation : elle change à chaque dictée et n'a rien à redessiner.
    @ObservationIgnored
    private var previous: MovieLine?

    func load() {
        let url = Self.fileURL

        if !FileManager.default.fileExists(atPath: url.path) {
            installDefault(at: url)
        }

        do {
            book = try MovieLineBook.load(from: url)
            Log.lifecycle.notice("répliques chargées : \(self.book.lines.count)")
        } catch {
            Log.lifecycle.error("répliques illisibles : \(error.localizedDescription, privacy: .public)")
            book = Self.bundled() ?? MovieLineBook()
        }
    }

    func save() {
        do {
            try createDirectoryIfNeeded()
            try book.save(to: Self.fileURL)
        } catch {
            Log.lifecycle.error("répliques non enregistrées : \(error.localizedDescription, privacy: .public)")
        }
    }

    func update(_ book: MovieLineBook) {
        self.book = book
        save()
    }

    /// Rétablit le catalogue livré avec l'application.
    func restoreDefaults() {
        guard let bundled = Self.bundled() else { return }
        update(bundled)
    }

    /// Tire la réplique de la prochaine dictée.
    func draw() -> MovieLine? {
        let line = book.draw(after: previous)
        previous = line
        return line
    }

    private static func bundled() -> MovieLineBook? {
        guard let url = Bundle.main.url(forResource: "repliques.default", withExtension: "json") else {
            return nil
        }
        return try? MovieLineBook.load(from: url)
    }

    private func installDefault(at url: URL) {
        do {
            try createDirectoryIfNeeded()
            guard let bundled = Bundle.main.url(forResource: "repliques.default", withExtension: "json") else {
                Log.lifecycle.notice("aucune réplique par défaut dans le bundle")
                return
            }
            try FileManager.default.copyItem(at: bundled, to: url)
            Log.lifecycle.notice("répliques par défaut installées")
        } catch {
            Log.lifecycle.error("installation des répliques : \(error.localizedDescription, privacy: .public)")
        }
    }

    private func createDirectoryIfNeeded() throws {
        let directory = Self.fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}
