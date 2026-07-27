import Foundation

/// Une touche modificatrice, indépendamment du côté du clavier.
public enum ModifierKey: String, Codable, Equatable, Hashable, Sendable, CaseIterable, Identifiable {
    case control, option, shift, command, function

    public var id: String { rawValue }

    public var symbol: String {
        switch self {
        case .control: return "⌃"
        case .option: return "⌥"
        case .shift: return "⇧"
        case .command: return "⌘"
        case .function: return "fn"
        }
    }

    public var label: String {
        switch self {
        case .control: return "Contrôle"
        case .option: return "Option"
        case .shift: return "Majuscule"
        case .command: return "Commande"
        case .function: return "Fonction"
        }
    }

    /// Ordre d'affichage retenu par macOS : ⌃⌥⇧⌘, la touche fn en tête.
    public var order: Int {
        switch self {
        case .function: return 0
        case .control: return 1
        case .option: return 2
        case .shift: return 3
        case .command: return 4
        }
    }

    /// La touche fn est unique sur le clavier : elle n'a pas de côté.
    public var supportsSides: Bool { self != .function }
}

/// Côté du clavier. `any` accepte les deux, comme le faisait l'ancien raccourci.
public enum ModifierSide: String, Codable, Equatable, Hashable, Sendable, CaseIterable, Identifiable {
    case any, left, right

    public var id: String { rawValue }

    /// Marqueur accolé au symbole. Rien pour `any` : un raccourci non latéralisé
    /// doit s'afficher comme partout ailleurs sur le système.
    public var marker: String {
        switch self {
        case .any: return ""
        case .left: return "ᴸ"
        case .right: return "ᴿ"
        }
    }

    public var label: String {
        switch self {
        case .any: return "Indifférent"
        case .left: return "Gauche"
        case .right: return "Droite"
        }
    }
}

/// Une touche modificatrice et le côté du clavier où elle est attendue.
public struct LateralModifier: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var key: ModifierKey
    public var side: ModifierSide

    public var id: String { "\(key.rawValue).\(side.rawValue)" }

    public init(_ key: ModifierKey, _ side: ModifierSide = .any) {
        self.key = key
        // La touche fn n'existe qu'en un exemplaire : lui donner un côté produirait
        // un raccourci que rien ne peut satisfaire.
        self.side = key.supportsSides ? side : .any
    }

    public var display: String { key.symbol + side.marker }
}

/// Masques d'un événement clavier, tels que CoreGraphics les rapporte.
///
/// Les valeurs sont recopiées ici plutôt qu'importées de CoreGraphics : ce module
/// doit rester compilable et testable sans framework graphique.
public enum ModifierFlags {

    // Bits de famille, sans indication de côté.
    public static let shift: UInt64 = 0x0002_0000
    public static let control: UInt64 = 0x0004_0000
    public static let option: UInt64 = 0x0008_0000
    public static let command: UInt64 = 0x0010_0000
    public static let function: UInt64 = 0x0080_0000

    // Bits latéralisés, hérités d'IOKit (`NX_DEVICE*KEYMASK`).
    public static let leftControl: UInt64 = 0x0000_0001
    public static let leftShift: UInt64 = 0x0000_0002
    public static let rightShift: UInt64 = 0x0000_0004
    public static let leftCommand: UInt64 = 0x0000_0008
    public static let rightCommand: UInt64 = 0x0000_0010
    public static let leftOption: UInt64 = 0x0000_0020
    public static let rightOption: UInt64 = 0x0000_0040
    public static let rightControl: UInt64 = 0x0000_2000

    /// Bit de famille, celui que tout clavier pose.
    public static func family(_ key: ModifierKey) -> UInt64 {
        switch key {
        case .shift: return shift
        case .control: return control
        case .option: return option
        case .command: return command
        case .function: return function
        }
    }

    /// Les deux bits latéralisés d'une famille.
    public static func sided(_ key: ModifierKey) -> UInt64 {
        switch key {
        case .shift: return leftShift | rightShift
        case .control: return leftControl | rightControl
        case .option: return leftOption | rightOption
        case .command: return leftCommand | rightCommand
        case .function: return 0
        }
    }

    /// Le bit d'une touche précise. Zéro quand le côté est indifférent.
    public static func bit(_ modifier: LateralModifier) -> UInt64 {
        switch (modifier.key, modifier.side) {
        case (.shift, .left): return leftShift
        case (.shift, .right): return rightShift
        case (.control, .left): return leftControl
        case (.control, .right): return rightControl
        case (.option, .left): return leftOption
        case (.option, .right): return rightOption
        case (.command, .left): return leftCommand
        case (.command, .right): return rightCommand
        default: return 0
        }
    }

    /// Les modificateurs enfoncés, tels qu'un enregistrement de raccourci les lit.
    ///
    /// Les deux touches d'une même famille enfoncées ensemble valent « indifférent » :
    /// il n'y a pas de côté à retenir quand l'utilisateur donne les deux.
    public static func modifiers(in flags: UInt64, lateralized: Bool = true) -> [LateralModifier] {
        ModifierKey.allCases.sorted { $0.order < $1.order }.compactMap { key in
            guard flags & family(key) != 0 else { return nil }
            guard lateralized, key.supportsSides else { return LateralModifier(key) }

            let left = flags & bit(LateralModifier(key, .left)) != 0
            let right = flags & bit(LateralModifier(key, .right)) != 0
            switch (left, right) {
            case (true, false): return LateralModifier(key, .left)
            case (false, true): return LateralModifier(key, .right)
            default: return LateralModifier(key)
            }
        }
    }

    /// La touche demandée est-elle enfoncée ?
    ///
    /// Les bits latéralisés sont préférés quand le clavier les pose. Certains
    /// claviers tiers ne les émettent pas : le bit de famille prend alors le relais,
    /// et la latéralité est perdue faute d'être rapportée, jamais faute d'être
    /// demandée.
    public static func isPressed(_ modifier: LateralModifier, in flags: UInt64) -> Bool {
        guard modifier.side != .any, modifier.key.supportsSides else {
            return flags & family(modifier.key) != 0
        }
        if flags & sided(modifier.key) != 0 {
            return flags & bit(modifier) != 0
        }
        return flags & family(modifier.key) != 0
    }
}

/// Codes des touches modificatrices. À la différence des bits de masque, ils sont
/// toujours latéralisés, sur tous les claviers.
public enum ModifierKeyCode {

    public static func decode(_ keyCode: UInt16) -> LateralModifier? {
        switch keyCode {
        case 54: return LateralModifier(.command, .right)
        case 55: return LateralModifier(.command, .left)
        case 56: return LateralModifier(.shift, .left)
        case 60: return LateralModifier(.shift, .right)
        case 58: return LateralModifier(.option, .left)
        case 61: return LateralModifier(.option, .right)
        case 59: return LateralModifier(.control, .left)
        case 62: return LateralModifier(.control, .right)
        case 63: return LateralModifier(.function)
        default: return nil
        }
    }

    /// Un changement de modificateur, tel que `flagsChanged` le rapporte.
    public struct Event: Equatable, Sendable {
        public var modifier: LateralModifier
        public var isDown: Bool

        public init(modifier: LateralModifier, isDown: Bool) {
            self.modifier = modifier
            self.isDown = isDown
        }
    }

    /// Un `flagsChanged` ne dit pas s'il s'agit d'un appui ou d'un relâchement :
    /// il faut le déduire de l'état des masques après coup.
    public static func event(keyCode: UInt16, flags: UInt64) -> Event? {
        guard let modifier = decode(keyCode) else { return nil }
        return Event(modifier: modifier, isDown: ModifierFlags.isPressed(modifier, in: flags))
    }
}

/// Ce qui déclenche une dictée.
public enum HotkeyTrigger: Codable, Equatable, Sendable {

    /// Une touche modificatrice seule, maintenue ou frappée brièvement.
    case modifierOnly(LateralModifier)

    /// Deux appuis rapprochés sur une touche modificatrice.
    case doubleTap(LateralModifier)

    /// Une combinaison classique : des modificateurs et une touche.
    case combination(modifiers: [LateralModifier], keyCode: UInt16)

    /// ⌘⇧J, sans latéralité : le raccourci d'origine, conservé par défaut.
    public static let commandShiftJ = HotkeyTrigger.combination(
        modifiers: [LateralModifier(.command), LateralModifier(.shift)],
        keyCode: 38
    )

    /// La combinaison doit-elle être retirée du flux clavier ?
    ///
    /// Une combinaison, oui : sans quoi la touche s'écrirait dans le document. Un
    /// modificateur seul, jamais — avaler l'appui sur ⌘ le supprimerait pour tout
    /// le système.
    public var consumesEvent: Bool {
        if case .combination = self { return true }
        return false
    }

    public var modifiers: [LateralModifier] {
        switch self {
        case .modifierOnly(let modifier), .doubleTap(let modifier):
            return [modifier]
        case .combination(let modifiers, _):
            return modifiers
        }
    }

    /// Les modificateurs enfoncés sont-ils exactement ceux qu'attend la combinaison ?
    ///
    /// L'exactitude compte : sans elle, ⌘⇧J déclencherait aussi sur ⌃⌘⇧J, et
    /// l'utilisateur perdrait un raccourci qu'il croyait libre.
    public func isSatisfied(byFlags flags: UInt64) -> Bool {
        let required = modifiers
        for key in ModifierKey.allCases {
            let wanted = required.filter { $0.key == key }
            if wanted.isEmpty {
                guard flags & ModifierFlags.family(key) == 0 else { return false }
            } else {
                guard wanted.allSatisfy({ ModifierFlags.isPressed($0, in: flags) }) else { return false }
            }
        }
        return true
    }

    /// Le raccourci décomposé en touches, une par capuchon à dessiner.
    ///
    /// Découper la représentation textuelle caractère par caractère ferait du
    /// marqueur de côté une touche à part entière.
    public func keyCaps(keyLabel: (UInt16) -> String = { "touche \($0)" }) -> [String] {
        let symbols = modifiers.sorted { $0.key.order < $1.key.order }.map(\.display)
        switch self {
        case .modifierOnly:
            return symbols
        case .doubleTap:
            return symbols + ["×2"]
        case .combination(_, let keyCode):
            return symbols + [keyLabel(keyCode)]
        }
    }

    /// Représentation lisible. Le libellé de la touche dépend de la disposition du
    /// clavier, que ce module ne connaît pas : il est fourni par l'appelant.
    public func displayString(keyLabel: (UInt16) -> String = { "touche \($0)" }) -> String {
        let caps = keyCaps(keyLabel: keyLabel)
        if case .doubleTap = self {
            return caps.dropLast().joined() + " ×2"
        }
        return caps.joined()
    }
}
