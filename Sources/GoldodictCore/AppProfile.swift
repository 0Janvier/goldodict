import Foundation

/// Comportement de dictée associé à une famille d'applications.
///
/// Une même dictée n'appelle pas le même traitement partout : la ponctuation
/// automatique et les majuscules de phrase sont utiles dans un mémoire, nuisibles
/// dans un terminal où l'on dicte une commande.
public struct AppProfile: Codable, Equatable, Sendable, Identifiable {

    public var id: String { name }

    public var name: String

    /// Identifiants de paquet des applications concernées.
    public var bundleIdentifiers: [String]

    /// Soumettre la dictée au correcteur local.
    public var correctText: Bool
    /// Interpréter « virgule », « point », « à la ligne ».
    public var punctuationCommands: Bool
    /// Majuscule en tête de phrase.
    public var capitalizeSentences: Bool
    /// Espaces insécables et guillemets français.
    public var frenchTypography: Bool
    /// Appliquer le lexique de correction du vocabulaire.
    public var applyLexicon: Bool
    /// Règles de style apprises ou écrites à la main, ajoutées aux instructions
    /// du correcteur pour ce profil.
    public var styleNotes: [String]

    public init(
        name: String,
        bundleIdentifiers: [String],
        correctText: Bool,
        punctuationCommands: Bool,
        capitalizeSentences: Bool,
        frenchTypography: Bool,
        applyLexicon: Bool = true,
        styleNotes: [String] = []
    ) {
        self.name = name
        self.bundleIdentifiers = bundleIdentifiers
        self.correctText = correctText
        self.punctuationCommands = punctuationCommands
        self.capitalizeSentences = capitalizeSentences
        self.frenchTypography = frenchTypography
        self.applyLexicon = applyLexicon
        self.styleNotes = styleNotes
    }

    private enum CodingKeys: String, CodingKey {
        case name, bundleIdentifiers, correctText, punctuationCommands
        case capitalizeSentences, frenchTypography, applyLexicon, styleNotes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        bundleIdentifiers = try container.decode([String].self, forKey: .bundleIdentifiers)
        correctText = try container.decode(Bool.self, forKey: .correctText)
        punctuationCommands = try container.decode(Bool.self, forKey: .punctuationCommands)
        capitalizeSentences = try container.decode(Bool.self, forKey: .capitalizeSentences)
        frenchTypography = try container.decode(Bool.self, forKey: .frenchTypography)
        applyLexicon = try container.decodeIfPresent(Bool.self, forKey: .applyLexicon) ?? true
        styleNotes = try container.decodeIfPresent([String].self, forKey: .styleNotes) ?? []
    }
}

extension AppProfile {

    /// Profil appliqué quand l'application au premier plan n'est rattachée à aucun
    /// profil particulier.
    public static let redaction = AppProfile(
        name: "Rédaction",
        bundleIdentifiers: [
            "com.microsoft.Word",
            "com.apple.mail",
            "com.apple.iWork.Pages",
            "com.apple.TextEdit",
            "com.apple.Notes",
            "fr.sztulman.goldocab",
            "com.soulver.Soulver3",
            "com.ulyssesapp.mac",
        ],
        correctText: true,
        punctuationCommands: true,
        capitalizeSentences: true,
        frenchTypography: true
    )

    /// Terminaux et éditeurs de code : le texte doit arriver tel qu'il a été dit.
    /// Une majuscule ou une espace insécable y casse une commande.
    public static let raw = AppProfile(
        name: "Brut",
        bundleIdentifiers: [
            "com.mitchellh.ghostty",
            "com.apple.Terminal",
            "net.kovidgoyal.kitty",
            "com.googlecode.iterm2",
            "com.apple.dt.Xcode",
            "com.microsoft.VSCode",
            "com.todesktop.230313mzl4w4u92", // Cursor
        ],
        correctText: false,
        punctuationCommands: false,
        capitalizeSentences: false,
        frenchTypography: false,
        applyLexicon: false
    )

    /// Messageries : ponctuation utile, correction inutile sur des phrases courtes,
    /// insécables mal rendues par la plupart des clients.
    public static let messaging = AppProfile(
        name: "Messagerie",
        bundleIdentifiers: [
            "com.tinyspeck.slackmacgap",
            "com.apple.MobileSMS",
            "net.whatsapp.WhatsApp",
            "ru.keepcoder.Telegram",
        ],
        correctText: false,
        punctuationCommands: true,
        capitalizeSentences: true,
        frenchTypography: false
    )

    public static let defaults: [AppProfile] = [.redaction, .raw, .messaging]
}

/// Table des profils, interrogée par identifiant de paquet.
public struct ProfileSet: Equatable, Sendable {

    public private(set) var profiles: [AppProfile]

    public init(profiles: [AppProfile] = AppProfile.defaults) {
        self.profiles = profiles
    }

    /// Profil retenu pour une application. Le premier profil de la liste sert de
    /// défaut : une application inconnue est traitée comme de la rédaction, ce qui
    /// est le cas le plus fréquent et le moins risqué.
    public func profile(for bundleIdentifier: String?) -> AppProfile {
        guard let bundleIdentifier else { return profiles.first ?? .redaction }
        return profiles.first { $0.bundleIdentifiers.contains(bundleIdentifier) }
            ?? profiles.first
            ?? .redaction
    }

    /// Profil désigné par son nom, source de vérité pour l'interface de réglages.
    public func profile(named name: String) -> AppProfile? {
        profiles.first { $0.name == name }
    }

    public mutating func replace(_ profile: AppProfile) {
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
    }
}
