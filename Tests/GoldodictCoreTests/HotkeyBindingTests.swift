import Foundation
import Testing
@testable import GoldodictCore

@Suite("Raccourci latéralisé")
struct HotkeyBindingTests {

    // Masques tels que CoreGraphics les rapporte : bit de famille et bit latéralisé.
    private let leftCommand = ModifierFlags.command | ModifierFlags.leftCommand
    private let rightCommand = ModifierFlags.command | ModifierFlags.rightCommand
    private let leftShift = ModifierFlags.shift | ModifierFlags.leftShift
    private let rightShift = ModifierFlags.shift | ModifierFlags.rightShift

    // MARK: - Latéralité

    @Test("La touche fn n'accepte pas de côté")
    func functionHasNoSide() {
        #expect(LateralModifier(.function, .left).side == .any)
        #expect(LateralModifier(.function, .right).display == "fn")
    }

    @Test("Le bit latéralisé distingue les deux touches d'une famille")
    func sideIsRead() {
        #expect(ModifierFlags.isPressed(LateralModifier(.command, .left), in: leftCommand))
        #expect(!ModifierFlags.isPressed(LateralModifier(.command, .right), in: leftCommand))
        #expect(ModifierFlags.isPressed(LateralModifier(.command, .right), in: rightCommand))
    }

    @Test("Un côté indifférent accepte les deux touches")
    func anySideAcceptsBoth() {
        #expect(ModifierFlags.isPressed(LateralModifier(.command), in: leftCommand))
        #expect(ModifierFlags.isPressed(LateralModifier(.command), in: rightCommand))
    }

    /// Certains claviers tiers ne posent que le bit de famille. Exiger le bit
    /// latéralisé rendrait alors le raccourci impossible à déclencher.
    @Test("Sans bit latéralisé, le bit de famille suffit")
    func familyBitIsAFallback() {
        #expect(ModifierFlags.isPressed(LateralModifier(.command, .left), in: ModifierFlags.command))
        #expect(ModifierFlags.isPressed(LateralModifier(.command, .right), in: ModifierFlags.command))
    }

    @Test("La lecture d'un masque rend les modificateurs dans l'ordre du système")
    func modifiersAreOrdered() {
        let flags = leftCommand | rightShift | ModifierFlags.control | ModifierFlags.leftControl
        let read = ModifierFlags.modifiers(in: flags)
        #expect(read == [
            LateralModifier(.control, .left),
            LateralModifier(.shift, .right),
            LateralModifier(.command, .left),
        ])
    }

    @Test("Les deux touches d'une famille valent « indifférent »")
    func bothSidesCollapseToAny() {
        let flags = ModifierFlags.command | ModifierFlags.leftCommand | ModifierFlags.rightCommand
        #expect(ModifierFlags.modifiers(in: flags) == [LateralModifier(.command)])
    }

    @Test("La lecture non latéralisée efface les côtés")
    func readingCanIgnoreSides() {
        let read = ModifierFlags.modifiers(in: leftCommand | rightShift, lateralized: false)
        #expect(read == [LateralModifier(.shift), LateralModifier(.command)])
    }

    // MARK: - Codes des touches modificatrices

    @Test("Les codes de touche portent toujours le côté")
    func keyCodesAreLateralized() {
        #expect(ModifierKeyCode.decode(55) == LateralModifier(.command, .left))
        #expect(ModifierKeyCode.decode(54) == LateralModifier(.command, .right))
        #expect(ModifierKeyCode.decode(63) == LateralModifier(.function))
        #expect(ModifierKeyCode.decode(38) == nil)
    }

    /// Un `flagsChanged` ne dit pas s'il s'agit d'un appui : le masque le dit.
    @Test("L'appui et le relâchement se déduisent du masque")
    func pressAndReleaseAreDeduced() {
        #expect(ModifierKeyCode.event(keyCode: 55, flags: leftCommand)?.isDown == true)
        #expect(ModifierKeyCode.event(keyCode: 55, flags: 0)?.isDown == false)
    }

    // MARK: - Satisfaction d'une combinaison

    @Test("La combinaison exige exactement ses modificateurs")
    func combinationIsExact() {
        let trigger = HotkeyTrigger.combination(
            modifiers: [LateralModifier(.command, .left), LateralModifier(.shift)],
            keyCode: 38
        )
        #expect(trigger.isSatisfied(byFlags: leftCommand | leftShift))
        #expect(trigger.isSatisfied(byFlags: leftCommand | rightShift))
        #expect(!trigger.isSatisfied(byFlags: rightCommand | leftShift))
        #expect(!trigger.isSatisfied(byFlags: leftCommand))
    }

    /// Sans exactitude, ⌘⇧J se déclencherait aussi sur ⌃⌘⇧J, et l'utilisateur
    /// perdrait un raccourci qu'il croyait libre.
    @Test("Un modificateur surnuméraire empêche le déclenchement")
    func strayModifierBlocks() {
        let trigger = HotkeyTrigger.commandShiftJ
        #expect(trigger.isSatisfied(byFlags: leftCommand | leftShift))
        #expect(!trigger.isSatisfied(byFlags: leftCommand | leftShift | ModifierFlags.control))
        #expect(!trigger.isSatisfied(byFlags: leftCommand | leftShift | ModifierFlags.function))
    }

    @Test("Un modificateur seul se satisfait de lui-même")
    func modifierOnlyIsSatisfied() {
        let trigger = HotkeyTrigger.modifierOnly(LateralModifier(.control, .right))
        #expect(trigger.isSatisfied(byFlags: ModifierFlags.control | ModifierFlags.rightControl))
        #expect(!trigger.isSatisfied(byFlags: ModifierFlags.control | ModifierFlags.leftControl))
    }

    // MARK: - Consommation

    /// Avaler l'appui sur ⌘ le supprimerait pour tout le système.
    @Test("Seule la combinaison est retirée du flux clavier")
    func onlyCombinationsAreConsumed() {
        #expect(HotkeyTrigger.commandShiftJ.consumesEvent)
        #expect(!HotkeyTrigger.modifierOnly(LateralModifier(.command)).consumesEvent)
        #expect(!HotkeyTrigger.doubleTap(LateralModifier(.command)).consumesEvent)
    }

    // MARK: - Affichage

    @Test("Les capuchons gardent le marqueur de côté avec leur symbole")
    func keyCapsKeepSideMarkers() {
        let trigger = HotkeyTrigger.combination(
            modifiers: [LateralModifier(.command, .right), LateralModifier(.shift, .left)],
            keyCode: 38
        )
        #expect(trigger.keyCaps(keyLabel: { _ in "J" }) == ["⇧ᴸ", "⌘ᴿ", "J"])
    }

    @Test("Le double appui s'annonce comme tel")
    func doubleTapIsAnnounced() {
        let trigger = HotkeyTrigger.doubleTap(LateralModifier(.command, .right))
        #expect(trigger.displayString() == "⌘ᴿ ×2")
    }

    @Test("Un raccourci sans latéralité s'affiche comme partout ailleurs")
    func plainShortcutLooksOrdinary() {
        #expect(HotkeyTrigger.commandShiftJ.displayString(keyLabel: { _ in "J" }) == "⇧⌘J")
    }

    // MARK: - Persistance

    @Test("Le raccourci survit à un aller-retour JSON")
    func triggerRoundTrips() throws {
        let cases: [HotkeyTrigger] = [
            .commandShiftJ,
            .modifierOnly(LateralModifier(.function)),
            .doubleTap(LateralModifier(.command, .right)),
            .combination(modifiers: [LateralModifier(.control, .left)], keyCode: 49),
        ]
        for trigger in cases {
            let data = try JSONEncoder().encode(trigger)
            #expect(try JSONDecoder().decode(HotkeyTrigger.self, from: data) == trigger)
        }
    }
}
