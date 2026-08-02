import AppKit
import GoldodictCore
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

    /// Le panneau est plus large que la capsule qu'il porte, et transparent autour.
    ///
    /// La capsule prend la largeur de son contenu, qui change avec l'état. Redimensionner
    /// la fenêtre à chaque changement obligerait à la repositionner dans le même geste,
    /// et le décalage se verrait. Une fenêtre fixe où la capsule est centrée coûte
    /// quelques pixels transparents, qui n'interceptent ni la souris ni le regard.
    /// Assez large pour « What we've got here is failure to communicate.  —  Cool
    /// Hand Luke » sans troncature, assez haut pour la variante à deux lignes.
    static let panelWidth: CGFloat = 720
    static let panelHeight: CGFloat = 80

    /// Niveau sonore instantané, fourni par la capture. Sans lui, les barres restent
    /// à plat : ce n'est pas une décoration mais la seule preuve que le micro entend.
    var levelProvider: () -> Float = { 0 }

    /// Réplique de la dictée en cours, déjà mise en forme.
    ///
    /// Elle est tirée une fois par dictée et poussée ici, jamais calculée à
    /// l'affichage : la pastille se redessine vingt fois par seconde, et un tirage
    /// dans une propriété calculée changerait de film à chaque image.
    var quote: String? {
        didSet { model.quote = quote }
    }

    private var panel: NSPanel?
    private let model = OverlayModel()
    private var ticker: Task<Void, Never>?

    func show(state: DictationState) {
        model.state = state

        if panel == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: Self.panelWidth, height: Self.panelHeight),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.isFloatingPanel = true
            panel.level = .statusBar
            panel.backgroundColor = .clear
            panel.isOpaque = false
            // L'ombre est portée par la capsule, pas par la fenêtre : celle-ci déborde
            // largement de la capsule et son ombre dessinerait un rectangle dans le vide.
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel.hidesOnDeactivate = false
            panel.contentViewController = NSHostingController(rootView: OverlayView(model: model))
            self.panel = panel
        }

        reposition()
        panel?.orderFrontRegardless()
        if state.isRecording { startTicking() } else { stopTicking() }
    }

    func update(state: DictationState) {
        model.state = state
        if state.isRecording { startTicking() } else { stopTicking() }
    }

    func hide() {
        stopTicking()
        panel?.orderOut(nil)
        model.reset()
    }

    // MARK: - Cadence

    /// Relève le niveau et l'écoulement du temps vingt fois par seconde.
    ///
    /// Cadence réglée pour l'œil, pas pour l'oreille : en deçà les barres sautent,
    /// au-delà le thread principal travaille sans que rien de plus ne se voie.
    private func startTicking() {
        guard ticker == nil else { return }
        model.beginRecording()

        ticker = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.model.tick(level: self.levelProvider())
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    private func stopTicking() {
        ticker?.cancel()
        ticker = nil
    }

    /// Bas de l'écran actif, au centre : hors du champ de saisie, toujours vu.
    private func reposition() {
        guard let panel else { return }
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
            ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        panel.setFrame(
            NSRect(
                x: visible.midX - Self.panelWidth / 2,
                y: visible.minY + 80,
                width: Self.panelWidth,
                height: Self.panelHeight
            ),
            display: false
        )
    }
}

@Observable
@MainActor
private final class OverlayModel {

    /// Nombre de barres. Sept relevés à cinquante millisecondes couvrent un tiers de
    /// seconde : assez pour voir passer une syllabe, assez peu pour que la capsule
    /// reste une capsule.
    static let barCount = 7

    var state: DictationState = .idle
    var quote: String?
    private(set) var bars: [Float] = Array(repeating: 0, count: OverlayModel.barCount)
    private(set) var elapsed: TimeInterval = 0
    private(set) var isSilent = false

    private var startedAt: TimeInterval = 0
    private var smoothed: Float = 0
    private var watch = SilenceWatch()

    func beginRecording() {
        let now = ProcessInfo.processInfo.systemUptime
        startedAt = now
        elapsed = 0
        smoothed = 0
        isSilent = false
        watch.begin(at: now)
        bars = Array(repeating: 0, count: Self.barCount)
    }

    /// Fait avancer le vumètre d'un cran et rend compte du silence prolongé.
    func tick(level: Float) {
        let now = ProcessInfo.processInfo.systemUptime
        elapsed = now - startedAt

        smoothed = AudioLevel.smoothed(previous: smoothed, target: AudioLevel.normalized(rms: level))
        bars.removeFirst()
        bars.append(smoothed)

        watch.absorb(level: smoothed, at: now)
        isSilent = watch.isSilent
    }

    func reset() {
        bars = Array(repeating: 0, count: Self.barCount)
        elapsed = 0
        smoothed = 0
        isSilent = false
    }
}

private struct OverlayView: View {
    let model: OverlayModel

    var body: some View {
        HStack(spacing: 10) {
            indicator

            if model.state.isRecording {
                VuMeter(bars: model.bars, tint: tint)
            }

            titleView

            if model.state.isRecording {
                Text(Self.clock(model.elapsed))
                    .font(.system(size: 13))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .fixedSize()
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(tint.opacity(0.30), lineWidth: 1))
        .shadow(color: .black.opacity(0.22), radius: 12, y: 4)
        .frame(width: RecordingOverlay.panelWidth, height: RecordingOverlay.panelHeight)
        .animation(.easeOut(duration: 0.14), value: title)
    }

    @ViewBuilder
    private var indicator: some View {
        switch model.state {
        case .recording:
            Circle()
                .fill(tint)
                .frame(width: 9, height: 9)
                .opacity(model.isSilent ? 1 : 0.55 + Double(model.bars.last ?? 0) * 0.45)
        case .transcribing, .correcting, .injecting:
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.7)
                .frame(width: 12, height: 12)
        case .inserted(let insertion):
            Image(systemName: insertion.note == nil ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
        case .idle:
            EmptyView()
        }
    }

    /// Le titre du format « réplique, film et année » tient sur deux lignes, séparées
    /// par un saut de ligne. La seconde passe en secondaire : c'est la réplique qu'on
    /// lit, sa provenance n'est qu'une mention.
    @ViewBuilder
    private var titleView: some View {
        let lines = title.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true)
        VStack(alignment: .leading, spacing: 1) {
            Text(lines.first.map(String.init) ?? title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
            if lines.count > 1 {
                Text(String(lines[1]))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .truncationMode(.tail)
    }

    /// Le silence prolongé prend la place du libellé courant : c'est la seule chose
    /// que l'utilisateur ait besoin de lire à cet instant. La réplique, elle, ne
    /// s'affiche que pendant l'enregistrement — les états suivants rendent compte
    /// d'un travail en cours et doivent rester factuels.
    private var title: String {
        if model.state.isRecording, model.isSilent { return "Rien n'est capté" }
        if model.state.isRecording, let quote = model.quote, !quote.isEmpty { return quote }
        if case .inserted(let insertion) = model.state, insertion.note == nil {
            return "\(insertion.summary) inséré"
        }
        return model.state.pillTitle
    }

    private var tint: Color {
        if model.state.isRecording { return model.isSilent ? .orange : .red }
        switch model.state {
        case .transcribing, .correcting, .injecting: return .accentColor
        case .inserted(let insertion): return insertion.note == nil ? .green : .orange
        case .failed: return .orange
        default: return .secondary
        }
    }

    /// « 0:14 », « 1:07 ». Les dictées dépassant l'heure n'existent pas.
    private static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Barres du niveau sonore, la plus récente à droite.
private struct VuMeter: View {
    let bars: [Float]
    let tint: Color

    var body: some View {
        HStack(alignment: .center, spacing: 2.5) {
            ForEach(Array(bars.enumerated()), id: \.offset) { _, value in
                Capsule()
                    .fill(tint.opacity(0.35 + Double(value) * 0.65))
                    // Une barre nulle reste visible : le vumètre doit se distinguer
                    // d'une capsule vide, sans quoi le silence ressemblerait à une
                    // panne d'affichage.
                    .frame(width: 3, height: 4 + CGFloat(value) * 16)
            }
        }
        .frame(height: 20)
        .animation(.linear(duration: 0.05), value: bars)
    }
}
