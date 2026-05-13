import Foundation

/// Cross-process log writer + reader. Shared between the main app and
/// the widget extension via the App Group container, so logs from both
/// processes land in one tail-able file Fabi can read on his iPhone
/// (no Mac / Console.app required).
///
/// Writers: BLEManager, HealthEngine, SharedHealthData, LucidWidgets,
/// SleepEngine — anywhere we used to NSLog. Reader: LogViewerView in
/// Settings reads the same file and shows the last 500 lines, filterable
/// by tag.
///
/// Storage: plain text file in
/// `containerURL(forSecurityApplicationGroupIdentifier: "group.com.fabi.lucidhealth.shared")`.
/// One line per event, ISO8601 timestamp + tag + message. Tail-bounded
/// at maxLines (oldest entries get dropped). NSLog is also called so
/// logs still land in Console.app for anyone with a Mac.
enum LucidLog {
    static let groupID = "group.com.fabi.lucidhealth.shared"
    static let logFile = "lucid-log.txt"
    private static let maxLines = 500

    private static let stampFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Write one line. Concurrent writes from main app + widget process
    /// rely on file-atomic write — last writer wins on the rare collision,
    /// which is fine for a debug log.
    static func log(_ tag: String, _ message: String) {
        let stamp = stampFormatter.string(from: Date())
        let line = "[\(stamp)] [\(tag)] \(message)"
        // System log for Mac / Console.app.
        NSLog("%@", line)
        appendLine(line)
    }

    /// Read all lines. Returns `["(empty)"]` if the file doesn't exist
    /// yet or the App Group access was denied.
    static func read() -> [String] {
        guard let url = sharedURL else {
            return ["(App Group denied — sharedURL nil)"]
        }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return ["(no log file yet — nothing has been logged)"]
        }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        return lines.isEmpty ? ["(empty)"] : lines
    }

    static func clear() {
        guard let url = sharedURL else { return }
        try? "".write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Private

    private static var sharedURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: groupID)?
            .appendingPathComponent(logFile)
    }

    private static func appendLine(_ line: String) {
        guard let url = sharedURL else { return }
        var lines: [String] = []
        if let existing = try? String(contentsOf: url, encoding: .utf8) {
            lines = existing.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        }
        lines.append(line)
        if lines.count > maxLines {
            lines = Array(lines.suffix(maxLines))
        }
        let joined = lines.joined(separator: "\n")
        try? joined.write(to: url, atomically: true, encoding: .utf8)
    }
}
