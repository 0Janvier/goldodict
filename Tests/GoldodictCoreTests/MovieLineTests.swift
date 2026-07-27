import Testing
@testable import GoldodictCore

@Suite("Répliques de cinéma")
struct MovieLineTests {

    private let taxi = MovieLine(replique: "You talkin' to me?", film: "Taxi Driver", annee: 1976)
    private let hal = MovieLine(replique: "Open the pod bay doors, HAL.", film: "2001: A Space Odyssey", annee: 1968)

    // MARK: - Mise en forme

    @Test("La réplique seule ne porte ni film ni année")
    func repliqueSeule() {
        #expect(taxi.rendered(.repliqueSeule) == "You talkin' to me?")
    }

    @Test("Réplique et film tiennent sur une ligne")
    func repliqueEtFilm() {
        let rendered = taxi.rendered(.repliqueEtFilm)
        #expect(rendered.contains("You talkin' to me?"))
        #expect(rendered.contains("Taxi Driver"))
        #expect(!rendered.contains("\n"))
    }

    @Test("Le format complet renvoie la provenance à la seconde ligne")
    func repliqueFilmAnnee() {
        let lines = taxi.rendered(.repliqueFilmAnnee).split(separator: "\n")
        #expect(lines.count == 2)
        #expect(lines[0] == "You talkin' to me?")
        #expect(lines[1] == "Taxi Driver, 1976")
    }

    @Test("Seul le format complet réclame deux lignes")
    func lineCount() {
        #expect(MovieLineFormat.repliqueSeule.lineCount == 1)
        #expect(MovieLineFormat.repliqueEtFilm.lineCount == 1)
        #expect(MovieLineFormat.repliqueFilmAnnee.lineCount == 2)
    }

    // MARK: - Tirage

    @Test("Un recueil vide ne tire rien")
    func emptyBookDrawsNothing() {
        #expect(MovieLineBook().draw() == nil)
    }

    @Test("Le tirage évite la réplique précédente")
    func drawAvoidsPrevious() {
        let book = MovieLineBook(lines: [taxi, hal])
        // Le tireur réclame toujours le premier candidat : sans exclusion, il
        // rendrait deux fois « You talkin' to me? ».
        let drawn = book.draw(after: taxi, pick: { _ in 0 })
        #expect(drawn == hal)
    }

    @Test("Une réplique unique est retirée plutôt que rien")
    func singleLineIsRedrawn() {
        let book = MovieLineBook(lines: [taxi])
        #expect(book.draw(after: taxi, pick: { _ in 0 }) == taxi)
    }

    @Test("Le tireur ne voit jamais la réplique exclue")
    func candidateCountExcludesPrevious() {
        let book = MovieLineBook(lines: [taxi, hal])
        var offered = 0
        _ = book.draw(after: hal, pick: { count in
            offered = count
            return 0
        })
        #expect(offered == 1)
    }

    @Test("Un index hors bornes retombe sur le premier candidat")
    func outOfBoundsFallsBack() {
        let book = MovieLineBook(lines: [taxi, hal])
        #expect(book.draw(pick: { _ in 99 }) == taxi)
    }

    // MARK: - Catalogue

    @Test("Une réplique ajoutée deux fois ne compte qu'une fois")
    func upsertIsIdempotent() {
        var book = MovieLineBook(lines: [taxi])
        book.upsert(MovieLine(replique: "You talkin' to me?", film: "Taxi Driver", annee: 1977))
        #expect(book.lines.count == 1)
        #expect(book.lines[0].annee == 1977)
    }

    @Test("La suppression porte sur l'identifiant, insensible à la casse")
    func removeIsCaseInsensitive() {
        var book = MovieLineBook(lines: [taxi, hal])
        book.remove(id: "you talkin' to me?")
        #expect(book.lines == [hal])
    }
}
