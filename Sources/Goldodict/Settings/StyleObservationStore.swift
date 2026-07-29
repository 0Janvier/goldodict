import Foundation
import GoldodictCore

/// Persistance des corrections observées, sur le patron de `ProfileStore`.
///
/// Le fichier ne contient jamais le texte d'une dictée : uniquement des paires
/// courtes, leurs compteurs et les décisions prises — un journal d'apprentissage
/// lisible à la main.
@MainActor
final class StyleObservationStore {

    /// `~/Library/Application Support/Goldodict/style-observations.json`
    static var fileURL: URL { SupportDirectory.url(for: "style-observations.json") }

    private(set) var observations = StyleObservations()

    func load() {
        let url = Self.fileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            observations = try StyleObservations.load(from: url)
            Log.lifecycle.notice("observations de style chargées : \(self.observations.entries.count)")
        } catch {
            Log.lifecycle.error("observations illisibles : \(error.localizedDescription, privacy: .public)")
            observations = StyleObservations()
        }
    }

    func save() {
        do {
            let directory = Self.fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try observations.save(to: Self.fileURL)
        } catch {
            Log.lifecycle.error("observations non enregistrées : \(error.localizedDescription, privacy: .public)")
        }
    }

    func record(before: String, after: String, profileName: String, kind: StyleSuggestionKind) {
        observations.record(before: before, after: after, profileName: profileName, kind: kind)
        save()
    }

    func setStatus(_ status: StyleObservation.Status, id: String) {
        observations.setStatus(status, id: id)
        save()
    }
}
