import Foundation

/// Retrouve, dans le contenu d'un champ de texte, le passage qui correspond à une
/// insertion antérieure — pour mesurer ce que l'utilisateur y a retouché.
///
/// Le champ peut contenir bien plus que l'insertion (tout un document). La
/// recherche glisse des fenêtres de taille voisine de l'insertion et compare des
/// sacs de mots : robuste aux retouches locales, aveugle aux réécritures — ce qui
/// est voulu, une réécriture n'est pas une correction à apprendre.
public enum InsertionLocator {

    /// En dessous, la fenêtre ne « ressemble » plus : rien n'est rendu.
    public static let similarityThreshold = 0.6

    /// Un champ démesuré (AX rend parfois un document entier) coûte trop cher :
    /// au-delà, l'observation est simplement abandonnée.
    public static let maxFieldTokens = 50_000

    /// Le passage du champ correspondant à l'insertion, s'il a été modifié.
    /// `nil` si l'insertion est introuvable ou parfaitement intacte.
    public static func modifiedPassage(of inserted: String, in field: String) -> String? {
        let needle = inserted.split(whereSeparator: \.isWhitespace).map(String.init)
        let haystack = field.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !needle.isEmpty, needle.count <= haystack.count,
              haystack.count <= maxFieldTokens else { return nil }

        var reference: [String: Int] = [:]
        for token in needle { reference[token, default: 0] += 1 }

        var best: (similarity: Double, range: Range<Int>)?

        // Trois tailles de fenêtre : l'insertion telle quelle, un quart plus
        // courte (mots supprimés), un quart plus longue (mots ajoutés).
        let sizes = Set([
            needle.count,
            max(1, Int((Double(needle.count) * 0.75).rounded())),
            Int((Double(needle.count) * 1.25).rounded()),
        ]).filter { $0 <= haystack.count }

        for size in sizes {
            var counts: [String: Int] = [:]
            var overlap = 0

            for index in 0..<haystack.count {
                let entering = haystack[index]
                counts[entering, default: 0] += 1
                if counts[entering]! <= reference[entering, default: 0] { overlap += 1 }

                if index >= size {
                    let leaving = haystack[index - size]
                    if counts[leaving]! <= reference[leaving, default: 0] { overlap -= 1 }
                    counts[leaving]! -= 1
                }

                guard index >= size - 1 else { continue }
                let similarity = Double(overlap) / Double(max(size, needle.count))
                if similarity >= similarityThreshold, similarity > (best?.similarity ?? 0) {
                    best = (similarity, (index - size + 1)..<(index + 1))
                }
            }
        }

        guard let best else { return nil }
        let passage = Array(haystack[best.range])
        guard passage != needle else { return nil }
        return passage.joined(separator: " ")
    }
}
