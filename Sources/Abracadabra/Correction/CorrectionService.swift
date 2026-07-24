import AbracadabraCore
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

    private let apple = AppleFoundationCorrector()
    private let ollama: OllamaCorrector
    private var guardRail = CorrectionGuard()

    init(ollamaModel: String = OllamaCorrector.defaultModel) {
        ollama = OllamaCorrector(model: ollamaModel)
    }

    func setThresholds(_ thresholds: CorrectionGuard.Thresholds) {
        guardRail.thresholds = thresholds
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

        if await ollama.isAvailable() {
            await ollama.warmUp()
        } else {
            Log.engine.notice("Ollama indisponible, pas de repli de correction")
        }
    }

    /// Correcteurs opérationnels, pour l'affichage dans les réglages.
    func availability() async -> (apple: Bool, ollama: Bool) {
        await (apple.isAvailable(), ollama.isAvailable())
    }

    func correct(_ raw: String) async -> Outcome {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return Outcome(text: raw, applied: false, note: nil)
        }

        // Apple d'abord pour la latence ; Ollama prend le relais s'il refuse le
        // contenu, s'il est indisponible ou s'il est trop lent.
        var note: String?
        for corrector in [apple as TextCorrector, ollama as TextCorrector] {
            do {
                let corrected = try await withDeadline(Self.deadline) {
                    try await corrector.correct(trimmed)
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
