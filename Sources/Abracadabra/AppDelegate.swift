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

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller.activate()
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.deactivate()
    }
}
