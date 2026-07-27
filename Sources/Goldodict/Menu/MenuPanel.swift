import AppKit
import GoldodictCore
import SwiftUI

/// Panneau déroulé par l'icône de la barre des menus.
///
/// Il répond à trois questions, dans cet ordre : l'application est-elle prête,
/// comment lancer une dictée, et où est passé ce que je viens de dicter. Tout le
/// reste — lexique, profils, seuils — vit dans les réglages, où l'on va rarement.
struct MenuPanel: View {

    let controller: DictationController
    let host: MenuBarController

    private static let width: CGFloat = 380

    @State private var anticipatedProfile: (name: String, application: String?)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            failure
            permissions
            actions
            history
            footer
        }
        .frame(width: Self.width)
        // Le panneau reste en mémoire d'une ouverture à l'autre : sans ce rappel,
        // l'application relevée par `host` resterait celle de la fois précédente.
        .onAppear { anticipatedProfile = host.anticipatedProfile }
    }

    // MARK: - En-tête

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Alignement en haut, et non centré : sur un libellé de deux lignes, une
            // pastille centrée verticalement flotterait entre les deux.
            HStack(alignment: .top, spacing: 8) {
                Circle()
                    .fill(stateTint)
                    .frame(width: 8, height: 8)
                    .padding(.top, 4)
                // Le libellé passe avant le nom de l'application : « 312 signes ·
                // Microsoft Word inséré » est ce que l'utilisateur vient lire, et
                // c'est « Goldodict » qui doit céder la largeur, jamais l'inverse.
                Text(controller.state.label)
                    .font(.system(size: 13, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
                Spacer(minLength: 4)
                Text("Goldodict")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .layoutPriority(0)
            }
            // Le profil que la prochaine dictée va cibler, utile seulement avant de
            // parler : une fois lancée, la dictée porte déjà le profil arrêté au clic.
            if controller.state == .idle, let anticipatedProfile {
                Text(profileLine(anticipatedProfile))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 16)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private func profileLine(_ profile: (name: String, application: String?)) -> String {
        guard let application = profile.application, !application.isEmpty else {
            return "Profil \(profile.name)"
        }
        return "Profil \(profile.name) · \(application)"
    }

    private var stateTint: Color {
        switch controller.state {
        case .idle: return .green
        case .recording: return .red
        case .transcribing, .correcting, .injecting: return .accentColor
        case .inserted(let insertion): return insertion.note == nil ? .green : .orange
        case .failed: return .orange
        }
    }

    // MARK: - Dernier échec

    /// Contrairement aux bandeaux d'autorisation, celui-ci n'est pas permanent : il
    /// rapporte un événement daté, pas un état de fait, et se referme donc de deux
    /// façons — une nouvelle dictée qui réussit, ou l'utilisateur qui l'écarte.
    @ViewBuilder
    private var failure: some View {
        if let message = controller.lastFailure {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.system(size: 11))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 6) {
                    Button("Réessayer", action: host.dictate)
                        .buttonStyle(.link)
                        .font(.system(size: 11, weight: .medium))
                    Button(action: controller.dismissFailure) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
        }
    }

    // MARK: - Autorisations

    /// Le refus de l'Accessibilité est le seul défaut que l'application ne peut pas
    /// signaler au moment où il compte : le texte est copié, rien n'est collé, et
    /// l'utilisateur croit avoir mal dicté. Le bandeau reste donc en permanence.
    @ViewBuilder
    private var permissions: some View {
        if !controller.microphoneGranted {
            Banner(
                symbol: "mic.slash.fill",
                message: "Micro refusé. Aucune dictée n'est possible.",
                action: "Ouvrir",
                perform: host.openMicrophoneSettings
            )
        }
        if !controller.accessibilityGranted {
            Banner(
                symbol: "exclamationmark.triangle.fill",
                message: "Accessibilité refusée. Le texte est copié, pas collé.",
                action: "Ouvrir",
                perform: host.openAccessibilitySettings
            )
        }
    }

    // MARK: - Dictée et moteur

    private var actions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: host.dictate) {
                HStack(spacing: 8) {
                    Image(systemName: controller.state.isRecording ? "stop.fill" : "mic.fill")
                    Text(controller.state.isRecording ? "Arrêter la dictée" : "Dicter maintenant")
                    Spacer(minLength: 8)
                    Text(controller.combination.displayString)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(controller.state.isRecording ? .red : .accentColor)
            .disabled(controller.state.isBusy && !controller.state.isRecording)

            // Seule preuve, pour qui a rouvert le panneau en cours de dictée, que le
            // micro entend — même lecture que la pastille flottante.
            if controller.state.isRecording {
                MenuLevelMeter(level: { controller.currentLevel })
            } else {
                Text("Appui bref pour basculer, maintenu pour parler.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Text("Moteur")
                    .font(.system(size: 12))
                Picker("", selection: engineSelection) {
                    Text(controller.appleEngine.displayName).tag("apple")
                    Text(controller.whisperEngine.displayName).tag("whisper-mlx")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(controller.state.isBusy)
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
    }

    private var engineSelection: Binding<String> {
        Binding(
            get: { controller.currentEngineIdentifier },
            set: { controller.selectEngine(identifier: $0) }
        )
    }

    // MARK: - Historique

    @ViewBuilder
    private var history: some View {
        Divider()

        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("DERNIÈRES DICTÉES")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                Spacer()
                if !controller.history.isEmpty {
                    Button("Effacer") { controller.clearHistory() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)

            if controller.history.isEmpty {
                Text("Rien encore. Le texte dicté restera ici jusqu'à la fermeture.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
            } else {
                // Cinq lignes : au-delà, le panneau dépasse la moitié de l'écran et
                // l'historique complet n'a de toute façon pas d'usage.
                ForEach(controller.history.prefix(5)) { entry in
                    HistoryRow(entry: entry)
                }
                .padding(.horizontal, 8)
            }
        }
        .padding(.bottom, 8)
    }

    // MARK: - Pied

    private var footer: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 0) {
                FooterButton(title: "Réglages…", symbol: "gearshape", perform: host.openSettings)
                Spacer()
                FooterButton(title: "Quitter", symbol: "power", perform: host.quit)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
    }
}

/// Bandeau d'alerte, réservé à ce qui empêche l'application de fonctionner.
private struct Banner: View {
    let symbol: String
    let message: String
    let action: String
    let perform: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 11))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button(action, action: perform)
                .buttonStyle(.link)
                .font(.system(size: 11, weight: .medium))
        }
        .padding(10)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }
}

/// Une dictée passée. Un clic la remet dans le presse-papiers : c'est le seul geste
/// utile ici, la dictée étant déjà partie dans le document.
private struct HistoryRow: View {
    let entry: DictationController.Dictation

    @State private var hovering = false
    @State private var copied = false

    var body: some View {
        Button(action: copy) {
            HStack(alignment: .top, spacing: 8) {
                Text(entry.time)
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                Text(entry.text)
                    .font(.system(size: 12))
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 4)
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 10))
                    .foregroundStyle(copied ? Color.green : Color.secondary)
                    .opacity(copied || hovering ? 1 : 0)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(hovering ? Color.primary.opacity(0.07) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.text, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }
}

/// Vumètre compact du panneau. Même calcul que la pastille flottante
/// (`AudioLevel.normalized`/`smoothed`, dans `GoldodictCore`), mais indépendant d'elle :
/// le panneau peut rester ouvert pendant une dictée sans dépendre de la pastille.
private struct MenuLevelMeter: View {
    let level: () -> Float

    private static let barCount = 5

    @State private var bars: [Float] = Array(repeating: 0, count: MenuLevelMeter.barCount)
    @State private var ticker: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(bars.enumerated()), id: \.offset) { _, value in
                Capsule()
                    .fill(Color.red.opacity(0.35 + Double(value) * 0.65))
                    .frame(width: 3, height: 4 + CGFloat(value) * 14)
            }
        }
        .frame(height: 18)
        .animation(.linear(duration: 0.08), value: bars)
        .onAppear(perform: start)
        .onDisappear(perform: stop)
    }

    private func start() {
        ticker = Task {
            var smoothed: Float = 0
            while !Task.isCancelled {
                smoothed = AudioLevel.smoothed(previous: smoothed, target: AudioLevel.normalized(rms: level()))
                bars.removeFirst()
                bars.append(smoothed)
                try? await Task.sleep(for: .milliseconds(80))
            }
        }
    }

    private func stop() {
        ticker?.cancel()
        ticker = nil
    }
}

private struct FooterButton: View {
    let title: String
    let symbol: String
    let perform: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: perform) {
            Label(title, systemImage: symbol)
                .font(.system(size: 12))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(hovering ? Color.primary.opacity(0.07) : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
