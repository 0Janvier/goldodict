import AbracadabraCore
import AppKit
import SwiftUI

struct SettingsView: View {
    let controller: DictationController

    var body: some View {
        TabView {
            GeneralSettings(controller: controller)
                .tabItem { Label("Général", systemImage: "gearshape") }
            PunctuationSettings(controller: controller)
                .tabItem { Label("Ponctuation", systemImage: "text.quote") }
            LexiconSettings(controller: controller)
                .tabItem { Label("Lexique", systemImage: "character.book.closed") }
        }
        .frame(width: 560, height: 460)
    }
}

// MARK: - Général

private struct GeneralSettings: View {
    let controller: DictationController
    @State private var whisperModels: [String] = []

    var body: some View {
        Form {
            Section("Moteur de transcription") {
                Picker("Moteur", selection: engineBinding) {
                    Text(controller.appleEngine.displayName).tag("apple")
                    Text("Whisper (MLX)").tag("whisper-mlx")
                }
                .pickerStyle(.radioGroup)

                if controller.currentEngineIdentifier == "whisper-mlx" {
                    Picker("Modèle", selection: modelBinding) {
                        ForEach(whisperModels, id: \.self) { model in
                            Text(WhisperMLXEngine.shortName(of: model)).tag(model)
                        }
                    }
                    Text("Transcription par lots : le texte arrive après le relâchement. Plus lent qu'Apple, souvent plus juste sur le vocabulaire technique.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Insertion") {
                Toggle("Coller automatiquement dans l'application active", isOn: autoPasteBinding)
                Toggle("Restaurer le presse-papiers après collage", isOn: restoreBinding)
                Text("Désactivé, le texte dicté reste dans le presse-papiers pour un collage manuel.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Déclenchement") {
                LabeledContent("Raccourci", value: controller.combination.displayString)
                Text("Appui bref : bascule marche/arrêt. Appui maintenu : la dictée s'arrête au relâchement.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Autorisations") {
                PermissionRow(
                    label: "Microphone",
                    granted: controller.microphoneGranted,
                    kind: .microphone
                )
                PermissionRow(
                    label: "Accessibilité",
                    granted: controller.accessibilityGranted,
                    kind: .accessibility
                )
            }

            Section {
                Toggle("Lancer au démarrage de la session", isOn: launchBinding)
            }
        }
        .formStyle(.grouped)
        .task {
            whisperModels = await controller.whisperEngine.availableModels()
        }
    }

    private var engineBinding: Binding<String> {
        Binding(
            get: { controller.currentEngineIdentifier },
            set: { controller.selectEngine(identifier: $0) }
        )
    }

    private var modelBinding: Binding<String> {
        Binding(
            get: { controller.whisperEngine.model },
            set: { controller.selectWhisperModel($0) }
        )
    }

    private var autoPasteBinding: Binding<Bool> {
        Binding(
            get: { controller.preferences.autoPaste },
            set: { controller.preferences.autoPaste = $0 }
        )
    }

    private var restoreBinding: Binding<Bool> {
        Binding(
            get: { controller.preferences.restorePasteboard },
            set: { controller.preferences.restorePasteboard = $0 }
        )
    }

    private var launchBinding: Binding<Bool> {
        Binding(
            get: { controller.preferences.launchAtLogin },
            set: { controller.preferences.launchAtLogin = $0 }
        )
    }
}

private struct PermissionRow: View {
    let label: String
    let granted: Bool
    let kind: PermissionGuard.Kind

    var body: some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(granted ? .green : .orange)
            Text(label)
            Spacer()
            if !granted {
                Button("Ouvrir les Réglages") { PermissionGuard.openSettings(for: kind) }
            }
        }
    }
}

// MARK: - Ponctuation

private struct PunctuationSettings: View {
    let controller: DictationController

    var body: some View {
        Form {
            Section("Commandes reconnues") {
                Toggle("Marques simples : « virgule », « point », « tiret »", isOn: binding(\.simpleMarks))
                Text("À désactiver si « le point de départ du délai » se transforme en ponctuation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Retours à la ligne : « à la ligne », « nouveau paragraphe »", isOn: binding(\.lineBreaks))
                Toggle("Marques composées : guillemets, parenthèses, « point d'interrogation »", isOn: binding(\.compoundMarks))
                Toggle("Majuscule en début de phrase", isOn: binding(\.capitalizeSentences))
            }

            Section("Typographie") {
                Text("Les espaces insécables sont posées automatiquement devant « ; : ! ? » et à l'intérieur des guillemets français, conformément à l'usage.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func binding(_ keyPath: WritableKeyPath<PunctuationCommands.Options, Bool>) -> Binding<Bool> {
        Binding(
            get: { controller.preferences.punctuationOptions[keyPath: keyPath] },
            set: { newValue in
                var options = controller.preferences.punctuationOptions
                options[keyPath: keyPath] = newValue
                controller.preferences.punctuationOptions = options
                controller.reloadPipeline()
            }
        )
    }
}

// MARK: - Lexique

private struct LexiconSettings: View {
    let controller: DictationController
    @State private var selection: Set<String> = []
    @State private var newHeard = ""
    @State private var newWritten = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Le moteur entend souvent de travers les noms propres et les abréviations. Chaque entrée corrige une déformation et oriente la reconnaissance.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Table(controller.lexiconStore.lexicon.entries, selection: $selection) {
                TableColumn("Entendu", value: \.entendu)
                TableColumn("Écrit", value: \.corrige)
                TableColumn("Suggéré au moteur") { entry in
                    Image(systemName: entry.biaiser ? "checkmark" : "minus")
                        .foregroundStyle(entry.biaiser ? .green : .secondary)
                }
                .width(130)
            }
            .frame(minHeight: 220)

            HStack(spacing: 8) {
                TextField("Entendu", text: $newHeard)
                TextField("Écrit", text: $newWritten)
                Button("Ajouter", action: add)
                    .disabled(newHeard.trimmed.isEmpty || newWritten.trimmed.isEmpty)
                Button("Supprimer", action: removeSelected)
                    .disabled(selection.isEmpty)
            }

            HStack {
                Button("Ouvrir le fichier") {
                    NSWorkspace.shared.activateFileViewerSelecting([LexiconStore.fileURL])
                }
                Spacer()
                Text(LexiconStore.fileURL.path)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
        }
        .padding(20)
    }

    private func add() {
        var lexicon = controller.lexiconStore.lexicon
        lexicon.upsert(LexiconEntry(entendu: newHeard.trimmed, corrige: newWritten.trimmed))
        controller.updateLexicon(lexicon)
        newHeard = ""
        newWritten = ""
    }

    private func removeSelected() {
        var lexicon = controller.lexiconStore.lexicon
        for id in selection { lexicon.remove(id: id) }
        controller.updateLexicon(lexicon)
        selection.removeAll()
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
