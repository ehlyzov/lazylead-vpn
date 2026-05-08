import Foundation

final class LogStore {
    let fileURL: URL
    private let lock = NSLock()

    init() {
        let logsDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("Lazylead VPN", isDirectory: true)

        try? FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        self.fileURL = logsDirectory.appendingPathComponent("lazylead-vpn.log")

        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
    }

    func append(_ message: String) {
        lock.lock()
        defer { lock.unlock() }

        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
        guard let data = line.data(using: .utf8) else {
            return
        }

        do {
            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            fputs("Lazylead VPN log write failed: \(error)\n", stderr)
        }
    }
}
