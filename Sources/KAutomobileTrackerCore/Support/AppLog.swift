import OSLog

public enum AppLog {
    public static let subsystem = "com.kautomobile.KAutomobileTracker"

    public static let analysis = Logger(subsystem: subsystem, category: "analysis")
    public static let network = Logger(subsystem: subsystem, category: "network")
    public static let persistence = Logger(subsystem: subsystem, category: "persistence")
    public static let bluetooth = Logger(subsystem: subsystem, category: "bluetooth")
}
