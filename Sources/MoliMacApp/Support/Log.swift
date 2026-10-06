import os

/// System log, read with
/// `log stream --predicate 'subsystem == "com.moliduo.mac"' --level debug`.
enum Log {
    static let subsystem = "com.moliduo.mac"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let mouse = Logger(subsystem: subsystem, category: "mouse")
    static let scroll = Logger(subsystem: subsystem, category: "scroll")
    static let actions = Logger(subsystem: subsystem, category: "actions")
}
