import AppKit
import GoldodictCore
import SwiftUI
import UniformTypeIdentifiers

/// Icône de la barre des menus et panneau qu'elle déroule.
///
/// `MenuBarExtra` en style `.menu` ne sait afficher qu'un `NSMenu` : ni témoin
/// coloré, ni bandeau d'alerte, ni sélecteur segmenté. Or l'information la plus
/// utile de ce menu est précisément une alerte — l'Accessibilité refusée, seul cas
/// où l'application échoue en silence. Le panneau est donc un `NSPopover` porté par
/// un `NSStatusItem`, où SwiftUI dessine ce qu'il veut.
///
/// L'icône elle-même passe par `StatusItemDropView` plutôt que par
/// `NSStatusItem.button` : le glisser-déposer d'un fichier audio exige des méthodes
/// de `NSDraggingDestination` réellement surchargées sur la vue, ce qu'AppKit ne
/// permet pas sur le bouton fourni par le système.
@MainActor
final class MenuBarController {

    private let controller: DictationController
    private let openSettingsAction: () -> Void
    private let importAudioAction: (URL, NSRunningApplication?) -> Void
    private let openArchitectAction: () -> Void

    private let statusItem: NSStatusItem
    private let dropView: StatusItemDropView
    private let popover = NSPopover()

    /// Application au premier plan avant que le clic ou le dépôt ne donne le focus à
    /// Goldodict. C'est elle que vise la dictée ou l'import lancés depuis le menu.
    private var previousApplication: NSRunningApplication?

    init(
        controller: DictationController,
        openSettings: @escaping () -> Void,
        importAudio: @escaping (URL, NSRunningApplication?) -> Void,
        openArchitect: @escaping () -> Void
    ) {
        self.controller = controller
        self.openSettingsAction = openSettings
        self.importAudioAction = importAudio
        self.openArchitectAction = openArchitect
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.dropView = StatusItemDropView(
            frame: NSRect(x: 0, y: 0, width: NSStatusItem.squareLength, height: NSStatusBar.system.thickness)
        )

        configureStatusItem()
        configurePopover()

        controller.onStateChange = { [weak self] state in
            self?.reflect(state)
        }
    }

    private func configureStatusItem() {
        dropView.image = StatusIcon.idle
        dropView.toolTip = "Goldodict — dictée"
        dropView.onClick = { [weak self] in self?.togglePopover() }
        dropView.onDropAudioFile = { [weak self] url in self?.handleDroppedFile(at: url) }
        statusItem.view = dropView
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
        dropView.image = state.isRecording ? StatusIcon.recording : StatusIcon.idle
        switch state {
        case .recording: dropView.contentTintColor = .systemRed
        case .failed: dropView.contentTintColor = .systemOrange
        default: dropView.contentTintColor = nil
        }
    }

    // MARK: - Ouverture

    private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
            return
        }

        // Relevé avant l'activation, sans quoi l'application « précédente » serait
        // Goldodict lui-même.
        previousApplication = NSWorkspace.shared.frontmostApplication

        popover.show(relativeTo: dropView.bounds, of: dropView, preferredEdge: .maxY)
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

    /// Ouvre un sélecteur de fichier et lance l'import sur celui choisi.
    ///
    /// Refusé pendant une dictée en cours : le moteur de transcription ne tient
    /// qu'une session à la fois, live ou importée.
    /// Ouvre la fenêtre du mode document. La garde d'occupation vit dans le
    /// contrôleur, qui refuse d'assembler une session si quelque chose tourne.
    func openArchitect() {
        guard !controller.isOccupied else { return }
        close()
        openArchitectAction()
    }

    func importAudioFile() {
        guard !controller.state.isBusy else { return }
        let target = previousApplication
        close()

        let panel = NSOpenPanel()
        panel.message = "Choisissez un fichier audio à transcrire."
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importAudioAction(url, target)
    }

    /// Un fichier déposé sur l'icône ne passe pas par l'ouverture du panneau : c'est
    /// donc ici, et non dans `togglePopover()`, que l'application précédente doit
    /// être relevée.
    private func handleDroppedFile(at url: URL) {
        guard !controller.state.isBusy else { return }
        importAudioAction(url, NSWorkspace.shared.frontmostApplication)
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

/// Vue de l'icône de la barre des menus, en remplacement de `NSStatusItem.button`.
///
/// `NSStatusItem.view` est dépréciée depuis macOS 10.14 mais reste la seule façon
/// d'obtenir une vue dont on surcharge réellement `draggingEntered`/
/// `performDragOperation` : le bouton fourni par le système ne peut pas être
/// sous-classé, AppKit en crée lui-même l'instance.
private final class StatusItemDropView: NSView {

    var onClick: (() -> Void)?
    var onDropAudioFile: ((URL) -> Void)?

    private let imageView = NSImageView()

    var image: NSImage? {
        get { imageView.image }
        set { imageView.image = newValue }
    }

    var contentTintColor: NSColor? {
        get { imageView.contentTintColor }
        set { imageView.contentTintColor = newValue }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        imageView.imageScaling = .scaleProportionallyDown
        imageView.frame = bounds
        imageView.autoresizingMask = [.width, .height]
        addSubview(imageView)
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("non prévu") }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        audioFileURL(from: sender) != nil ? .copy : []
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard let url = audioFileURL(from: sender) else { return false }
        onDropAudioFile?(url)
        return true
    }

    /// N'accepte qu'un seul fichier, et seulement s'il s'agit bien d'audio : une image
    /// ou un PDF déposé par erreur sur l'icône ne doit rien déclencher.
    private func audioFileURL(from info: any NSDraggingInfo) -> URL? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: [UTType.audio.identifier],
        ]
        guard let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL],
              urls.count == 1 else { return nil }
        return urls.first
    }
}
