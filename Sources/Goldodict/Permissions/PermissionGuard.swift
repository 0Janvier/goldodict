import AVFoundation
import AppKit
import ApplicationServices

/// Autorisations système dont dépend Goldodict.
enum PermissionGuard {

    enum Kind {
        case microphone
        case accessibility
        case inputMonitoring

        var settingsURL: URL {
            switch self {
            case .microphone:
                return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
            case .accessibility:
                return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            case .inputMonitoring:
                return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
            }
        }

        var label: String {
            switch self {
            case .microphone: return "Microphone"
            case .accessibility: return "Accessibilité"
            case .inputMonitoring: return "Surveillance de l'entrée"
            }
        }
    }

    static var microphoneStatus: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }

    /// Demande l'accès au micro. Le système n'affiche la fenêtre qu'une seule fois ;
    /// ensuite, seul un passage par les Réglages peut changer la réponse.
    static func requestMicrophone() async -> Bool {
        switch microphoneStatus {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted: return false
        @unknown default: return false
        }
    }

    /// L'Accessibilité est requise pour le Cmd+V simulé qui colle le texte dicté.
    /// - Parameter prompting: affiche la fenêtre système invitant à autoriser.
    static func hasAccessibility(prompting: Bool = false) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompting]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    /// La Surveillance de l'entrée est requise pour lire le raccourci global.
    ///
    /// Elle n'a rien à voir avec l'Accessibilité : l'une laisse écrire dans les
    /// autres applications, l'autre laisse y lire le clavier. Le tap d'événements
    /// dont dépend le raccourci relève de la seconde.
    static var hasInputMonitoring: Bool { CGPreflightListenEventAccess() }

    /// La fenêtre système n'apparaît qu'une fois par signature. Ensuite, seul le
    /// panneau des Réglages permet de revenir en arrière.
    @discardableResult
    static func requestInputMonitoring() -> Bool { CGRequestListenEventAccess() }

    static func openSettings(for kind: Kind) {
        NSWorkspace.shared.open(kind.settingsURL)
    }
}
