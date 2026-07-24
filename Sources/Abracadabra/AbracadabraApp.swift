import AbracadabraCore
import SwiftUI

@main
struct AbracadabraApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    private var controller: DictationController { delegate.controller }

    var body: some Scene {
        MenuBarExtra {
            MenuView(controller: controller)
        } label: {
            Image(systemName: controller.state.symbolName)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
        }
    }
}

struct MenuView: View {
    let controller: DictationController

    var body: some View {
        Text(controller.state.label)
        Text("Dicter : \(controller.combination.displayString) — bref pour basculer, maintenu pour parler")

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

        SettingsLink { Text("Réglages…") }
            .keyboardShortcut(",", modifiers: .command)

        Button("Quitter Abracadabra") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q", modifiers: .command)
    }
}

struct SettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Réglages")
                .font(.title2)
            Text("Le contenu des réglages arrive au lot 5.")
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 480, height: 320, alignment: .topLeading)
    }
}
