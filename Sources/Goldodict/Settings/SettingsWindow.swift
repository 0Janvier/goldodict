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

    /// Nom sous lequel macOS retient la taille et la position choisies.
    private static let frameName = "fr.sztulman.goldodict.settings"

    func show() {
        if window == nil {
            // Redimensionnable : la fenêtre contient désormais des listes de longueur
            // arbitraire, l'historique, le lexique, les profils. Les figer à 760 sur
            // 560 revenait à décider pour l'utilisateur combien de lignes il a le
            // droit de voir d'un coup.
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Réglages de Goldodict"
            window.isReleasedWhenClosed = false
            // La taille choisie est retenue d'une session à l'autre. Le centrage ne
            // vaut que la première fois, faute de quoi il défferait ce réglage.
            if !window.setFrameUsingName(Self.frameName) {
                window.center()
            }
            window.setFrameAutosaveName(Self.frameName)
            window.contentView = NSHostingView(rootView: SettingsView(controller: controller))
            self.window = window
        }

        // Une application accessoire doit demander l'activation explicitement,
        // sinon sa fenêtre s'ouvre derrière celle du premier plan.
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
