import AbracadabraCore
import Foundation

/// Persistance du lexique dans un fichier JSON éditable à la main.
///
/// Le format reste volontairement lisible : ajouter un terme ne doit pas exiger
/// d'ouvrir l'application.
@MainActor
final class LexiconStore {

    /// `~/Library/Application Support/Abracadabra/lexique.json`
    static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base
            .appendingPathComponent("Abracadabra", isDirectory: true)
            .appendingPathComponent("lexique.json")
    }

    private(set) var lexicon = Lexicon()

    /// Charge le lexique de l'utilisateur, en l'initialisant depuis le modèle livré
    /// avec l'application au premier lancement.
    func load() {
        let url = Self.fileURL

        if !FileManager.default.fileExists(atPath: url.path) {
            installDefault(at: url)
        }

        do {
            lexicon = try Lexicon.load(from: url)
            Log.lifecycle.notice("lexique chargé : \(self.lexicon.entries.count) entrées")
        } catch {
            Log.lifecycle.error("lexique illisible : \(error.localizedDescription, privacy: .public)")
            lexicon = Lexicon()
        }
    }

    func save() {
        do {
            try createDirectoryIfNeeded()
            try lexicon.save(to: Self.fileURL)
        } catch {
            Log.lifecycle.error("lexique non enregistré : \(error.localizedDescription, privacy: .public)")
        }
    }

    func update(_ lexicon: Lexicon) {
        self.lexicon = lexicon
        save()
    }

    private func installDefault(at url: URL) {
        do {
            try createDirectoryIfNeeded()
            guard let bundled = Bundle.main.url(forResource: "lexique.default", withExtension: "json") else {
                Log.lifecycle.notice("aucun lexique par défaut dans le bundle")
                return
            }
            try FileManager.default.copyItem(at: bundled, to: url)
            Log.lifecycle.notice("lexique par défaut installé")
        } catch {
            Log.lifecycle.error("installation du lexique : \(error.localizedDescription, privacy: .public)")
        }
    }

    private func createDirectoryIfNeeded() throws {
        let directory = Self.fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}
