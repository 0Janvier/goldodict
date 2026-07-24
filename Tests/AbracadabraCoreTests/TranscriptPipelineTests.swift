import Testing
@testable import AbracadabraCore

@Suite("Commandes de ponctuation")
struct PunctuationCommandsTests {

    private let commands = PunctuationCommands()

    @Test("Les commandes simples deviennent des signes")
    func simpleMarks() {
        #expect(commands.apply(to: "bonjour virgule ceci est un test point")
            .contains(","))
        #expect(commands.apply(to: "bonjour virgule ceci est un test point")
            .contains("."))
    }

    @Test("Les commandes composées passent avant les simples")
    func compoundBeforeSimple() {
        let result = commands.apply(to: "est-ce recevable point d'interrogation")
        #expect(result.contains("?"))
        #expect(!result.contains("."))
    }

    @Test("Les accents manquants n'empêchent pas la reconnaissance")
    func diacriticInsensitive() {
        let withAccent = commands.apply(to: "premier moyen à la ligne second moyen")
        let without = commands.apply(to: "premier moyen a la ligne second moyen")
        #expect(withAccent.contains("\n"))
        #expect(without.contains("\n"))
    }

    @Test("Un mot contenant la commande n'est pas altéré")
    func noPartialMatch() {
        #expect(commands.apply(to: "le pointage est fait") == "le pointage est fait")
        #expect(commands.apply(to: "la ponctuation") == "la ponctuation")
    }

    @Test("Les guillemets français sont produits")
    func frenchQuotes() {
        let result = commands.apply(to: "il écrit ouvrez les guillemets recevable fermez les guillemets")
        #expect(result.contains("«"))
        #expect(result.contains("»"))
    }

    @Test("Le groupe des marques simples est désactivable")
    func simpleMarksDisabled() {
        var options = PunctuationCommands.Options.default
        options.simpleMarks = false
        let restricted = PunctuationCommands(options: options)
        let result = restricted.apply(to: "le point de départ du délai virgule")
        #expect(result.contains("point"))
        #expect(result.contains("virgule"))
    }
}

@Suite("Typographie française")
struct FrenchTypographyTests {

    @Test("La ponctuation basse est collée au mot précédent")
    func lowMarksAreTight() {
        #expect(FrenchTypography.normalize("bonjour , ceci") == "Bonjour, ceci"
            || FrenchTypography.normalize("bonjour , ceci") == "bonjour, ceci")
    }

    @Test("La ponctuation haute reçoit une espace insécable")
    func highMarksGetNonBreakingSpace() {
        let result = FrenchTypography.normalize("est-ce recevable ?")
        #expect(result.contains("\u{00A0}?"))
    }

    @Test("Les guillemets portent des espaces insécables internes")
    func quotesGetInnerNonBreakingSpaces() {
        let result = FrenchTypography.normalize("il dit « recevable »")
        #expect(result.contains("«\u{00A0}"))
        #expect(result.contains("\u{00A0}»"))
    }

    @Test("Les accents traversent la normalisation intacts")
    func accentsSurvive() {
        let source = "la requête est irrecevable, le délai étant expiré à Toulouse"
        let result = FrenchTypography.normalize(source)
        #expect(result.contains("requête"))
        #expect(result.contains("délai"))
        #expect(result.contains("étant"))
        #expect(result.contains("à Toulouse"))
    }

    @Test("La majuscule est posée en tête et après un point")
    func sentencesAreCapitalized() {
        let result = FrenchTypography.capitalizeSentences("la requête est tardive. elle sera rejetée.")
        #expect(result.hasPrefix("La requête"))
        #expect(result.contains(". Elle sera"))
    }

    @Test("Une majuscule accentuée est correctement produite")
    func accentedCapital() {
        #expect(FrenchTypography.capitalizeSentences("établissement public").hasPrefix("É"))
    }
}

@Suite("Lexique")
struct LexiconTests {

    private let lexicon = Lexicon(entries: [
        LexiconEntry(entendu: "cage de baisse", corrige: "CAA de Bordeaux"),
        LexiconEntry(entendu: "cé jaïna", corrige: "CE, Sect."),
        LexiconEntry(entendu: "tribunal", corrige: "tribunal administratif", biaiser: false),
    ])

    @Test("Une déformation phonétique est corrigée")
    func correctsMishearing() {
        #expect(lexicon.correct("saisir la cage de baisse").contains("CAA de Bordeaux"))
    }

    @Test("La correction ignore les accents de la source")
    func correctionIgnoresAccents() {
        #expect(lexicon.correct("arrêt ce jaina rendu").contains("CE, Sect."))
    }

    @Test("Seules les entrées marquées alimentent le vocabulaire contextuel")
    func contextualStringsRespectFlag() {
        let strings = lexicon.contextualStrings
        #expect(strings.contains("CAA de Bordeaux"))
        #expect(!strings.contains("tribunal administratif"))
    }

    @Test("Les entrées longues sont appliquées avant les courtes")
    func longestEntriesFirst() {
        let overlapping = Lexicon(entries: [
            LexiconEntry(entendu: "conseil", corrige: "Conseil"),
            LexiconEntry(entendu: "conseil d'état", corrige: "Conseil d'État"),
        ])
        #expect(overlapping.correct("le conseil d'état juge").contains("Conseil d'État"))
    }
}

@Suite("Chaîne de traitement complète")
struct PipelineTests {

    @Test("Une dictée juridique est mise en forme de bout en bout")
    func endToEnd() {
        let lexicon = Lexicon(entries: [
            LexiconEntry(entendu: "cage de baisse", corrige: "CAA de Bordeaux")
        ])
        let pipeline = TranscriptPipeline(lexicon: lexicon)
        let result = pipeline.process(
            "la requête est portée devant la cage de baisse virgule elle est recevable point"
        )

        #expect(result.hasPrefix("La requête"))
        #expect(result.contains("CAA de Bordeaux,"))
        #expect(result.hasSuffix("recevable."))
    }

    @Test("Un texte vide ne produit rien")
    func emptyStaysEmpty() {
        #expect(TranscriptPipeline().process("   \n  ") == "")
    }

    @Test("Les accents survivent à la chaîne entière")
    func accentsSurvivePipeline() {
        let result = TranscriptPipeline().process(
            "le délai de recours était expiré virgule la requête est irrecevable point"
        )
        #expect(result.contains("délai"))
        #expect(result.contains("était"))
        #expect(result.contains("expiré"))
        #expect(result.contains("irrecevable."))
    }
}
