import AbracadabraCore
import SwiftUI

@main
struct AbracadabraApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    private var controller: DictationController { delegate.controller }

    var body: some Scene {
        MenuBarExtra {
            MenuView(controller: controller) { delegate.openSettings() }
        } label: {
            Image(systemName: controller.state.symbolName)
        }
        .menuBarExtraStyle(.menu)
    }
}

struct MenuView: View {
    let controller: DictationController
    let openSettings: () -> Void

    private var engineLabel: String {
        controller.currentEngineIdentifier == "apple"
            ? controller.appleEngine.displayName
            : controller.whisperEngine.displayName
    }

    var body: some View {
        Text(controller.state.label)
        Text("Dicter : \(controller.combination.displayString) — bref pour basculer, maintenu pour parler")

        Divider()

        Menu("Moteur : \(engineLabel)") {
            Button {
                controller.select(engine: controller.appleEngine)
            } label: {
                Label(
                    controller.appleEngine.displayName,
                    systemImage: controller.currentEngineIdentifier == "apple" ? "checkmark" : ""
                )
            }
            Button {
                controller.select(engine: controller.whisperEngine)
            } label: {
                Label(
                    controller.whisperEngine.displayName,
                    systemImage: controller.currentEngineIdentifier == "whisper-mlx" ? "checkmark" : ""
                )
            }
        }

        Divider()

        if controller.history.isEmpty {
            Text("Aucune dictée")
        } else {
            ForEach(Array(controller.history.enumerated()), id: \.offset) { _, entry in
                Button(entry.prefix(60) + (entry.count > 60 ? "…" : "")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(entry, forType: .string)
                }
            }
            Divider()
            Button("Effacer l'historique") { controller.clearHistory() }
        }

        Divider()

        Button("Réglages…", action: openSettings)
            .keyboardShortcut(",", modifiers: .command)

        Button("Quitter Abracadabra") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q", modifiers: .command)
    }
}

