import Foundation

/**
 * LogFileViewer - Tails /tmp/mousetrail.log and provides colored, chunked display.
 * Reads the last chunk of the file on open and polls for new lines.
 */
@Observable
class LogFileViewer {
    static let shared = LogFileViewer()

    static let logPath = "/tmp/mousetrail.log"
    static let restartMarker = "━━━ MouseTrail started"
    private static let tailBytes = 32_768  // Read last 32KB on initial load

    struct LogLine: Identifiable {
        let id: Int
        let text: String
        let kind: Kind

        enum Kind {
            case info
            case debug
            case error
            case restart
        }
    }

    var lines: [LogLine] = []
    private var fileOffset: UInt64 = 0
    private var nextID = 0
    private var pollTimer: Timer?

    private init() {}

    /// Write a restart separator to the log file, then load the tail.
    func start() {
        writeRestartMarker()
        loadTail()
        startPolling()
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    /// Load the last chunk of the log file.
    func loadTail() {
        guard let handle = FileHandle(forReadingAtPath: Self.logPath) else { return }
        defer { handle.closeFile() }

        let fileSize = handle.seekToEndOfFile()
        let readStart: UInt64 = fileSize > UInt64(Self.tailBytes) ? fileSize - UInt64(Self.tailBytes) : 0
        handle.seek(toFileOffset: readStart)
        let data = handle.readDataToEndOfFile()
        fileOffset = fileSize

        guard let content = String(data: data, encoding: .utf8) else { return }

        // If we started mid-file, drop the first partial line
        var text = content
        if readStart > 0, let firstNewline = text.firstIndex(of: "\n") {
            text = String(text[text.index(after: firstNewline)...])
        }

        let rawLines = text.components(separatedBy: "\n").filter { !$0.isEmpty }
        lines = rawLines.map { makeLine($0) }
    }

    /// Poll for new lines appended since last read.
    func pollNewLines() {
        guard let handle = FileHandle(forReadingAtPath: Self.logPath) else { return }
        defer { handle.closeFile() }

        let fileSize = handle.seekToEndOfFile()
        guard fileSize > fileOffset else {
            if fileSize < fileOffset { fileOffset = 0 }  // File was truncated
            return
        }

        handle.seek(toFileOffset: fileOffset)
        let data = handle.readDataToEndOfFile()
        fileOffset = fileSize

        guard let content = String(data: data, encoding: .utf8) else { return }
        let rawLines = content.components(separatedBy: "\n").filter { !$0.isEmpty }
        lines.append(contentsOf: rawLines.map { makeLine($0) })

        // Cap total lines kept in memory
        if lines.count > 2000 {
            lines.removeFirst(lines.count - 2000)
        }
    }

    func clear() {
        lines.removeAll()
        // Truncate the file
        FileManager.default.createFile(atPath: Self.logPath, contents: nil)
        fileOffset = 0
        writeRestartMarker()
    }

    func getAllText() -> String {
        lines.map(\.text).joined(separator: "\n")
    }

    private func writeRestartMarker() {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let marker = "\(Self.restartMarker) \(df.string(from: Date())) ━━━\n"
        if let handle = FileHandle(forWritingAtPath: Self.logPath) {
            handle.seekToEndOfFile()
            handle.write(marker.data(using: .utf8)!)
            handle.closeFile()
        } else {
            FileManager.default.createFile(atPath: Self.logPath, contents: marker.data(using: .utf8))
        }
    }

    private func makeLine(_ text: String) -> LogLine {
        let kind: LogLine.Kind
        if text.contains(Self.restartMarker) {
            kind = .restart
        } else if text.contains("[error]") || text.contains("crash") || text.contains("fatal") {
            kind = .error
        } else if text.contains("[debug]") {
            kind = .debug
        } else {
            kind = .info
        }
        let line = LogLine(id: nextID, text: text, kind: kind)
        nextID += 1
        return line
    }

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.pollNewLines()
        }
    }
}
