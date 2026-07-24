import AVFoundation
import Foundation

/// Achemine les tampons du thread audio vers le moteur de transcription.
///
/// Deux problèmes sont résolus ici. D'abord l'**ordre** : lancer une tâche par
/// tampon ne garantit rien sur leur ordonnancement et mélangerait l'audio ; un
/// `AsyncStream` est une file d'attente, consommée séquentiellement par une unique
/// tâche. Ensuite le **démarrage** : la capture commence dès l'enfoncement de la
/// touche, alors que le moteur met quelques dizaines de millisecondes à s'ouvrir.
/// Les tampons émis pendant ce laps sont mis en attente, non perdus.
///
/// Un relais vaut pour une seule dictée : un `AsyncStream` ne se consomme qu'une fois.
final class BufferRelay: @unchecked Sendable {

    private let stream: AsyncStream<AVAudioPCMBuffer>
    private let continuation: AsyncStream<AVAudioPCMBuffer>.Continuation
    private var pump: Task<Void, Never>?

    init() {
        (stream, continuation) = AsyncStream<AVAudioPCMBuffer>.makeStream(
            bufferingPolicy: .unbounded
        )
    }

    /// Appelé depuis le thread audio temps réel.
    func push(_ buffer: AVAudioPCMBuffer) {
        continuation.yield(buffer)
    }

    /// Démarre l'acheminement vers le moteur, en commençant par ce qui attend déjà.
    func attach(to engine: TranscriptionEngine) {
        guard pump == nil else { return }
        pump = Task {
            for await buffer in stream {
                await engine.feed(buffer)
            }
        }
    }

    /// Ferme la file et attend que le moteur ait reçu le dernier tampon.
    func drain() async {
        continuation.finish()
        await pump?.value
    }

    func cancel() {
        continuation.finish()
        pump?.cancel()
        pump = nil
    }
}
