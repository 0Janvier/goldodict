import OSLog

/// Journal unifié. Lecture en direct :
/// `log stream --predicate 'subsystem == "fr.sztulman.goldodict"' --level debug`
enum Log {
    static let lifecycle = Logger(subsystem: "fr.sztulman.goldodict", category: "lifecycle")
    static let hotkey = Logger(subsystem: "fr.sztulman.goldodict", category: "hotkey")
    static let audio = Logger(subsystem: "fr.sztulman.goldodict", category: "audio")
    static let engine = Logger(subsystem: "fr.sztulman.goldodict", category: "engine")
    static let output = Logger(subsystem: "fr.sztulman.goldodict", category: "output")
    static let importing = Logger(subsystem: "fr.sztulman.goldodict", category: "import")
    static let goldocab = Logger(subsystem: "fr.sztulman.goldodict", category: "goldocab")
}
