import OSLog

enum Log {
    private static let logger = Logger(subsystem: "com.dragon.PhotoViewer", category: "browser")

    static func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
    }

    static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }
}
