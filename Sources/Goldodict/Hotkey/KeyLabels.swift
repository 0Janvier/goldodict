import Carbon.HIToolbox
import Foundation

/// Nom affichable d'une touche, dans la disposition du clavier réellement branché.
///
/// Une table figée mentirait : le code 12 porte « A » en AZERTY et « Q » en QWERTY.
/// Le libellé est donc demandé au système, qui seul connaît la disposition active.
enum KeyLabels {

    /// Touches sans caractère imprimable, que la traduction rendrait par un blanc
    /// ou un caractère de contrôle.
    private static let named: [Int: String] = [
        kVK_Space: "Espace",
        kVK_Return: "Entrée",
        kVK_Tab: "Tabulation",
        kVK_Delete: "Suppr.",
        kVK_ForwardDelete: "Suppr. avant",
        kVK_Escape: "Échap",
        kVK_LeftArrow: "←",
        kVK_RightArrow: "→",
        kVK_UpArrow: "↑",
        kVK_DownArrow: "↓",
        kVK_Home: "Début",
        kVK_End: "Fin",
        kVK_PageUp: "Page préc.",
        kVK_PageDown: "Page suiv.",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4",
        kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8",
        kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15",
    ]

    static func label(for keyCode: UInt16) -> String {
        if let name = named[Int(keyCode)] { return name }
        if let translated = translate(keyCode), !translated.isEmpty {
            return translated.uppercased()
        }
        return "touche \(keyCode)"
    }

    /// Traduit le code en caractère, modificateurs à zéro, par la table de la
    /// disposition courante.
    private static func translate(_ keyCode: UInt16) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }

        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)

        let status = data.withUnsafeBytes { buffer -> OSStatus in
            guard let layout = buffer.bindMemory(to: UCKeyboardLayout.self).baseAddress else {
                return OSStatus(paramErr)
            }
            return UCKeyTranslate(
                layout,
                keyCode,
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                characters.count,
                &length,
                &characters
            )
        }

        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: characters, count: length)
    }
}
