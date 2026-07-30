import AVFoundation
import Foundation

/// Moteur Whisper, accéléré par MLX sur puce Apple.
///
/// Le modèle tourne dans un démon Python maintenu en vie : le charger à chaque
/// dictée coûterait plusieurs secondes. Les échantillons sont transmis en PCM brut
/// via un fichier temporaire, que le démon lit avec NumPy et passe directement à
/// `mlx_whisper.transcribe`. Cette voie évite `ffmpeg`, absent de la machine et
/// exigé par l'interface en ligne de commande de mlx_whisper.
final class WhisperMLXEngine: TranscriptionEngine {

    let identifier = "whisper-mlx"
    var displayName: String { "Whisper (\(Self.shortName(of: model)))" }

    /// Dépôt HuggingFace du modèle.
    ///
    /// Immuable : changer de modèle se fait en remplaçant l'instance, ce qui évite
    /// une propriété mutable partagée entre le thread audio et l'interface.
    let model: String

    private let session: Session

    init(model: String = WhisperMLXEngine.defaultModel) {
        self.model = model
        self.session = Session(model: model)
    }

    static let defaultModel = "mlx-community/whisper-large-v3-turbo"

    static func shortName(of repository: String) -> String {
        repository.split(separator: "/").last.map(String.init)?
            .replacingOccurrences(of: "whisper-", with: "") ?? repository
    }

    /// Whisper attend du 16 kHz mono en virgule flottante, sans exception.
    func preferredAudioFormat() async -> AVAudioFormat {
        AudioCapture.whisperFormat
    }

    /// Whisper transcrit par lots : il n'a rien à émettre pendant que l'on parle.
    /// `onPartialText` est donc ignoré, ce qui est sa nature et non une lacune.
    func start(
        locale: Locale,
        contextualStrings: [String],
        onPartialText: (@Sendable (String) -> Void)?
    ) async throws {
        await session.begin(locale: locale, contextualStrings: contextualStrings, model: model)
    }

    func feed(_ buffer: AVAudioPCMBuffer) async {
        await session.accumulate(buffer)
    }

    func finish() async throws -> String {
        try await session.transcribe()
    }

    func cancel() async {
        await session.reset()
    }

    /// Modèles Whisper présents dans le cache HuggingFace de la machine.
    func availableModels() async -> [String] {
        await session.availableModels()
    }

    func shutdown() async {
        await session.shutdown()
    }
}

// MARK: - Session

private actor Session {

    /// En deçà de ce niveau crête, on considère qu'il n'y a pas eu de parole.
    /// Whisper invente du texte sur du silence — « Merci. », « Sous-titres réalisés
    /// par… » — ce qui insérerait des mots jamais prononcés dans un écrit.
    private static let silenceThreshold: Float = 0.01

    private var samples: [Float] = []
    private var prompt: String?
    private var language = "fr"
    private var model: String
    private var daemon: Daemon?

    init(model: String) {
        self.model = model
    }

    func begin(locale: Locale, contextualStrings: [String], model: String) {
        samples.removeAll(keepingCapacity: true)
        self.model = model
        language = locale.language.languageCode?.identifier ?? "fr"
        prompt = contextualStrings.isEmpty ? nil : contextualStrings.joined(separator: ", ")
    }

    func accumulate(_ buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?[0] else { return }
        samples.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
    }

    func transcribe() async throws -> String {
        defer { samples.removeAll(keepingCapacity: true) }

        guard !samples.isEmpty else { return "" }

        let peak = samples.reduce(Float(0)) { Swift.max($0, abs($1)) }
        guard peak >= Self.silenceThreshold else {
            Log.engine.notice("dictée écartée : crête \(peak) sous le seuil de silence")
            return ""
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("goldodict-\(UUID().uuidString).f32")
        defer { try? FileManager.default.removeItem(at: url) }

        try samples.withUnsafeBufferPointer { pointer in
            let data = Data(buffer: pointer)
            try data.write(to: url, options: .atomic)
        }

        var request: [String: Any] = [
            "cmd": "transcribe",
            "path": url.path,
            "language": language,
            "model": model,
        ]
        if let prompt { request["prompt"] = prompt }

        let response = try await daemonInstance().send(request)
        guard response["ok"] as? Bool == true else {
            throw TranscriptionEngineError.failed(
                response["error"] as? String ?? "échec de la transcription Whisper"
            )
        }
        return (response["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func availableModels() async -> [String] {
        guard let response = try? await daemonInstance().send(["cmd": "models"]),
              let models = response["models"] as? [String] else {
            return [WhisperMLXEngine.defaultModel]
        }
        return models
    }

    func reset() {
        samples.removeAll(keepingCapacity: true)
    }

    func shutdown() {
        daemon?.terminate()
        daemon = nil
    }

    private func daemonInstance() throws -> Daemon {
        if let daemon, daemon.isRunning { return daemon }
        let daemon = try Daemon()
        self.daemon = daemon
        return daemon
    }
}

// MARK: - Démon Python

/// Enveloppe du processus Python, dialogue en JSON ligne par ligne.
private final class Daemon {

    /// Interpréteur du venv pipx où mlx-whisper est installé, résolu depuis le
    /// dossier personnel — jamais de chemin d'utilisateur codé en dur.
    static let interpreter = NSHomeDirectory() + "/.local/pipx/venvs/mlx-whisper/bin/python"

    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let errors = Pipe()
    private var buffer = Data()

    var isRunning: Bool { process.isRunning }

    init() throws {
        guard let script = Bundle.main.resourceURL?
            .appendingPathComponent("sidecar/goldodict_whisper.py"),
              FileManager.default.fileExists(atPath: script.path) else {
            throw TranscriptionEngineError.unavailable("Whisper (script absent du bundle)")
        }
        guard FileManager.default.isExecutableFile(atPath: Self.interpreter) else {
            throw TranscriptionEngineError.unavailable("Whisper (interpréteur Python introuvable)")
        }

        process.executableURL = URL(fileURLWithPath: Self.interpreter)
        process.arguments = [script.path]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors

        // Les barres de progression HuggingFace partent sur stderr ; on les draine
        // pour ne pas saturer le tube, sans polluer le dialogue JSON.
        errors.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Log.engine.debug("whisper stderr : \(text, privacy: .public)")
        }

        try process.run()
        Log.engine.notice("démon Whisper démarré")
    }

    func send(_ request: [String: Any]) async throws -> [String: Any] {
        let payload = try JSONSerialization.data(withJSONObject: request)
        input.fileHandleForWriting.write(payload)
        input.fileHandleForWriting.write(Data("\n".utf8))
        return try readLine()
    }

    /// Lecture bloquante d'une ligne complète. Le démon répond exactement une ligne
    /// par requête, et les appels sont sérialisés par l'acteur appelant.
    private func readLine() throws -> [String: Any] {
        while true {
            if let index = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                let line = buffer[buffer.startIndex..<index]
                buffer.removeSubrange(buffer.startIndex...index)
                guard !line.isEmpty else { continue }
                guard let object = try JSONSerialization.jsonObject(with: line) as? [String: Any] else {
                    throw TranscriptionEngineError.failed("réponse Whisper illisible")
                }
                return object
            }

            let chunk = output.fileHandleForReading.availableData
            guard !chunk.isEmpty else {
                throw TranscriptionEngineError.failed("démon Whisper interrompu")
            }
            buffer.append(chunk)
        }
    }

    func terminate() {
        errors.fileHandleForReading.readabilityHandler = nil
        if process.isRunning { process.terminate() }
    }

    deinit {
        terminate()
    }
}
