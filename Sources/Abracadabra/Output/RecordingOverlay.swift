import AbracadabraCore
import AppKit
import SwiftUI

/// Pastille flottante affichée pendant la dictée.
///
/// L'icône de la barre des menus ne suffit pas : sur un écran large, la barre est
/// saturée et macOS relègue les icônes surnuméraires derrière un chevron, où elles
/// deviennent invisibles. Sans retour perceptible, l'utilisateur ne sait pas si sa
/// dictée est en cours et appuie de nouveau sur le raccourci, ce qui l'interrompt.
///
/// Le panneau est `nonactivatingPanel` et ignore la souris : il ne prend jamais le
/// focus, sans quoi le collage automatique atterrirait dans la mauvaise application.
@MainActor
final class RecordingOverlay {

    private var panel: NSPanel?
    private let model = OverlayModel()

    func show(state: DictationState) {
        model.state = state

        if panel == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 300, height: 66),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.isFloatingPanel = true
            panel.level = .statusBar
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = true
            panel.ignoresMouseEvents = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel.hidesOnDeactivate = false
            panel.contentView = NSHostingView(rootView: OverlayView(model: model))
            self.panel = panel
        }

        reposition()
        panel?.orderFrontRegardless()
    }

    func update(state: DictationState) {
        model.state = state
    }

    func hide() {
        panel?.orderOut(nil)
    }

    /// Bas de l'écran actif, au centre : hors du champ de saisie, toujours vu.
    private func reposition() {
        guard let panel else { return }
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
            ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.minY + 80
        ))
    }
}

@Observable
@MainActor
private final class OverlayModel {
    var state: DictationState = .idle
}

private struct OverlayView: View {
    let model: OverlayModel

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: model.state.symbolName)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(tint)
                .symbolEffect(.pulse, isActive: isRecording)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .frame(width: 300, height: 66, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(tint.opacity(0.35), lineWidth: 1)
        )
    }

    private var isRecording: Bool {
        if case .recording = model.state { return true }
        return false
    }

    private var tint: Color {
        switch model.state {
        case .recording: return .red
        case .transcribing, .injecting: return .accentColor
        case .failed: return .orange
        case .idle: return .secondary
        }
    }

    private var title: String {
        switch model.state {
        case .recording: return "Dictée en cours"
        case .transcribing: return "Transcription"
        case .injecting: return "Insertion"
        case .failed: return "Erreur"
        case .idle: return "Prêt"
        }
    }

    private var subtitle: String {
        switch model.state {
        case .recording(.pushToTalk): return "Relâchez pour insérer le texte"
        case .recording(.toggle): return "Appuyez de nouveau pour terminer"
        case .transcribing: return "Traitement local en cours"
        case .injecting: return "Collage dans l'application active"
        case .failed(let message): return message
        case .idle: return ""
        }
    }
}
