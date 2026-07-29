import GoldodictCore
import AppKit
import SwiftUI

/// Fenêtre de réglages.
///
/// Les cinq onglets d'égale importance de la version précédente donnaient le même
/// poids à ce qu'on règle une fois pour toutes et à ce qu'on ajuste souvent, et
/// séparaient en trois écrans (correction, ponctuation, lexique) ce qui n'est qu'une
/// seule chaîne : ce qui arrive au texte entre la voix et le document. La barre
/// latérale les regroupe en quatre rubriques et garde en permanence sous les yeux
/// l'état des autorisations, seul endroit où l'application peut échouer en silence.
struct SettingsView: View {

    let controller: DictationController

    @State private var section: Section = .dictation

    enum Section: String, CaseIterable, Identifiable {
        case dictation, text, vocabulary, applications, learning, repliques

        var id: String { rawValue }

        var title: String {
            switch self {
            case .dictation: return "Dictée"
            case .text: return "Texte"
            case .vocabulary: return "Vocabulaire"
            case .applications: return "Applications"
            case .learning: return "Style appris"
            case .repliques: return "Répliques"
            }
        }

        var symbol: String {
            switch self {
            case .dictation: return "mic"
            case .text: return "text.alignleft"
            case .vocabulary: return "character.book.closed"
            case .applications: return "app.badge.checkmark"
            case .learning: return "sparkles"
            case .repliques: return "film"
            }
        }

        var subtitle: String {
            switch self {
            case .dictation: return "Raccourci, moteur, insertion"
            case .text: return "Correction, ponctuation, typographie"
            case .vocabulary: return "Noms propres et abréviations"
            case .applications: return "Un traitement par application"
            case .learning: return "Corrections répétées, proposées avant d'être apprises"
            case .repliques: return "Ce que dit la pastille"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(Section.allCases, selection: $section) { item in
                    NavigationLink(value: item) {
                        Label {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.title)
                                Text(item.subtitle)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                            }
                        } icon: {
                            Image(systemName: item.symbol)
                        }
                    }
                }
                .listStyle(.sidebar)

                Divider()
                StatusPanel(controller: controller) { section = .text }
            }
            .navigationSplitViewColumnWidth(min: 210, ideal: 210, max: 210)
        } detail: {
            Group {
                switch section {
                case .dictation: DictationSettings(controller: controller)
                case .text: TextSettings(controller: controller)
                case .vocabulary: LexiconSettings(controller: controller)
                case .applications: ProfileSettings(controller: controller)
                case .learning: StyleLearningSettings(controller: controller)
                case .repliques: RepliqueSettings(controller: controller)
                }
            }
            .navigationTitle(section.title)
        }
        .frame(width: 760, height: 560)
    }
}

// MARK: - État permanent

/// Bandeau d'état, visible quelle que soit la rubrique ouverte.
///
/// L'Accessibilité refusée ne se manifeste nulle part au moment où elle bloque :
/// le texte est copié, rien n'est collé, et l'utilisateur croit avoir mal dicté.
private struct StatusPanel: View {
    let controller: DictationController
    let showCorrection: () -> Void

    @State private var availability: (apple: Bool, ollama: Bool) = (false, false)
    @State private var pulse = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("ÉTAT")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)

            StatusLine(
                label: "Microphone",
                ok: controller.microphoneGranted,
                detail: controller.microphoneGranted ? "autorisé" : "refusé"
            ) {
                PermissionGuard.openSettings(for: .microphone)
            }

            StatusLine(
                label: "Accessibilité",
                ok: controller.accessibilityGranted,
                detail: controller.accessibilityGranted ? "autorisée" : "le texte n'est pas collé"
            ) {
                PermissionGuard.openSettings(for: .accessibility)
            }

            StatusLine(
                label: "Raccourci",
                ok: controller.hotkeyArmed,
                detail: controller.hotkeyArmed
                    ? controller.triggerDisplayString
                    : "surveillance de l'entrée refusée"
            ) {
                PermissionGuard.openSettings(for: .inputMonitoring)
            }

            StatusLine(
                label: "Relecture",
                ok: availability.apple || availability.ollama,
                detail: correctorDetail,
                action: showCorrection
            )
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .task { availability = await controller.correctorAvailability() }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            pulse &+= 1
        }
    }

    private var correctorDetail: String {
        if !controller.preferences.correctionEnabled { return "désactivée" }
        if availability.apple { return "modèle Apple" }
        if availability.ollama { return "Ollama" }
        return "aucun modèle disponible"
    }
}

private struct StatusLine: View {
    let label: String
    let ok: Bool
    let detail: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Circle()
                    .fill(ok ? Color.green : Color.orange)
                    .frame(width: 6, height: 6)
                VStack(alignment: .leading, spacing: 1) {
                    Text(label).font(.system(size: 11, weight: .medium))
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Dictée

private struct DictationSettings: View {
    let controller: DictationController
    @State private var whisperModels: [String] = []

    var body: some View {
        Form {
            Section("Déclenchement") {
                HotkeyRecorder(controller: controller)
                Text("Appui bref : la dictée bascule en marche puis en arrêt. Appui maintenu : elle s'arrête au relâchement.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

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
                Text("Sans collage automatique, le texte dicté reste dans le presse-papiers et se colle par ⌘V.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Lancer au démarrage de la session", isOn: launchBinding)
            }
        }
        .formStyle(.grouped)
        .task { whisperModels = await controller.whisperEngine.availableModels() }
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

// MARK: - Texte

/// Degré de liberté laissé au correcteur.
///
/// Le réglage sous-jacent est une part minimale de mots à conserver, exprimée en
/// pourcentage. C'était demander à l'utilisateur d'arbitrer un paramètre plutôt
/// qu'une conséquence : trois positions nommées disent ce qu'il obtient.
private enum Fidelity: String, CaseIterable, Identifiable {
    case faithful, balanced, loose

    var id: String { rawValue }

    var retention: Double {
        switch self {
        case .faithful: return 0.90
        case .balanced: return 0.75
        case .loose: return 0.60
        }
    }

    var title: String {
        switch self {
        case .faithful: return "Fidèle"
        case .balanced: return "Équilibré"
        case .loose: return "Souple"
        }
    }

    var detail: String {
        switch self {
        case .faithful:
            return "Le correcteur ne touche qu'à la ponctuation, aux accents et aux accords. Vos mots restent les vôtres."
        case .balanced:
            return "Les hésitations et les répétitions disparaissent, la phrase garde sa forme. Réglage recommandé."
        case .loose:
            return "Le correcteur peut recomposer une phrase mal dite. À réserver aux dictées rapides que vous relirez."
        }
    }

    /// Le seuil enregistré peut venir d'une version antérieure, où il se réglait au
    /// curseur : on retient la position la plus proche plutôt que d'imposer un défaut.
    static func closest(to value: Double) -> Fidelity {
        allCases.min { abs($0.retention - value) < abs($1.retention - value) } ?? .balanced
    }
}

private struct TextSettings: View {
    let controller: DictationController
    @State private var availability: (apple: Bool, ollama: Bool) = (false, false)

    var body: some View {
        Form {
            Section("Relecture par un modèle local") {
                Toggle("Corriger la dictée avant insertion", isOn: enabledBinding)
                Text("Le modèle rétablit la ponctuation, les accents et les accords, et supprime les hésitations. Rien ne quitte cet ordinateur.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if controller.preferences.correctionEnabled {
                    Picker("Latitude", selection: fidelityBinding) {
                        ForEach(Fidelity.allCases) { level in
                            Text(level.title).tag(level)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(Fidelity.closest(to: controller.preferences.correctionRetention).detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section("Modèles de relecture") {
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

            Section("Commandes de ponctuation") {
                Toggle("Marques simples : « virgule », « point », « tiret »", isOn: punctuation(\.simpleMarks))
                Text("À désactiver si « le point de départ du délai » se transforme en ponctuation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Retours à la ligne : « à la ligne », « nouveau paragraphe »", isOn: punctuation(\.lineBreaks))
                Toggle("Marques composées : guillemets, parenthèses, « point d'interrogation »", isOn: punctuation(\.compoundMarks))
                Toggle("Majuscule en début de phrase", isOn: punctuation(\.capitalizeSentences))
            }

            Section("Typographie française") {
                Text("Les espaces insécables sont posées automatiquement devant « ; : ! ? » et à l'intérieur des guillemets français, conformément à l'usage.")
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

    private var fidelityBinding: Binding<Fidelity> {
        Binding(
            get: { Fidelity.closest(to: controller.preferences.correctionRetention) },
            set: { controller.setCorrectionRetention($0.retention) }
        )
    }

    private func punctuation(_ keyPath: WritableKeyPath<PunctuationCommands.Options, Bool>) -> Binding<Bool> {
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

// MARK: - Applications

private struct ProfileSettings: View {
    let controller: DictationController
    @State private var selected: String?

    private var profiles: [AppProfile] { controller.profileStore.profiles.profiles }

    private var current: AppProfile? {
        guard let selected else { return profiles.first }
        return controller.profileStore.profiles.profile(named: selected)
    }

    var body: some View {
        HSplitView {
            List(profiles, selection: $selected) { profile in
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.name)
                    Text(applicationSummary(profile))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                .tag(profile.id)
            }
            .frame(minWidth: 170, maxWidth: 220)

            if let profile = current {
                detail(for: profile)
            } else {
                Text("Aucun profil").foregroundStyle(.secondary)
            }
        }
        .onAppear { selected = selected ?? profiles.first?.id }
    }

    private func applicationSummary(_ profile: AppProfile) -> String {
        let count = profile.bundleIdentifiers.count
        return "\(count) application\(count > 1 ? "s" : "")"
    }

    private func detail(for profile: AppProfile) -> some View {
        Form {
            Section("Traitement du texte") {
                Toggle("Relecture par le modèle local", isOn: binding(profile.id, \.correctText))
                Toggle("Commandes de ponctuation", isOn: binding(profile.id, \.punctuationCommands))
                Toggle("Majuscule en début de phrase", isOn: binding(profile.id, \.capitalizeSentences))
                Toggle("Typographie française", isOn: binding(profile.id, \.frenchTypography))
                Toggle("Lexique de vocabulaire", isOn: binding(profile.id, \.applyLexicon))
            }

            Section("Applications") {
                if profile.bundleIdentifiers.isEmpty {
                    Text("Aucune application. Ce profil ne s'appliquera jamais.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(profile.bundleIdentifiers, id: \.self) { identifier in
                    HStack {
                        Text(displayName(for: identifier))
                        Spacer()
                        Text(identifier)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Button {
                            remove(identifier, from: profile)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                }

                Button("Ajouter une application…") { add(to: profile) }

                if profile.id == profiles.first?.id {
                    Text("Ce profil est aussi celui des applications non répertoriées.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Style de correction") {
                if profile.styleNotes.isEmpty {
                    Text("Aucune règle. Elles s'apprennent depuis « Style appris », ou s'écrivent ici.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(profile.styleNotes, id: \.self) { note in
                    HStack {
                        Text(note).font(.callout)
                        Spacer()
                        Button {
                            var updated = profile
                            updated.styleNotes.removeAll { $0 == note }
                            controller.updateProfile(updated)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                HStack {
                    TextField("Nouvelle règle transmise au correcteur", text: $newStyleNote)
                        .onSubmit { addStyleNote(to: profile) }
                    Button("Ajouter") { addStyleNote(to: profile) }
                        .disabled(newStyleNote.trimmed.isEmpty)
                }
            }
        }
        .formStyle(.grouped)
    }

    @State private var newStyleNote = ""

    private func addStyleNote(to profile: AppProfile) {
        let note = newStyleNote.trimmed
        guard !note.isEmpty else { return }
        var updated = profile
        if !updated.styleNotes.contains(note) {
            updated.styleNotes.append(note)
            controller.updateProfile(updated)
        }
        newStyleNote = ""
    }

    /// Nom affiché par le Finder, quand l'application est installée. Un identifiant
    /// de paquet seul ne dit rien à personne.
    private func displayName(for identifier: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) else {
            return identifier
        }
        return FileManager.default.displayName(atPath: url.path)
    }

    /// Le panneau de sélection évite de faire chercher un identifiant de paquet :
    /// l'utilisateur désigne l'application, le système en donne l'identifiant.
    private func add(to profile: AppProfile) {
        let panel = NSOpenPanel()
        panel.title = "Choisir une application"
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true

        guard panel.runModal() == .OK else { return }

        let identifiers = panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }
        guard !identifiers.isEmpty else { return }

        // Une même application dans deux profils rendrait le traitement imprévisible,
        // le premier profil de la liste l'emportant sans que rien ne le signale.
        for other in profiles where other.id != profile.id {
            let remaining = other.bundleIdentifiers.filter { !identifiers.contains($0) }
            if remaining.count != other.bundleIdentifiers.count {
                var updated = other
                updated.bundleIdentifiers = remaining
                controller.updateProfile(updated)
            }
        }

        var updated = profile
        for identifier in identifiers where !updated.bundleIdentifiers.contains(identifier) {
            updated.bundleIdentifiers.append(identifier)
        }
        controller.updateProfile(updated)
    }

    private func remove(_ identifier: String, from profile: AppProfile) {
        var updated = profile
        updated.bundleIdentifiers.removeAll { $0 == identifier }
        controller.updateProfile(updated)
    }

    /// Le binding relit le profil dans le magasin à chaque accès.
    ///
    /// Capturer la valeur rendue par `ForEach` donnerait une copie figée : la vue
    /// afficherait un état qui n'est plus celui du magasin, et une écriture partirait
    /// de cette copie périmée en réinscrivant au passage les réglages voisins.
    private func binding(
        _ id: String,
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

// MARK: - Vocabulaire

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
            .frame(minHeight: 260)

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

// MARK: - Répliques

/// Catalogue des répliques et mise en forme de la pastille.
///
/// Le choix du format est une liste, et non un menu déroulant : chaque ligne montre
/// le rendu exact plutôt que de le décrire, et les flèches du clavier suffisent à
/// passer de l'un à l'autre en voyant ce qui change.
private struct RepliqueSettings: View {
    let controller: DictationController
    @State private var selection: Set<String> = []
    @State private var newQuote = ""
    @State private var newFilm = ""
    @State private var newYear = ""

    /// Réplique d'aperçu, fixe. Un tirage au sort dans cet écran rendrait le menu
    /// illisible : le rendu changerait en même temps que le format.
    private static let sample = MovieLine(replique: "You talkin' to me?", film: "Taxi Driver", annee: 1976)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pendant la dictée, la pastille affiche une réplique de cinéma tirée au sort. Le format se choisit ici, aux flèches du clavier.")
                .font(.callout)
                .foregroundStyle(.secondary)

            List(MovieLineFormat.allCases, selection: formatBinding) { format in
                VStack(alignment: .leading, spacing: 2) {
                    Text(format.label)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(Self.sample.rendered(format))
                        .font(.system(size: 13, weight: .medium))
                }
                .padding(.vertical, 2)
            }
            .frame(height: 150)

            Table(controller.repliqueStore.book.lines, selection: $selection) {
                TableColumn("Réplique", value: \.replique)
                TableColumn("Film", value: \.film)
                TableColumn("Année") { line in Text(String(line.annee)) }
                    .width(60)
            }
            .frame(minHeight: 160)

            HStack(spacing: 8) {
                TextField("Réplique", text: $newQuote)
                TextField("Film", text: $newFilm)
                TextField("Année", text: $newYear)
                    .frame(width: 60)
                Button("Ajouter", action: add)
                    .disabled(!canAdd)
                Button("Supprimer", action: removeSelected)
                    .disabled(selection.isEmpty)
            }

            HStack {
                Button("Ouvrir le fichier") {
                    NSWorkspace.shared.activateFileViewerSelecting([RepliqueStore.fileURL])
                }
                Button("Rétablir le catalogue livré") {
                    controller.repliqueStore.restoreDefaults()
                }
                Spacer()
                Text(RepliqueStore.fileURL.path)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
        }
        .padding(20)
    }

    /// La sélection d'une `List` porte sur l'identifiant de l'élément, jamais sur
    /// l'élément lui-même.
    private var formatBinding: Binding<MovieLineFormat.ID?> {
        Binding(
            get: { controller.preferences.lineFormat.id },
            set: { raw in
                guard let raw, let value = MovieLineFormat(rawValue: raw) else { return }
                controller.preferences.lineFormat = value
            }
        )
    }

    private var canAdd: Bool {
        !newQuote.trimmed.isEmpty && !newFilm.trimmed.isEmpty && Int(newYear.trimmed) != nil
    }

    private func add() {
        guard let year = Int(newYear.trimmed) else { return }
        var book = controller.repliqueStore.book
        book.upsert(MovieLine(replique: newQuote.trimmed, film: newFilm.trimmed, annee: year))
        controller.updateRepliques(book)
        newQuote = ""
        newFilm = ""
        newYear = ""
    }

    private func removeSelected() {
        var book = controller.repliqueStore.book
        for id in selection { book.remove(id: id) }
        controller.updateRepliques(book)
        selection.removeAll()
    }
}

// MARK: - Style appris

private struct StyleLearningSettings: View {
    let controller: DictationController

    private var pending: [StyleObservation] {
        controller.styleObservationStore.observations.proposals(threshold: 1)
            .filter { $0.status == .pending }
    }

    var body: some View {
        Form {
            Section {
                Toggle("Relever les corrections manuelles", isOn: Binding(
                    get: { controller.preferences.styleLearningEnabled },
                    set: { controller.preferences.styleLearningEnabled = $0 }
                ))
                Text("Depuis « Reprendre… » dans le menu, après une dictée. Seules des paires courtes sont conservées, jamais le texte des dictées.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Corrections observées") {
                if pending.isEmpty {
                    Text("Rien à examiner. Une correction relevée \(StyleObservations.defaultThreshold) fois devient une proposition dans le menu.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(pending) { observation in
                    VStack(alignment: .leading, spacing: 3) {
                        Text("« \(observation.before) » → « \(observation.after) »")
                            .font(.callout)
                        HStack(spacing: 10) {
                            Text("\(observation.occurrences)× · \(observation.profileName)")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            Spacer()
                            Button("Lexique") { controller.acceptStyleProposal(observation, as: .lexicon) }
                                .controlSize(.small)
                            Button("Style") { controller.acceptStyleProposal(observation, as: .style) }
                                .controlSize(.small)
                            Button("Ignorer") { controller.dismissStyleProposal(observation) }
                                .controlSize(.small)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            Section {
                Button("Ouvrir le fichier des observations") {
                    NSWorkspace.shared.activateFileViewerSelecting([StyleObservationStore.fileURL])
                }
                .disabled(!FileManager.default.fileExists(atPath: StyleObservationStore.fileURL.path))
            }
        }
        .formStyle(.grouped)
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
