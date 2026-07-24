import Foundation

/// Emplacement des fichiers de configuration, et reprise de ceux d'Abracadabra.
///
/// L'application s'est appelée Abracadabra jusqu'à la version 0.1.0 et écrivait
/// dans `~/Library/Application Support/Abracadabra/`. Le lexique et les profils y
/// représentent un travail de réglage que personne n'a envie de refaire : ils sont
/// recopiés au premier accès. La copie est délibérée plutôt qu'un déplacement, pour
/// qu'un retour à l'ancienne version reste possible tant que l'utilisateur n'a pas
/// supprimé l'ancien dossier lui-même.
enum SupportDirectory {

    private static let current = "Goldodict"
    private static let legacy = "Abracadabra"

    /// Fichier de configuration, l'ancien dossier ayant été repris s'il existait.
    static func url(for name: String) -> URL {
        let directory = base(current)
        adoptLegacyIfNeeded(into: directory)
        return directory.appendingPathComponent(name)
    }

    private static func base(_ folder: String) -> URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(folder, isDirectory: true)
    }

    /// Recopie une seule fois par lancement, et seulement si le dossier actuel
    /// n'existe pas encore : une reprise ultérieure écraserait des réglages récents.
    private static var adopted = false

    private static func adoptLegacyIfNeeded(into directory: URL) {
        guard !adopted else { return }
        adopted = true

        let manager = FileManager.default
        let source = base(legacy)
        guard manager.fileExists(atPath: source.path),
              !manager.fileExists(atPath: directory.path) else { return }

        do {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            let contents = try manager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
            for file in contents {
                let destination = directory.appendingPathComponent(file.lastPathComponent)
                guard !manager.fileExists(atPath: destination.path) else { continue }
                try manager.copyItem(at: file, to: destination)
            }
            Log.lifecycle.notice("réglages repris depuis Abracadabra : \(contents.count) fichiers")
        } catch {
            Log.lifecycle.error("reprise Abracadabra : \(error.localizedDescription, privacy: .public)")
        }
    }
}
