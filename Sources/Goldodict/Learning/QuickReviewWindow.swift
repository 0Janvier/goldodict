import AppKit
import Observation
import SwiftUI

/// Petite fenêtre flottante de relecture avant collage.
///
/// La dictée transcrite s'y affiche, corrigeable à la volée. Entrée valide et
/// colle dans l'application d'origine ; Maj-Entrée insère un retour à la ligne ;
/// Échap ou la fermeture annulent sans coller. Toute retouche nourrit le même
/// moteur d'apprentissage que la fenêtre de reprise.
@MainActor
final class QuickReviewWindowController: NSObject, NSWindowDelegate {

    private var panel: NSPanel?
    private let controller: DictationController
    private let model = QuickReviewModel()

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
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 190),
                styleMask: [.titled, .closable, .utilityWindow, .resizable],
                backing: .buffered,
                defer: false
            )
            panel.title = "Relecture"
            panel.level = .floating
            panel.isReleasedWhenClosed = false
            panel.setFrameAutosaveName("QuickReviewPanel")
            panel.delegate = self
            panel.contentView = NSHostingView(
                rootView: QuickReviewView(
                    model: model,
                    confirm: { [weak self] in self?.confirm() },
                    cancel: { [weak self] in self?.cancelAndClose() }
                )
            )
            if panel.frame.origin == .zero { panel.center() }
            self.panel = panel
        }
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
    }

    private func confirm() {
        guard let request = pending else { return }
        pending = nil
        panel?.orderOut(nil)
        controller.completeReview(request, edited: model.text)
    }

    private func cancelAndClose() {
        panel?.performClose(nil)
    }

    func windowWillClose(_ notification: Notification) {
        if let request = pending {
            pending = nil
            controller.cancelReview(request)
        }
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

    @FocusState private var editorFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextEditor(text: $model.text)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .focused($editorFocused)
                .onKeyPress { press in
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

            HStack(spacing: 10) {
                if let name = model.applicationName {
                    Text("→ \(name)")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("⏎ coller · ⇧⏎ ligne · ⎋ annuler")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(10)
        .frame(minWidth: 380, minHeight: 140)
        .onAppear { editorFocused = true }
    }
}
