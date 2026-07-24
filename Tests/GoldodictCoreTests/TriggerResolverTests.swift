import Testing
@testable import GoldodictCore

@Suite("Résolution du geste de déclenchement")
struct TriggerResolverTests {

    @Test("Un appui maintenu enregistre puis s'arrête au relâchement")
    func heldPressRecordsUntilRelease() {
        var resolver = TriggerResolver(holdThreshold: 0.25)
        #expect(resolver.keyDown(at: 0) == .start(.pushToTalk))
        #expect(resolver.isDictating)
        #expect(resolver.keyUp(at: 1.5) == .stop)
        #expect(resolver.isDictating == false)
    }

    @Test("Un appui bref bascule en dictée continue")
    func briefPressSwitchesToToggle() {
        var resolver = TriggerResolver(holdThreshold: 0.25)
        #expect(resolver.keyDown(at: 0) == .start(.pushToTalk))
        #expect(resolver.keyUp(at: 0.10) == .switchToToggle)
        #expect(resolver.isDictating)
    }

    @Test("Un second appui arrête la dictée en mode bascule")
    func secondPressStopsToggle() {
        var resolver = TriggerResolver(holdThreshold: 0.25)
        _ = resolver.keyDown(at: 0)
        _ = resolver.keyUp(at: 0.10)
        #expect(resolver.keyDown(at: 5.0) == .stop)
        #expect(resolver.keyUp(at: 5.05) == .none)
        #expect(resolver.isDictating == false)
    }

    @Test("Un appui maintenu pour arrêter la bascule ne relance rien")
    func longSecondPressDoesNotRestart() {
        var resolver = TriggerResolver(holdThreshold: 0.25)
        _ = resolver.keyDown(at: 0)
        _ = resolver.keyUp(at: 0.05)
        #expect(resolver.keyDown(at: 3.0) == .stop)
        #expect(resolver.keyUp(at: 4.0) == .none)
        #expect(resolver.isDictating == false)
    }

    @Test("La répétition automatique du clavier est ignorée")
    func keyRepeatIsIgnored() {
        var resolver = TriggerResolver(holdThreshold: 0.25)
        #expect(resolver.keyDown(at: 0) == .start(.pushToTalk))
        #expect(resolver.keyDown(at: 0.5) == .none)
        #expect(resolver.keyDown(at: 0.6) == .none)
        #expect(resolver.keyUp(at: 1.0) == .stop)
    }

    @Test("Le seuil est une borne stricte")
    func thresholdIsStrict() {
        var resolver = TriggerResolver(holdThreshold: 0.25)
        _ = resolver.keyDown(at: 0)
        #expect(resolver.keyUp(at: 0.25) == .stop)
    }

    @Test("Une réinitialisation ramène au repos")
    func resetReturnsToIdle() {
        var resolver = TriggerResolver(holdThreshold: 0.25)
        _ = resolver.keyDown(at: 0)
        _ = resolver.keyUp(at: 0.05)
        #expect(resolver.isDictating)
        resolver.reset()
        #expect(resolver.isDictating == false)
        #expect(resolver.keyDown(at: 10) == .start(.pushToTalk))
    }
}
