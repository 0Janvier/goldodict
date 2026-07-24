import AbracadabraCore
import AppKit
import AVFoundation
import Foundation
import Observation

/// Chef d'orchestre de la dictée : il relie le raccourci, la capture audio, le
/// moteur de transcription et l'insertion du texte. Il ne connaîtra jamais qu'un
/// protocole de moteur, jamais un moteur particulier.
@Observable
@MainActor
final class DictationController {

    private(set) var state: DictationState = .idle {
        didSet { reflectStateInOverlay() }
    }
    private(set) var lastTranscript: String = ""

    private let overlay = RecordingOverlay()
    private var overlayDismissal: Task<Void, Never>?

    /// La pastille flottante est le seul retour réellement visible : l'icône de la
    /// barre des menus disparaît derrière le chevron dès que la barre est chargée.
    private func reflectStateInOverlay() {
        overlayDismissal?.cancel()

        switch state {
        case .idle:
            overlay.hide()
        case .recording, .transcribing, .correcting, .injecting:
            overlay.show(state: state)
        case .notice, .failed:
            overlay.show(state: state)
            overlayDismissal = Task { [weak self] in
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled else { return }
                self?.overlay.hide()
            }
        }
    }

    /// Les vingt dernières dictées, en mémoire seule. Rien n'est écrit sur disque :
    /// ni l'audio, ni le texte, ce qui ferme la question du secret professionnel.
    private(set) var history: [String] = []
    private let historyLimit = 20

    private var resolver = TriggerResolver()
    private let hotkey = HotkeyMonitor()
    private let capture = AudioCapture()
    @ObservationIgnored
    private var engine: TranscriptionEngine

    init() {
        engine = appleEngine
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
    let preferences = Preferences()

    var microphoneGranted: Bool { PermissionGuard.microphoneStatus == .authorized }
    var accessibilityGranted: Bool { PermissionGuard.hasAccessibility() }

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

    /// Vocabulaire transmis au moteur avant transcription, tiré du lexique.
    private var contextualStrings: [String] { lexiconStore.lexicon.contextualStrings }

    private var relay: BufferRelay?

    /// Format réclamé par le moteur, interrogé une seule fois puis conservé : le
    /// résoudre à chaque dictée retarderait le démarrage de la capture.
    private var audioFormat: AVAudioFormat?

    /// Raccourci actuellement armé, affiché dans le menu.
    private(set) var combination: HotkeyMonitor.Combination = .commandShiftJ

    /// Enregistre le raccourci global. À appeler une fois l'application lancée.
    func activate(combination: HotkeyMonitor.Combination? = nil) {
        hotkey.onEvent = { [weak self] isDown in
            MainActor.assumeIsolated {
                self?.handleHotkey(isDown: isDown)
            }
        }

        let combination = combination ?? preferences.hotkey
        resolver = TriggerResolver(holdThreshold: preferences.holdThreshold)
        self.combination = combination
        if !hotkey.register(combination) {
            state = .failed("raccourci \(combination.displayString) déjà pris")
        }

        lexiconStore.load()
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

        // Les deux autorisations sont demandées au lancement plutôt qu'au milieu
        // d'une dictée, où la fenêtre système volerait le focus de l'application
        // dans laquelle l'utilisateur est en train d'écrire.
        Task { _ = await PermissionGuard.requestMicrophone() }
        _ = PermissionGuard.hasAccessibility(prompting: true)

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
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        activeProfile = profileStore.profiles.profile(for: frontmost)
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

        state = .recording(mode)
        play(.start)
        Log.audio.notice("capture démarrée (\(String(describing: mode), privacy: .public))")

        let engine = self.engine
        let locale = self.locale
        let strings = self.contextualStrings
        let onPartial: @Sendable (String) -> Void = { [weak self] text in
            Task { @MainActor in self?.showPartial(text) }
        }
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

    /// Texte provisoire du moteur, affiché pendant que l'utilisateur parle.
    private func showPartial(_ text: String) {
        guard state.isBusy else { return }
        overlay.update(partialText: text)
    }

    private func endCapture() {
        let samples = capture.sampleCount
        capture.stop()
        capture.onBuffer = nil
        overlay.flushPartialText()
        play(.stop)
        state = .transcribing
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
        } else if let note {
            // Le texte est bien inséré : la note informe de ce qui a été fait, ou
            // n'a pas pu l'être, sans être présentée comme une panne.
            state = .notice(note)
        } else {
            state = .idle
        }
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
        history.insert(transcript, at: 0)
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
