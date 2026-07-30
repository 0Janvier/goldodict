import Foundation

/// Repère un code de dossier du cabinet (« 26-812 ») dans une chaîne quelconque —
/// typiquement le titre de la fenêtre au premier plan, puisque les documents de
/// travail portent le code dans leur nom (convention NomClient-AA-XXX-titre).
public enum DossierCodeDetector {

    /// Les codes trouvés, dans l'ordre d'apparition, sans doublon.
    ///
    /// Un code est deux chiffres (l'année), un tiret, trois chiffres — bordé par
    /// autre chose que des chiffres : « 2609-0306 » n'en contient pas.
    public static func codes(in text: String) -> [String] {
        var found: [String] = []
        var seen = Set<String>()
        let characters = Array(text)
        var index = 0

        while index <= characters.count - 6 {
            let window = characters[index..<index + 6]
            if isCode(window),
               digitBefore(characters, index) == false,
               digitAfter(characters, index + 6) == false {
                let code = String(window)
                if seen.insert(code).inserted { found.append(code) }
                index += 6
            } else {
                index += 1
            }
        }
        return found
    }

    /// Le premier code qui correspond à un dossier connu.
    public static func match(in text: String, among dossiers: [DossierContext]) -> DossierContext? {
        for code in codes(in: text) {
            if let dossier = dossiers.first(where: { $0.code == code }) {
                return dossier
            }
        }
        return nil
    }

    private static func isCode(_ window: ArraySlice<Character>) -> Bool {
        let chars = Array(window)
        return chars[0].isNumber && chars[1].isNumber && chars[2] == "-"
            && chars[3].isNumber && chars[4].isNumber && chars[5].isNumber
    }

    private static func digitBefore(_ characters: [Character], _ index: Int) -> Bool {
        index > 0 && characters[index - 1].isNumber
    }

    private static func digitAfter(_ characters: [Character], _ index: Int) -> Bool {
        index < characters.count && characters[index].isNumber
    }
}
