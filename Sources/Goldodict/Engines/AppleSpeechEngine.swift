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
    }

    /// Rend le module utilisable par le processus courant.
    ///
    /// **Le framework nomme presque pareil deux notions distinctes.**
    /// `SpeechTranscriber.installedLocales` dit ce que le système a téléchargé, une
    /// fois pour toutes. `AssetInventory.status(forModules:)` dit si le modèle est
    /// rattaché au processus courant, et ce rattachement se perd — au lancement
    /// suivant, mais aussi en cours de session : statut `installed` à 16 h 26,
    /// retombé à `supported` à 17 h 41 dans le même processus.
    ///
    /// Le geste qui rattache est `reserve(locale:)`, pas le téléchargement. Sonde du
    /// 27/07/2026, processus neuf, modèle déjà téléchargé : statut `supported`,
    /// `reserve` rend `true`, statut `installed` dans la foulée, sans qu'un octet
    /// soit transféré. La version précédente appelait bien `reserve` mais jetait son
    /// `Bool` : une réservation refusée passait pour un succès, et l'échec ne se
    /// manifestait qu'au verdict final, où il était imputé au téléchargement.
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

        await attach(locale, named: name)
        if await AssetInventory.status(forModules: [transcriber]) == .installed {
            Log.engine.notice("modèle \(name, privacy: .public) rattaché par réservation, sans téléchargement")
            return
        }

        // Le téléchargement ne sert que si le modèle manque vraiment sur la machine.
        // `nil` n'est pas un succès : le module n'est pas installé et le système
        // n'offre rien pour l'installer. Le taire reviendrait à annoncer une
        // préparation réussie puis à échouer au premier mot dicté.
        guard let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) else {
            Log.engine.error("modèle \(name, privacy: .public) : aucune requête d'installation disponible")
            throw TranscriptionEngineError.assetsMissing(name)
        }

        Log.engine.notice("téléchargement du modèle \(name, privacy: .public)…")
        try await request.downloadAndInstall()

        // Un téléchargement réussi laisse encore le rattachement à faire.
        await attach(locale, named: name)

        let after = await AssetInventory.status(forModules: [transcriber])
        Log.engine.notice("modèle \(name, privacy: .public) : statut après installation \(String(describing: after), privacy: .public)")
        guard after == .installed else {
            throw TranscriptionEngineError.assetsMissing(name)
        }
    }

    /// Verdict de la sonde de santé du service de reconnaissance.
    enum ServiceHealth {
        /// Le modèle est rattaché au processus, la dictée fonctionnera.
        case healthy
        /// Le modèle est téléchargé mais le rattachement échoue : la connexion XPC
        /// du framework vers le démon est morte et ne reviendra pas dans ce
        /// processus. Seule une relance de l'application répare.
        case deadConnection
        /// Le modèle manque vraiment ou la langue n'est pas prise en charge —
        /// relancer n'y changerait rien.
        case degraded
    }

    /// Sonde l'état du service sans rien télécharger.
    ///
    /// macOS arrête le démon Speech après une période d'inactivité et le framework,
    /// qui tient sa connexion XPC dans un singleton, ne la recrée jamais : chaque
    /// appel à `AssetInventory` échoue alors en silence (erreur 4099 dans le journal)
    /// en rendant `supported`, `false` et des listes vides. Constaté le 29/07/2026 :
    /// dictées saines jusqu'à 11 h 45, connexion morte à 14 h 49 après trois heures
    /// de repos, état identique trente et une minutes plus tard. La signature de cet
    /// état : le rattachement refuse alors que `SpeechTranscriber.installedLocales`
    /// — qui, lui, répond juste même connexion morte — contient bien la langue.
    static func probeHealth(locale: Locale) async -> ServiceHealth {
        guard SpeechTranscriber.isAvailable,
              let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            return .degraded
        }
        let transcriber = makeTranscriber(locale: supported)
        if await AssetInventory.status(forModules: [transcriber]) == .installed {
            return .healthy
        }
        let name = supported.identifier(.bcp47)
        await attach(supported, named: name)
        if await AssetInventory.status(forModules: [transcriber]) == .installed {
            return .healthy
        }
        let downloaded = await SpeechTranscriber.installedLocales
        if downloaded.contains(where: { $0.identifier(.bcp47) == name }) {
            return .deadConnection
        }
        return .degraded
    }

    /// Rattache la locale au processus par réservation, en reprenant la réservation
    /// que le système a pu révoquer.
    ///
    /// `reserve` rend `false` sans lever d'erreur quand il ne réserve rien, et ce
    /// `Bool` est alors la seule trace de l'échec. La libération avant reprise est
    /// tentée sans condition : la panne du 27/07/2026 à 18 h 54 a montré une vue
    /// processus désynchronisée au point de tout contredire — statut `supported` et
    /// `reserve` refusé dans l'app, pendant qu'un processus neuf lisait au même
    /// instant `installed` et la réservation en place. Une garde fondée sur
    /// `reservedLocales` lu depuis le processus malade ne déclenche donc jamais.
    /// Sans réservation à libérer, `release` rend `false` et ne coûte rien.
    private static func attach(_ locale: Locale, named name: String) async {
        if await reserve(locale, named: name) { return }

        let reserved = await AssetInventory.reservedLocales.map { $0.identifier(.bcp47) }
        let downloaded = await SpeechTranscriber.installedLocales.map { $0.identifier(.bcp47) }
        Log.engine.notice(
            "vue du processus — réservées : [\(reserved.joined(separator: ", "), privacy: .public)] sur \(AssetInventory.maximumReservedLocales, privacy: .public), téléchargées : [\(downloaded.joined(separator: ", "), privacy: .public)]"
        )

        let released = await AssetInventory.release(reservedLocale: locale)
        Log.engine.notice("réservation \(name, privacy: .public) libérée pour reprise : \(released, privacy: .public)")
        _ = await reserve(locale, named: name)
    }

    private static func reserve(_ locale: Locale, named name: String) async -> Bool {
        do {
            let accepted = try await AssetInventory.reserve(locale: locale)
            Log.engine.notice("réservation du modèle \(name, privacy: .public) : \(accepted, privacy: .public)")
            return accepted
        } catch {
            Log.engine.error("réservation du modèle \(name, privacy: .public) refusée : \(error.localizedDescription, privacy: .public)")
            return false
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
