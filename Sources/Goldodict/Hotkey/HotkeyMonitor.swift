import CoreGraphics
import Foundation
import GoldodictCore

/// Raccourci clavier global.
///
/// Carbon (`RegisterEventHotKey`) tenait ce rôle et se passait de l'autorisation
/// « Surveillance de l'entrée ». Il a été abandonné pour une raison qu'aucun
/// réglage ne contourne : il ne rapporte que des masques de famille, jamais le côté
/// du clavier, et ignore purement la touche fn. Distinguer ⌘ gauche de ⌘ droite
/// impose de lire le flux clavier, donc un `CGEventTap`.
///
/// Le tap ne retire du flux que ce qu'il doit : une combinaison, sans quoi la
/// touche s'écrirait dans le document. Jamais un modificateur seul — avaler l'appui
/// sur ⌘ le supprimerait pour tout le système.
final class HotkeyMonitor {

    /// Appelé sur la boucle principale à chaque enfoncement (`true`) et relâchement (`false`).
    /// Geste du raccourci, avec **l'instant où il s'est produit**.
    ///
    /// L'instant voyage avec l'événement plutôt que d'être relevé à l'arrivée : le
    /// destinataire est prévenu de façon différée, et sans cela le délai de remise
    /// s'ajouterait à la durée d'appui mesurée. Un tapotement bref passerait alors
    /// pour un appui maintenu.
    var onEvent: ((Bool, TimeInterval) -> Void)?

    private(set) var trigger: HotkeyTrigger?
    private(set) var isArmed = false

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    private var detector = DoubleTapDetector()

    /// Le geste est-il en cours ? Sert à n'émettre le relâchement que si l'appui a
    /// été émis, et à ne pas dupliquer un appui sur répétition automatique.
    private var isEngaged = false

    /// Une touche ordinaire a été frappée pendant qu'un modificateur était tenu :
    /// c'est un raccourci de l'utilisateur, pas une dictée. Le geste reste annulé
    /// jusqu'au relâchement complet.
    private var isCancelled = false

    /// Arme le raccourci, en remplaçant celui éventuellement actif.
    /// - Returns: `true` si le tap a pu être créé. L'échec signale une autorisation
    ///   manquante, jamais un conflit avec une autre application.
    @discardableResult
    func register(_ trigger: HotkeyTrigger) -> Bool {
        unregister()
        self.trigger = trigger
        detector = DoubleTapDetector()

        let mask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: hotkeyTapCallback,
            userInfo: context
        ) else {
            Log.hotkey.error("création du tap refusée — autorisation manquante")
            self.trigger = nil
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.tap = tap
        self.source = source
        isArmed = true
        Log.hotkey.notice("raccourci armé : \(trigger.displayString(keyLabel: KeyLabels.label), privacy: .public)")
        return true
    }

    func unregister() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
            self.tap = nil
        }
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            self.source = nil
        }
        trigger = nil
        isArmed = false
        isEngaged = false
        isCancelled = false
    }

    // MARK: - Traitement

    /// - Returns: `true` pour retirer l'événement du flux clavier.
    fileprivate func handle(type: CGEventType, event: CGEvent) -> Bool {
        // Le système désarme le tap si le rappel traîne. Le réarmer ici est la seule
        // occasion de le faire : sans cela, le raccourci cesse silencieusement de
        // répondre et rien ne le signale.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            Log.hotkey.error("tap désarmé par le système, réarmé")
            return false
        }

        guard let trigger else { return false }
        let flags = event.flags.rawValue
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))

        switch type {
        case .flagsChanged:
            return handleFlagsChanged(trigger: trigger, keyCode: keyCode, flags: flags)
        case .keyDown:
            return handleKeyDown(trigger: trigger, keyCode: keyCode, flags: flags, event: event)
        case .keyUp:
            return handleKeyUp(trigger: trigger, keyCode: keyCode)
        default:
            return false
        }
    }

    private func handleFlagsChanged(trigger: HotkeyTrigger, keyCode: UInt16, flags: UInt64) -> Bool {
        guard let change = ModifierKeyCode.event(keyCode: keyCode, flags: flags) else { return false }

        switch trigger {
        case .combination:
            // Relâcher un modificateur pendant la dictée y met fin : maintenir ⌘⇧J
            // puis lâcher ⌘ avant J doit s'arrêter là, sans quoi la dictée
            // continuerait sans que rien ne la retienne.
            if isEngaged, !change.isDown, trigger.modifiers.contains(where: { $0.key == change.modifier.key }) {
                emit(isDown: false)
            }
            return false

        case .modifierOnly(let wanted), .doubleTap(let wanted):
            guard matches(change.modifier, wanted) else {
                // Un autre modificateur s'ajoute : le geste devient un raccourci
                // ordinaire, il ne déclenchera pas de dictée.
                if change.isDown, !isEngaged { isCancelled = true }
                if !change.isDown, !hasAnyModifier(in: flags) { isCancelled = false }
                return false
            }

            if change.isDown {
                return handleTriggerKeyDown(trigger: trigger, flags: flags)
            } else {
                if isEngaged { emit(isDown: false) }
                isCancelled = false
                return false
            }
        }
    }

    private func handleTriggerKeyDown(trigger: HotkeyTrigger, flags: UInt64) -> Bool {
        guard !isEngaged else { return false }

        // Un modificateur accompagné d'un autre est un raccourci, pas une dictée.
        guard trigger.isSatisfied(byFlags: flags) else {
            isCancelled = true
            return false
        }
        isCancelled = false

        switch trigger {
        case .doubleTap:
            let now = ProcessInfo.processInfo.systemUptime
            guard detector.press(at: now) else { return false }
            emit(isDown: true)
        default:
            emit(isDown: true)
        }
        return false
    }

    private func handleKeyDown(trigger: HotkeyTrigger, keyCode: UInt16, flags: UInt64, event: CGEvent) -> Bool {
        switch trigger {
        case .combination(_, let wantedKey):
            guard keyCode == wantedKey, trigger.isSatisfied(byFlags: flags) else { return false }
            // La répétition automatique ne relance rien : le geste a déjà commencé.
            guard event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else { return true }
            emit(isDown: true)
            return true

        case .modifierOnly, .doubleTap:
            // Une frappe pendant que le modificateur est tenu : l'utilisateur
            // compose un raccourci. La dictée en cours s'arrête, le geste est annulé.
            if isEngaged { emit(isDown: false) }
            isCancelled = true
            detector.reset()
            return false
        }
    }

    private func handleKeyUp(trigger: HotkeyTrigger, keyCode: UInt16) -> Bool {
        guard case .combination(_, let wantedKey) = trigger, keyCode == wantedKey else { return false }
        if isEngaged { emit(isDown: false) }
        return true
    }

    /// Un modificateur attendu sans côté accepte les deux touches.
    private func matches(_ pressed: LateralModifier, _ wanted: LateralModifier) -> Bool {
        guard pressed.key == wanted.key else { return false }
        return wanted.side == .any || pressed.side == wanted.side
    }

    private func hasAnyModifier(in flags: UInt64) -> Bool {
        ModifierKey.allCases.contains { flags & ModifierFlags.family($0) != 0 }
    }

    private func emit(isDown: Bool) {
        guard isDown != isEngaged else { return }
        isEngaged = isDown

        // Horloge monotone, relevée ici : c'est le seul endroit qui coïncide avec
        // l'événement, la suite étant différée.
        let at = ProcessInfo.processInfo.systemUptime
        Log.hotkey.debug("événement \(isDown ? "enfoncé" : "relâché", privacy: .public)")

        // Le rappel du tap s'exécute sur la boucle principale, et doit lui rendre la
        // main immédiatement : macOS désarme un tap dont le rappel dépasse son budget
        // de temps, et les événements de cette fenêtre sont perdus. Le traitement,
        // lui, ouvre le micro et lit l'Accessibilité, ce qui se compte en centaines
        // de millisecondes. Il est donc remis au tour de boucle suivant.
        let handler = onEvent
        DispatchQueue.main.async { handler?(isDown, at) }
    }

    deinit {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
    }
}

/// Le rappel du tap est une fonction C : il ne capture rien et retrouve l'instance
/// par le pointeur d'utilisateur passé à `tapCreate`.
private let hotkeyTapCallback: CGEventTapCallBack = { _, type, event, context in
    guard let context else { return Unmanaged.passUnretained(event) }
    let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(context).takeUnretainedValue()
    if monitor.handle(type: type, event: event) {
        return nil
    }
    return Unmanaged.passUnretained(event)
}
