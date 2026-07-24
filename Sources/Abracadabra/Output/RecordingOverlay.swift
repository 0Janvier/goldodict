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

    static let panelWidth: CGFloat = 420

    private var panel: NSPanel?
    private let model = OverlayModel()

    func show(state: DictationState) {
        model.state = state

        if panel == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: Self.panelWidth, height: 66),
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

            // `contentViewController` fait suivre la fenêtre à la taille intrinsèque
            // de la vue, ce que `contentView` ne fait pas. L'origine restant fixe et
            // AppKit comptant depuis le bas, la pastille s'étend vers le haut quand
            // le texte s'allonge, au lieu de déborder sous l'écran.
            panel.contentViewController = NSHostingController(rootView: OverlayView(model: model))
            self.panel = panel
        }

        reposition()
        panel?.orderFrontRegardless()
    }

    func update(state: DictationState) {
        model.state = state
    }

    /// Texte provisoire affiché pendant la dictée.
    ///
    /// Les résultats volatils arrivent plusieurs fois par seconde ; redessiner à
    /// chaque fois ferait travailler le thread principal pour rien, alors que l'œil
    /// ne distingue pas mieux au-delà de dix rafraîchissements par seconde.
    func update(partialText: String) {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastTextUpdate >= 0.1 || partialText.isEmpty else {
            pendingText = partialText
            return
        }
        lastTextUpdate = now
        pendingText = nil
        model.partialText = partialText
    }

    private var lastTextUpdate: TimeInterval = 0
    private var pendingText: String?

    /// Force l'affichage du dernier texte reçu, sans attendre la fenêtre de
    /// rafraîchissement : appelé à la fin de la dictée pour ne rien perdre.
    func flushPartialText() {
        if let pendingText {
            model.partialText = pendingText
            self.pendingText = nil
        }
    }

    func hide() {
        panel?.orderOut(nil)
        model.partialText = ""
        pendingText = nil
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
    var partialText: String = ""
}

private struct OverlayView: View {
    let model: OverlayModel

    /// Au-delà, seule la fin est montrée : c'est le mot en cours qui intéresse
    /// celui qui parle, pas le début de sa phrase.
    private static let visibleCharacters = 220

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
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

            if !visibleText.isEmpty {
                Text(visibleText)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.disabled)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(width: RecordingOverlay.panelWidth, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(tint.opacity(0.35), lineWidth: 1)
        )
        .animation(.easeOut(duration: 0.12), value: model.partialText.isEmpty)
    }

    private var visibleText: String {
        let text = model.partialText
        guard text.count > Self.visibleCharacters else { return text }
        return "…" + String(text.suffix(Self.visibleCharacters))
    }

    private var isRecording: Bool {
        if case .recording = model.state { return true }
        return false
    }

    private var tint: Color {
        switch model.state {
        case .recording: return .red
        case .transcribing, .correcting, .injecting: return .accentColor
        case .notice: return .blue
        case .failed: return .orange
        case .idle: return .secondary
        }
    }

    private var title: String {
        switch model.state {
        case .recording: return "Dictée en cours"
        case .transcribing: return "Transcription"
        case .correcting: return "Correction"
        case .injecting: return "Insertion"
        case .notice: return "Texte inséré"
        case .failed: return "Erreur"
        case .idle: return "Prêt"
        }
    }

    private var subtitle: String {
        switch model.state {
        case .recording(.pushToTalk): return "Relâchez pour insérer le texte"
        case .recording(.toggle): return "Appuyez de nouveau pour terminer"
        case .transcribing: return "Traitement local en cours"
        case .correcting: return "Relecture par le modèle local"
        case .injecting: return "Collage dans l'application active"
        case .notice(let message): return message
        case .failed(let message): return message
        case .idle: return ""
        }
    }
}
