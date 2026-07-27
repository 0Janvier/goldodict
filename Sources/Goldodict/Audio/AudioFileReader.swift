import AVFoundation
import Foundation

/// Lecture d'un fichier audio existant, ramenée au format réclamé par le moteur en
/// service.
///
/// Même principe de conversion que `AudioCapture` — un `AVAudioConverter` du format
/// natif vers le format cible — mais en tirage : il n'y a pas de tap temps réel à
/// écouter, seulement un fichier à lire par blocs jusqu'à épuisement.
enum AudioFileReader {

    private static let chunkSize: AVAudioFrameCount = 4096

    /// Lit `url` entièrement et livre chaque tampon converti à `feed`, dans l'ordre.
    ///
    /// `feed` est asynchrone et attendue avant le bloc suivant : c'est ce qui permet
    /// à l'appelant de la brancher directement sur `TranscriptionEngine.feed(_:)`,
    /// dont l'acteur sérialise déjà les tampons un par un.
    static func read(
        fileAt url: URL,
        targetFormat: AVAudioFormat,
        feed: (AVAudioPCMBuffer) async -> Void
    ) async throws {
        let file = try AVAudioFile(forReading: url)
        let sourceFormat = file.processingFormat

        guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
            throw AudioCaptureError.converterUnavailable
        }

        guard let sourceBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: chunkSize) else {
            throw AudioCaptureError.converterUnavailable
        }

        let ratio = targetFormat.sampleRate / sourceFormat.sampleRate

        while true {
            sourceBuffer.frameLength = 0
            try file.read(into: sourceBuffer, frameCount: chunkSize)
            guard sourceBuffer.frameLength > 0 else { break }

            let capacity = AVAudioFrameCount(Double(sourceBuffer.frameLength) * ratio) + 1024
            guard let outBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
                throw AudioCaptureError.converterUnavailable
            }

            var consumed = false
            var conversionError: NSError?
            let status = converter.convert(to: outBuffer, error: &conversionError) { _, statusOut in
                if consumed {
                    statusOut.pointee = .noDataNow
                    return nil
                }
                consumed = true
                statusOut.pointee = .haveData
                return sourceBuffer
            }

            if status == .error {
                throw AudioCaptureError.conversionFailed(
                    conversionError?.localizedDescription ?? "erreur inconnue"
                )
            }
            guard outBuffer.frameLength > 0 else { continue }
            await feed(outBuffer)
        }
    }
}
