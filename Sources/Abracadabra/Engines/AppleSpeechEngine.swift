import AVFoundation
import Foundation
import Speech

/// Moteur natif macOS 26 : `SpeechAnalyzer` piloté par un module `SpeechTranscriber`.
///
/// Transcription strictement locale, au fil de l'eau, sans dépendance ni
/// téléchargement autre que le modèle de langue géré par le système.
final class AppleSpeechEngine: TranscriptionEngine {

    let identifier = "apple"
    let displayName = "Apple (macOS)"

    /// L'état est confiné dans un acteur : `SpeechAnalyzer` est lui-même un acteur,
    /// et la capture audio alimente le moteur depuis un thread temps réel.
    private let session = Session()

    static var isAvailable: Bool { SpeechTranscriber.isAvailable }

    func preferredAudioFormat() async -> AVAudioFormat {
        await session.preferredAudioFormat()
    }

    func start(locale: Locale, contextualStrings: [String]) async throws {
        try await session.start(locale: locale, contextualStrings: contextualStrings)
    }

    func feed(_ buffer: AVAudioPCMBuffer) async {
        await session.feed(buffer)
    }

    func finish() async throws -> String {
        try await session.finish()
    }

    func cancel() async {
        await session.cancel()
    }

    /// Vérifie la disponibilité du modèle pour une langue et le télécharge si besoin.
    /// Un modèle absent n'est pas une erreur : c'est un téléchargement à déclencher.
    static func prepareAssets(for locale: Locale) async throws {
        guard SpeechTranscriber.isAvailable else {
            throw TranscriptionEngineError.unavailable("Apple")
        }
        let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale)
        guard let supported else {
            throw TranscriptionEngineError.localeUnsupported(locale.identifier)
        }

        let transcriber = SpeechTranscriber(locale: supported, preset: .progressiveTranscription)
        switch await AssetInventory.status(forModules: [transcriber]) {
        case .installed:
            break
        case .unsupported:
            throw TranscriptionEngineError.localeUnsupported(supported.identifier)
        case .supported, .downloading:
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await request.downloadAndInstall()
            }
        @unknown default:
            break
        }

        // Les modèles installés sont soumis à un quota ; la réservation garantit
        // que celui du français ne sera pas évincé au profit d'une autre langue.
        _ = try? await AssetInventory.reserve(locale: supported)
    }
}

// MARK: - Session

private actor Session {

    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private var collector: Task<String, Error>?

    func preferredAudioFormat() async -> AVAudioFormat {
        let probe = SpeechTranscriber(locale: Locale(identifier: "fr_FR"), preset: .progressiveTranscription)
        return await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [probe])
            ?? AudioCapture.whisperFormat
    }

    func start(locale: Locale, contextualStrings: [String]) async throws {
        await cancel()

        guard SpeechTranscriber.isAvailable else {
            throw TranscriptionEngineError.unavailable("Apple")
        }
        guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            throw TranscriptionEngineError.localeUnsupported(locale.identifier)
        }

        let transcriber = SpeechTranscriber(locale: supported, preset: .progressiveTranscription)
        guard await AssetInventory.status(forModules: [transcriber]) == .installed else {
            throw TranscriptionEngineError.assetsMissing(supported.identifier)
        }

        let context = AnalysisContext()
        if !contextualStrings.isEmpty {
            context.contextualStrings[.general] = contextualStrings
        }

        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        let analyzer = SpeechAnalyzer(
            inputSequence: stream,
            modules: [transcriber],
            analysisContext: context
        )

        // Les résultats sont consommés en tâche de fond dès maintenant : la séquence
        // se termine d'elle-même lorsque l'analyseur est finalisé.
        collector = Task {
            var text = AttributedString()
            for try await result in transcriber.results where result.isFinal {
                text += result.text
            }
            return String(text.characters)
        }

        self.transcriber = transcriber
        self.analyzer = analyzer
        self.continuation = continuation
    }

    func feed(_ buffer: AVAudioPCMBuffer) {
        continuation?.yield(AnalyzerInput(buffer: buffer))
    }

    func finish() async throws -> String {
        guard let analyzer, let collector else {
            throw TranscriptionEngineError.notStarted
        }
        continuation?.finish()
        try await analyzer.finalizeAndFinishThroughEndOfInput()

        let text = try await collector.value
        teardown()
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func cancel() async {
        continuation?.finish()
        collector?.cancel()
        if let analyzer {
            await analyzer.cancelAndFinishNow()
        }
        teardown()
    }

    private func teardown() {
        continuation = nil
        collector = nil
        analyzer = nil
        transcriber = nil
    }
}
