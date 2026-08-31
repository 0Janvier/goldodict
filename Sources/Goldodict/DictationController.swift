import GoldodictCore
import AppKit
import AVFoundation
import Foundation
import Observation

enum AudioImportError: LocalizedError {
    case busy

    var errorDescription: String? {
        switch self {
        case .busy: return "une dictée est en cours, réessayez après"
        }
    }
}

/// Chef d'orchestre de la dictée : il relie le raccourci, la capture audio, le
/// moteur de transcription et l'insertion du texte. Il ne connaîtra jamais qu'un
/// protocole de moteur, jamais un moteur particulier.
@Observable
@MainActor
final class DictationController {

    private(set) var state: DictationState = .idle {
        didSet {
            reflectStateInOverlay()
            onStateChange?(state)
            if case .failed(let message) = state { lastFailure = message }
        }
    }
    private(set) var lastTranscript: String = ""

    /// Dernier échec, indépendant de `state`.
    ///
    /// `state` revient à `.idle` cinq secondes après un échec — la pastille flottante
    /// ne doit pas rester rouge indéfiniment. Le panneau de la barre des menus, lui,
    /// est consulté après coup : l'erreur y reste jusqu'à ce qu'une nouvelle dictée
    /// démarre ou que l'utilisateur la referme.
    private(set) var lastFailure: String?

    func dismissFailure() {
        lastFailure = nil
    }

    /// Prévient la barre des menus. L'icône du `NSStatusItem` est une image AppKit,
    /// hors de portée du suivi d'observation de SwiftUI : sans ce rappel, elle
    /// resterait au repos pendant toute la dictée.
    @ObservationIgnored
    var onStateChange: ((DictationState) -> Void)?

    private let overlay = RecordingOverlay()
    private var overlayDismissal: Task<Void, Never>?

    /// La pastille flottante est le seul retour réellement visible : l'icône de la
    /// barre des menus disparaît derrière le chevron dès que la barre est chargée.
    ///
    /// La confirmation d'insertion s'efface plus vite qu'une erreur : elle apprend
    /// que tout s'est bien passé, ce qui se lit d'un coup d'œil ; un échec demande à
    /// être lu jusqu'au bout.
    private func reflectStateInOverlay() {
        overlayDismissal?.cancel()

        switch state {
        case .idle, .reviewing:
            overlay.hide()
        case .recording, .transcribing, .correcting, .injecting:
            overlay.show(state: state)
        case .inserted(let insertion):
            overlay.show(state: state)
            dismissOverlay(after: insertion.note == nil ? 2 : 5)
        case .failed:
            overlay.show(state: state)
            dismissOverlay(after: 5)
        }
    }

    /// L'état revient au repos en même temps que la pastille s'efface, sans quoi le
    /// menu continuerait d'annoncer la dernière insertion des heures durant.
    private func dismissOverlay(after seconds: Double) {
        overlayDismissal = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self, self.state.isTransient else { return }
            self.state = .idle
        }
    }

    /// Une dictée passée, telle que le menu la présente.
    struct Dictation: Identifiable, Equatable {
        let id = UUID()
        let text: String
        let date: Date
        /// Profil qui a traité la dictée : c'est à lui que profitera une
        /// correction relevée dans la fenêtre de reprise.
        let profileName: String

        /// « 14:32 ». L'heure suffit : l'historique ne survit pas à la session.
        var time: String {
            Dictation.formatter.string(from: date)
        }

        private static let formatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "fr_FR")
            formatter.dateFormat = "HH:mm"
            return formatter
        }()
    }

    /// Les vingt dernières dictées, en mémoire seule. Rien n'est écrit sur disque :
    /// ni l'audio, ni le texte, ce qui ferme la question du secret professionnel.
    private(set) var history: [Dictation] = []
    private let historyLimit = 20

    private var resolver = TriggerResolver()
    private let hotkey = HotkeyMonitor()
    private let capture = AudioCapture()
    @ObservationIgnored
    private var engine: TranscriptionEngine

    /// Identifiant du moteur en service, suivi par l'observation.
    ///
    /// `engine` en est exclu, et à juste titre : c'est un objet, pas une valeur.
    /// Mais l'interface a besoin de savoir lequel est en service, et une propriété
    /// calculée par-dessus un stockage exclu ne notifie rien. Les boutons du choix
    /// de moteur restaient donc figés sur celui du lancement, dans la fenêtre
    /// d'accueil comme dans les réglages et le panneau du menu, alors même que la
    /// sélection était prise en compte et écrite dans les préférences.
    private(set) var currentEngineIdentifier: String

    init() {
        engine = appleEngine
        currentEngineIdentifier = appleEngine.identifier
        // La pastille lit le niveau à sa propre cadence plutôt que de le recevoir :
        // la capture le produit sur un thread temps réel, où le moindre passage par
        // la boucle principale serait payé en craquements.
        overlay.levelProvider = { [capture] in capture.level }
    }

    /// Change de moteur. Le format audio est réinterrogé, les deux moteurs n'ayant
    /// pas les mêmes exigences.
    func select(engine newEngine: TranscriptionEngine, force: Bool = false) {
        guard !state.isBusy, force || newEngine.identifier != engine.identifier else { return }
        engine = newEngine
        currentEngineIdentifier = newEngine.identifier
        audioFormat = nil
        Log.engine.notice("moteur sélectionné : \(newEngine.identifier, privacy: .public)")

        Task { [weak self] in
            let format = await newEngine.preferredAudioFormat()
            await self?.cache(audioFormat: format, from: newEngine.identifier)
        }
    }

    /// Langue de dictée, lue dans les préférences.
    var locale: Locale { Locale(identifier: preferences.localeIdentifier) }

    let lexiconStore = LexiconStore()
    let repliqueStore = RepliqueStore()
    let preferences = Preferences()

    /// Réplique de la dictée en cours, tirée une fois pour toutes à son démarrage.
    private(set) var currentLine: MovieLine?

    /// Tire la réplique de la dictée qui commence et la remet à la pastille.
    ///
    /// Le tirage a lieu ici, et non dans `DictationState` : cet état doit rester une
    /// valeur déterministe, et la pastille se redessine vingt fois par seconde.
    private func drawQuote() {
        currentLine = repliqueStore.draw()
        overlay.quote = currentLine?.rendered(preferences.lineFormat)
    }

    func updateRepliques(_ book: MovieLineBook) {
        repliqueStore.update(book)
    }

    var microphoneGranted: Bool { PermissionGuard.microphoneStatus == .authorized }
    var accessibilityGranted: Bool { PermissionGuard.hasAccessibility() }
    var inputMonitoringGranted: Bool { PermissionGuard.hasInputMonitoring }

    /// Niveau sonore instantané. Même source que la pastille flottante
    /// (`overlay.levelProvider`) : le panneau de la barre des menus peut rester
    /// ouvert pendant une dictée sans dupliquer la capture.
    var currentLevel: Float { capture.level }

    /// Recharge la chaîne de traitement depuis le lexique et les réglages.
    func reloadPipeline() {
        pipeline.lexicon = lexiconStore.lexicon
        pipeline.punctuation = PunctuationCommands(options: preferences.punctuationOptions)
    }

    func updateLexicon(_ lexicon: Lexicon) {
        lexiconStore.update(lexicon)
        reloadPipeline()
    }

    func selectEngine(identifier: String) {
        preferences.engineIdentifier = identifier
        select(engine: identifier == "whisper-mlx" ? whisperEngine : appleEngine)
    }

    func updateProfile(_ profile: AppProfile) {
        profileStore.update(profile)
    }

    func correctorAvailability() async -> CorrectionService.Availability {
        await corrector.availability()
    }

    /// Change l'ordre d'essai des correcteurs.
    func setCorrectionOrder(primary: String, fallback: Bool) {
        preferences.correctionPrimary = primary
        preferences.correctionFallback = fallback
        Task { [corrector] in await corrector.setOrder(primary: primary, fallback: fallback) }
    }

    /// Change le modèle de repli. Le service le précharge s'il est servi.
    func setOllamaModel(_ model: String) {
        guard model != preferences.ollamaModel else { return }
        preferences.ollamaModel = model
        Task { [corrector] in await corrector.setOllamaModel(model) }
    }

    func setCorrectionRetention(_ value: Double) {
        preferences.correctionRetention = value
        let thresholds = CorrectionGuard.Thresholds(retention: value)
        Task { [corrector] in await corrector.setThresholds(thresholds) }
    }

    /// Moteurs disponibles, dans l'ordre d'affichage.
    let appleEngine = AppleSpeechEngine()
    private(set) var whisperEngine = WhisperMLXEngine()

    /// Change le modèle Whisper. L'instance est remplacée plutôt que mutée, le
    /// modèle étant immuable par construction.
    func selectWhisperModel(_ model: String) {
        guard !state.isBusy, model != whisperEngine.model else { return }
        preferences.whisperModel = model
        let wasSelected = currentEngineIdentifier == whisperEngine.identifier
        let previous = whisperEngine
        whisperEngine = WhisperMLXEngine(model: model)
        Task { await previous.shutdown() }
        if wasSelected { select(engine: whisperEngine, force: true) }
    }

    /// Chaîne de traitement du texte brut : ponctuation, lexique, typographie.
    private var pipeline = TranscriptPipeline()

    let profileStore = ProfileStore()
    /// Le modèle de repli vient des préférences, et non du défaut compilé.
    ///
    /// `CorrectionService()` était construit sans argument : le réglage
    /// `correction.ollamaModel` avait un getter, un setter, un défaut enregistré et
    /// une place dans les réglages, mais n'atteignait jamais le correcteur, qui
    /// restait sur `qwen3:8b` quoi qu'on choisisse. Différé, parce qu'il lui faut
    /// `preferences`.
    @ObservationIgnored
    private lazy var corrector = CorrectionService(ollamaModel: preferences.ollamaModel)

    /// Profil retenu pour la dictée en cours.
    ///
    /// Il est arrêté à l'enfoncement de la touche, jamais à l'insertion : entre les
    /// deux, l'application au premier plan a pu changer, et le texte serait alors
    /// traité selon les règles d'une fenêtre qui n'est plus la cible.
    private var activeProfile: AppProfile = .redaction

    /// Nom de l'application visée, arrêté au même instant que le profil et pour la
    /// même raison : il sert à confirmer où le texte est parti.
    private var activeApplicationName: String?

    /// Identifiant de paquet de la même application : l'observation du champ ne
    /// relit que dans l'application où le texte est parti.
    private var activeBundleIdentifier: String?

    /// L'application elle-même, pour lui rendre le premier plan après une
    /// relecture — la fenêtre flottante l'aura pris pour être éditable.
    private var activeApplication: NSRunningApplication?

    /// Vocabulaire transmis au moteur avant transcription : le lexique, enrichi
    /// des termes du dossier actif quand il y en a un.
    private var contextualStrings: [String] {
        lexiconStore.lexicon.contextualStrings + dossiers.contextualTerms
    }

    let dossiers = DossierCoordinator()
    let learning = LearningCoordinator()
    private var captureStartedAt: Date?

    var activeDossier: DossierContext? { dossiers.activeDossier }
    var availableDossiers: [DossierContext] { dossiers.availableDossiers }
    var dossierSessionSeconds: TimeInterval { dossiers.dossierSessionSeconds }

    func refreshDossiers() { dossiers.refresh() }
    func selectDossier(_ dossier: DossierContext?) { dossiers.select(dossier) }
    func prepareRelaunchHandoff() { dossiers.prepareRelaunchHandoff() }

    // MARK: - Relecture à la volée

    /// Le texte prêt et son contexte, remis à la fenêtre de relecture.
    struct ReviewRequest {
        let text: String
        let profileName: String
        let note: String?
        let application: NSRunningApplication?
        let applicationName: String?
        let bundleIdentifier: String?
    }

    /// Présente la fenêtre de relecture. Câblé par l'AppDelegate, comme les
    /// autres fenêtres ; s'il manque, le collage direct reprend ses droits.
    @ObservationIgnored
    var presentReview: ((ReviewRequest) -> Void)?

    /// Entrée : appliquer l'éventuelle retouche à l'apprentissage, rendre le
    /// premier plan à l'application d'origine, coller.
    func completeReview(_ request: ReviewRequest, edited: String) {
        let text = edited.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? request.text
            : edited

        if text != request.text {
            let learned = submitStyleCorrection(
                original: request.text,
                corrected: text,
                profileName: request.profileName
            )
            if learned > 0 {
                Log.learning.notice("relecture : \(learned) correction(s) relevée(s)")
            }
        }

        request.application?.activate()
        Task { [weak self] in
            // Le même délai que la dictée lancée depuis le menu : sans lui, le
            // collage partirait avant que la bascule d'application n'aboutisse.
            try? await Task.sleep(for: .milliseconds(180))
            guard let self else { return }
            self.state = .injecting
            let outcome = await TextInjector.inject(
                text,
                autoPaste: self.preferences.autoPaste,
                restorePasteboard: self.preferences.restorePasteboard
            )
            self.record(transcript: text, profileName: request.profileName)
            if outcome != .pasted {
                self.state = .failed("texte copié, Accessibilité non autorisée")
            } else {
                self.learning.rememberInsertion(
                    text: text,
                    bundleIdentifier: request.bundleIdentifier,
                    profileName: request.profileName
                )
                self.state = .inserted(Insertion(
                    characters: text.count,
                    application: request.applicationName,
                    note: request.note
                ))
            }
        }
    }

    /// ⌘C depuis la fenêtre de relecture : le texte retouché est déjà dans le
    /// presse-papiers, le collage est laissé à l'utilisateur. Sans ce chemin, la
    /// fenêtre resterait ouverte et l'état `reviewing` bloquerait la dictée suivante.
    func finishReviewByCopy(_ request: ReviewRequest, edited: String) {
        let text = edited.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? request.text
            : edited

        if text != request.text {
            let learned = submitStyleCorrection(
                original: request.text,
                corrected: text,
                profileName: request.profileName
            )
            if learned > 0 {
                Log.learning.notice("relecture : \(learned) correction(s) relevée(s)")
            }
        }

        record(transcript: text, profileName: request.profileName)
        request.application?.activate()
        state = .idle
        Log.learning.debug("relecture copiée")
    }

    /// Échap ou fermeture : rien n'est collé, mais la dictée reste à
    /// l'historique — elle se récupère par « Reprendre… » ou la copie manuelle.
    func cancelReview(_ request: ReviewRequest) {
        record(transcript: request.text, profileName: request.profileName)
        state = .idle
        Log.learning.debug("relecture annulée")
    }

    var styleObservationStore: StyleObservationStore { learning.store }

    @discardableResult
    func submitStyleCorrection(original: String, corrected: String, profileName: String) -> Int {
        learning.record(
            original: original,
            corrected: corrected,
            profileName: profileName,
            enabled: preferences.styleLearningEnabled,
            lexicon: lexiconStore.lexicon
        )
    }

    var styleProposals: [StyleObservation] { learning.proposals }

    func acceptStyleProposal(_ observation: StyleObservation, as kind: StyleSuggestionKind) {
        switch learning.accept(observation, as: kind) {
        case .lexicon(let entendu, let corrige):
            var lexicon = lexiconStore.lexicon
            lexicon.upsert(LexiconEntry(entendu: entendu, corrige: corrige))
            updateLexicon(lexicon)
        case .style(let profileName, let note):
            guard var profile = profileStore.profiles.profile(named: profileName) else { break }
            if !profile.styleNotes.contains(note) {
                profile.styleNotes.append(note)
                updateProfile(profile)
            }
        }
    }

    func dismissStyleProposal(_ observation: StyleObservation) {
        learning.dismiss(observation)
    }

    // MARK: - Mode document (l'Architecte)

    /// Une session de document occupe le moteur Whisper et le micro : la dictée
    /// ordinaire est suspendue tant qu'elle dure.
    private(set) var architectActive = false

    /// L'application est-elle accaparée, par une dictée ou par une session de
    /// document ? C'est la garde des boutons du panneau.
    var isOccupied: Bool { state.isBusy || architectActive }

    /// Assemble une session de document, ou refuse si quelque chose tourne déjà.
    ///
    /// Le moteur est celui en service : Apple donne le plan au fil de la parole,
    /// Whisper reste disponible pour le vocabulaire technique.
    func makeArchitectSession(
        restoring snapshot: ArchitectSnapshot? = nil,
        persistURL: URL? = nil
    ) -> ArchitectSession? {
        guard !isOccupied else { return nil }
        architectActive = true
        return ArchitectSession(
            engine: engine,
            corrector: corrector,
            pipeline: pipeline,
            contextualStrings: contextualStrings,
            locale: locale,
            inputDeviceUID: preferences.inputDeviceUID,
            snapshot: snapshot,
            persistURL: persistURL,
            onRelease: { [weak self] in self?.architectActive = false }
        )
    }

    func imputeDossierSession() {
        do {
            try dossiers.impute()
        } catch {
            Log.goldocab.error("imputation impossible : \(error.localizedDescription, privacy: .public)")
            lastFailure = "imputation : \(error.localizedDescription)"
        }
    }

    private var relay: BufferRelay?

    /// Ouverture du moteur en cours, rendant `true` si la session a bien démarré.
    ///
    /// La capture commence sans l'attendre, pour ne pas perdre le début de la phrase,
    /// mais la fin de dictée, elle, doit l'attendre : finaliser un moteur qui n'a pas
    /// encore ouvert sa session lève `notStarted` et perd tout ce qui a été dit.
    private var opening: Task<Bool, Never>?

    /// Format réclamé par le moteur, interrogé une seule fois puis conservé : le
    /// résoudre à chaque dictée retarderait le démarrage de la capture.
    private var audioFormat: AVAudioFormat?

    /// Raccourci actuellement armé, affiché dans le menu.
    private(set) var trigger: HotkeyTrigger = .commandShiftJ

    /// Le raccourci tel qu'il s'écrit, dans la disposition du clavier branché.
    var triggerDisplayString: String { trigger.displayString(keyLabel: KeyLabels.label) }

    /// Le tap clavier a-t-il pu être armé ? Un échec vient d'une autorisation
    /// refusée, et il est muet : sans ce drapeau, le raccourci ne répondrait plus
    /// sans que rien ne l'explique.
    private(set) var hotkeyArmed = true

    /// Enregistre le raccourci global. À appeler une fois l'application lancée.
    func activate(trigger: HotkeyTrigger? = nil) {
        hotkey.onEvent = { [weak self] isDown, at in
            MainActor.assumeIsolated {
                self?.handleHotkey(isDown: isDown, at: at)
            }
        }

        let trigger = trigger ?? preferences.hotkeyTrigger
        resolver = TriggerResolver(holdThreshold: preferences.holdThreshold)
        self.trigger = trigger
        hotkeyArmed = hotkey.register(trigger)
        if !hotkeyArmed {
            state = .failed("raccourci inactif — autorisez la surveillance de l'entrée")
        }

        lexiconStore.load()
        repliqueStore.load()
        profileStore.load()
        learning.store.load()
        ArchitectSession.purgeStaleSessions()

        // L'unité d'entrée audio est mise en place tout de suite, mais pas dans la
        // foulée du lancement : elle coûte un quart de seconde, et le raccourci a
        // priorité. Deux secondes plus tard, plus personne n'attend, et la première
        // dictée ne paiera plus ce que toutes les suivantes s'épargnent déjà.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            self?.capture.warmUp()
        }
        reloadPipeline()
        dossiers.restoreRelaunchHandoff()
        capture.preferredDeviceUID = preferences.inputDeviceUID

        // Le préchargement du modèle Ollama est déterminant : à froid, la première
        // correction demande près de huit secondes et serait abandonnée pour rien.
        let thresholds = CorrectionGuard.Thresholds(retention: preferences.correctionRetention)
        let primary = preferences.correctionPrimary
        let fallback = preferences.correctionFallback
        Task { [corrector] in
            await corrector.setThresholds(thresholds)
            await corrector.setOrder(primary: primary, fallback: fallback)
            await corrector.warmUp()
        }

        // Le moteur de transcription mérite le même égard, et plus encore : il est
        // sur le chemin de la première dictée, celle où l'on juge l'application.
        // Seul celui qui est en service est préchauffé, il serait absurde de lancer
        // un démon Python pour un utilisateur resté sur le moteur d'Apple.
        if preferences.engineIdentifier == whisperEngine.identifier {
            Task { [whisperEngine] in await whisperEngine.warmUp() }
        }

        // Modèle Whisper et moteur retenus lors de la session précédente.
        if preferences.whisperModel != whisperEngine.model {
            whisperEngine = WhisperMLXEngine(model: preferences.whisperModel)
        }
        if preferences.engineIdentifier == "whisper-mlx" {
            select(engine: whisperEngine)
        }

        // Les autorisations ne sont pas demandées ici. Deux fenêtres système au
        // lancement se referment sans être lues ; elles relèvent de la fenêtre
        // d'accueil, qui les présente une par une et en montre l'état. Le manque est
        // ensuite signalé en permanence par le bandeau du menu.
        Log.lifecycle.notice(
            "autorisations — micro : \(self.microphoneGranted, privacy: .public), accessibilité : \(self.accessibilityGranted, privacy: .public), surveillance de l'entrée : \(self.inputMonitoringGranted, privacy: .public)"
        )

        // Le modèle de langue peut demander un téléchargement au premier lancement.
        // L'anticiper évite que la première dictée échoue faute de modèle.
        let locale = self.locale
        // Le moteur interrogé est celui en service, et non `appleEngine` : la
        // restauration du moteur enregistré a déjà eu lieu quelques lignes plus haut,
        // et sa propre résolution de format aboutit plus vite que celle-ci. Demander
        // le format d'Apple ici revenait à l'écraser systématiquement, et à livrer de
        // l'Int16 à un moteur qui attend du mono virgule flottante.
        let active = engine
        let identifier = currentEngineIdentifier
        Task { [weak self] in
            do {
                try await AppleSpeechEngine.prepareAssets(for: locale)
            } catch {
                await self?.reportPreparationFailure(error.localizedDescription)
            }
            // Le format doit être connu AVANT la première capture : livrer au moteur
            // un format autre que celui qu'il réclame ne produit pas une erreur mais
            // une assertion fatale dans le framework Speech.
            let format = await active.preferredAudioFormat()
            Log.engine.notice("format du moteur \(identifier, privacy: .public) : \(format, privacy: .public)")
            await self?.cache(audioFormat: format, from: identifier)
        }
    }

    private func reportPreparationFailure(_ reason: String) {
        if case .idle = state { state = .failed(reason) }
    }

    func deactivate() {
        hotkey.unregister()
    }

    /// Change le raccourci et le réarme aussitôt.
    func updateTrigger(_ trigger: HotkeyTrigger) {
        preferences.hotkeyTrigger = trigger
        self.trigger = trigger
        hotkeyArmed = hotkey.register(trigger)
        if hotkeyArmed, case .failed = state { state = .idle }
    }

    // MARK: - Geste de déclenchement

    /// - Parameter at: instant du geste, relevé par le moniteur au moment où
    ///   l'événement est survenu. Le relever ici fausserait la durée d'appui du
    ///   temps de remise, et un tapotement bref serait pris pour un appui maintenu.
    private func handleHotkey(isDown: Bool, at: TimeInterval) {
        let decision = isDown ? resolver.keyDown(at: at) : resolver.keyUp(at: at)

        Log.hotkey.debug("décision : \(String(describing: decision), privacy: .public)")

        switch decision {
        case .start(let mode):
            beginCapture(mode: mode)
        case .switchToToggle:
            if case .recording = state { state = .recording(.toggle) }
        case .stop:
            endCapture()
        case .none:
            break
        }
    }

    /// Démarre ou arrête une dictée depuis le menu.
    ///
    /// Le clic a mis Goldodict au premier plan, alors que la dictée vise l'application
    /// où l'utilisateur écrivait — celle-là même que `beginCapture` interroge pour
    /// choisir le profil, et celle où le texte sera collé. On la réactive donc avant
    /// de démarrer, puis on laisse à macOS le temps de la bascule : sans ce délai, le
    /// texte atterrirait dans le vide.
    func toggleFromMenu(returningTo application: NSRunningApplication?) {
        if state.isRecording {
            resolver.reset()
            endCapture()
            return
        }
        guard !state.isBusy else { return }

        application?.activate()
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard let self, !self.state.isBusy else { return }
            self.resolver.adoptToggle()
            self.beginCapture(mode: .toggle)
        }
    }

    func applyInputDevice(_ uid: String?) {
        preferences.inputDeviceUID = uid
        capture.preferredDeviceUID = uid
    }

    private func beginCapture(mode: TriggerMode) {
        guard !isOccupied else {
            resolver.reset()
            return
        }
        guard PermissionGuard.microphoneStatus == .authorized else {
            resolver.reset()
            state = .failed("microphone non autorisé")
            Task { _ = await PermissionGuard.requestMicrophone() }
            return
        }

        // Sans format résolu, aucune capture : mieux vaut refuser cette dictée que
        // deviner. Le format est normalement connu dès le lancement.
        guard let format = audioFormat else {
            resolver.reset()
            state = .failed("moteur en cours de préparation, réessayez")
            Log.engine.error("dictée refusée : format du moteur pas encore résolu")
            return
        }

        // Le profil est arrêté ici, avant que quoi que ce soit d'autre n'ait pu
        // prendre le premier plan.
        let application = NSWorkspace.shared.frontmostApplication
        let frontmost = application?.bundleIdentifier
        activeProfile = profileStore.profiles.profile(for: frontmost)
        activeApplicationName = application?.localizedName
        activeBundleIdentifier = frontmost
        activeApplication = application
        Log.lifecycle.notice(
            "profil \(self.activeProfile.name, privacy: .public) pour \(frontmost ?? "application inconnue", privacy: .public)"
        )

        let relay = BufferRelay()
        self.relay = relay
        capture.onBuffer = { buffer in relay.push(buffer) }

        do {
            // La capture démarre sans attendre l'ouverture du moteur : le relais
            // conserve les tampons produits entre-temps.
            try capture.start(targetFormat: format)
        } catch {
            resolver.reset()
            self.relay = nil
            state = .failed(error.localizedDescription)
            return
        }

        lastFailure = nil
        overlay.inputDeviceName = AudioDevices.name(ofUID: preferences.inputDeviceUID)
            ?? AudioDevices.defaultInputName
        overlay.partialText = nil
        state = .recording(mode)
        play(.start)
        captureStartedAt = Date()
        drawQuote()
        Log.audio.notice("capture démarrée (\(String(describing: mode), privacy: .public))")

        // Les lectures d'Accessibilité viennent après l'ouverture du micro, et non
        // avant. Chacune s'accorde un quart de seconde d'attente avant d'abandonner
        // (`AXUIElementSetMessagingTimeout`), et il y en a plusieurs : tout ce qui
        // était dit pendant ce temps se perdait, alors que le premier mot est
        // précisément ce qu'on tient à ne pas perdre.
        //
        // Rien n'est sacrifié à les décaler. Le relais conserve les tampons produits
        // pendant qu'elles s'exécutent, et le vocabulaire n'est gelé que plus bas :
        // le dossier détecté nourrit toujours cette dictée-ci, pas la suivante.
        if preferences.dossierAutoDetect {
            dossiers.autoDetect(for: application)
        }
        learning.observeLastInsertionIfPossible(
            frontmost: frontmost,
            enabled: preferences.styleLearningEnabled,
            observeField: preferences.styleObservationAuto,
            lexicon: lexiconStore.lexicon
        )
        if let start = captureStartedAt {
            dossiers.markSessionStart(at: start)
        }
        let engine = self.engine
        let locale = self.locale
        let strings = self.contextualStrings
        let onPartial: @Sendable (String) -> Void = { text in
            Task { @MainActor [weak self] in
                self?.overlay.partialText = text
            }
        }
        opening = Task { [weak self] in
            do {
                try await engine.start(
                    locale: locale,
                    contextualStrings: strings,
                    onPartialText: onPartial
                )
                Log.engine.notice("moteur ouvert")
                relay.attach(to: engine)
                return true
            } catch {
                Log.engine.error("ouverture du moteur : \(error.localizedDescription, privacy: .public)")
                await self?.abortCapture(reason: error.localizedDescription)
                return false
            }
        }
    }

    private func endCapture() {
        let samples = capture.sampleCount
        capture.stop()
        capture.onBuffer = nil
        play(.stop)
        state = .transcribing
        if let start = captureStartedAt {
            dossiers.addCaptureDuration(from: start)
        }
        captureStartedAt = nil
        overlay.partialText = nil
        Log.audio.debug("capture arrêtée, \(samples) échantillons accumulés")

        let engine = self.engine
        let relay = self.relay
        let opening = self.opening
        self.relay = nil
        self.opening = nil

        Task { [weak self] in
            // Une dictée peut se terminer avant que le moteur ait fini d'ouvrir sa
            // session : l'ouverture est asynchrone et prend d'ordinaire une dizaine
            // de millisecondes, mais soixante-dix quand le service traîne. Finaliser
            // sans l'attendre lève `notStarted` et perd la dictée. Attendre ne coûte
            // rien, le relais conserve les tampons produits pendant ce temps.
            //
            // Une ouverture ratée a déjà été signalée par `abortCapture` et n'a
            // laissé aucune session : il n'y a plus rien à finaliser.
            guard await opening?.value ?? true else { return }

            await relay?.drain()
            Log.engine.debug("relais vidé, finalisation du moteur")
            do {
                let text = try await engine.finish()
                Log.engine.notice("transcription : \(text.count) caractères")
                await self?.deliver(text)
            } catch {
                Log.engine.error("transcription : \(error.localizedDescription, privacy: .public)")
                await self?.abortCapture(reason: error.localizedDescription)
            }
        }
    }

    private func deliver(_ text: String) async {
        let profile = activeProfile
        let prepared = pipeline.prepare(text, profile: profile)
        guard !prepared.isEmpty else {
            state = .idle
            return
        }

        var corrected = prepared
        var note: String?

        if profile.correctText, preferences.correctionEnabled {
            state = .correcting
            let outcome = await corrector.correct(prepared, styleNotes: profile.styleNotes)
            corrected = outcome.text
            note = outcome.note
        }

        let cleaned = pipeline.finalize(corrected, profile: profile)
        guard !cleaned.isEmpty else {
            state = .idle
            return
        }

        // Relecture à la volée : le texte s'arrête dans la fenêtre flottante,
        // le collage attendra la touche Entrée.
        if preferences.reviewBeforePaste, let presentReview {
            state = .reviewing
            presentReview(ReviewRequest(
                text: cleaned,
                profileName: profile.name,
                note: note,
                application: activeApplication,
                applicationName: activeApplicationName,
                bundleIdentifier: activeBundleIdentifier
            ))
            return
        }

        state = .injecting
        let outcome = await TextInjector.inject(
            cleaned,
            autoPaste: preferences.autoPaste,
            restorePasteboard: preferences.restorePasteboard
        )
        record(transcript: cleaned, profileName: profile.name)

        if outcome != .pasted {
            state = .failed("texte copié, Accessibilité non autorisée")
        } else {
            learning.rememberInsertion(
                text: cleaned,
                bundleIdentifier: activeBundleIdentifier,
                profileName: profile.name
            )
            state = .inserted(
                Insertion(
                    characters: cleaned.count,
                    application: activeApplicationName,
                    note: note
                )
            )
        }
    }

    // MARK: - Import de fichier

    /// Transcrit un fichier audio existant avec le moteur actuellement sélectionné,
    /// sans passer par le microphone ni par l'insertion.
    ///
    /// Reprend la chaîne de `deliver(_:)` — préparation, correction, finalisation —
    /// mais s'arrête au texte : un import n'a pas d'application cible arrêtée au
    /// clic, et son résultat va dans une fenêtre, pas dans l'historique des dictées
    /// collées.
    func transcribeAudioFile(at url: URL) async throws -> String {
        guard !isOccupied else {
            throw AudioImportError.busy
        }

        Log.importing.notice("import démarré : \(url.lastPathComponent, privacy: .public)")

        let engine = self.engine
        let format = await engine.preferredAudioFormat()
        let locale = self.locale
        let strings = self.contextualStrings

        try await engine.start(locale: locale, contextualStrings: strings, onPartialText: nil)
        do {
            try await AudioFileReader.read(fileAt: url, targetFormat: format) { buffer in
                await engine.feed(buffer)
            }
        } catch {
            await engine.cancel()
            Log.importing.error("lecture du fichier : \(error.localizedDescription, privacy: .public)")
            throw error
        }
        let text = try await engine.finish()
        Log.importing.notice("transcription : \(text.count) caractères")

        let profile = AppProfile.redaction
        let prepared = pipeline.prepare(text, profile: profile)
        guard !prepared.isEmpty else { return "" }

        var corrected = prepared
        if profile.correctText, preferences.correctionEnabled {
            let outcome = await corrector.correct(prepared, styleNotes: profile.styleNotes)
            corrected = outcome.text
        }
        return pipeline.finalize(corrected, profile: profile)
    }

    private func abortCapture(reason: String) {
        capture.stop()
        capture.onBuffer = nil
        relay?.cancel()
        relay = nil
        resolver.reset()
        Task { [engine] in await engine.cancel() }
        state = .failed(reason)
    }

    /// Retient le format, sauf s'il vient d'un moteur qui n'est plus en service.
    ///
    /// Deux résolutions peuvent être en vol en même temps, celle du lancement et
    /// celle d'un changement de moteur, et rien ne garantit leur ordre d'arrivée.
    /// Sans cette garde, la dernière arrivée gagne, fût-elle périmée.
    private func cache(audioFormat: AVAudioFormat, from identifier: String) {
        guard identifier == currentEngineIdentifier else {
            Log.engine.notice(
                "format de \(identifier, privacy: .public) écarté, le moteur en service est \(self.currentEngineIdentifier, privacy: .public)"
            )
            return
        }
        self.audioFormat = audioFormat
    }

    // MARK: - Historique

    func record(transcript: String, profileName: String = AppProfile.redaction.name) {
        guard !transcript.isEmpty else { return }
        lastTranscript = transcript
        history.insert(Dictation(text: transcript, date: Date(), profileName: profileName), at: 0)
        if history.count > historyLimit {
            history.removeLast(history.count - historyLimit)
        }
    }

    func clearHistory() {
        history.removeAll()
        lastTranscript = ""
    }

    // MARK: - Retour sonore

    private enum Cue: String {
        case start = "Tink"
        case stop = "Pop"
    }

    private func play(_ cue: Cue) {
        guard preferences.soundCues else { return }
        NSSound(named: NSSound.Name(cue.rawValue))?.play()
    }
}
