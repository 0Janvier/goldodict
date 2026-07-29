import AppKit
import GoldodictCore
import SwiftUI
import UniformTypeIdentifiers

/// Fenêtre du mode document : dicter longuement, voir le plan se construire,
/// exporter en Word. Sur le modèle de la fenêtre d'import — une `NSWindow` gérée
/// à la main, hors de toute scène SwiftUI.
@MainActor
final class ArchitectWindowController: NSObject, NSWindowDelegate {

    private var window: NSWindow?
    private let controller: DictationController
    private var session: ArchitectSession?

    init(controller: DictationController) {
        self.controller = controller
    }

    func open() {
        if session == nil {
            guard let session = controller.makeArchitectSession() else { return }
            self.session = session
        }
        show()
    }

    private func show() {
        guard let session else { return }
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 480),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Document dicté"
            window.isReleasedWhenClosed = false
            window.center()
            window.delegate = self
            self.window = window
        }
        window?.contentView = NSHostingView(rootView: ArchitectView(session: session))
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// La fermeture met fin à la session : le moteur et le micro sont rendus,
    /// le fichier de reprise est effacé.
    func windowWillClose(_ notification: Notification) {
        if let session {
            Task {
                await session.finish()
                session.tearDown()
            }
        }
        session = nil
        window?.contentView = nil
    }
}

struct ArchitectView: View {

    let session: ArchitectSession

    @State private var exportFailure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            outlineView
            Divider()
            footer
        }
        .padding(16)
        .frame(minWidth: 480, minHeight: 400)
    }

    private var header: some View {
        HStack(spacing: 12) {
            switch session.phase {
            case .idle:
                Label("Prêt à dicter", systemImage: "doc.text")
            case .recording:
                Label("Dictée en cours", systemImage: "mic.fill")
                    .foregroundStyle(.red)
                MenuLevelMeter(level: { session.level })
                    .frame(maxWidth: 120)
            case .paused:
                Label("En pause", systemImage: "pause.fill")
            case .finishing:
                Label("Transcription des derniers segments…", systemImage: "hourglass")
            case .finished:
                Label("Document prêt", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .failed(let reason):
                Label(reason, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }

            Spacer()

            if session.segmentCount > 0 || session.pendingCount > 0 {
                Text("\(session.segmentCount) segments\(session.pendingCount > 0 ? " · \(session.pendingCount) en attente" : "")")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    private var outlineView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                if session.outline.isEmpty {
                    Text("Le plan apparaîtra ici — « titre un, sur la recevabilité », « grand A », « petit un », « citation », « nouvel alinéa ».")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                } else {
                    ForEach(session.outline.sections) { node in
                        OutlineRow(node: node)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                switch session.phase {
                case .idle, .paused:
                    Button(session.phase == .idle ? "Démarrer" : "Reprendre") {
                        Task { await session.start() }
                    }
                    .buttonStyle(.borderedProminent)
                case .recording:
                    Button("Pause") { session.pause() }
                default:
                    EmptyView()
                }

                if session.phase == .recording || session.phase == .paused {
                    Button("Terminer") {
                        Task { await session.finish() }
                    }
                }

                Spacer()

                if session.phase == .finished, !session.outline.isEmpty {
                    Button("Exporter en DOCX…") { export() }
                        .buttonStyle(.borderedProminent)
                }
            }

            if let exportFailure {
                Text(exportFailure)
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }

            Text("Le plan en cours est conservé sur ce Mac le temps de la session, puis effacé à l'export ou à la fermeture.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }

    private func export() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "docx") ?? .data]
        panel.nameFieldStringValue = "Document dicté.docx"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let title = url.deletingPathExtension().lastPathComponent
            try session.exportDocx(title: title).write(to: url)
            exportFailure = nil
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            exportFailure = "export : \(error.localizedDescription)"
        }
    }
}

private struct OutlineRow: View {
    let node: OutlineNode

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(node.marker)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
                Text(node.heading.isEmpty ? "…" : node.heading)
                    .font(.system(size: 12, weight: node.level == 1 ? .semibold : .regular))
            }
            .padding(.leading, CGFloat(node.level - 1) * 16)

            if !node.blocks.isEmpty {
                Text("\(node.blocks.count) bloc\(node.blocks.count > 1 ? "s" : "")")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, CGFloat(node.level - 1) * 16 + 22)
            }

            ForEach(node.children) { child in
                OutlineRow(node: child)
            }
        }
    }
}
