import Testing
@testable import GoldodictCore

@Suite("État de dictée")
struct DictationStateTests {

    @Test("L'état au repos n'est pas occupé")
    func idleIsNotBusy() {
        #expect(DictationState.idle.isBusy == false)
        #expect(DictationState.failed("micro indisponible").isBusy == false)
    }

    @Test("Les états actifs sont occupés")
    func activeStatesAreBusy() {
        #expect(DictationState.recording(.toggle).isBusy)
        #expect(DictationState.recording(.pushToTalk).isBusy)
        #expect(DictationState.transcribing.isBusy)
        #expect(DictationState.injecting.isBusy)
    }

    @Test("Les deux modes de déclenchement portent des libellés distincts")
    func triggerModesHaveDistinctLabels() {
        #expect(DictationState.recording(.pushToTalk).label != DictationState.recording(.toggle).label)
    }

    @Test("Le libellé d'erreur reprend le message")
    func failureLabelCarriesMessage() {
        #expect(DictationState.failed("modèle français absent").label.contains("modèle français absent"))
    }
}
