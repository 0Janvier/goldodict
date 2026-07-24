import AbracadabraCore
import AppKit
import Foundation
import Observation

/// Chef d'orchestre de la dictée : il relie le raccourci, la capture audio, le
/// moteur de transcription et l'insertion du texte. Il ne connaîtra jamais qu'un
/// protocole de moteur, jamais un moteur particulier.
@Observable
@MainActor
final class DictationController {

    private(set) var state: DictationState = .idle
    private(set) var lastTranscript: String = ""

    /// Les vingt dernières dictées, en mémoire seule. Rien n'est écrit sur disque :
    /// ni l'audio, ni le texte, ce qui ferme la question du secret professionnel.
    private(set) var history: [String] = []
    private let historyLimit = 20

    private var resolver = TriggerResolver()
    private let hotkey = HotkeyMonitor()
    private let capture = AudioCapture()

    /// Enregistre le raccourci global. À appeler une fois l'application lancée.
    func activate(combination: HotkeyMonitor.Combination = .controlOptionSpace) {
        hotkey.onEvent = { [weak self] isDown in
            MainActor.assumeIsolated {
                self?.handleHotkey(isDown: isDown)
            }
        }
        if !hotkey.register(combination) {
            state = .failed("raccourci déjà pris par une autre application")
        }
    }

    func deactivate() {
        hotkey.unregister()
    }

    // MARK: - Geste de déclenchement

    private func handleHotkey(isDown: Bool) {
        // Horloge monotone : insensible aux changements d'heure système.
        let now = ProcessInfo.processInfo.systemUptime
        let decision = isDown ? resolver.keyDown(at: now) : resolver.keyUp(at: now)

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

        do {
            try capture.start()
            state = .recording(mode)
            play(.start)
        } catch {
            resolver.reset()
            state = .failed(error.localizedDescription)
        }
    }

    private func endCapture() {
        let samples = capture.stop()
        play(.stop)

        guard !samples.isEmpty else {
            state = .idle
            return
        }

        state = .transcribing

        // Le moteur de transcription est branché au lot 2. En attendant, un compte
        // rendu de la capture permet de vérifier la chaîne raccourci → audio.
        let duration = Double(samples.count) / AudioCapture.targetSampleRate
        let peak = samples.map(abs).max() ?? 0
        record(transcript: String(
            format: "[capture] %.2f s, %d échantillons, crête %.3f",
            duration, samples.count, peak
        ))
        state = .idle
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
