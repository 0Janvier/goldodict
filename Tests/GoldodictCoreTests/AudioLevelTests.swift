import Foundation
import Testing
@testable import GoldodictCore

@Suite("Niveau audio")
struct AudioLevelTests {

    @Test("Un micro coupé rend zéro")
    func silenceIsZero() {
        #expect(AudioLevel.normalized(rms: 0) == 0)
    }

    @Test("Le bruit de fond reste sous le plancher")
    func backgroundNoiseStaysBelowFloor() {
        // -60 dB, sous le plancher de -55 : un ventilateur ne doit pas animer la barre.
        #expect(AudioLevel.normalized(rms: 0.001) == 0)
    }

    @Test("Une voix proche du micro sature la barre")
    func loudVoiceSaturates() {
        // -6 dB, au-dessus du plafond de -12.
        #expect(AudioLevel.normalized(rms: 0.5) == 1)
    }

    @Test("La plage utile est strictement croissante")
    func usefulRangeIsMonotonic() {
        let murmur = AudioLevel.normalized(rms: 0.01)     // -40 dB
        let speech = AudioLevel.normalized(rms: 0.05)     // -26 dB
        let close = AudioLevel.normalized(rms: 0.15)      // -16,5 dB
        #expect(murmur > 0 && close < 1)
        #expect(murmur < speech)
        #expect(speech < close)
    }

    @Test("Le milieu de plage tombe au milieu de la barre")
    func midRangeIsCentred() {
        // -33,5 dB, exactement entre le plancher et le plafond.
        let value = AudioLevel.normalized(rms: pow(10, -33.5 / 20))
        #expect(abs(value - 0.5) < 0.01)
    }

    @Test("Le lissage monte plus vite qu'il ne descend")
    func smoothingRisesFasterThanItFalls() {
        let rise = AudioLevel.smoothed(previous: 0, target: 1)
        let fall = 1 - AudioLevel.smoothed(previous: 1, target: 0)
        #expect(rise > fall)
    }

    @Test("Le lissage converge vers sa cible sans la dépasser")
    func smoothingConvergesWithoutOvershoot() {
        var value: Float = 0
        for _ in 0..<40 {
            value = AudioLevel.smoothed(previous: value, target: 0.8)
            #expect(value <= 0.8)
        }
        #expect(abs(value - 0.8) < 0.001)
    }

    @Test("Un niveau stable ne bouge plus")
    func steadyLevelIsFixedPoint() {
        #expect(AudioLevel.smoothed(previous: 0.4, target: 0.4) == 0.4)
    }
}
