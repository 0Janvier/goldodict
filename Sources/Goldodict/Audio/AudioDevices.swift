import CoreAudio
import Foundation

/// Le périphérique d'entrée que le système donne à `AVAudioEngine`.
///
/// `AudioCapture` n'ouvre pas un périphérique choisi mais celui que macOS désigne
/// par défaut, ce qui va de soi tant que ce périphérique est un micro. Quand c'est
/// un câble virtuel (BlackHole, un pilote de visioconférence, un agrégat mal réglé),
/// la capture réussit et ne rend que des zéros.
///
/// Le nom du périphérique est alors la seule chose qui sépare « le micro est en
/// panne » de « ce n'est pas le micro qui est écouté », et l'utilisateur n'a aucun
/// moyen de le deviner : les autorisations sont au vert et le vumètre est à plat.
enum AudioDevices {

    /// Nom du périphérique d'entrée par défaut.
    ///
    /// Rend `nil` s'il n'y a pas d'entrée ou si CoreAudio refuse de répondre. Ce
    /// n'est pas une panne à signaler : le message se rabat alors sur sa forme
    /// courte, qui reste vraie.
    static var defaultInputName: String? {
        guard let device = defaultInputDevice() else { return nil }
        return name(of: device)
    }

    /// Où l'on change de périphérique. La pastille et la fenêtre du mode document
    /// disent la même chose, et il n'y a qu'un endroit à corriger le jour où Apple
    /// renomme encore ce panneau.
    static let settingsHint = "Réglages Système > Son > Entrée"

    /// Constat rendu à l'utilisateur quand plus rien n'est capté.
    static func silenceMessage(device: String?) -> String {
        guard let device else { return "Rien n'est capté" }
        return "Rien n'est capté depuis « \(device) »"
    }

    private static func defaultInputDevice() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &device
        )
        guard status == noErr, device != kAudioObjectUnknown else { return nil }
        return device
    }

    /// `AudioObjectGetPropertyData` rend la chaîne déjà retenue. Passer par
    /// `Unmanaged` rend cette possession visible plutôt que de s'en remettre au
    /// hasard d'un pont automatique.
    private static func name(of device: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name)
        guard status == noErr, let value = name?.takeRetainedValue() else { return nil }

        let label = value as String
        return label.isEmpty ? nil : label
    }
}
