import GoldodictCore
import Foundation

/// Persistance des profils par application, sur le patron de `LexiconStore`.
///
/// Fichier JSON lisible, à côté du lexique : ajouter une application à un profil ne
/// doit pas obliger à ouvrir l'application.
@MainActor
final class ProfileStore {

    /// `~/Library/Application Support/Goldodict/profils.json`
    static var fileURL: URL { SupportDirectory.url(for: "profils.json") }

    private(set) var profiles = ProfileSet()

    func load() {
        let url = Self.fileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            save()
            return
        }

        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode([AppProfile].self, from: data)
            guard !decoded.isEmpty else {
                Log.lifecycle.error("profils vides, retour aux valeurs par défaut")
                profiles = ProfileSet()
                return
            }
            profiles = ProfileSet(profiles: decoded)
            Log.lifecycle.notice("profils chargés : \(self.profiles.profiles.count)")
        } catch {
            Log.lifecycle.error("profils illisibles : \(error.localizedDescription, privacy: .public)")
            profiles = ProfileSet()
        }
    }

    func save() {
        do {
            let directory = Self.fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try encoder.encode(profiles.profiles).write(to: Self.fileURL, options: .atomic)
        } catch {
            Log.lifecycle.error("profils non enregistrés : \(error.localizedDescription, privacy: .public)")
        }
    }

    func update(_ profile: AppProfile) {
        profiles.replace(profile)
        save()
    }
}
