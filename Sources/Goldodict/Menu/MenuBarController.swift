import AppKit
import GoldodictCore
import SwiftUI

/// Icône de la barre des menus et panneau qu'elle déroule.
///
/// `MenuBarExtra` en style `.menu` ne sait afficher qu'un `NSMenu` : ni témoin
/// coloré, ni bandeau d'alerte, ni sélecteur segmenté. Or l'information la plus
/// utile de ce menu est précisément une alerte — l'Accessibilité refusée, seul cas
/// où l'application échoue en silence. Le panneau est donc un `NSPopover` porté par
/// un `NSStatusItem`, où SwiftUI dessine ce qu'il veut.
@MainActor
final class MenuBarController {

    private let controller: DictationController
    private let openSettingsAction: () -> Void

    private let statusItem: NSStatusItem
    private let popover = NSPopover()

    /// Application au premier plan avant que le clic ne donne le focus à Goldodict.
    /// C'est elle que vise la dictée lancée depuis le menu.
    private var previousApplication: NSRunningApplication?

    init(controller: DictationController, openSettings: @escaping () -> Void) {
        self.controller = controller
        self.openSettingsAction = openSettings
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        configureStatusItem()
        configurePopover()

        controller.onStateChange = { [weak self] state in
            self?.reflect(state)
        }
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.image = StatusIcon.idle
        button.imagePosition = .imageOnly
        button.toolTip = "Goldodict — dictée"
        button.target = self
        button.action = #selector(togglePopover)
    }

    private func configurePopover() {
        let hosting = NSHostingController(
            rootView: MenuPanel(controller: controller, host: self)
        )
        // La hauteur suit le contenu : l'historique grandit au fil des dictées et un
        // panneau de taille fixe finirait par le tronquer ou flotter à moitié vide.
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting
        popover.behavior = .transient
        popover.animates = false
    }

    /// Reflète l'état dans l'icône : la bouche s'ouvre pendant la dictée, le rouge
    /// signale l'enregistrement, l'orange l'échec.
    private func reflect(_ state: DictationState) {
        guard let button = statusItem.button else { return }
        button.image = state.isRecording ? StatusIcon.recording : StatusIcon.idle
        switch state {
        case .recording: button.contentTintColor = .systemRed
        case .failed: button.contentTintColor = .systemOrange
        default: button.contentTintColor = nil
        }
    }

    // MARK: - Ouverture

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        guard let button = statusItem.button else { return }

        // Relevé avant l'activation, sans quoi l'application « précédente » serait
        // Goldodict lui-même.
        previousApplication = NSWorkspace.shared.frontmostApplication

        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        popover.performClose(nil)
    }

    /// Profil qui s'appliquerait à une dictée lancée maintenant depuis le menu, déduit
    /// de l'application relevée avant l'ouverture du panneau — la même que `dictate()`
    /// vise. Lu par `MenuPanel` à chaque apparition, `previousApplication` n'étant connu
    /// qu'à ce moment-là.
    var anticipatedProfile: (name: String, application: String?) {
        let profile = controller.profileStore.profiles.profile(for: previousApplication?.bundleIdentifier)
        return (profile.name, previousApplication?.localizedName)
    }

    // MARK: - Actions du panneau

    /// Le panneau se ferme avant que la dictée ne démarre : il masquerait la fenêtre
    /// visée et retiendrait le focus que le collage doit lui rendre.
    func dictate() {
        let target = previousApplication
        close()
        controller.toggleFromMenu(returningTo: target)
    }

    func openSettings() {
        close()
        openSettingsAction()
    }

    func openAccessibilitySettings() {
        close()
        PermissionGuard.openSettings(for: .accessibility)
    }

    func openMicrophoneSettings() {
        close()
        PermissionGuard.openSettings(for: .microphone)
    }

    func openInputMonitoringSettings() {
        close()
        PermissionGuard.openSettings(for: .inputMonitoring)
    }

    func quit() {
        NSApplication.shared.terminate(nil)
    }
}
