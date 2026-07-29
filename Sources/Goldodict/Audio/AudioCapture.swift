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
/// Le moteur est recréé à chaque capture. Une instance unique survivant aux
/// changements de périphérique d'entrée rend un format périmé (l'ancien matériel),
/// et `installTap` lève alors une exception Objective-C qu'aucun `catch` Swift
/// n'intercepte : la dictée cesse de démarrer jusqu'au relancement de l'application.
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

    private var engine: AVAudioEngine?
    private var targetFormat = AudioCapture.whisperFormat

    private var converter: AVAudioConverter?
    private let accumulator = SampleAccumulator()
    private let meter = LevelMeter()

    private(set) var isRunning = false

    /// Nombre d'échantillons capturés depuis le démarrage.
    var sampleCount: Int { accumulator.count }

    /// Niveau sonore instantané (valeur efficace) du dernier tampon capté.
    ///
    /// Il est mesuré sur le tampon natif, avant conversion : le format cible dépend du
    /// moteur en service et n'est pas toujours du mono virgule flottante, si bien qu'un
    /// niveau tiré du tampon converti resterait à zéro sur certains moteurs. Or c'est
    /// exactement ce que le témoin doit distinguer d'un micro coupé.
    var level: Float { meter.value }

    /// - Parameter targetFormat: format attendu par le moteur de transcription.
    ///   Les échantillons ne sont accumulés que s'il s'agit de mono virgule flottante,
    ///   seul cas où la transcription par lots (Whisper) a du sens.
    func start(targetFormat: AVAudioFormat = AudioCapture.whisperFormat) throws {
        guard !isRunning else { return }

        accumulator.reset()
        meter.reset()
        self.targetFormat = targetFormat

        let engine = AVAudioEngine()
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
            self.converter = nil
            throw AudioCaptureError.engineFailed(error.localizedDescription)
        }
        self.engine = engine
        isRunning = true
    }

    /// Arrête la capture et rend l'intégralité des échantillons collectés.
    @discardableResult
    func stop() -> [Float] {
        guard isRunning, let engine else { return accumulator.drain() }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
        converter = nil
        isRunning = false
        return accumulator.drain()
    }

    private func handle(_ buffer: AVAudioPCMBuffer, nativeFormat: AVAudioFormat) {
        meter.absorb(buffer)
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
    private let lock = NSLock()

    var count: Int {
        lock.lock(); defer { lock.unlock() }
        return storage.count
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?[0] else { return }
        let frames = Int(buffer.frameLength)
        lock.lock()
        storage.append(contentsOf: UnsafeBufferPointer(start: channel, count: frames))
        lock.unlock()
    }

    func drain() -> [Float] {
        lock.lock(); defer { lock.unlock() }
        let result = storage
        storage.removeAll(keepingCapacity: true)
        return result
    }

    func reset() {
        lock.lock(); defer { lock.unlock() }
        storage.removeAll(keepingCapacity: true)
    }
}

/// Sonomètre : valeur efficace du dernier tampon, écrite depuis le thread audio et
/// lue depuis la boucle principale.
///
/// Le calcul ne parcourt pas tous les échantillons. Un tampon de 4 096 valeurs arrive
/// une quinzaine de fois par seconde, sur un thread temps réel où tout dépassement
/// s'entend sous forme de craquement. Un échantillon sur seize suffit à établir un
/// niveau : la valeur sert à dessiner des barres, pas à mesurer.
private final class LevelMeter {
    private var latest: Float = 0
    private let lock = NSLock()
    private static let stride = 16

    var value: Float {
        lock.lock(); defer { lock.unlock() }
        return latest
    }

    func absorb(_ buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?[0] else { return }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return }

        var sumOfSquares: Float = 0
        var counted = 0
        var index = 0
        while index < frames {
            let sample = channel[index]
            sumOfSquares += sample * sample
            counted += 1
            index += Self.stride
        }
        guard counted > 0 else { return }
        let rms = (sumOfSquares / Float(counted)).squareRoot()

        lock.lock()
        latest = rms
        lock.unlock()
    }

    func reset() {
        lock.lock(); defer { lock.unlock() }
        latest = 0
    }
}
