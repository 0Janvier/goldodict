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

    func start(
        locale: Locale,
        contextualStrings: [String],
        onPartialText: (@Sendable (String) -> Void)?
    ) async throws {
        try await session.start(
            locale: locale,
            contextualStrings: contextualStrings,
            onPartialText: onPartialText
        )
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

    /// Construit le module de transcription. Une fabrique unique, parce que
    /// l'installation d'asset et la session doivent porter sur la même configuration.
    ///
    /// Le contenu des presets n'est pas documenté : l'initialiseur explicite est le
    /// seul moyen de garantir l'émission des résultats volatils, sans lesquels rien
    /// ne peut s'afficher pendant que l'utilisateur parle.
    static func makeTranscriber(locale: Locale) -> SpeechTranscriber {
        SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )
    }

    /// Vérifie la disponibilité du modèle pour une langue et le télécharge si besoin.
    /// Un modèle absent n'est pas une erreur : c'est un téléchargement à déclencher.
    static func prepareAssets(for locale: Locale) async throws {
        guard SpeechTranscriber.isAvailable else {
            throw TranscriptionEngineError.unavailable("Apple")
        }
        guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            throw TranscriptionEngineError.localeUnsupported(locale.identifier)
        }
        try await install(makeTranscriber(locale: supported), locale: supported)

        // Les modèles installés sont soumis à un quota ; la réservation garantit
        // que celui du français ne sera pas évincé au profit d'une autre langue.
        do {
            try await AssetInventory.reserve(locale: supported)
        } catch {
            // Sans effet sur la dictée du jour : une réservation refusée signifie
            // seulement que le modèle pourra être évincé plus tard.
            Log.engine.notice("réservation du modèle refusée : \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Rend le module utilisable, en installant l'asset de langue si nécessaire.
    ///
    /// **Le statut n'est pas persistant.** `AssetInventory` le rend pour le processus
    /// courant : une installation faite au lancement couvre toutes les instances de la
    /// session, mais tout retombe à `.supported` au processus suivant. La vérification
    /// a donc lieu aussi à l'ouverture de chaque dictée, et pas seulement au démarrage.
    ///
    /// Toutes les branches sont tracées. La version précédente rendait la main en
    /// silence quand `assetInstallationRequest` valait `nil`, si bien que l'échec ne se
    /// manifestait qu'à la première dictée, treize minutes plus tard, sans rien dans le
    /// journal pour dire ce qui avait été tenté.
    static func install(_ transcriber: SpeechTranscriber, locale: Locale) async throws {
        let name = locale.identifier(.bcp47)
        let status = await AssetInventory.status(forModules: [transcriber])
        Log.engine.notice("modèle \(name, privacy: .public) : statut \(String(describing: status), privacy: .public)")

        switch status {
        case .installed:
            return
        case .unsupported:
            throw TranscriptionEngineError.localeUnsupported(name)
        default:
            break
        }

        // `nil` n'est pas un succès : le module n'est pas installé et le système
        // n'offre rien pour l'installer. Le taire reviendrait à annoncer une
        // préparation réussie puis à échouer au premier mot dicté.
        guard let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) else {
            Log.engine.error("modèle \(name, privacy: .public) : aucune requête d'installation disponible")
            throw TranscriptionEngineError.assetsMissing(name)
        }

        Log.engine.notice("téléchargement du modèle \(name, privacy: .public)…")
        try await request.downloadAndInstall()

        let after = await AssetInventory.status(forModules: [transcriber])
        Log.engine.notice("modèle \(name, privacy: .public) : statut après installation \(String(describing: after), privacy: .public)")
        guard after == .installed else {
            throw TranscriptionEngineError.assetsMissing(name)
        }
    }
}

// MARK: - Session

private actor Session {

    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private var collector: Task<String, Error>?
    private var expectedFormat: AVAudioFormat?
    private var rejectedBuffers = 0

    func preferredAudioFormat() async -> AVAudioFormat {
        let probe = AppleSpeechEngine.makeTranscriber(locale: Locale(identifier: "fr_FR"))
        let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [probe])
            ?? AudioCapture.whisperFormat
        expectedFormat = format
        return format
    }

    func start(
        locale: Locale,
        contextualStrings: [String],
        onPartialText: (@Sendable (String) -> Void)?
    ) async throws {
        await cancel()

        guard SpeechTranscriber.isAvailable else {
            throw TranscriptionEngineError.unavailable("Apple")
        }
        guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            throw TranscriptionEngineError.localeUnsupported(locale.identifier)
        }

        // L'installation est refaite ici, et pas seulement au lancement : le statut
        // rendu par `AssetInventory` ne vaut que pour le processus courant. Elle est
        // instantanée quand le modèle est déjà attaché. La capture, elle, tourne déjà
        // et le relais conserve les tampons produits pendant ce temps.
        let transcriber = AppleSpeechEngine.makeTranscriber(locale: supported)
        try await AppleSpeechEngine.install(transcriber, locale: supported)

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
        //
        // Deux natures de résultat cohabitent. Les résultats finaux s'ajoutent au
        // texte définitif. Les volatils sont des hypothèses de travail que le moteur
        // remplace à mesure qu'il écoute : ils ne s'accumulent pas, seul le dernier
        // vaut, et il est concaténé au texte acquis pour l'affichage.
        collector = Task {
            var settled = AttributedString()
            for try await result in transcriber.results {
                if result.isFinal {
                    settled += result.text
                    onPartialText?(String(settled.characters))
                } else {
                    onPartialText?(String(settled.characters) + String(result.text.characters))
                }
            }
            return String(settled.characters)
        }

        self.transcriber = transcriber
        self.analyzer = analyzer
        self.continuation = continuation
    }

    func feed(_ buffer: AVAudioPCMBuffer) {
        // Un tampon au mauvais format ne provoque pas une erreur côté framework
        // mais une assertion fatale qui tue le processus. On l'écarte ici.
        if let expectedFormat, buffer.format != expectedFormat {
            rejectedBuffers += 1
            if rejectedBuffers == 1 {
                Log.engine.error(
                    "tampon écarté, format \(buffer.format, privacy: .public) au lieu de \(expectedFormat, privacy: .public)"
                )
            }
            return
        }
        continuation?.yield(AnalyzerInput(buffer: buffer))
    }

    func finish() async throws -> String {
        guard let analyzer, let collector else {
            throw TranscriptionEngineError.notStarted
        }
        continuation?.finish()
        Log.engine.debug("flux clos, appel de finalizeAndFinishThroughEndOfInput")
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        Log.engine.debug("analyseur finalisé, attente du collecteur")

        let text = try await collector.value
        Log.engine.debug("collecteur terminé")
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
        rejectedBuffers = 0
    }
}
