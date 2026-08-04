import GoldodictCore
import Foundation

/// Orchestre la correction : choix du correcteur, délai maximal, repli, contrôle
/// de fidélité.
///
/// Aucune de ces étapes n'est silencieuse. Une correction abandonnée ou refusée
/// laisse passer le texte brut et se signale, parce qu'un avocat doit savoir ce qui
/// a été fait de sa dictée.
actor CorrectionService {

    /// Résultat rendu au contrôleur.
    struct Outcome: Sendable {
        let text: String
        let applied: Bool
        /// Renseigné lorsque la correction n'a pas été appliquée.
        let note: String?
    }

    /// Au-delà, la dictée brute part telle quelle : un texte imparfait vaut mieux
    /// qu'un texte qui n'arrive pas.
    private static let deadline: Duration = .seconds(4)

    /// État des deux correcteurs, pour l'affichage dans les réglages.
    struct Availability: Sendable {
        let apple: Bool
        let ollama: OllamaCorrector.Availability
    }

    private let apple = AppleFoundationCorrector()
    /// Remplacé, et non muté : le modèle est immuable dans `OllamaCorrector`, ce qui
    /// évite une propriété partagée entre l'acteur et les appels en vol.
    private var ollama: OllamaCorrector
    private var guardRail = CorrectionGuard()
    private var primaryIdentifier = "apple"
    private var useFallback = true

    init(ollamaModel: String = OllamaCorrector.defaultModel) {
        ollama = OllamaCorrector(model: ollamaModel)
    }

    func setThresholds(_ thresholds: CorrectionGuard.Thresholds) {
        guardRail.thresholds = thresholds
    }

    /// Ordre d'essai des correcteurs.
    ///
    /// Apple d'abord vaut pour la latence, pas dans l'absolu : un Ollama monté avec
    /// un gros modèle corrige souvent mieux, et son seul défaut est de coûter une
    /// seconde de plus. L'arbitrage entre vitesse et qualité revient à celui qui
    /// dicte, pas à l'application.
    ///
    /// - Parameter fallback: essayer l'autre quand le premier refuse le contenu,
    ///   manque, ou dépasse le délai. Sans lui, un refus laisse passer le texte brut.
    func setOrder(primary: String, fallback: Bool) {
        primaryIdentifier = primary
        useFallback = fallback
    }

    /// Les correcteurs à essayer, dans l'ordre.
    private var chain: [TextCorrector] {
        let ordered: [TextCorrector] = primaryIdentifier == ollama.identifier
            ? [ollama, apple]
            : [apple, ollama]
        return useFallback ? ordered : Array(ordered.prefix(1))
    }

    /// Change le modèle de repli et le précharge s'il est servi.
    func setOllamaModel(_ model: String) async {
        guard model != ollama.model else { return }
        ollama = OllamaCorrector(model: model)
        Log.engine.notice("modèle Ollama choisi : \(model, privacy: .public)")
        if await ollama.isAvailable() { await ollama.warmUp() }
    }

    /// Prépare les deux correcteurs. Le préchargement d'Ollama est le plus utile :
    /// sans lui, la première correction dépasserait le délai pour rien.
    func warmUp() async {
        if await apple.isAvailable() {
            await apple.warmUp()
            Log.engine.notice("correcteur Apple prêt")
        } else {
            Log.engine.notice(
                "correcteur Apple indisponible : \(AppleFoundationCorrector.unavailabilityReason ?? "raison inconnue", privacy: .public)"
            )
        }

        switch await ollama.availability() {
        case .ready:
            await ollama.warmUp()
        case .modelMissing(let served):
            Log.engine.notice(
                "Ollama tourne mais ne sert pas \(self.ollama.model, privacy: .public) — servis : [\(served.joined(separator: ", "), privacy: .public)]"
            )
        case .daemonUnreachable:
            Log.engine.notice("démon Ollama injoignable, pas de repli de correction")
        }
    }

    /// Correcteurs opérationnels, pour l'affichage dans les réglages.
    func availability() async -> Availability {
        await Availability(apple: apple.isAvailable(), ollama: ollama.availability())
    }

    func correct(_ raw: String, styleNotes: [String] = []) async -> Outcome {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return Outcome(text: raw, applied: false, note: nil)
        }

        var note: String?
        for corrector in chain {
            do {
                let corrected = try await withDeadline(Self.deadline) {
                    try await corrector.correct(trimmed, styleNotes: styleNotes)
                }
                let verdict = guardRail.evaluate(raw: trimmed, corrected: corrected)
                Log.engine.notice(
                    "correction \(corrector.identifier, privacy: .public) — \(verdict.summary, privacy: .public)"
                )

                if verdict.accepted {
                    return Outcome(text: corrected, applied: true, note: note)
                }
                // Une correction infidèle n'appelle pas de seconde tentative : le
                // second modèle produirait la même dérive à partir du même texte.
                return Outcome(
                    text: trimmed,
                    applied: false,
                    note: "correction écartée (\(verdict.reason ?? "infidèle"))"
                )
            } catch let error as CorrectionError {
                note = Self.describe(error, corrector: corrector)
                Log.engine.error("\(note ?? "", privacy: .public)")
            } catch {
                note = error.localizedDescription
                Log.engine.error("correction : \(error.localizedDescription, privacy: .public)")
            }
        }

        return Outcome(text: trimmed, applied: false, note: note)
    }

    private static func describe(_ error: CorrectionError, corrector: TextCorrector) -> String {
        switch error {
        case .contentRefused:
            return "\(corrector.displayName) a refusé ce contenu, repli en cours"
        case .timedOut:
            return "\(corrector.displayName) trop lent, repli en cours"
        case .unavailable(let reason):
            return "\(reason), repli en cours"
        case .failed(let detail):
            return detail
        }
    }

    /// Borne une opération dans le temps. `Task.timeout` n'existant pas, on met la
    /// tâche utile en concurrence avec une temporisation et on garde la première.
    private func withDeadline<T: Sendable>(
        _ duration: Duration,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: duration)
                throw CorrectionError.timedOut
            }
            guard let result = try await group.next() else {
                throw CorrectionError.timedOut
            }
            group.cancelAll()
            return result
        }
    }
}
