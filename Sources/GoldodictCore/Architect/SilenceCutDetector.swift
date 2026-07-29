import Foundation

/// Décide où couper les segments d'une dictée longue.
///
/// Une coupe demande deux choses : que de la voix ait été entendue depuis la
/// dernière coupe (un silence prolongé n'engendre pas des segments vides), et un
/// silence continu suffisamment long pour n'être ni une respiration ni une
/// hésitation. Le garde-fou de durée coupe en pleine voix un segment qui
/// n'en finit pas — Whisper travaille mieux sur des paquets bornés.
public struct SilenceCutDetector: Sendable {

    public var rmsThreshold: Float
    public var minSilenceDuration: TimeInterval
    public var maxSegmentDuration: TimeInterval

    private var silence: TimeInterval = 0
    private var segment: TimeInterval = 0
    private var heardVoice = false

    public init(
        rmsThreshold: Float = 0.02,
        minSilenceDuration: TimeInterval = 1.2,
        maxSegmentDuration: TimeInterval = 90
    ) {
        self.rmsThreshold = rmsThreshold
        self.minSilenceDuration = minSilenceDuration
        self.maxSegmentDuration = maxSegmentDuration
    }

    /// À appeler pour chaque tampon capté. Rend `true` la fois exacte où il faut
    /// clore le segment courant.
    public mutating func ingest(rms: Float, bufferDuration: TimeInterval) -> Bool {
        segment += bufferDuration

        if rms < rmsThreshold {
            silence += bufferDuration
        } else {
            silence = 0
            heardVoice = true
        }

        let silenceCut = heardVoice && silence >= minSilenceDuration
        let overflowCut = heardVoice && segment >= maxSegmentDuration

        if silenceCut || overflowCut {
            reset()
            return true
        }
        return false
    }

    public mutating func reset() {
        silence = 0
        segment = 0
        heardVoice = false
    }
}
