import GoldodictCore
import SwiftUI

@main
struct GoldodictApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    /// L'application n'a aucune fenêtre à elle : la barre des menus est un
    /// `NSStatusItem` piloté par `MenuBarController`, les réglages une fenêtre AppKit.
    /// La scène `Settings` ne sert qu'à satisfaire le protocole `App`, qui en exige
    /// une ; elle reste invisible pour une application accessoire.
    var body: some Scene {
        Settings { EmptyView() }
    }
}
