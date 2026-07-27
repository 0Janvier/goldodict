import AppKit
import Observation
import SwiftUI

/// Fenêtre de résultat d'un import de fichier audio.
///
/// Sur le modèle de `SettingsWindowController` : une `NSWindow` gérée à la main,
/// hors de toute scène SwiftUI. Contrairement à une dictée live, l'import n'insère
/// rien de lui-même — la fenêtre montre le texte obtenu et laisse le geste de
/// collage à l'utilisateur, qui choisit son moment.
@MainActor
final class AudioImportWindowController {

    private var window: NSWindow?
    private let controller: DictationController
    private let model = AudioImportModel()

    init(controller: DictationController) {
        self.controller = controller
    }

    /// Ouvre la fenêtre et lance la transcription de `url`.
    ///
    /// - Parameter returningTo: application au premier plan avant que le geste
    ///   d'import (menu ou glisser-déposer) n'ait donné le focus à Goldodict.
    ///   C'est elle que vise le bouton Coller, jamais Goldodict lui-même.
    func transcribe(fileAt url: URL, returningTo application: NSRunningApplication?) {
        model.targetApplication = application
        model.start(fileName: url.lastPathComponent)
        show()

        Task { [controller, model] in
            do {
                let text = try await controller.transcribeAudioFile(at: url)
                model.finish(text: text)
            } catch {
                Log.importing.error("import : \(error.localizedDescription, privacy: .public)")
                model.fail(reason: error.localizedDescription)
            }
        }
    }

    private func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 360),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Import audio"
            window.isReleasedWhenClosed = false
            window.center()
            window.contentView = NSHostingView(rootView: AudioImportView(model: model))
            self.window = window
        }

        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

/// État de la fenêtre, observé par `AudioImportView`.
///
/// Reste hors de `GoldodictCore` : rien ici n'a de logique à tester isolément,
/// contrairement à `DictationState` qui encode un geste de déclenchement.
@Observable
@MainActor
final class AudioImportModel {

    enum Phase {
        case transcribing(fileName: String)
        case done(String)
        case failed(String)
    }

    private(set) var phase: Phase = .transcribing(fileName: "")

    /// Application vers laquelle le bouton Coller doit revenir.
    var targetApplication: NSRunningApplication?

    func start(fileName: String) {
        phase = .transcribing(fileName: fileName)
    }

    func finish(text: String) {
        phase = .done(text)
    }

    func fail(reason: String) {
        phase = .failed(reason)
    }
}

/// Contenu de la fenêtre d'import : en cours, résultat, ou échec.
struct AudioImportView: View {

    let model: AudioImportModel

    @State private var copied = false

    var body: some View {
        Group {
            switch model.phase {
            case .transcribing(let fileName):
                transcribing(fileName)
            case .done(let text):
                result(text)
            case .failed(let reason):
                failure(reason)
            }
        }
        .padding(20)
        .frame(width: 480, height: 360, alignment: .topLeading)
    }

    private func transcribing(_ fileName: String) -> some View {
        VStack(spacing: 10) {
            ProgressView()
            Text("Transcription de \(fileName)…")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func result(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView {
                Text(text)
                    .font(.system(size: 13))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 10) {
                Button(copied ? "Copié" : "Copier") { copy(text) }
                Button("Coller") { paste(text) }
                    .buttonStyle(.borderedProminent)
                Spacer()
            }
        }
    }

    private func failure(_ reason: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 22))
                .foregroundStyle(.orange)
            Text(reason)
                .font(.system(size: 13))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }

    /// Réactive l'application visée avant de coller : la fenêtre d'import a le
    /// focus au moment du clic, et un Cmd+V simulé sans ce geste se collerait
    /// dans Goldodict lui-même.
    private func paste(_ text: String) {
        let target = model.targetApplication
        Task {
            target?.activate()
            try? await Task.sleep(for: .milliseconds(180))
            await TextInjector.inject(text, autoPaste: true, restorePasteboard: false)
        }
    }
}
