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
    private lazy var architectWindow = ArchitectWindowController(controller: controller)
    private lazy var styleReviewWindow = StyleReviewWindowController(controller: controller)
    private lazy var quickReviewWindow = QuickReviewWindowController(controller: controller)
    private var menuBar: MenuBarController?
    private var speechWatchdog: SpeechServiceWatchdog?

    private static let firstRunKey = "didPresentOnboarding"

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.lifecycle.notice("applicationDidFinishLaunching")

        menuBar = MenuBarController(
            controller: controller,
            openSettings: { [weak self] in self?.settingsWindow.show() },
            importAudio: { [weak self] url, application in
                self?.importWindow.transcribe(fileAt: url, returningTo: application)
            },
            openArchitect: { [weak self] in self?.architectWindow.open() },
            reviewDictation: { [weak self] dictation in self?.styleReviewWindow.review(dictation) }
        )

        controller.presentReview = { [weak self] request in
            self?.quickReviewWindow.present(request)
        }

        controller.activate()

        speechWatchdog = SpeechServiceWatchdog(controller: controller) { [weak self] in
            self?.relaunchForSpeechRecovery()
        }
        speechWatchdog?.start()

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

    /// Se relance pour obtenir un processus neuf, seul remède à la connexion
    /// Speech morte. `open` est lancé en sous-processus détaché AVANT la sortie :
    /// une fois `exit(0)` prononcé, plus rien ne tourne ici, et la seconde de
    /// délai laisse au processus le temps de disparaître pour qu'`open` démarre
    /// une instance vraiment neuve.
    private func relaunchForSpeechRecovery() {
        let path = Bundle.main.bundlePath
        // En exécution hors bundle (swift run), il n'y a rien à relancer.
        guard path.hasSuffix(".app") else {
            Log.lifecycle.error("relance ignorée : exécution hors bundle (\(path, privacy: .public))")
            return
        }

        controller.prepareRelaunchHandoff()
        controller.deactivate()
        speechWatchdog?.stop()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 1; /usr/bin/open -g \"\(path)\""]
        do {
            try process.run()
        } catch {
            Log.lifecycle.error("relance impossible : \(error.localizedDescription, privacy: .public)")
            return
        }
        exit(0)
    }
}
