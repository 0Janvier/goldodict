import AVFoundation
import Foundation

enum AudioCaptureError: LocalizedError {
    case converterUnavailable
    case conversionFailed(String)
    case engineFailed(String)

    var errorDescription: String? {
        switch self {
        case .converterUnavailable: return "conversion audio impossible"
        case .conversionFailed(let detail): return "conversion audio : \(detail)"
        case .engineFailed(let detail): return "microphone : \(detail)"
        }
    }
}

/// Capture du microphone, ramenée au format réclamé par le moteur en service.
///
/// Le format natif de l'entrée varie selon le matériel (48 kHz stéréo sur les micros
/// intégrés, tout autre chose sur une interface externe). Le tap est donc installé
/// avec le format natif — passer un format différent fait crasher `AVAudioEngine` —
/// et un `AVAudioConverter` ramène chaque tampon au format cible.
///
/// Le format cible est fourni par l'appelant, car les deux moteurs ne demandent pas
/// la même chose : Whisper veut du 16 kHz mono, Apple impose le format que lui rend
/// `SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith:)`.
final class AudioCapture {

    static let whisperSampleRate: Double = 16_000

    /// PCM 16 kHz mono virgule flottante, format d'entrée de Whisper.
    static let whisperFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: AudioCapture.whisperSampleRate,
        channels: 1,
        interleaved: false
    )!

    /// Tampons convertis, livrés au fil de l'eau pour les moteurs en streaming.
    /// Appelé depuis un thread audio temps réel : ne rien y faire de coûteux.
    var onBuffer: ((AVAudioPCMBuffer) -> Void)?

    private let engine = AVAudioEngine()
    private var targetFormat = AudioCapture.whisperFormat

    private var converter: AVAudioConverter?
    private let accumulator = SampleAccumulator()

    private(set) var isRunning = false

    /// Nombre d'échantillons capturés depuis le démarrage.
    var sampleCount: Int { accumulator.count }

    /// Niveau sonore instantané (RMS) du dernier tampon, pour le retour visuel.
    var level: Float { accumulator.level }

    /// - Parameter targetFormat: format attendu par le moteur de transcription.
    ///   Les échantillons ne sont accumulés que s'il s'agit de mono virgule flottante,
    ///   seul cas où la transcription par lots (Whisper) a du sens.
    func start(targetFormat: AVAudioFormat = AudioCapture.whisperFormat) throws {
        guard !isRunning else { return }

        accumulator.reset()
        self.targetFormat = targetFormat

        let input = engine.inputNode
        let nativeFormat = input.outputFormat(forBus: 0)

        guard let converter = AVAudioConverter(from: nativeFormat, to: targetFormat) else {
            throw AudioCaptureError.converterUnavailable
        }
        self.converter = converter

        input.installTap(onBus: 0, bufferSize: 4096, format: nativeFormat) { [weak self] buffer, _ in
            self?.handle(buffer, nativeFormat: nativeFormat)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw AudioCaptureError.engineFailed(error.localizedDescription)
        }
        isRunning = true
    }

    /// Arrête la capture et rend l'intégralité des échantillons collectés.
    @discardableResult
    func stop() -> [Float] {
        guard isRunning else { return accumulator.drain() }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        converter = nil
        isRunning = false
        return accumulator.drain()
    }

    private func handle(_ buffer: AVAudioPCMBuffer, nativeFormat: AVAudioFormat) {
        guard let converter else { return }

        let ratio = targetFormat.sampleRate / nativeFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

        var consumed = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, statusOut in
            if consumed {
                statusOut.pointee = .noDataNow
                return nil
            }
            consumed = true
            statusOut.pointee = .haveData
            return buffer
        }

        guard status != .error, output.frameLength > 0 else { return }

        if targetFormat.channelCount == 1, targetFormat.commonFormat == .pcmFormatFloat32 {
            accumulator.append(output)
        }
        onBuffer?(output)
    }
}

/// Accumulateur d'échantillons protégé par un verrou : il est alimenté depuis le
/// thread audio et lu depuis la boucle principale.
private final class SampleAccumulator {
    private var storage: [Float] = []
    private var lastLevel: Float = 0
    private let lock = NSLock()

    var count: Int {
        lock.lock(); defer { lock.unlock() }
        return storage.count
    }

    var level: Float {
        lock.lock(); defer { lock.unlock() }
        return lastLevel
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?[0] else { return }
        let frames = Int(buffer.frameLength)
        var sumOfSquares: Float = 0
        for index in 0..<frames {
            let sample = channel[index]
            sumOfSquares += sample * sample
        }
        let rms = frames > 0 ? (sumOfSquares / Float(frames)).squareRoot() : 0

        lock.lock()
        storage.append(contentsOf: UnsafeBufferPointer(start: channel, count: frames))
        lastLevel = rms
        lock.unlock()
    }

    func drain() -> [Float] {
        lock.lock(); defer { lock.unlock() }
        let result = storage
        storage.removeAll(keepingCapacity: true)
        lastLevel = 0
        return result
    }

    func reset() {
        lock.lock(); defer { lock.unlock() }
        storage.removeAll(keepingCapacity: true)
        lastLevel = 0
    }
}
