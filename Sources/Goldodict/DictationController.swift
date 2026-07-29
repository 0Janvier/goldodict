import GoldodictCore
import AppKit
import AVFoundation
import Foundation
import Observation

enum AudioImportError: LocalizedError {
    case busy

    var errorDescription: String? {
        switch self {
        case .busy: return "une dictée est en cours, réessayez après"
        }
    }
}

/// Chef d'orchestre de la dictée : il relie le raccourci, la capture audio, le
/// moteur de transcription et l'insertion du texte. Il ne connaîtra jamais qu'un
/// protocole de moteur, jamais un moteur particulier.
@Observable
@MainActor
final class DictationController {

    private(set) var state: DictationState = .idle {
        didSet {
            reflectStateInOverlay()
            onStateChange?(state)
            if case .failed(let message) = state { lastFailure = message }
        }
    }
    private(set) var lastTranscript: String = ""

    /// Dernier échec, indépendant de `state`.
    ///
    /// `state` revient à `.idle` cinq secondes après un échec — la pastille flottante
    /// ne doit pas rester rouge indéfiniment. Le panneau de la barre des menus, lui,
    /// est consulté après coup : l'erreur y reste jusqu'à ce qu'une nouvelle dictée
    /// démarre ou que l'utilisateur la referme.
    private(set) var lastFailure: String?

    func dismissFailure() {
        lastFailure = nil
    }

    /// Prévient la barre des menus. L'icône du `NSStatusItem` est une image AppKit,
    /// hors de portée du suivi d'observation de SwiftUI : sans ce rappel, elle
    /// resterait au repos pendant toute la dictée.
    @ObservationIgnored
    var onStateChange: ((DictationState) -> Void)?

    private let overlay = RecordingOverlay()
    private var overlayDismissal: Task<Void, Never>?

    /// La pastille flottante est le seul retour réellement visible : l'icône de la
    /// barre des menus disparaît derrière le chevron dès que la barre est chargée.
    ///
    /// La confirmation d'insertion s'efface plus vite qu'une erreur : elle apprend
    /// que tout s'est bien passé, ce qui se lit d'un coup d'œil ; un échec demande à
    /// être lu jusqu'au bout.
    private func reflectStateInOverlay() {
        overlayDismissal?.cancel()

        switch state {
        case .idle:
            overlay.hide()
        case .recording, .transcribing, .correcting, .injecting:
            overlay.show(state: state)
        case .inserted(let insertion):
            overlay.show(state: state)
            dismissOverlay(after: insertion.note == nil ? 2 : 5)
        case .failed:
            overlay.show(state: state)
            dismissOverlay(after: 5)
        }
    }

    /// L'état revient au repos en même temps que la pastille s'efface, sans quoi le
    /// menu continuerait d'annoncer la dernière insertion des heures durant.
    private func dismissOverlay(after seconds: Double) {
        overlayDismissal = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self, self.state.isTransient else { return }
            self.state = .idle
        }
    }

    /// Une dictée passée, telle que le menu la présente.
    struct Dictation: Identifiable, Equatable {
        let id = UUID()
        let text: String
        let date: Date

        /// « 14:32 ». L'heure suffit : l'historique ne survit pas à la session.
        var time: String {
            Dictation.formatter.string(from: date)
        }

        private static let formatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "fr_FR")
            formatter.dateFormat = "HH:mm"
            return formatter
        }()
    }

    /// Les vingt dernières dictées, en mémoire seule. Rien n'est écrit sur disque :
    /// ni l'audio, ni le texte, ce qui ferme la question du secret professionnel.
    private(set) var history: [Dictation] = []
    private let historyLimit = 20

    private var resolver = TriggerResolver()
    private let hotkey = HotkeyMonitor()
    private let capture = AudioCapture()
    @ObservationIgnored
    private var engine: TranscriptionEngine

    init() {
        engine = appleEngine
        // La pastille lit le niveau à sa propre cadence plutôt que de le recevoir :
        // la capture le produit sur un thread temps réel, où le moindre passage par
        // la boucle principale serait payé en craquements.
        overlay.levelProvider = { [capture] in capture.level }
    }

    /// Change de moteur. Le format audio est réinterrogé, les deux moteurs n'ayant
    /// pas les mêmes exigences.
    func select(engine newEngine: TranscriptionEngine, force: Bool = false) {
        guard !state.isBusy, force || newEngine.identifier != engine.identifier else { return }
        engine = newEngine
        audioFormat = nil
        Log.engine.notice("moteur sélectionné : \(newEngine.identifier, privacy: .public)")

        Task { [weak self] in
            let format = await newEngine.preferredAudioFormat()
            await self?.cache(audioFormat: format)
        }
    }

    var currentEngineIdentifier: String { engine.identifier }

    /// Langue de dictée. Le français est le seul usage prévu, mais le moteur Apple
    /// exige une locale explicite et le choix sera exposé dans les réglages.
    var locale = Locale(identifier: "fr_FR")

    let lexiconStore = LexiconStore()
    let repliqueStore = RepliqueStore()
    let preferences = Preferences()

    /// Réplique de la dictée en cours, tirée une fois pour toutes à son démarrage.
    private(set) var currentLine: MovieLine?

    /// Tire la réplique de la dictée qui commence et la remet à la pastille.
    ///
    /// Le tirage a lieu ici, et non dans `DictationState` : cet état doit rester une
    /// valeur déterministe, et la pastille se redessine vingt fois par seconde.
    private func drawQuote() {
        currentLine = repliqueStore.draw()
        overlay.quote = currentLine?.rendered(preferences.lineFormat)
    }

    func updateRepliques(_ book: MovieLineBook) {
        repliqueStore.update(book)
    }

    var microphoneGranted: Bool { PermissionGuard.microphoneStatus == .authorized }
    var accessibilityGranted: Bool { PermissionGuard.hasAccessibility() }
    var inputMonitoringGranted: Bool { PermissionGuard.hasInputMonitoring }

    /// Niveau sonore instantané. Même source que la pastille flottante
    /// (`overlay.levelProvider`) : le panneau de la barre des menus peut rester
    /// ouvert pendant une dictée sans dupliquer la capture.
    var currentLevel: Float { capture.level }

    /// Recharge la chaîne de traitement depuis le lexique et les réglages.
    func reloadPipeline() {
        pipeline.lexicon = lexiconStore.lexicon
        pipeline.punctuation = PunctuationCommands(options: preferences.punctuationOptions)
    }

    func updateLexicon(_ lexicon: Lexicon) {
        lexiconStore.update(lexicon)
        reloadPipeline()
    }

    func selectEngine(identifier: String) {
        preferences.engineIdentifier = identifier
        select(engine: identifier == "whisper-mlx" ? whisperEngine : appleEngine)
    }

    func updateProfile(_ profile: AppProfile) {
        profileStore.update(profile)
    }

    func correctorAvailability() async -> (apple: Bool, ollama: Bool) {
        await corrector.availability()
    }

    func setCorrectionRetention(_ value: Double) {
        preferences.correctionRetention = value
        let thresholds = CorrectionGuard.Thresholds(retention: value)
        Task { [corrector] in await corrector.setThresholds(thresholds) }
    }

    /// Moteurs disponibles, dans l'ordre d'affichage.
    let appleEngine = AppleSpeechEngine()
    private(set) var whisperEngine = WhisperMLXEngine()

    /// Change le modèle Whisper. L'instance est remplacée plutôt que mutée, le
    /// modèle étant immuable par construction.
    func selectWhisperModel(_ model: String) {
        guard !state.isBusy, model != whisperEngine.model else { return }
        preferences.whisperModel = model
        let wasSelected = currentEngineIdentifier == whisperEngine.identifier
        let previous = whisperEngine
        whisperEngine = WhisperMLXEngine(model: model)
        Task { await previous.shutdown() }
        if wasSelected { select(engine: whisperEngine, force: true) }
    }

    /// Chaîne de traitement du texte brut : ponctuation, lexique, typographie.
    private var pipeline = TranscriptPipeline()

    let profileStore = ProfileStore()
    private let corrector = CorrectionService()

    /// Profil retenu pour la dictée en cours.
    ///
    /// Il est arrêté à l'enfoncement de la touche, jamais à l'insertion : entre les
    /// deux, l'application au premier plan a pu changer, et le texte serait alors
    /// traité selon les règles d'une fenêtre qui n'est plus la cible.
    private var activeProfile: AppProfile = .redaction

    /// Nom de l'application visée, arrêté au même instant que le profil et pour la
    /// même raison : il sert à confirmer où le texte est parti.
    private var activeApplicationName: String?

    /// Vocabulaire transmis au moteur avant transcription : le lexique, enrichi
    /// des termes du dossier actif quand il y en a un.
    private var contextualStrings: [String] {
        lexiconStore.lexicon.contextualStrings + (activeDossier?.terms ?? [])
    }

    // MARK: - Dossier actif (pont Goldocab)

    private let goldocabReader = GoldocabReader()

    /// Dossier Goldocab sélectionné dans le panneau. Éphémère : jamais persisté,
    /// son vocabulaire disparaît avec lui.
    private(set) var activeDossier: DossierContext?

    /// Dossiers ouverts dans Goldocab, rafraîchis à l'ouverture du panneau.
    private(set) var availableDossiers: [DossierContext] = []

    /// Temps de dictée cumulé sur le dossier actif depuis sa sélection ou la
    /// dernière imputation.
    private(set) var dossierSessionSeconds: TimeInterval = 0
    private var dossierSessionStart: Date?
    private var captureStartedAt: Date?

    func refreshDossiers() {
        availableDossiers = goldocabReader.activeDossiers()
        // Le dossier actif suit la base : s'il a été clos entre-temps, il sort.
        if let current = activeDossier,
           !availableDossiers.contains(where: { $0.id == current.id }) {
            selectDossier(nil)
        }
    }

    func selectDossier(_ dossier: DossierContext?) {
        guard dossier?.id != activeDossier?.id else { return }
        activeDossier = dossier
        dossierSessionSeconds = 0
        dossierSessionStart = nil
        if let dossier {
            Log.goldocab.notice("dossier actif : \(dossier.code, privacy: .public) (\(dossier.terms.count) termes)")
        } else {
            Log.goldocab.notice("aucun dossier actif")
        }
    }

    /// Dépose le cumul de la session dans l'outbox Goldocab. Geste explicite,
    /// jamais automatique : l'entrée arrive « à revoir » côté Goldocab.
    func imputeDossierSession() {
        guard let dossier = activeDossier, dossierSessionSeconds > 0 else { return }
        do {
            try OutboxWriter.deposit(.dictation(
                dossier: dossier,
                startedAt: dossierSessionStart ?? Date(),
                duration: dossierSessionSeconds
            ))
            dossierSessionSeconds = 0
            dossierSessionStart = nil
        } catch {
            Log.goldocab.error("imputation impossible : \(error.localizedDescription, privacy: .public)")
            lastFailure = "imputation : \(error.localizedDescription)"
        }
    }

    private var relay: BufferRelay?

    /// Format réclamé par le moteur, interrogé une seule fois puis conservé : le
    /// résoudre à chaque dictée retarderait le démarrage de la capture.
    private var audioFormat: AVAudioFormat?

    /// Raccourci actuellement armé, affiché dans le menu.
    private(set) var trigger: HotkeyTrigger = .commandShiftJ

    /// Le raccourci tel qu'il s'écrit, dans la disposition du clavier branché.
    var triggerDisplayString: String { trigger.displayString(keyLabel: KeyLabels.label) }

    /// Le tap clavier a-t-il pu être armé ? Un échec vient d'une autorisation
    /// refusée, et il est muet : sans ce drapeau, le raccourci ne répondrait plus
    /// sans que rien ne l'explique.
    private(set) var hotkeyArmed = true

    /// Enregistre le raccourci global. À appeler une fois l'application lancée.
    func activate(trigger: HotkeyTrigger? = nil) {
        hotkey.onEvent = { [weak self] isDown in
            MainActor.assumeIsolated {
                self?.handleHotkey(isDown: isDown)
            }
        }

        let trigger = trigger ?? preferences.hotkeyTrigger
        resolver = TriggerResolver(holdThreshold: preferences.holdThreshold)
        self.trigger = trigger
        hotkeyArmed = hotkey.register(trigger)
        if !hotkeyArmed {
            state = .failed("raccourci inactif — autorisez la surveillance de l'entrée")
        }

        lexiconStore.load()
        repliqueStore.load()
        profileStore.load()
        reloadPipeline()

        // Le préchargement du modèle Ollama est déterminant : à froid, la première
        // correction demande près de huit secondes et serait abandonnée pour rien.
        let thresholds = CorrectionGuard.Thresholds(retention: preferences.correctionRetention)
        Task { [corrector] in
            await corrector.setThresholds(thresholds)
            await corrector.warmUp()
        }

        // Modèle Whisper et moteur retenus lors de la session précédente.
        if preferences.whisperModel != whisperEngine.model {
            whisperEngine = WhisperMLXEngine(model: preferences.whisperModel)
        }
        if preferences.engineIdentifier == "whisper-mlx" {
            select(engine: whisperEngine)
        }

        // Les autorisations ne sont pas demandées ici. Deux fenêtres système au
        // lancement se referment sans être lues ; elles relèvent de la fenêtre
        // d'accueil, qui les présente une par une et en montre l'état. Le manque est
        // ensuite signalé en permanence par le bandeau du menu.
        Log.lifecycle.notice(
            "autorisations — micro : \(self.microphoneGranted, privacy: .public), accessibilité : \(self.accessibilityGranted, privacy: .public), surveillance de l'entrée : \(self.inputMonitoringGranted, privacy: .public)"
        )

        // Le modèle de langue peut demander un téléchargement au premier lancement.
        // L'anticiper évite que la première dictée échoue faute de modèle.
        let locale = self.locale
        let engine = self.appleEngine as TranscriptionEngine
        Task { [weak self] in
            do {
                try await AppleSpeechEngine.prepareAssets(for: locale)
            } catch {
                await self?.reportPreparationFailure(error.localizedDescription)
            }
            // Le format doit être connu AVANT la première capture : livrer au moteur
            // un format autre que celui qu'il réclame ne produit pas une erreur mais
            // une assertion fatale dans le framework Speech.
            let format = await engine.preferredAudioFormat()
            Log.engine.notice("format du moteur : \(format, privacy: .public)")
            await self?.cache(audioFormat: format)
        }
    }

    private func reportPreparationFailure(_ reason: String) {
        if case .idle = state { state = .failed(reason) }
    }

    func deactivate() {
        hotkey.unregister()
    }

    /// Change le raccourci et le réarme aussitôt.
    func updateTrigger(_ trigger: HotkeyTrigger) {
        preferences.hotkeyTrigger = trigger
        self.trigger = trigger
        hotkeyArmed = hotkey.register(trigger)
        if hotkeyArmed, case .failed = state { state = .idle }
    }

    // MARK: - Geste de déclenchement

    private func handleHotkey(isDown: Bool) {
        // Horloge monotone : insensible aux changements d'heure système.
        let now = ProcessInfo.processInfo.systemUptime
        let decision = isDown ? resolver.keyDown(at: now) : resolver.keyUp(at: now)

        Log.hotkey.debug("décision : \(String(describing: decision), privacy: .public)")

        switch decision {
        case .start(let mode):
            beginCapture(mode: mode)
        case .switchToToggle:
            if case .recording = state { state = .recording(.toggle) }
        case .stop:
            endCapture()
        case .none:
            break
        }
    }

    /// Démarre ou arrête une dictée depuis le menu.
    ///
    /// Le clic a mis Goldodict au premier plan, alors que la dictée vise l'application
    /// où l'utilisateur écrivait — celle-là même que `beginCapture` interroge pour
    /// choisir le profil, et celle où le texte sera collé. On la réactive donc avant
    /// de démarrer, puis on laisse à macOS le temps de la bascule : sans ce délai, le
    /// texte atterrirait dans le vide.
    func toggleFromMenu(returningTo application: NSRunningApplication?) {
        if state.isRecording {
            resolver.reset()
            endCapture()
            return
        }
        guard !state.isBusy else { return }

        application?.activate()
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard let self, !self.state.isBusy else { return }
            self.resolver.adoptToggle()
            self.beginCapture(mode: .toggle)
        }
    }

    private func beginCapture(mode: TriggerMode) {
        guard PermissionGuard.microphoneStatus == .authorized else {
            resolver.reset()
            state = .failed("microphone non autorisé")
            Task { _ = await PermissionGuard.requestMicrophone() }
            return
        }

        // Sans format résolu, aucune capture : mieux vaut refuser cette dictée que
        // deviner. Le format est normalement connu dès le lancement.
        guard let format = audioFormat else {
            resolver.reset()
            state = .failed("moteur en cours de préparation, réessayez")
            Log.engine.error("dictée refusée : format du moteur pas encore résolu")
            return
        }

        // Le profil est arrêté ici, avant que quoi que ce soit d'autre n'ait pu
        // prendre le premier plan.
        let application = NSWorkspace.shared.frontmostApplication
        let frontmost = application?.bundleIdentifier
        activeProfile = profileStore.profiles.profile(for: frontmost)
        activeApplicationName = application?.localizedName
        Log.lifecycle.notice(
            "profil \(self.activeProfile.name, privacy: .public) pour \(frontmost ?? "application inconnue", privacy: .public)"
        )

        let relay = BufferRelay()
        self.relay = relay
        capture.onBuffer = { buffer in relay.push(buffer) }

        do {
            // La capture démarre sans attendre l'ouverture du moteur : le relais
            // conserve les tampons produits entre-temps.
            try capture.start(targetFormat: format)
        } catch {
            resolver.reset()
            self.relay = nil
            state = .failed(error.localizedDescription)
            return
        }

        drawQuote()

        lastFailure = nil
        state = .recording(mode)
        play(.start)
        captureStartedAt = Date()
        if activeDossier != nil, dossierSessionStart == nil { dossierSessionStart = captureStartedAt }
        Log.audio.notice("capture démarrée (\(String(describing: mode), privacy: .public))")

        let engine = self.engine
        let locale = self.locale
        let strings = self.contextualStrings
        // Le texte provisoire n'est plus affiché : la pastille montre le niveau sonore
        // et la durée, qui répondent à la seule question posée pendant qu'on parle,
        // celle de savoir si l'on est entendu. Le moteur continue de le produire, il
        // sert au démarrage de la reconnaissance.
        let onPartial: @Sendable (String) -> Void = { _ in }
        Task { [weak self] in
            do {
                try await engine.start(
                    locale: locale,
                    contextualStrings: strings,
                    onPartialText: onPartial
                )
                Log.engine.notice("moteur ouvert")
                relay.attach(to: engine)
            } catch {
                Log.engine.error("ouverture du moteur : \(error.localizedDescription, privacy: .public)")
                await self?.abortCapture(reason: error.localizedDescription)
            }
        }
    }

    private func endCapture() {
        let samples = capture.sampleCount
        capture.stop()
        capture.onBuffer = nil
        play(.stop)
        state = .transcribing
        if activeDossier != nil, let start = captureStartedAt {
            dossierSessionSeconds += Date().timeIntervalSince(start)
        }
        captureStartedAt = nil
        Log.audio.debug("capture arrêtée, \(samples) échantillons accumulés")

        let engine = self.engine
        let relay = self.relay
        self.relay = nil

        Task { [weak self] in
            await relay?.drain()
            Log.engine.debug("relais vidé, finalisation du moteur")
            do {
                let text = try await engine.finish()
                Log.engine.notice("transcription : \(text.count) caractères")
                await self?.deliver(text)
            } catch {
                Log.engine.error("transcription : \(error.localizedDescription, privacy: .public)")
                await self?.abortCapture(reason: error.localizedDescription)
            }
        }
    }

    private func deliver(_ text: String) async {
        let profile = activeProfile
        let prepared = pipeline.prepare(text, profile: profile)
        guard !prepared.isEmpty else {
            state = .idle
            return
        }

        var corrected = prepared
        var note: String?

        if profile.correctText, preferences.correctionEnabled {
            state = .correcting
            let outcome = await corrector.correct(prepared)
            corrected = outcome.text
            note = outcome.note
        }

        let cleaned = pipeline.finalize(corrected, profile: profile)
        guard !cleaned.isEmpty else {
            state = .idle
            return
        }

        state = .injecting
        let outcome = await TextInjector.inject(
            cleaned,
            autoPaste: preferences.autoPaste,
            restorePasteboard: preferences.restorePasteboard
        )
        record(transcript: cleaned)

        if outcome != .pasted {
            state = .failed("texte copié, Accessibilité non autorisée")
        } else {
            // Le compte de signes et le nom de l'application confirment que la dictée
            // est arrivée là où elle était attendue. La note, quand il y en a une,
            // signale ce qui n'a pas pu être fait sans présenter cela comme une panne.
            state = .inserted(
                Insertion(
                    characters: cleaned.count,
                    application: activeApplicationName,
                    note: note
                )
            )
        }
    }

    // MARK: - Import de fichier

    /// Transcrit un fichier audio existant avec le moteur actuellement sélectionné,
    /// sans passer par le microphone ni par l'insertion.
    ///
    /// Reprend la chaîne de `deliver(_:)` — préparation, correction, finalisation —
    /// mais s'arrête au texte : un import n'a pas d'application cible arrêtée au
    /// clic, et son résultat va dans une fenêtre, pas dans l'historique des dictées
    /// collées.
    func transcribeAudioFile(at url: URL) async throws -> String {
        guard !state.isBusy else {
            throw AudioImportError.busy
        }

        Log.importing.notice("import démarré : \(url.lastPathComponent, privacy: .public)")

        let engine = self.engine
        let format = await engine.preferredAudioFormat()
        let locale = self.locale
        let strings = self.contextualStrings

        try await engine.start(locale: locale, contextualStrings: strings, onPartialText: nil)
        do {
            try await AudioFileReader.read(fileAt: url, targetFormat: format) { buffer in
                await engine.feed(buffer)
            }
        } catch {
            await engine.cancel()
            Log.importing.error("lecture du fichier : \(error.localizedDescription, privacy: .public)")
            throw error
        }
        let text = try await engine.finish()
        Log.importing.notice("transcription : \(text.count) caractères")

        let profile = AppProfile.redaction
        let prepared = pipeline.prepare(text, profile: profile)
        guard !prepared.isEmpty else { return "" }

        var corrected = prepared
        if profile.correctText, preferences.correctionEnabled {
            let outcome = await corrector.correct(prepared)
            corrected = outcome.text
        }
        return pipeline.finalize(corrected, profile: profile)
    }

    private func abortCapture(reason: String) {
        capture.stop()
        capture.onBuffer = nil
        relay?.cancel()
        relay = nil
        resolver.reset()
        Task { [engine] in await engine.cancel() }
        state = .failed(reason)
    }

    private func cache(audioFormat: AVAudioFormat) {
        self.audioFormat = audioFormat
    }

    // MARK: - Historique

    func record(transcript: String) {
        guard !transcript.isEmpty else { return }
        lastTranscript = transcript
        history.insert(Dictation(text: transcript, date: Date()), at: 0)
        if history.count > historyLimit {
            history.removeLast(history.count - historyLimit)
        }
    }

    func clearHistory() {
        history.removeAll()
        lastTranscript = ""
    }

    // MARK: - Retour sonore

    private enum Cue: String {
        case start = "Tink"
        case stop = "Pop"
    }

    private func play(_ cue: Cue) {
        NSSound(named: NSSound.Name(cue.rawValue))?.play()
    }
}
