import AppKit

/// Point d'accroche du cycle de vie AppKit.
///
/// Tout est porté ici plutôt que dans une scène SwiftUI : le raccourci global doit
/// être armé dès le lancement, et l'icône de la barre des menus est un
/// `NSStatusItem`, hors du monde des scènes.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    let controller = DictationController()
    private(set) lazy var settingsWindow = SettingsWindowController(controller: controller)
    private lazy var onboardingWindow = OnboardingWindowController(controller: controller)
    private lazy var importWindow = AudioImportWindowController(controller: controller)
    private var menuBar: MenuBarController?

    private static let firstRunKey = "didPresentOnboarding"

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.lifecycle.notice("applicationDidFinishLaunching")

        menuBar = MenuBarController(
            controller: controller,
            openSettings: { [weak self] in self?.settingsWindow.show() },
            importAudio: { [weak self] url, application in
                self?.importWindow.transcribe(fileAt: url, returningTo: application)
            }
        )

        controller.activate()

        // Au premier lancement, les deux autorisations manquent et l'icône de la
        // barre des menus peut être reléguée derrière le chevron : sans cette
        // fenêtre, l'utilisateur n'aurait ni la dictée, ni le moyen de comprendre
        // pourquoi.
        if !UserDefaults.standard.bool(forKey: Self.firstRunKey) {
            UserDefaults.standard.set(true, forKey: Self.firstRunKey)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.onboardingWindow.show()
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
