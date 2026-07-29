import Foundation
import FoundationModels

/// Correcteur fondé sur le modèle de langue embarqué de macOS 26.
///
/// Tourne entièrement sur l'appareil, sans réseau ni dépendance. C'est le choix par
/// défaut : la latence se compte en fractions de seconde là où un modèle servi par
/// Ollama demande plus d'une seconde.
///
/// Réserve connue : ses garde-fous de contenu peuvent refuser un texte de procédure
/// pénale — violences, infractions sexuelles. Le refus est remonté tel quel afin que
/// `CorrectionService` bascule sur le repli plutôt que d'abandonner la correction.
final class AppleFoundationCorrector: TextCorrector {

    let identifier = "apple-fm"
    let displayName = "Apple (sur l'appareil)"

    private let holder = SessionHolder()

    func isAvailable() async -> Bool {
        SystemLanguageModel.default.isAvailable
    }

    /// Raison de l'indisponibilité, à afficher dans les réglages.
    static var unavailabilityReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible: return "appareil non compatible"
            case .appleIntelligenceNotEnabled: return "Apple Intelligence désactivée"
            case .modelNotReady: return "modèle en cours de téléchargement"
            @unknown default: return "indisponible"
            }
        @unknown default:
            return "indisponible"
        }
    }

    func warmUp() async {
        await holder.prepare()
    }

    func correct(_ text: String, styleNotes: [String]) async throws -> String {
        try await holder.correct(text, styleNotes: styleNotes)
    }
}

/// Les sessions sont conservées entre deux corrections : les recréer à chaque
/// dictée referait payer l'initialisation du modèle. Il y en a une par jeu de
/// règles de style — en pratique, une par profil réellement utilisé.
private actor SessionHolder {

    private var sessions: [String: LanguageModelSession] = [:]

    private func makeSession(styleNotes: [String]) -> LanguageModelSession {
        LanguageModelSession(instructions: CorrectionPrompt.instructions(styleNotes: styleNotes))
    }

    private static func key(for styleNotes: [String]) -> String {
        styleNotes.joined(separator: "\u{1}")
    }

    func prepare() {
        guard SystemLanguageModel.default.isAvailable else { return }
        let key = Self.key(for: [])
        if sessions[key] == nil { sessions[key] = makeSession(styleNotes: []) }
    }

    func correct(_ text: String, styleNotes: [String]) async throws -> String {
        guard SystemLanguageModel.default.isAvailable else {
            throw CorrectionError.unavailable(
                AppleFoundationCorrector.unavailabilityReason ?? "Apple"
            )
        }

        let key = Self.key(for: styleNotes)
        let session = sessions[key] ?? makeSession(styleNotes: styleNotes)
        sessions[key] = session

        // Température basse : on veut une correction reproductible, pas une variation
        // stylistique. Le plafond de jetons évite qu'un modèle parti en digression
        // ne produise une réponse sans rapport avec la dictée.
        let options = GenerationOptions(
            temperature: 0.1,
            maximumResponseTokens: max(256, text.count)
        )

        do {
            let response = try await session.respond(
                to: CorrectionPrompt.prompt(for: text),
                options: options
            )
            return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch let error as LanguageModelSession.GenerationError {
            // Une session ayant refusé un contenu reste marquée : on la jette pour
            // que la dictée suivante reparte sur une session saine.
            sessions[key] = nil
            throw Self.translate(error)
        } catch {
            sessions[key] = nil
            throw CorrectionError.failed(error.localizedDescription)
        }
    }

    private static func translate(_ error: LanguageModelSession.GenerationError) -> CorrectionError {
        switch error {
        case .guardrailViolation:
            return .contentRefused("le modèle Apple")
        case .exceededContextWindowSize:
            return .failed("dictée trop longue pour le modèle Apple")
        case .unsupportedLanguageOrLocale:
            return .unavailable("Apple (langue non prise en charge)")
        default:
            return .failed(error.localizedDescription)
        }
    }
}
