import AppKit
import Observation
import SwiftUI

/// Fenêtre flottante de relecture avant collage.
///
/// La dictée transcrite s'y affiche, corrigeable à la volée. Entrée valide et
/// colle dans l'application d'origine ; Maj-Entrée insère un retour à la ligne ;
/// ⌘C copie le texte et referme — sans quoi le collage manuel laisserait l'état
/// `reviewing` occupé et bloquerait la dictée suivante ; Échap ou la fermeture
/// annulent sans coller. Toute retouche nourrit le même moteur d'apprentissage
/// que la fenêtre de reprise.
@MainActor
final class QuickReviewWindowController: NSObject, NSWindowDelegate {

    private var panel: NSPanel?
    private let controller: DictationController
    private let model = QuickReviewModel()
    private var keyMonitor: Any?

    /// La demande en cours, consommée à la première issue (validation, annulation
    /// ou fermeture) : la fermeture qui suit une validation ne ré-annule rien.
    private var pending: DictationController.ReviewRequest?

    init(controller: DictationController) {
        self.controller = controller
    }

    func present(_ request: DictationController.ReviewRequest) {
        // Une relecture encore ouverte est annulée par la nouvelle : la dictée
        // la plus récente a toujours raison.
        if let stale = pending {
            controller.cancelReview(stale)
        }
        pending = request
        model.prepare(request.text, applicationName: request.applicationName)
        show()
    }

    private func show() {
        if panel == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 680, height: 380),
                styleMask: [.titled, .closable, .utilityWindow, .resizable],
                backing: .buffered,
                defer: false
            )
            panel.title = "Relecture"
            panel.titleVisibility = .hidden
            panel.titlebarAppearsTransparent = true
            panel.backgroundColor = .washiPaper
            panel.isOpaque = true
            panel.level = .floating
            panel.hidesOnDeactivate = true
            panel.isReleasedWhenClosed = false
            panel.minSize = NSSize(width: 560, height: 260)
            panel.setFrameAutosaveName("QuickReviewPanel")
            panel.delegate = self
            panel.contentView = NSHostingView(
                rootView: QuickReviewView(
                    model: model,
                    confirm: { [weak self] in self?.confirm() },
                    cancel: { [weak self] in self?.cancelAndClose() },
                    copy: { [weak self] in self?.copyAndDismiss() }
                )
            )
            if panel.frame.origin == .zero { panel.center() }
            self.panel = panel
        }
        startKeyMonitor()
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
    }

    private func confirm() {
        guard let request = pending else { return }
        pending = nil
        dismissPanel()
        controller.completeReview(request, edited: model.text)
    }

    /// ⌘C : le texte retouché va dans le presse-papiers, la fenêtre se referme,
    /// l'application d'origine reprend le premier plan pour le ⌘V qui suit.
    private func copyAndDismiss() {
        guard let request = pending else { return }
        pending = nil
        let text = model.text
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        dismissPanel()
        controller.finishReviewByCopy(request, edited: text)
    }

    private func cancelAndClose() {
        panel?.performClose(nil)
    }

    /// `close()` plutôt qu'`orderOut` : un panneau flottant ordonné hors écran
    /// reste souvent la fenêtre clé, visible, et garde l'application occupée.
    private func dismissPanel() {
        stopKeyMonitor()
        panel?.close()
    }

    func windowWillClose(_ notification: Notification) {
        stopKeyMonitor()
        if let request = pending {
            pending = nil
            controller.cancelReview(request)
        }
    }

    // MARK: - Clavier

    /// Le `TextEditor` avale Entrée et ⌘C avant que `.onKeyPress` les voie.
    /// Le moniteur local les prend en amont, uniquement tant que le panneau a le focus.
    private func startKeyMonitor() {
        stopKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKey(event) ?? event
        }
    }

    private func stopKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private func handleKey(_ event: NSEvent) -> NSEvent? {
        guard panel?.isKeyWindow == true, pending != nil else { return event }

        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])

        if modifiers == .command {
            switch event.keyCode {
            case 8: // C
                copyAndDismiss()
                return nil
            case 9: // V — le texte vient d'être copié : coller dans l'app d'origine.
                if NSPasteboard.general.string(forType: .string) == model.text {
                    confirm()
                    return nil
                }
            default:
                break
            }
        }

        if modifiers.contains(.shift) == false {
            switch event.keyCode {
            case 36, 76: // Entrée, Entrée pavé
                confirm()
                return nil
            case 53: // Échap
                cancelAndClose()
                return nil
            default:
                break
            }
        }

        return event
    }
}

@Observable @MainActor
final class QuickReviewModel {
    var text = ""
    private(set) var applicationName: String?

    func prepare(_ text: String, applicationName: String?) {
        self.text = text
        self.applicationName = applicationName
    }
}

struct QuickReviewView: View {

    @Bindable var model: QuickReviewModel
    let confirm: () -> Void
    let cancel: () -> Void
    let copy: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var editorFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            Washi.vermillion
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 16) {
                header
                editor
                footer
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 16)
        }
        .background(Washi.paper(colorScheme))
        .frame(minWidth: 560, minHeight: 260)
        .onAppear { editorFocused = true }
        .onCopyCommand {
            copy()
            return []
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("Relecture")
                .font(.system(size: 22, design: .serif))
                .foregroundStyle(Washi.ink(colorScheme))
            Spacer(minLength: 8)
            if let name = model.applicationName {
                Text("dans \(name)")
                    .font(.system(size: 13, design: .serif))
                    .foregroundStyle(Washi.mist(colorScheme))
                    .lineLimit(1)
            }
        }
    }

    private var editor: some View {
        TextEditor(text: $model.text)
            .font(.system(size: 18, design: .serif))
            .foregroundStyle(Washi.ink(colorScheme))
            .scrollContentBackground(.hidden)
            .background(Washi.paper(colorScheme))
            .padding(.horizontal, 2)
            .focused($editorFocused)
            .tint(Washi.vermillion)
            .onKeyPress { press in
                if press.modifiers.contains(.command), press.characters == "c" {
                    copy()
                    return .handled
                }
                switch press.key {
                case .return where !press.modifiers.contains(.shift):
                    confirm()
                    return .handled
                case .escape:
                    cancel()
                    return .handled
                default:
                    return .ignored
                }
            }
    }

    private var footer: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("⌘C copier · Entrée coller · Maj-Entrée ligne · Échap annuler")
                .font(.system(size: 11, design: .serif))
                .foregroundStyle(Washi.mist(colorScheme))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button("Coller") { confirm() }
                .buttonStyle(.borderedProminent)
                .tint(Washi.vermillion)
                .controlSize(.large)
        }
    }
}

/// Papier washi, encre sumi, vermillon. Un seul accent, deux modes dessinés
/// séparément plutôt qu'un invert.
private enum Washi {
    static let vermillion = Color(red: 0.710, green: 0.290, blue: 0.235)

    static func paper(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.118, green: 0.106, blue: 0.090)
            : Color(red: 0.965, green: 0.945, blue: 0.910)
    }

    static func ink(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.910, green: 0.878, blue: 0.831)
            : Color(red: 0.102, green: 0.098, blue: 0.086)
    }

    static func mist(_ scheme: ColorScheme) -> Color {
        ink(scheme).opacity(0.55)
    }
}

private extension NSColor {
    static let washiPaper = NSColor(name: "WashiPaper") { appearance in
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if dark {
            return NSColor(srgbRed: 0.118, green: 0.106, blue: 0.090, alpha: 1)
        }
        return NSColor(srgbRed: 0.965, green: 0.945, blue: 0.910, alpha: 1)
    }
}

#if DEBUG
#Preview("Relecture") {
    let model = QuickReviewModel()
    model.prepare(
        "Le tribunal administratif de Toulouse est compétent pour connaître de ce recours.",
        applicationName: "Pages"
    )
    return QuickReviewView(
        model: model,
        confirm: {},
        cancel: {},
        copy: {}
    )
    .frame(width: 680, height: 380)
}
#endif
