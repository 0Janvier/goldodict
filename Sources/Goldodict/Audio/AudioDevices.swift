import CoreAudio
import Foundation

/// Périphériques d'entrée CoreAudio, et le message à afficher quand l'un d'eux
/// n'entend plus rien.
///
/// `AudioCapture` peut viser un périphérique choisi. Sans ce choix, macOS donne
/// l'entrée par défaut — un câble virtuel (BlackHole, une visio) rend alors une
/// capture verte et un silence réel.
enum AudioDevices {

    struct InputDevice: Identifiable, Equatable, Hashable, Sendable {
        let uid: String
        let name: String
        var id: String { uid }
    }

    /// Entrées capables de fournir au moins un canal.
    static func inputDevices() -> [InputDevice] {
        devices().compactMap { id in
            guard inputChannelCount(of: id) > 0 else { return nil }
            guard let uid = uid(of: id), let name = name(of: id) else { return nil }
            return InputDevice(uid: uid, name: name)
        }
    }

    static func name(ofUID uid: String?) -> String? {
        guard let uid, let id = id(forUID: uid) else { return nil }
        return name(of: id)
    }

    static func id(forUID uid: String) -> AudioDeviceID? {
        devices().first { self.uid(of: $0) == uid }
    }

    /// Nom du périphérique d'entrée par défaut.
    static var defaultInputName: String? {
        guard let device = defaultInputDevice() else { return nil }
        return name(of: device)
    }

    static var defaultInputUID: String? {
        guard let device = defaultInputDevice() else { return nil }
        return uid(of: device)
    }

    /// Où l'on change de périphérique si Goldodict n'en impose pas un.
    static let settingsHint = "Réglages Système > Son > Entrée"

    static func silenceMessage(device: String?) -> String {
        guard let device else { return "Rien n'est capté" }
        return "Rien n'est capté depuis « \(device) »"
    }

    // MARK: - CoreAudio

    private static func defaultInputDevice() -> AudioDeviceID? {
        property(
            object: AudioObjectID(kAudioObjectSystemObject),
            selector: kAudioHardwarePropertyDefaultInputDevice,
            as: AudioDeviceID.self
        ).flatMap { $0 == kAudioObjectUnknown ? nil : $0 }
    }

    private static func devices() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size
        ) == noErr, size > 0 else { return [] }

        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = Array(repeating: AudioDeviceID(0), count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids
        ) == noErr else { return [] }
        return ids
    }

    private static func inputChannelCount(of device: AudioDeviceID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr, size > 0 else {
            return 0
        }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<Int>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, raw) == noErr else { return 0 }
        let bufferList = raw.assumingMemoryBound(to: AudioBufferList.self)
        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        return buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    static func name(of device: AudioDeviceID) -> String? {
        stringProperty(device, kAudioObjectPropertyName)
    }

    private static func uid(of device: AudioDeviceID) -> String? {
        stringProperty(device, kAudioDevicePropertyDeviceUID)
    }

    private static func stringProperty(_ device: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
        guard status == noErr, let string = value?.takeRetainedValue() as String?, !string.isEmpty else {
            return nil
        }
        return string
    }

    private static func property<T>(
        object: AudioObjectID,
        selector: AudioObjectPropertySelector,
        as type: T.Type
    ) -> T? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { value.deallocate() }
        var size = UInt32(MemoryLayout<T>.size)
        let status = AudioObjectGetPropertyData(object, &address, 0, nil, &size, value)
        guard status == noErr else { return nil }
        return value.pointee
    }
}
