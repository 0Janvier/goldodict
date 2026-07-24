import AbracadabraCore
import Carbon.HIToolbox
import Foundation
import Observation
import ServiceManagement

/// Réglages persistés dans les préférences utilisateur.
///
/// Le lexique, lui, reste un fichier JSON séparé : il doit pouvoir être édité à la
/// main, sauvegardé et transporté indépendamment de l'application.
@Observable
@MainActor
final class Preferences {

    private enum Key {
        static let engine = "engine.identifier"
        static let whisperModel = "engine.whisper.model"
        static let hotkeyCode = "hotkey.keyCode"
        static let hotkeyModifiers = "hotkey.modifiers"
        static let autoPaste = "output.autoPaste"
        static let restorePasteboard = "output.restorePasteboard"
        static let holdThreshold = "trigger.holdThreshold"
        static let simpleMarks = "punctuation.simpleMarks"
        static let lineBreaks = "punctuation.lineBreaks"
        static let compoundMarks = "punctuation.compoundMarks"
        static let capitalize = "punctuation.capitalize"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.engine: "apple",
            Key.whisperModel: WhisperMLXEngine.defaultModel,
            Key.hotkeyCode: Int(kVK_ANSI_J),
            Key.hotkeyModifiers: Int(cmdKey | shiftKey),
            Key.autoPaste: true,
            Key.restorePasteboard: false,
            Key.holdThreshold: 0.25,
            Key.simpleMarks: true,
            Key.lineBreaks: true,
            Key.compoundMarks: true,
            Key.capitalize: true,
        ])
    }

    // MARK: - Moteur

    var engineIdentifier: String {
        get { access(keyPath: \.engineIdentifier); return defaults.string(forKey: Key.engine) ?? "apple" }
        set { withMutation(keyPath: \.engineIdentifier) { defaults.set(newValue, forKey: Key.engine) } }
    }

    var whisperModel: String {
        get { access(keyPath: \.whisperModel); return defaults.string(forKey: Key.whisperModel) ?? WhisperMLXEngine.defaultModel }
        set { withMutation(keyPath: \.whisperModel) { defaults.set(newValue, forKey: Key.whisperModel) } }
    }

    // MARK: - Déclenchement

    var hotkey: HotkeyMonitor.Combination {
        get {
            access(keyPath: \.hotkey)
            return HotkeyMonitor.Combination(
                keyCode: UInt32(defaults.integer(forKey: Key.hotkeyCode)),
                modifiers: UInt32(defaults.integer(forKey: Key.hotkeyModifiers))
            )
        }
        set {
            withMutation(keyPath: \.hotkey) {
                defaults.set(Int(newValue.keyCode), forKey: Key.hotkeyCode)
                defaults.set(Int(newValue.modifiers), forKey: Key.hotkeyModifiers)
            }
        }
    }

    var holdThreshold: Double {
        get { access(keyPath: \.holdThreshold); return defaults.double(forKey: Key.holdThreshold) }
        set { withMutation(keyPath: \.holdThreshold) { defaults.set(newValue, forKey: Key.holdThreshold) } }
    }

    // MARK: - Insertion

    var autoPaste: Bool {
        get { access(keyPath: \.autoPaste); return defaults.bool(forKey: Key.autoPaste) }
        set { withMutation(keyPath: \.autoPaste) { defaults.set(newValue, forKey: Key.autoPaste) } }
    }

    /// Rendre au presse-papiers son contenu antérieur. Désactivé par défaut : le
    /// texte dicté doit rester disponible pour un collage manuel.
    var restorePasteboard: Bool {
        get { access(keyPath: \.restorePasteboard); return defaults.bool(forKey: Key.restorePasteboard) }
        set { withMutation(keyPath: \.restorePasteboard) { defaults.set(newValue, forKey: Key.restorePasteboard) } }
    }

    // MARK: - Ponctuation

    var punctuationOptions: PunctuationCommands.Options {
        get {
            access(keyPath: \.punctuationOptions)
            return PunctuationCommands.Options(
                simpleMarks: defaults.bool(forKey: Key.simpleMarks),
                lineBreaks: defaults.bool(forKey: Key.lineBreaks),
                compoundMarks: defaults.bool(forKey: Key.compoundMarks),
                capitalizeSentences: defaults.bool(forKey: Key.capitalize)
            )
        }
        set {
            withMutation(keyPath: \.punctuationOptions) {
                defaults.set(newValue.simpleMarks, forKey: Key.simpleMarks)
                defaults.set(newValue.lineBreaks, forKey: Key.lineBreaks)
                defaults.set(newValue.compoundMarks, forKey: Key.compoundMarks)
                defaults.set(newValue.capitalizeSentences, forKey: Key.capitalize)
            }
        }
    }

    // MARK: - Lancement au démarrage

    var launchAtLogin: Bool {
        get {
            access(keyPath: \.launchAtLogin)
            return SMAppService.mainApp.status == .enabled
        }
        set {
            withMutation(keyPath: \.launchAtLogin) {
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    Log.lifecycle.error("lancement au démarrage : \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }
}
