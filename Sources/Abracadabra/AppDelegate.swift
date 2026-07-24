import AppKit

/// Point d'accroche du cycle de vie AppKit.
///
/// Le contrôleur est porté ici plutôt que dans un `@State` de la scène SwiftUI :
/// `MenuBarExtra` ne construit son contenu qu'à la première ouverture du menu, or
/// le raccourci global doit être armé dès le lancement, sans quoi la dictée
/// resterait inerte tant que l'utilisateur n'aurait pas cliqué sur l'icône.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    let controller = DictationController()
    private(set) lazy var settingsWindow = SettingsWindowController(controller: controller)

    private static let firstRunKey = "didPresentSettings"

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.lifecycle.notice("applicationDidFinishLaunching")
        controller.activate()

        // Sur une barre de menus chargée, macOS relègue l'icône derrière le chevron
        // et l'utilisateur n'a alors aucun moyen d'atteindre les réglages. On les
        // présente donc une fois, au tout premier lancement.
        if !UserDefaults.standard.bool(forKey: Self.firstRunKey) {
            UserDefaults.standard.set(true, forKey: Self.firstRunKey)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.settingsWindow.show()
            }
        }
    }

    func openSettings() {
        settingsWindow.show()
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.deactivate()
    }
}
