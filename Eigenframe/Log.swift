import OSLog

/// Centralised loggers for each subsystem. Use the most specific logger available.
enum Log {
    static let engine   = Logger(subsystem: "com.eigenframe.app", category: "WallpaperEngine")
    static let spaces   = Logger(subsystem: "com.eigenframe.app", category: "SpaceManager")
    static let config   = Logger(subsystem: "com.eigenframe.app", category: "ConfigStore")
    static let ui       = Logger(subsystem: "com.eigenframe.app", category: "UI")
}
