import AppKit
import ApplicationServices

/// Titre de la fenêtre focalisée d'une application, par l'Accessibilité.
///
/// L'autorisation est déjà accordée pour le collage ; la lecture d'un titre de
/// fenêtre n'exige rien de plus. Certaines applications (Electron, navigateurs)
/// répondent mal ou pas du tout : tout échec rend `nil`, et l'appelant fait sans.
enum WindowTitleReader {

    static func focusedWindowTitle(of application: NSRunningApplication?) -> String? {
        guard let pid = application?.processIdentifier else { return nil }
        let element = AXUIElementCreateApplication(pid)
        // Une application qui ne répond pas à l'Accessibilité ferait attendre six
        // secondes par défaut — inacceptable au départ d'une dictée.
        AXUIElementSetMessagingTimeout(element, 0.25)

        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &window) == .success,
              let window, CFGetTypeID(window) == AXUIElementGetTypeID() else { return nil }

        var title: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window as! AXUIElement, kAXTitleAttribute as CFString, &title) == .success,
              let value = title as? String, !value.isEmpty else { return nil }
        return value
    }
}
