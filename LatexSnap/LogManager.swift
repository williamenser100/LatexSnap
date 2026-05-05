import Foundation

enum LogLevel { case info, success, error }

struct LogEntry: Identifiable {
    let id = UUID()
    let timestamp = Date()
    let message: String
    let level: LogLevel
}

@MainActor
class LogManager: ObservableObject {
    static let shared = LogManager()
    @Published var entries: [LogEntry] = []

    func log(_ message: String, level: LogLevel = .info) {
        entries.insert(LogEntry(message: message, level: level), at: 0)
        if entries.count > 200 { entries.removeLast() }
    }
}
