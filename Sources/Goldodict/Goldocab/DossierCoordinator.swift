import AppKit
import Foundation
import GoldodictCore
import Observation

/// Pont Goldocab : dossier actif, vocabulaire éphémère, imputation du temps.
@Observable
@MainActor
final class DossierCoordinator {

    private let goldocabReader = GoldocabReader()

    /// Dossier sélectionné dans le panneau. Éphémère : jamais persisté, son
    /// vocabulaire disparaît avec lui.
    private(set) var activeDossier: DossierContext?

    /// Dossiers ouverts dans Goldocab, rafraîchis à l'ouverture du panneau.
    private(set) var availableDossiers: [DossierContext] = []

    /// Temps de dictée cumulé sur le dossier actif depuis sa sélection ou la
    /// dernière imputation.
    private(set) var dossierSessionSeconds: TimeInterval = 0
    private var dossierSessionStart: Date?

    /// Temps non imputé des dossiers quittés : un basculement — surtout
    /// automatique — ne doit jamais effacer des minutes à facturer.
    private var parkedSessions: [Int64: (seconds: TimeInterval, start: Date?)] = [:]

    var contextualTerms: [String] { activeDossier?.terms ?? [] }

    func refresh() {
        availableDossiers = goldocabReader.activeDossiers()
        if let current = activeDossier,
           !availableDossiers.contains(where: { $0.id == current.id }) {
            select(nil)
        }
    }

    func select(_ dossier: DossierContext?) {
        guard dossier?.id != activeDossier?.id else { return }

        if let previous = activeDossier, dossierSessionSeconds > 0 {
            parkedSessions[previous.id] = (dossierSessionSeconds, dossierSessionStart)
        }
        activeDossier = dossier
        if let dossier, let parked = parkedSessions.removeValue(forKey: dossier.id) {
            dossierSessionSeconds = parked.seconds
            dossierSessionStart = parked.start
        } else {
            dossierSessionSeconds = 0
            dossierSessionStart = nil
        }

        if let dossier {
            Log.goldocab.notice("dossier actif : \(dossier.code, privacy: .private) (\(dossier.terms.count) termes)")
        } else {
            Log.goldocab.notice("aucun dossier actif")
        }
    }

    /// Cherche un code de dossier dans le titre de la fenêtre visée et bascule
    /// dessus. Silencieux par construction.
    func autoDetect(for application: NSRunningApplication?) {
        guard let title = WindowTitleReader.focusedWindowTitle(of: application) else { return }
        if availableDossiers.isEmpty {
            availableDossiers = goldocabReader.activeDossiers()
        }
        var match = DossierCodeDetector.match(in: title, among: availableDossiers)
        if match == nil, !DossierCodeDetector.codes(in: title).isEmpty {
            availableDossiers = goldocabReader.activeDossiers()
            match = DossierCodeDetector.match(in: title, among: availableDossiers)
        }
        guard let match, match.id != activeDossier?.id else { return }
        select(match)
        Log.goldocab.notice("dossier détecté par la fenêtre : \(match.code, privacy: .private)")
    }

    func markSessionStart(at date: Date) {
        if activeDossier != nil, dossierSessionStart == nil {
            dossierSessionStart = date
        }
    }

    func addCaptureDuration(from start: Date) {
        guard activeDossier != nil else { return }
        dossierSessionSeconds += Date().timeIntervalSince(start)
    }

    func impute() throws {
        guard let dossier = activeDossier, dossierSessionSeconds > 0 else { return }
        try OutboxWriter.deposit(.dictation(
            dossier: dossier,
            startedAt: dossierSessionStart ?? Date(),
            duration: dossierSessionSeconds
        ))
        dossierSessionSeconds = 0
        dossierSessionStart = nil
    }

    // MARK: - Relais de relance

    private static let handoffKey = "speechRelaunchHandoff"

    func prepareRelaunchHandoff() {
        guard let dossier = activeDossier else { return }
        var payload: [String: Any] = [
            "dossierId": NSNumber(value: dossier.id),
            "seconds": dossierSessionSeconds,
        ]
        if let start = dossierSessionStart {
            payload["start"] = start.timeIntervalSince1970
        }
        UserDefaults.standard.set(payload, forKey: Self.handoffKey)
    }

    func restoreRelaunchHandoff() {
        guard let payload = UserDefaults.standard.dictionary(forKey: Self.handoffKey) else { return }
        UserDefaults.standard.removeObject(forKey: Self.handoffKey)
        guard let id = (payload["dossierId"] as? NSNumber)?.int64Value else { return }

        availableDossiers = goldocabReader.activeDossiers()
        guard let dossier = availableDossiers.first(where: { $0.id == id }) else { return }
        activeDossier = dossier
        dossierSessionSeconds = payload["seconds"] as? Double ?? 0
        if let start = payload["start"] as? Double {
            dossierSessionStart = Date(timeIntervalSince1970: start)
        }
        Log.goldocab.notice("dossier \(dossier.code, privacy: .private) repris après relance (\(Int(self.dossierSessionSeconds)) s en cours)")
    }
}
