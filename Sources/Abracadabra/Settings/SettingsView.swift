import AbracadabraCore
import AppKit
import SwiftUI

struct SettingsView: View {
    let controller: DictationController

    var body: some View {
        TabView {
            GeneralSettings(controller: controller)
                .tabItem { Label("Général", systemImage: "gearshape") }
            CorrectionSettings(controller: controller)
                .tabItem { Label("Correction", systemImage: "wand.and.sparkles") }
            PunctuationSettings(controller: controller)
                .tabItem { Label("Ponctuation", systemImage: "text.quote") }
            LexiconSettings(controller: controller)
                .tabItem { Label("Lexique", systemImage: "character.book.closed") }
            ProfileSettings(controller: controller)
                .tabItem { Label("Profils", systemImage: "app.badge.checkmark") }
        }
        .frame(width: 620, height: 500)
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

// MARK: - Correction

private struct CorrectionSettings: View {
    let controller: DictationController
    @State private var availability: (apple: Bool, ollama: Bool) = (false, false)

    var body: some View {
        Form {
            Section("Relecture par un modèle local") {
                Toggle("Corriger la dictée avant insertion", isOn: enabledBinding)
                Text("Le modèle rétablit la ponctuation, les accents et les accords, et supprime les hésitations. Il ne reformule pas et ne quitte jamais cet ordinateur.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Modèles") {
                CorrectorRow(
                    label: "Apple, sur l'appareil",
                    detail: availability.apple
                        ? "prêt, utilisé en premier"
                        : (AppleFoundationCorrector.unavailabilityReason ?? "indisponible"),
                    ready: availability.apple
                )
                CorrectorRow(
                    label: "Ollama — \(controller.preferences.ollamaModel)",
                    detail: availability.ollama
                        ? "prêt, prend le relais en cas de refus ou de lenteur"
                        : "démon arrêté, aucun repli disponible",
                    ready: availability.ollama
                )
                Text("Le modèle d'Apple refuse parfois les contenus sensibles, fréquents en matière pénale. Ollama prend alors le relais, sans quoi la dictée passerait sans correction.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Fidélité") {
                LabeledContent("Mots à conserver") {
                    HStack {
                        Slider(value: retentionBinding, in: 0.5...0.95, step: 0.05)
                            .frame(width: 180)
                        Text("\(Int(controller.preferences.correctionRetention * 100)) %")
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }
                Text("Une correction qui remplace davantage de mots que ce seuil est écartée, et le texte brut inséré à sa place. Abaisser le seuil laisse passer des reformulations.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task { availability = await controller.correctorAvailability() }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { controller.preferences.correctionEnabled },
            set: { controller.preferences.correctionEnabled = $0 }
        )
    }

    private var retentionBinding: Binding<Double> {
        Binding(
            get: { controller.preferences.correctionRetention },
            set: { controller.setCorrectionRetention($0) }
        )
    }
}

private struct CorrectorRow: View {
    let label: String
    let detail: String
    let ready: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: ready ? "checkmark.circle.fill" : "minus.circle")
                .foregroundStyle(ready ? .green : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

// MARK: - Profils

private struct ProfileSettings: View {
    let controller: DictationController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Le traitement s'adapte à l'application dans laquelle vous dictez. Une application non répertoriée reçoit le premier profil de la liste.")
                .font(.callout)
                .foregroundStyle(.secondary)

            List {
                ForEach(controller.profileStore.profiles.profiles) { profile in
                    Section(profile.name) {
                        Toggle("Correction par le modèle local", isOn: binding(id: profile.id, \.correctText))
                        Toggle("Commandes de ponctuation", isOn: binding(id: profile.id, \.punctuationCommands))
                        Toggle("Majuscule en début de phrase", isOn: binding(id: profile.id, \.capitalizeSentences))
                        Toggle("Typographie française", isOn: binding(id: profile.id, \.frenchTypography))
                        Toggle("Lexique de vocabulaire", isOn: binding(id: profile.id, \.applyLexicon))
                        Text(profile.bundleIdentifiers.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            HStack {
                Button("Ouvrir le fichier") {
                    NSWorkspace.shared.activateFileViewerSelecting([ProfileStore.fileURL])
                }
                Spacer()
                Text("Ajouter une application se fait dans le fichier profils.json")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(20)
    }

    /// Le binding relit le profil dans le magasin à chaque accès.
    ///
    /// Capturer la valeur rendue par `ForEach` donnerait une copie figée : la vue
    /// afficherait un état qui n'est plus celui du magasin, et une écriture partirait
    /// de cette copie périmée en réinscrivant au passage les réglages voisins.
    private func binding(
        id: String,
        _ keyPath: WritableKeyPath<AppProfile, Bool>
    ) -> Binding<Bool> {
        Binding(
            get: { controller.profileStore.profiles.profile(named: id)?[keyPath: keyPath] ?? false },
            set: { newValue in
                guard var updated = controller.profileStore.profiles.profile(named: id) else { return }
                updated[keyPath: keyPath] = newValue
                controller.updateProfile(updated)
            }
        )
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
