import AVFoundation
import Foundation
import GoldodictCore
import Observation

/// Session de dictée de document long.
///
/// La capture audio tourne en continu ; les silences découpent des segments,
/// transcrits et corrigés en arrière-plan pendant que la dictée continue. Deux
/// sessions Whisper ne se chevauchent jamais — l'acteur du moteur ne le
/// supporterait pas — donc les segments patientent dans une file traitée en série.
///
/// Le plan en construction est écrit sur disque après chaque segment : un crash à
/// la minute dix-huit ne perd que le segment en cours. C'est la seule entorse au
/// principe « rien sur disque », assumée et bornée — le fichier est supprimé à
/// l'export ou à la fermeture volontaire de la fenêtre.
@Observable @MainActor
final class ArchitectSession {

    enum Phase: Equatable {
        case idle
        case recording
        case paused
        case finishing
        case finished
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var outline = DocumentOutline()
    private(set) var segmentCount = 0
    private(set) var pendingCount = 0
    private(set) var startedAt: Date?

    var level: Float { capture?.level ?? 0 }

    /// Plus rien n'est capté depuis assez longtemps pour que ce ne soit plus une
    /// pause. La pastille le disait déjà, pas cette fenêtre : on pouvait dicter
    /// vingt minutes devant un vumètre à plat sans qu'un mot le signale.
    private(set) var isSilent = false

    /// Périphérique écouté au moment où le silence a été déclaré.
    private(set) var inputDeviceName: String?

    private let engine: WhisperMLXEngine
    private let corrector: CorrectionService
    private let pipeline: TranscriptPipeline
    private let contextualStrings: [String]
    private let locale: Locale
    private let onRelease: () -> Void

    private var capture: AudioCapture?
    private var audioFormat: AVAudioFormat?
    private var builder = DocumentOutlineBuilder()
    private let collector = SegmentCollector()
    private var pendingSegments: [[AVAudioPCMBuffer]] = []
    private var processing: Task<Void, Never>?
    private var watch = SilenceWatch()
    private var watching: Task<Void, Never>?

    private let sessionID = UUID()

    init(
        engine: WhisperMLXEngine,
        corrector: CorrectionService,
        pipeline: TranscriptPipeline,
        contextualStrings: [String],
        locale: Locale,
        onRelease: @escaping () -> Void
    ) {
        self.engine = engine
        self.corrector = corrector
        self.pipeline = pipeline
        self.contextualStrings = contextualStrings
        self.locale = locale
        self.onRelease = onRelease
    }

    var persistedURL: URL {
        Self.sessionsDirectory.appendingPathComponent("\(sessionID.uuidString).json")
    }

    private static var sessionsDirectory: URL {
        SupportDirectory.url(for: "ArchitectSessions")
    }

    /// Efface au lancement les snapshots qu'un crash aurait laissés : le fichier
    /// de reprise n'a de sens que le temps d'une session, pas au-delà de deux
    /// jours — au nom du principe « rien ne traîne sur disque ».
    static func purgeStaleSessions(olderThan age: TimeInterval = 48 * 3600) {
        let manager = FileManager.default
        guard let files = try? manager.contentsOfDirectory(
            at: sessionsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }

        let cutoff = Date().addingTimeInterval(-age)
        for file in files {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            if modified < cutoff {
                try? manager.removeItem(at: file)
                Log.architect.notice("session périmée purgée : \(file.lastPathComponent, privacy: .public)")
            }
        }
    }

    // MARK: - Cycle de vie

    func start() async {
        guard phase == .idle || phase == .paused else { return }
        do {
            let format: AVAudioFormat
            if let audioFormat {
                format = audioFormat
            } else {
                format = await engine.preferredAudioFormat()
                audioFormat = format
            }

            let capture = AudioCapture()
            capture.onBuffer = { [collector, weak capture] buffer in
                // Thread audio temps réel : uniquement des gestes bon marché.
                let duration = Double(buffer.frameLength) / buffer.format.sampleRate
                let cut = collector.absorb(buffer, rms: capture?.level ?? 0, duration: duration)
                if cut {
                    Task { @MainActor [weak self] in self?.closeSegment() }
                }
            }
            try capture.start(targetFormat: format)
            self.capture = capture
            if startedAt == nil { startedAt = Date() }
            phase = .recording
            startWatching()
            Log.architect.notice("session document démarrée")
        } catch {
            phase = .failed(error.localizedDescription)
            Log.architect.error("démarrage : \(error.localizedDescription, privacy: .public)")
        }
    }

    func pause() {
        guard phase == .recording else { return }
        stopCapture()
        closeSegment()
        phase = .paused
    }

    /// Arrête la capture, traite ce qui reste et clôt la session.
    func finish() async {
        guard phase == .recording || phase == .paused else { return }
        stopCapture()
        closeSegment()
        phase = .finishing
        await processing?.value
        phase = .finished
        Log.architect.notice("session close : \(self.segmentCount) segments")
    }

    /// Export DOCX. Rend les octets ; l'appelant choisit la destination.
    func exportDocx(title: String) -> Data {
        DocxExporter.build(outline: outline, title: title)
    }

    /// À la sortie de la fenêtre : efface le fichier de reprise et rend la main
    /// au contrôleur de dictée.
    func tearDown() {
        stopCapture()
        processing?.cancel()
        try? FileManager.default.removeItem(at: persistedURL)
        onRelease()
    }

    private func stopCapture() {
        capture?.stop()
        capture?.onBuffer = nil
        capture = nil
        stopWatching()
    }

    // MARK: - Surveillance du silence

    /// Relève le niveau à la cadence du vumètre du panneau, pour que l'avertissement
    /// et les barres racontent la même chose au même instant.
    ///
    /// Le relevé ne se fait pas dans `onBuffer` : ce rappel tourne sur le thread
    /// audio temps réel, où lire une propriété CoreAudio se paierait en craquements.
    private func startWatching() {
        guard watching == nil else { return }
        watch.begin(at: ProcessInfo.processInfo.systemUptime)
        isSilent = false
        inputDeviceName = nil

        watching = Task { [weak self] in
            var smoothed: Float = 0
            while !Task.isCancelled {
                guard let self else { return }
                smoothed = AudioLevel.smoothed(
                    previous: smoothed,
                    target: AudioLevel.normalized(rms: self.level)
                )
                if self.watch.absorb(level: smoothed, at: ProcessInfo.processInfo.systemUptime) {
                    self.inputDeviceName = AudioDevices.defaultInputName
                    Log.architect.notice("plus rien n'est capté depuis le périphérique d'entrée")
                }
                self.isSilent = self.watch.isSilent
                try? await Task.sleep(for: .milliseconds(80))
            }
        }
    }

    private func stopWatching() {
        watching?.cancel()
        watching = nil
        isSilent = false
        inputDeviceName = nil
    }

    // MARK: - Segments

    private func closeSegment() {
        let buffers = collector.drain()
        guard !buffers.isEmpty else { return }
        pendingSegments.append(buffers)
        pendingCount = pendingSegments.count
        processQueueIfIdle()
    }

    private func processQueueIfIdle() {
        guard processing == nil else { return }
        processing = Task { [weak self] in
            while let self, !Task.isCancelled {
                guard !self.pendingSegments.isEmpty else { break }
                let segment = self.pendingSegments.removeFirst()
                self.pendingCount = self.pendingSegments.count
                await self.transcribe(segment: segment)
            }
            self?.processing = nil
            // Des segments ont pu arriver entre la sortie de boucle et ce point.
            if let self, !self.pendingSegments.isEmpty { self.processQueueIfIdle() }
        }
    }

    private func transcribe(segment: [AVAudioPCMBuffer]) async {
        do {
            try await engine.start(locale: locale, contextualStrings: contextualStrings, onPartialText: nil)
            for buffer in segment {
                await engine.feed(buffer)
            }
            let raw = try await engine.finish()
            guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

            let prepared = pipeline.prepare(raw, profile: .redaction)
            let tokens = DocumentOutlineParser.tokenize(prepared)

            // Seule la prose passe au correcteur : les mots de commande ne
            // l'atteignent jamais, il ne peut ni les avaler ni les paraphraser.
            var corrected: [DocumentToken] = []
            for token in tokens {
                switch token {
                case .command:
                    corrected.append(token)
                case .prose(let text):
                    let outcome = await corrector.correct(text)
                    corrected.append(.prose(pipeline.finalize(outcome.text, profile: .redaction)))
                }
            }

            builder.append(corrected)
            outline = builder.outline
            segmentCount += 1
            persist()
        } catch {
            Log.architect.error("segment : \(error.localizedDescription, privacy: .public)")
        }
    }

    private func persist() {
        do {
            let directory = Self.sessionsDirectory
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(outline)
            try data.write(to: persistedURL, options: .atomic)
        } catch {
            Log.architect.error("persistance : \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// Accumulateur de tampons du segment courant, alimenté depuis le thread audio.
private final class SegmentCollector: @unchecked Sendable {
    private var buffers: [AVAudioPCMBuffer] = []
    private var detector = SilenceCutDetector()
    private let lock = NSLock()

    /// Absorbe un tampon et dit s'il faut couper le segment ici.
    func absorb(_ buffer: AVAudioPCMBuffer, rms: Float, duration: TimeInterval) -> Bool {
        lock.lock(); defer { lock.unlock() }
        buffers.append(buffer)
        return detector.ingest(rms: rms, bufferDuration: duration)
    }

    func drain() -> [AVAudioPCMBuffer] {
        lock.lock(); defer { lock.unlock() }
        let result = buffers
        buffers.removeAll(keepingCapacity: true)
        detector.reset()
        return result
    }
}
