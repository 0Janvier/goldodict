import OSLog

/// Journal unifié. Lecture en direct :
/// `log stream --predicate 'subsystem == "fr.sztulman.abracadabra"' --level debug`
enum Log {
    static let lifecycle = Logger(subsystem: "fr.sztulman.abracadabra", category: "lifecycle")
    static let hotkey = Logger(subsystem: "fr.sztulman.abracadabra", category: "hotkey")
    static let audio = Logger(subsystem: "fr.sztulman.abracadabra", category: "audio")
    static let engine = Logger(subsystem: "fr.sztulman.abracadabra", category: "engine")
    static let output = Logger(subsystem: "fr.sztulman.abracadabra", category: "output")
}
