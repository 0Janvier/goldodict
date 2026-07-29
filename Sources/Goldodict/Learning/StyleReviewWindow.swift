import AppKit
import Observation
import SwiftUI

/// Fenêtre de reprise d'une dictée : le texte inséré à gauche, un éditeur
/// pré-rempli à droite. Le geste d'y corriger EST le consentement — rien n'est
/// appliqué au pipeline à ce stade, seules des paires courtes sont comptées.
@MainActor
final class StyleReviewWindowController {

    private var window: NSWindow?
    private let controller: DictationController
    private let model = StyleReviewModel()

    init(controller: DictationController) {
        self.controller = controller
    }

    func review(_ dictation: DictationController.Dictation) {
        model.prepare(dictation)
        show()
    }

    private func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 640, height: 380),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Reprendre la dictée"
            window.isReleasedWhenClosed = false
            window.center()
            window.contentView = NSHostingView(
                rootView: StyleReviewView(model: model, controller: controller) { [weak window] in
                    window?.close()
                }
            )
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

@Observable @MainActor
final class StyleReviewModel {
    var original = ""
    var edited = ""
    var profileName = ""
    private(set) var savedPairCount: Int?

    func prepare(_ dictation: DictationController.Dictation) {
        original = dictation.text
        edited = dictation.text
        profileName = dictation.profileName
        savedPairCount = nil
    }

    func saved(_ count: Int) {
        savedPairCount = count
    }
}

struct StyleReviewView: View {

    @Bindable var model: StyleReviewModel
    let controller: DictationController
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("TEXTE INSÉRÉ")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                    ScrollView {
                        Text(model.original)
                            .font(.system(size: 12))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.4)))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("VOTRE VERSION")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                    TextEditor(text: $model.edited)
                        .font(.system(size: 12))
                        .padding(4)
                        .background(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                }
            }

            HStack {
                if let count = model.savedPairCount {
                    Text(count == 0
                         ? "Aucune correction courte relevée."
                         : "\(count) correction\(count > 1 ? "s" : "") relevée\(count > 1 ? "s" : "").")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Fermer") { dismiss() }
                Button("Enregistrer les corrections") {
                    let count = controller.submitStyleCorrection(
                        original: model.original,
                        corrected: model.edited,
                        profileName: model.profileName
                    )
                    model.saved(count)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.edited == model.original)
            }

            Text("Seules les substitutions courtes sont retenues, jamais le texte entier. Trois occurrences d'une même correction déclenchent une proposition.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .frame(minWidth: 560, minHeight: 320)
    }
}
