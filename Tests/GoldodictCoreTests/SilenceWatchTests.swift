import Foundation
import Testing
@testable import GoldodictCore

@Suite("Surveillance du silence")
struct SilenceWatchTests {

    /// La montre est alimentée à la main plutôt qu'à l'horloge : trois secondes de
    /// délai se franchissent ici en une ligne, et le test ne dure rien.
    private func watch(at start: TimeInterval = 0) -> SilenceWatch {
        var watch = SilenceWatch()
        watch.begin(at: start)
        return watch
    }

    @Test("Une capture qui démarre n'est pas en silence")
    func freshWatchIsNotSilent() {
        #expect(watch().isSilent == false)
    }

    @Test("Un blanc court reste un blanc dans la phrase")
    func shortGapIsNotSilence() {
        var watch = watch()
        watch.absorb(level: 0, at: 2.9)
        #expect(watch.isSilent == false)
    }

    @Test("Trois secondes sans rien déclarent le silence")
    func prolongedGapIsSilence() {
        var watch = watch()
        watch.absorb(level: 0, at: 3.1)
        #expect(watch.isSilent)
    }

    @Test("Le front n'est rendu qu'une fois par épisode")
    func edgeIsReportedOnce() {
        var watch = watch()
        let declared = watch.absorb(level: 0, at: 3.1)
        let again = watch.absorb(level: 0, at: 3.2)
        let later = watch.absorb(level: 0, at: 9)
        #expect(declared)
        #expect(again == false)
        #expect(later == false)
    }

    @Test("Une voix repousse le silence")
    func audibleLevelPostponesSilence() {
        var watch = watch()
        watch.absorb(level: 0.4, at: 2.9)
        watch.absorb(level: 0, at: 5.5)
        #expect(watch.isSilent == false)
        watch.absorb(level: 0, at: 6.1)
        #expect(watch.isSilent)
    }

    @Test("Le retour du son réarme le front")
    func soundRearmsTheEdge() {
        var watch = watch()
        let first = watch.absorb(level: 0, at: 3.1)
        #expect(first)

        watch.absorb(level: 0.4, at: 4)
        #expect(watch.isSilent == false)

        let second = watch.absorb(level: 0, at: 7.1)
        #expect(second)
    }

    @Test("Un souffle sous le seuil ne compte pas comme entendu")
    func levelBelowThresholdIsNotAudible() {
        var watch = watch()
        for step in stride(from: 0.5, through: 3.5, by: 0.5) {
            watch.absorb(level: SilenceWatch.defaultAudibleLevel, at: step)
        }
        #expect(watch.isSilent)
    }

    @Test("Une nouvelle capture repart du calme")
    func beginResetsTheWatch() {
        var watch = watch()
        watch.absorb(level: 0, at: 3.1)
        #expect(watch.isSilent)

        watch.begin(at: 100)
        #expect(watch.isSilent == false)
        watch.absorb(level: 0, at: 102.9)
        #expect(watch.isSilent == false)
    }
}
