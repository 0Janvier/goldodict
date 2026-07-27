import Foundation
import Testing
@testable import GoldodictCore

/// `#expect` réécrit l'expression qu'on lui donne et en fige les termes : un appel
/// `mutating` ne peut pas y figurer. Chaque appui est donc évalué avant.
@Suite("Double appui")
struct DoubleTapDetectorTests {

    /// Rend le verdict de chaque appui de la suite fournie.
    private func fire(_ times: [TimeInterval], window: TimeInterval = DoubleTapDetector.defaultWindow) -> [Bool] {
        var detector = DoubleTapDetector(window: window)
        return times.map { detector.press(at: $0) }
    }

    @Test("Un appui isolé ne déclenche rien")
    func singlePressIsSilent() {
        #expect(fire([0]) == [false])
    }

    @Test("Deux appuis rapprochés déclenchent")
    func closePressesFire() {
        #expect(fire([0, 0.2]) == [false, true])
    }

    /// Bornes prises sur des valeurs exactement représentables : `1.3 - 1.0` vaut
    /// `0.30000000000000004` en binaire, et ferait échouer un test d'égalité qui
    /// ne dit rien du détecteur.
    @Test("La borne de la fenêtre est incluse")
    func windowBoundIsInclusive() {
        #expect(fire([1.0, 1.5], window: 0.5) == [false, true])
    }

    @Test("Au-delà de la fenêtre, rien ne déclenche")
    func lateSecondPressIsSilent() {
        #expect(fire([0, 0.31], window: 0.3) == [false, false])
    }

    /// Le second appui trop tardif devient le premier d'une nouvelle paire, sans
    /// quoi il faudrait attendre pour recommencer.
    @Test("Un appui tardif ouvre une nouvelle paire")
    func latePressRearms() {
        #expect(fire([0, 1.0, 1.1], window: 0.3) == [false, false, true])
    }

    /// Sans remise à zéro après un déclenchement, maintenir le doigt sur la touche
    /// déclencherait en cascade.
    @Test("Le troisième appui ne déclenche pas")
    func thirdPressIsSilent() {
        #expect(fire([0, 0.1, 0.2], window: 0.3) == [false, true, false])
    }

    @Test("Quatre appuis donnent deux déclenchements")
    func fourPressesFireTwice() {
        #expect(fire([0, 0.1, 0.2, 0.3], window: 0.3) == [false, true, false, true])
    }

    @Test("La remise à zéro oublie l'appui en attente")
    func resetForgetsPendingPress() {
        var detector = DoubleTapDetector(window: 0.3)
        let first = detector.press(at: 0)
        detector.reset()
        let second = detector.press(at: 0.1)
        #expect(first == false)
        #expect(second == false)
    }

    @Test("La fenêtre par défaut vaut trois cents millisecondes")
    func defaultWindow() {
        #expect(DoubleTapDetector.defaultWindow == 0.3)
        #expect(DoubleTapDetector().window == 0.3)
    }
}
