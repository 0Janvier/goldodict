import Foundation
import Testing
@testable import GoldodictCore

@Suite("Construction du plan")
struct DocumentOutlineBuilderTests {

    @Test("L'intitulé est limité au segment portant le titre")
    func headingLimitedToSegment() {
        var builder = DocumentOutlineBuilder()
        builder.append(DocumentOutlineParser.tokenize("titre un, sur la recevabilité."))
        builder.append(DocumentOutlineParser.tokenize("la requête a été introduite dans le délai."))

        let section = builder.outline.sections[0]
        #expect(section.marker == "I.")
        #expect(section.heading == "sur la recevabilité.")
        #expect(section.blocks == [.paragraph("la requête a été introduite dans le délai.")])
    }

    @Test("Les niveaux s'imbriquent, les frères se suivent")
    func nestingAndSiblings() {
        var builder = DocumentOutlineBuilder()
        builder.append(DocumentOutlineParser.tokenize("titre un, sur la recevabilité"))
        builder.append(DocumentOutlineParser.tokenize("grand a, le délai"))
        builder.append(DocumentOutlineParser.tokenize("grand b, l'intérêt à agir"))
        builder.append(DocumentOutlineParser.tokenize("titre deux, sur le fond"))

        let outline = builder.outline
        #expect(outline.sections.count == 2)
        #expect(outline.sections[0].children.map(\.marker) == ["A.", "B."])
        #expect(outline.sections[1].marker == "II.")
        #expect(outline.sections[1].children.isEmpty)
    }

    @Test("Un grand A sans titre préalable s'attache à la racine")
    func orphanLevelTwo() {
        var builder = DocumentOutlineBuilder()
        builder.append(DocumentOutlineParser.tokenize("grand a, le contexte"))
        #expect(builder.outline.sections.count == 1)
        #expect(builder.outline.sections[0].level == 2)
    }

    @Test("La prose d'avant tout titre va au préambule")
    func preamble() {
        var builder = DocumentOutlineBuilder()
        builder.append(DocumentOutlineParser.tokenize("la présente consultation porte sur un marché public."))
        #expect(builder.outline.preamble == [.paragraph("la présente consultation porte sur un marché public.")])
    }

    @Test("Une pause de respiration ne fragmente pas le paragraphe, nouvel alinéa coupe")
    func mergeAndBreak() {
        var builder = DocumentOutlineBuilder()
        builder.append(DocumentOutlineParser.tokenize("titre un, sur le fond"))
        builder.append(DocumentOutlineParser.tokenize("la décision est illégale"))
        builder.append(DocumentOutlineParser.tokenize("pour deux raisons. nouvel alinéa, d'abord, l'incompétence."))

        let blocks = builder.outline.sections[0].blocks
        #expect(blocks == [
            .paragraph("la décision est illégale pour deux raisons."),
            .paragraph("d'abord, l'incompétence."),
        ])
    }

    @Test("La citation traverse les segments et se referme proprement")
    func quoteAcrossSegments() {
        var builder = DocumentOutlineBuilder()
        builder.append(DocumentOutlineParser.tokenize("titre un, textes applicables"))
        builder.append(DocumentOutlineParser.tokenize("citation le délai est de deux mois"))
        builder.append(DocumentOutlineParser.tokenize("à compter de la notification, fin de citation. ce délai est expiré."))

        let blocks = builder.outline.sections[0].blocks
        #expect(blocks == [
            .quote("le délai est de deux mois à compter de la notification"),
            .paragraph("ce délai est expiré."),
        ])
    }

    @Test("Une citation jamais refermée n'empêche rien")
    func unclosedQuote() {
        var builder = DocumentOutlineBuilder()
        builder.append(DocumentOutlineParser.tokenize("citation un texte resté ouvert"))
        #expect(builder.outline.preamble == [.quote("un texte resté ouvert")])
    }

    @Test("Le plan survit à un aller-retour JSON")
    func codableRoundTrip() throws {
        var builder = DocumentOutlineBuilder()
        builder.append(DocumentOutlineParser.tokenize("titre un, sur la recevabilité"))
        builder.append(DocumentOutlineParser.tokenize("citation le texte, fin de citation"))

        let data = try JSONEncoder().encode(builder.outline)
        let decoded = try JSONDecoder().decode(DocumentOutline.self, from: data)
        #expect(decoded == builder.outline)
    }
}

@Suite("Détecteur de coupe au silence")
struct SilenceCutDetectorTests {

    @Test("La coupe survient après le silence requis, une seule fois")
    func cutsOnceAfterSilence() {
        var detector = SilenceCutDetector(rmsThreshold: 0.02, minSilenceDuration: 1.0, maxSegmentDuration: 90)
        #expect(detector.ingest(rms: 0.3, bufferDuration: 0.25) == false)

        #expect(detector.ingest(rms: 0.001, bufferDuration: 0.5) == false)
        #expect(detector.ingest(rms: 0.001, bufferDuration: 0.5) == true)
        // Après la coupe, le compteur repart : pas de coupe en rafale.
        #expect(detector.ingest(rms: 0.001, bufferDuration: 0.5) == false)
    }

    @Test("Sans voix entendue, le silence ne coupe jamais")
    func silenceAloneNeverCuts() {
        var detector = SilenceCutDetector(rmsThreshold: 0.02, minSilenceDuration: 1.0, maxSegmentDuration: 90)
        for _ in 0..<20 {
            #expect(detector.ingest(rms: 0.001, bufferDuration: 0.5) == false)
        }
    }

    @Test("Un retour de voix remet le compteur de silence à zéro")
    func voiceResetsSilence() {
        var detector = SilenceCutDetector(rmsThreshold: 0.02, minSilenceDuration: 1.0, maxSegmentDuration: 90)
        _ = detector.ingest(rms: 0.3, bufferDuration: 0.25)
        _ = detector.ingest(rms: 0.001, bufferDuration: 0.9)
        _ = detector.ingest(rms: 0.3, bufferDuration: 0.25)
        #expect(detector.ingest(rms: 0.001, bufferDuration: 0.9) == false)
    }

    @Test("Le garde-fou coupe un segment trop long même en pleine voix")
    func overflowCut() {
        var detector = SilenceCutDetector(rmsThreshold: 0.02, minSilenceDuration: 1.0, maxSegmentDuration: 3.0)
        #expect(detector.ingest(rms: 0.3, bufferDuration: 1.0) == false)
        #expect(detector.ingest(rms: 0.3, bufferDuration: 1.0) == false)
        #expect(detector.ingest(rms: 0.3, bufferDuration: 1.0) == true)
    }
}
