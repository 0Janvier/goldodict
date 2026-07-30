import AppKit
import ApplicationServices

/// Contenu du champ de texte focalisé, par l'Accessibilité.
///
/// Lecture seule, jamais persistée : le texte lu ne sert qu'à un diff en mémoire
/// dont seules des paires courtes survivent. Les applications qui exposent mal
/// leurs champs (Electron, certains navigateurs) rendent `nil` — l'observation
/// est opportuniste, pas garantie.
enum FocusedFieldReader {

    /// Au-delà, AX rend probablement un document entier : trop cher à traiter.
    private static let maxCharacters = 400_000

    static func focusedFieldValue() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, 0.25)

        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide, kAXFocusedUIElementAttribute as CFString, &focused
        ) == .success, let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }

        let element = focused as! AXUIElement
        AXUIElementSetMessagingTimeout(element, 0.25)

        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success,
              let text = value as? String, !text.isEmpty, text.count <= maxCharacters else { return nil }
        return text
    }
}
