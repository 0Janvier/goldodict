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

        // Le compteur doit être relevé APRÈS le clear. `clearContents()` l'incrémente
        // déjà : attendre « au-delà du compteur d'avant le clear » réussissait aussitôt,
        // presse-papiers encore vide ou ancien contenu encore visible pour l'application
        // cible. Cmd+V collait alors ce qu'il y avait avant la dictée — souvent un
        // extrait d'interface ou de journal d'outil encore dans le presse-papiers.
        pasteboard.clearContents()
        let countBeforeSet = pasteboard.changeCount

        // Un seul item, texte brut uniquement : évite qu'un type riche résiduel
        // (HTML, RTF) d'une copie antérieure ne soit préféré au plain text.
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        guard pasteboard.writeObjects([item]) else { return .copiedOnly }

        guard autoPaste else { return .copiedOnly }
        guard PermissionGuard.hasAccessibility() else { return .copiedOnly }

        guard await waitForChange(on: pasteboard, beyond: countBeforeSet) else {
            return .copiedOnly
        }
        // Le compteur a bougé : encore faut-il que ce soit notre texte. Un concurrent
        // (gestionnaire de presse-papiers, autre processus) peut avoir écrit entre-temps.
        guard pasteboard.string(forType: .string) == text else {
            Log.output.error("presse-papiers altéré avant collage, insertion annulée")
            return .copiedOnly
        }

        sendPasteShortcut()

        if let previous {
            // L'application cible lit le presse-papiers de façon asynchrone ; restaurer
            // trop tôt lui fait coller l'ancien contenu. Electron (Cursor, VS Code,
            // Slack…) est particulièrement lent : 250 ms n'y suffisait pas.
            try? await Task.sleep(for: .milliseconds(500))
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
