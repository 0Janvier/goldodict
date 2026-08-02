import AppKit
import GoldodictCore
import SwiftUI

/// Fenêtre du premier lancement.
///
/// Elle existe pour une raison précise : sans les trois autorisations système,
/// Goldodict n'entend rien, ne colle rien ou ne répond pas au raccourci, et rien
/// dans l'interface ne le dit au moment où cela se produit. Les demander une par
/// une, avec l'état visible en permanence, vaut mieux que trois fenêtres système
/// surgies au lancement, que l'utilisateur écarte sans les lire.
@MainActor
final class OnboardingWindowController {

    private var window: NSWindow?
    private let controller: DictationController

    init(controller: DictationController) {
        self.controller = controller
    }

    func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 540, height: 520),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Bienvenue dans Goldodict"
            window.isReleasedWhenClosed = false
            window.center()
            window.contentView = NSHostingView(
                rootView: OnboardingView(controller: controller) { [weak self] in
                    self?.window?.close()
                }
            )
            self.window = window
        }

        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct OnboardingView: View {

    let controller: DictationController
    let finish: () -> Void

    @State private var step = 0
    /// Les autorisations changent dans les Réglages Système, hors de portée de
    /// SwiftUI : sans relevé périodique, la fenêtre continuerait d'afficher « refusé »
    /// une fois l'utilisateur revenu.
    @State private var pulse = 0
    @State private var trial = ""
    @FocusState private var trialFocused: Bool

    private static let steps = ["Autorisations", "Moteur", "Essai"]

    var body: some View {
        VStack(spacing: 0) {
            progress

            Group {
                switch step {
                case 0: permissionsStep
                case 1: engineStep
                default: trialStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(24)

            footer
        }
        .frame(width: 540, height: 520)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            pulse &+= 1
        }
    }

    // MARK: - Progression

    private var progress: some View {
        HStack(spacing: 6) {
            ForEach(Array(Self.steps.enumerated()), id: \.offset) { index, title in
                Text(title)
                    .font(.system(size: 11, weight: index == step ? .semibold : .regular))
                    .foregroundStyle(index == step ? Color.primary : Color.secondary)
                if index < Self.steps.count - 1 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 6)
    }

    // MARK: - Étape 1

    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Title("Trois autorisations, une seule fois")
            Lead("La première laisse Goldodict entendre votre voix, la deuxième lui laisse déposer le texte dans le document où vous écrivez, la troisième lui laisse reconnaître votre raccourci.")

            PermissionRow(
                symbol: "mic.fill",
                title: "Microphone",
                detail: "Sans elle, aucune dictée n'est possible.",
                granted: controller.microphoneGranted,
                action: { Task { _ = await PermissionGuard.requestMicrophone() } }
            )

            PermissionRow(
                symbol: "hand.raised.fill",
                title: "Accessibilité",
                detail: "Elle autorise le collage automatique. Sans elle, le texte est copié et il faut le coller à la main.",
                granted: controller.accessibilityGranted,
                action: {
                    // La fenêtre système n'apparaît qu'une fois par signature ; ensuite
                    // seul le panneau des Réglages permet de revenir en arrière.
                    if !PermissionGuard.hasAccessibility(prompting: true) {
                        PermissionGuard.openSettings(for: .accessibility)
                    }
                }
            )

            PermissionRow(
                symbol: "keyboard",
                title: "Surveillance de l'entrée",
                detail: "Elle autorise la lecture du raccourci, y compris la distinction entre les touches de gauche et de droite. Sans elle, la dictée ne se déclenche que depuis la barre des menus.",
                granted: controller.inputMonitoringGranted,
                action: {
                    if !PermissionGuard.requestInputMonitoring() {
                        PermissionGuard.openSettings(for: .inputMonitoring)
                    }
                }
            )

            if !controller.accessibilityGranted {
                Button("Continuer sans coller automatiquement") {
                    controller.preferences.autoPaste = false
                    step = 1
                }
                .buttonStyle(.link)
                .font(.system(size: 12))
            }
        }
    }

    // MARK: - Étape 2

    private var engineStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Title("Quel moteur de transcription ?")
            Lead("Le choix se change à tout moment depuis la barre des menus.")

            EngineCard(
                title: controller.appleEngine.displayName,
                detail: "Transcrit pendant que vous parlez, le texte arrive presque aussitôt. Modèle du système, aucun téléchargement.",
                selected: controller.currentEngineIdentifier == "apple"
            ) {
                controller.selectEngine(identifier: "apple")
            }

            EngineCard(
                title: controller.whisperEngine.displayName,
                detail: "Transcrit une fois la phrase finie, avec une meilleure tenue sur le vocabulaire juridique. Compte quelques secondes de plus.",
                selected: controller.currentEngineIdentifier == "whisper-mlx",
                unavailable: WhisperMLXEngine.unavailabilityReason
            ) {
                controller.selectEngine(identifier: "whisper-mlx")
            }
        }
    }

    // MARK: - Étape 3

    private var trialStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Title("Essayez maintenant")
            Lead("Cliquez dans le cadre, maintenez le raccourci et dictez une phrase. Relâchez : le texte s'écrit ici même.")

            HStack(spacing: 8) {
                ForEach(controller.trigger.keyCaps(keyLabel: KeyLabels.label), id: \.self) { key in
                    Text(key)
                        .font(.system(size: 15, weight: .medium))
                        .frame(minWidth: 30, minHeight: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.primary.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(Color.primary.opacity(0.12))
                        )
                }
                Text("maintenu pour parler, bref pour basculer")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            TextEditor(text: $trial)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(height: 120)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(trialFocused ? Color.accentColor : Color.primary.opacity(0.12))
                )
                .focused($trialFocused)

            if !controller.preferences.autoPaste {
                Text("Le collage automatique est désactivé : le texte ira dans le presse-papiers, à coller par ⌘V.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { trialFocused = true }
    }

    // MARK: - Pied

    private var footer: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                if step > 0 {
                    Button("Retour") { step -= 1 }
                }
                Spacer()
                if step < 2 {
                    Button("Continuer") { step += 1 }
                        .keyboardShortcut(.defaultAction)
                        .disabled(step == 0 && !controller.microphoneGranted)
                } else {
                    Button("Terminer", action: finish)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
    }
}

// MARK: - Éléments

private struct Title: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).font(.system(size: 19, weight: .semibold))
    }
}

private struct Lead: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct PermissionRow: View {
    let symbol: String
    let title: String
    let detail: String
    let granted: Bool
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15))
                .foregroundStyle(granted ? Color.green : Color.secondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if granted {
                Label("Autorisé", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.green)
                    .labelStyle(.titleAndIcon)
            } else {
                Button("Autoriser", action: action)
                    .controlSize(.small)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.04))
        )
    }
}

private struct EngineCard: View {
    let title: String
    let detail: String
    let selected: Bool
    /// Ce qui empêche ce moteur de tourner ici, `nil` s'il est prêt. Proposer un
    /// moteur qu'on ne peut pas lancer revient à laisser l'utilisateur découvrir
    /// l'absence à sa première dictée, quand il est trop tard pour la rattraper.
    var unavailable: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 13, weight: .medium))
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let unavailable {
                        Label(unavailable, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 2)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(selected ? Color.accentColor.opacity(0.10) : Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(selected ? Color.accentColor.opacity(0.5) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(unavailable != nil)
        .opacity(unavailable == nil ? 1 : 0.65)
    }
}
