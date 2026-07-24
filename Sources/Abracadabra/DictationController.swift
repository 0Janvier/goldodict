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
        case .recording, .transcribing, .injecting:
            overlay.show(state: state)
        case .failed:
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
    private var engine: TranscriptionEngine = AppleSpeechEngine()

    /// Langue de dictée. Le français est le seul usage prévu, mais le moteur Apple
    /// exige une locale explicite et le choix sera exposé dans les réglages.
    var locale = Locale(identifier: "fr_FR")

    let lexiconStore = LexiconStore()

    /// Chaîne de traitement du texte brut : ponctuation, lexique, typographie.
    private var pipeline = TranscriptPipeline()

    /// Vocabulaire transmis au moteur avant transcription, tiré du lexique.
    private var contextualStrings: [String] { lexiconStore.lexicon.contextualStrings }

    private var relay: BufferRelay?

    /// Format réclamé par le moteur, interrogé une seule fois puis conservé : le
    /// résoudre à chaque dictée retarderait le démarrage de la capture.
    private var audioFormat: AVAudioFormat?

    /// Raccourci actuellement armé, affiché dans le menu.
    private(set) var combination: HotkeyMonitor.Combination = .commandShiftJ

    /// Enregistre le raccourci global. À appeler une fois l'application lancée.
    func activate(combination: HotkeyMonitor.Combination = .commandShiftJ) {
        hotkey.onEvent = { [weak self] isDown in
            MainActor.assumeIsolated {
                self?.handleHotkey(isDown: isDown)
            }
        }
        self.combination = combination
        if !hotkey.register(combination) {
            state = .failed("raccourci \(combination.displayString) déjà pris")
        }

        lexiconStore.load()
        pipeline.lexicon = lexiconStore.lexicon

        // Les deux autorisations sont demandées au lancement plutôt qu'au milieu
        // d'une dictée, où la fenêtre système volerait le focus de l'application
        // dans laquelle l'utilisateur est en train d'écrire.
        Task { _ = await PermissionGuard.requestMicrophone() }
        _ = PermissionGuard.hasAccessibility(prompting: true)

        // Le modèle de langue peut demander un téléchargement au premier lancement.
        // L'anticiper évite que la première dictée échoue faute de modèle.
        let locale = self.locale
        let engine = self.engine
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

        Log.hotkey.notice("décision : \(String(describing: decision), privacy: .public)")

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
        Task { [weak self] in
            do {
                try await engine.start(locale: locale, contextualStrings: strings)
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
        Log.audio.notice("capture arrêtée, \(samples) échantillons accumulés")

        let engine = self.engine
        let relay = self.relay
        self.relay = nil

        Task { [weak self] in
            await relay?.drain()
            Log.engine.notice("relais vidé, finalisation du moteur")
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
        let cleaned = pipeline.process(text)
        guard !cleaned.isEmpty else {
            state = .idle
            return
        }

        state = .injecting
        let outcome = await TextInjector.inject(cleaned)
        record(transcript: cleaned)
        state = outcome == .pasted ? .idle : .failed("texte copié, Accessibilité non autorisée")
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
