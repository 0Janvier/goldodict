import AppKit
import SwiftUI

/// Fenêtre de réglages gérée à la main.
///
/// La scène `Settings` de SwiftUI s'ouvre par un sélecteur dont le nom a changé
/// selon les versions de macOS et qui reste sans effet dans une application sans
/// icône du Dock. Une `NSWindow` explicite ne dépend d'aucun de ces aléas.
@MainActor
final class SettingsWindowController {

    private var window: NSWindow?
    private let controller: DictationController

    init(controller: DictationController) {
        self.controller = controller
    }

    func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 460),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Réglages de Goldodict"
            window.isReleasedWhenClosed = false
            window.center()
            window.contentView = NSHostingView(rootView: SettingsView(controller: controller))
            self.window = window
        }

        // Une application accessoire doit demander l'activation explicitement,
        // sinon sa fenêtre s'ouvre derrière celle du premier plan.
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
