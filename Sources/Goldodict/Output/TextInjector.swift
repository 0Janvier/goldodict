import AppKit
import Carbon.HIToolbox
import Foundation

/// Place le texte dicté dans le presse-papiers et le colle dans l'application active.
@MainActor
enum TextInjector {

    enum Outcome: Equatable {
        case pasted
        /// Texte copié mais non collé, l'autorisation Accessibilité faisant défaut.
        case copiedOnly
    }

    /// - Parameters:
    ///   - text: texte à insérer.
    ///   - autoPaste: simuler Cmd+V après la copie.
    ///   - restorePasteboard: rendre au presse-papiers son contenu antérieur une fois
    ///     le collage effectué. Désactivé par défaut : le texte dicté doit rester
    ///     disponible pour un collage manuel ultérieur.
    @discardableResult
    static func inject(
        _ text: String,
        autoPaste: Bool = true,
        restorePasteboard: Bool = false
    ) async -> Outcome {
        guard !text.isEmpty else { return .copiedOnly }

        let pasteboard = NSPasteboard.general
        let previous = restorePasteboard ? snapshot(of: pasteboard) : nil

        let countBeforeWrite = pasteboard.changeCount
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        guard autoPaste else { return .copiedOnly }
        guard PermissionGuard.hasAccessibility() else { return .copiedOnly }

        // Coller avant que le presse-papiers ait réellement changé collerait le
        // contenu précédent. On attend que le compteur de modifications ait bougé.
        guard await waitForChange(on: pasteboard, beyond: countBeforeWrite) else {
            return .copiedOnly
        }

        sendPasteShortcut()

        if let previous {
            // L'application cible lit le presse-papiers de façon asynchrone ; restaurer
            // trop tôt lui fait coller l'ancien contenu.
            try? await Task.sleep(for: .milliseconds(250))
            restore(previous, to: pasteboard)
        }

        return .pasted
    }

    // MARK: - Presse-papiers

    private static func waitForChange(
        on pasteboard: NSPasteboard,
        beyond count: Int,
        timeout: Duration = .milliseconds(300)
    ) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if pasteboard.changeCount != count { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return pasteboard.changeCount != count
    }

    private struct Snapshot {
        let items: [[NSPasteboard.PasteboardType: Data]]
    }

    private static func snapshot(of pasteboard: NSPasteboard) -> Snapshot {
        let items = (pasteboard.pasteboardItems ?? []).map { item in
            var contents: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { contents[type] = data }
            }
            return contents
        }
        return Snapshot(items: items)
    }

    private static func restore(_ snapshot: Snapshot, to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !snapshot.items.isEmpty else { return }
        let items = snapshot.items.map { contents -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in contents { item.setData(data, forType: type) }
            return item
        }
        pasteboard.writeObjects(items)
    }

    // MARK: - Frappe simulée

    /// Émet Cmd+V au niveau du système.
    ///
    /// Les événements sont postés sur `.cghidEventTap`, le point d'injection le plus
    /// bas, afin que l'application au premier plan les reçoive comme une frappe
    /// ordinaire. Le drapeau `.maskCommand` doit être posé sur l'enfoncement **et**
    /// le relâchement, faute de quoi certaines applications voient un V isolé.
    private static func sendPasteShortcut() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        let v = CGKeyCode(kVK_ANSI_V)

        // Empêche les touches physiquement enfoncées (celles du raccourci de dictée)
        // de se mêler à l'événement synthétique.
        source.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval
        )

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
