import AppKit
import GoldodictCore
import SwiftUI

/// Enregistrement du raccourci : l'utilisateur fait le geste, l'application le lit.
///
/// Aucun sélecteur de touche par touche. Un raccourci se décrit mal et se montre
/// bien, et c'est le seul moyen de savoir laquelle des deux touches ⌘ a servi : le
/// côté ne se choisit pas dans une liste, il se prouve en appuyant.
struct HotkeyRecorder: View {

    let controller: DictationController

    @State private var kind: Kind = .combination
    @State private var lateralized = true
    @State private var monitor: Any?
    @State private var captured: HotkeyTrigger?

    enum Kind: String, CaseIterable, Identifiable {
        case combination, modifierOnly, doubleTap

        var id: String { rawValue }

        var label: String {
            switch self {
            case .combination: return "Combinaison"
            case .modifierOnly: return "Modificateur seul"
            case .doubleTap: return "Double appui"
            }
        }

        var hint: String {
            switch self {
            case .combination: return "Des modificateurs et une touche, ⌘⇧J par exemple."
            case .modifierOnly: return "Une seule touche modificatrice, maintenue. Frapper une autre touche pendant ce temps annule la dictée : le raccourci reste utilisable."
            case .doubleTap: return "Deux appuis rapprochés sur une touche modificatrice, dans les trois cents millisecondes."
            }
        }
    }

    private var isRecording: Bool { monitor != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Déclencheur", selection: kindBinding) {
                ForEach(Kind.allCases) { kind in
                    Text(kind.label).tag(kind)
                }
            }
            .pickerStyle(.radioGroup)

            Text(kind.hint)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Text(isRecording ? "Faites le geste…" : controller.triggerDisplayString)
                    .font(.system(size: 15, weight: .medium))
                    .monospacedDigit()
                    .frame(minWidth: 120, alignment: .leading)
                    .foregroundStyle(isRecording ? .secondary : .primary)

                Button(isRecording ? "Annuler" : "Modifier") {
                    isRecording ? stop() : start()
                }
                Spacer()
            }

            Toggle("Distinguer les touches de gauche et de droite", isOn: lateralBinding)
                .disabled(isRecording)

            if !controller.hotkeyArmed {
                Label(
                    "Le raccourci n'est pas actif. Autorisez Goldodict dans Confidentialité et sécurité, rubrique Surveillance de l'entrée, puis relancez l'application.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }
        }
        .onDisappear(perform: stop)
    }

    // MARK: - Réglages annexes

    private var kindBinding: Binding<Kind> {
        Binding(
            get: { kind },
            set: { newValue in
                stop()
                kind = newValue
            }
        )
    }

    /// Retirer la latéralité ne demande pas de refaire le geste : les côtés du
    /// raccourci en place sont simplement effacés.
    private var lateralBinding: Binding<Bool> {
        Binding(
            get: { lateralized },
            set: { newValue in
                lateralized = newValue
                guard !newValue else { return }
                controller.updateTrigger(Self.delateralized(controller.trigger))
            }
        )
    }

    private static func delateralized(_ trigger: HotkeyTrigger) -> HotkeyTrigger {
        let flat = trigger.modifiers.map { LateralModifier($0.key) }
        switch trigger {
        case .modifierOnly:
            return .modifierOnly(flat.first ?? LateralModifier(.command))
        case .doubleTap:
            return .doubleTap(flat.first ?? LateralModifier(.command))
        case .combination(_, let keyCode):
            return .combination(modifiers: flat, keyCode: keyCode)
        }
    }

    // MARK: - Capture

    /// Le moniteur est local : il ne voit que les frappes destinées à cette fenêtre,
    /// et n'a besoin d'aucune autorisation. Il rend `nil` pour que la touche
    /// enregistrée ne se propage pas aux commandes de la fenêtre.
    private func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            capture(event)
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func capture(_ event: NSEvent) {
        // Les bits latéralisés vivent dans les poids faibles du masque, que
        // `deviceIndependentFlagsMask` supprime. On lit donc le masque brut.
        let flags = UInt64(event.modifierFlags.rawValue)

        switch event.type {
        case .flagsChanged:
            guard let change = ModifierKeyCode.event(keyCode: event.keyCode, flags: flags), change.isDown else { return }
            guard kind != .combination else { return }
            let modifier = lateralized ? change.modifier : LateralModifier(change.modifier.key)
            commit(kind == .doubleTap ? .doubleTap(modifier) : .modifierOnly(modifier))

        case .keyDown:
            // Échap referme l'enregistrement sans rien changer.
            guard event.keyCode != 53 else { return stop() }
            guard kind == .combination else { return }
            let modifiers = ModifierFlags.modifiers(in: flags, lateralized: lateralized)
            // Une touche sans modificateur serait captée dans toutes les
            // applications, jusque dans un champ de saisie.
            guard !modifiers.isEmpty else { return }
            commit(.combination(modifiers: modifiers, keyCode: event.keyCode))

        default:
            break
        }
    }

    private func commit(_ trigger: HotkeyTrigger) {
        captured = trigger
        controller.updateTrigger(trigger)
        stop()
    }
}
