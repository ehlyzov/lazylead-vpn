import Foundation
import LazyleadVPNCore

final class CommandRunner {
    private let logStore: LogStore

    init(logStore: LogStore) {
        self.logStore = logStore
    }

    @discardableResult
    func run(_ command: VPNCommand, output: @escaping (String) -> Void = { _ in }) throws -> Int32 {
        let process = makeProcess(command)
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        logStore.append("RUN \(display(command))")
        try process.run()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let text = String(data: data, encoding: .utf8), !text.isEmpty {
            output(text)
            logStore.append(text.trimmingCharacters(in: .newlines))
        }

        process.waitUntilExit()
        logStore.append("EXIT \(process.terminationStatus): \(display(command))")
        return process.terminationStatus
    }

    func output(_ command: VPNCommand) throws -> (status: Int32, text: String) {
        var captured = ""
        let status = try run(command) { text in
            captured += text
        }
        return (status, captured)
    }

    func start(
        _ command: VPNCommand,
        output: @escaping (String) -> Void,
        onExit: @escaping (Int32) -> Void
    ) throws -> Process {
        let process = makeProcess(command)
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else {
                return
            }
            self?.logStore.append(text.trimmingCharacters(in: .newlines))
            output(text)
        }

        process.terminationHandler = { process in
            pipe.fileHandleForReading.readabilityHandler = nil
            self.logStore.append("EXIT \(process.terminationStatus): \(self.display(command))")
            onExit(process.terminationStatus)
        }

        logStore.append("START \(display(command))")
        try process.run()
        return process
    }

    private func makeProcess(_ command: VPNCommand) -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath(command.executable))
        process.arguments = command.arguments
        if let workingDirectory = command.workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        }
        return process
    }

    private func executablePath(_ executable: String) -> String {
        if executable.contains("/") {
            return executable
        }

        let candidates = [
            "/opt/homebrew/bin/\(executable)",
            "/usr/local/bin/\(executable)",
            "/usr/bin/\(executable)",
            "/bin/\(executable)"
        ]

        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? executable
    }

    private func display(_ command: VPNCommand) -> String {
        ([command.executable] + command.arguments).joined(separator: " ")
    }
}
