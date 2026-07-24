import Carbon.HIToolbox
import Foundation

/// Raccourci clavier global.
///
/// L'API Carbon `RegisterEventHotKey` est retenue plutôt qu'un `CGEventTap` parce
/// qu'elle délivre `kEventHotKeyReleased` aussi bien que `kEventHotKeyPressed` —
/// nécessaire pour distinguer l'appui bref du maintien — **sans** exiger
/// l'autorisation « Surveillance de l'entrée ». Une permission système en moins.
final class HotkeyMonitor {

    struct Combination: Equatable {
        /// Code de touche virtuel (`kVK_*`), indépendant de la disposition AZERTY.
        var keyCode: UInt32
        /// Masque Carbon : `controlKey`, `optionKey`, `cmdKey`, `shiftKey`.
        var modifiers: UInt32

        /// ⌘⇧J. La touche J occupe la même position physique en AZERTY qu'en QWERTY,
        /// le code de touche virtuel est donc fiable sans traitement particulier.
        ///
        /// À ne pas confondre avec ⌃⌥Espace, que macOS réserve pour « Sélectionner
        /// la source de saisie suivante » et qu'un raccourci applicatif ne peut pas
        /// capter.
        static let commandShiftJ = Combination(
            keyCode: UInt32(kVK_ANSI_J),
            modifiers: UInt32(cmdKey | shiftKey)
        )

        /// Représentation lisible, dans l'ordre d'affichage retenu par macOS.
        var displayString: String {
            var symbols = ""
            if modifiers & UInt32(controlKey) != 0 { symbols += "⌃" }
            if modifiers & UInt32(optionKey) != 0 { symbols += "⌥" }
            if modifiers & UInt32(shiftKey) != 0 { symbols += "⇧" }
            if modifiers & UInt32(cmdKey) != 0 { symbols += "⌘" }
            return symbols + Self.keyLabel(for: keyCode)
        }

        private static func keyLabel(for keyCode: UInt32) -> String {
            switch Int(keyCode) {
            case kVK_Space: return "Espace"
            case kVK_ANSI_J: return "J"
            case kVK_ANSI_K: return "K"
            case kVK_ANSI_D: return "D"
            case kVK_F5: return "F5"
            default: return "touche \(keyCode)"
            }
        }
    }

    /// Appelé sur la boucle principale à chaque enfoncement (`true`) et relâchement (`false`).
    var onEvent: ((Bool) -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var combination: Combination?

    /// Enregistre le raccourci, en remplaçant celui éventuellement actif.
    /// - Returns: `true` si l'enregistrement a réussi. Un échec signale presque
    ///   toujours un raccourci déjà pris par une autre application.
    @discardableResult
    func register(_ combination: Combination) -> Bool {
        unregister()

        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]

        let context = Unmanaged.passUnretained(self).toOpaque()
        let installStatus = InstallEventHandler(
            GetEventDispatcherTarget(),
            hotkeyEventHandler,
            eventTypes.count,
            &eventTypes,
            context,
            &handlerRef
        )
        guard installStatus == noErr else { return false }

        let hotKeyID = EventHotKeyID(signature: OSType(0x41425241 /* "ABRA" */), id: 1)
        let registerStatus = RegisterEventHotKey(
            combination.keyCode,
            combination.modifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )
        guard registerStatus == noErr else {
            unregister()
            return false
        }

        self.combination = combination
        return true
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
        combination = nil
    }

    fileprivate func dispatch(isDown: Bool) {
        onEvent?(isDown)
    }

    deinit {
        unregister()
    }
}

/// Le rappel Carbon est une fonction C : il ne capture rien et retrouve l'instance
/// par le pointeur de contexte passé à `InstallEventHandler`.
private let hotkeyEventHandler: EventHandlerUPP = { _, event, context in
    guard let event, let context else { return OSStatus(eventNotHandledErr) }
    let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(context).takeUnretainedValue()
    let kind = GetEventKind(event)
    switch Int(kind) {
    case kEventHotKeyPressed:
        monitor.dispatch(isDown: true)
    case kEventHotKeyReleased:
        monitor.dispatch(isDown: false)
    default:
        return OSStatus(eventNotHandledErr)
    }
    return noErr
}
