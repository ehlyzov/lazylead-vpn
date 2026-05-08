import Foundation
import LazyleadVPNCore

final class AdminScriptRunner {
    private let logStore: LogStore
    private let sudoersConfiguredPath = "/etc/sudoers.d/lazylead-vpn"

    init(logStore: LogStore) {
        self.logStore = logStore
    }

    @discardableResult
    func run(_ adminCommand: VPNCommand, fallbackShellCommand: String) throws -> Int32 {
        if FileManager.default.fileExists(atPath: sudoersConfiguredPath),
           FileManager.default.isExecutableFile(atPath: adminCommand.executable) {
            let status = try runPasswordlessSudo(adminCommand)
            if status == 0 {
                return status
            }

            logStore.append("PASSWORDLESS SUDO failed with status \(status); falling back to administrator prompt")
        }

        return try runWithAdministratorPrompt(fallbackShellCommand)
    }

    @discardableResult
    private func runPasswordlessSudo(_ command: VPNCommand) throws -> Int32 {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        process.arguments = ["-n", command.executable] + command.arguments
        process.standardOutput = pipe
        process.standardError = pipe

        logStore.append("SUDO RUN \(display(command))")
        try process.run()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let text = String(data: data, encoding: .utf8), !text.isEmpty {
            logStore.append(text.trimmingCharacters(in: .newlines))
        }

        process.waitUntilExit()
        logStore.append("SUDO EXIT \(process.terminationStatus): \(display(command))")
        return process.terminationStatus
    }

    @discardableResult
    private func runWithAdministratorPrompt(_ shellCommand: String) throws -> Int32 {
        let process = Process()
        let pipe = Pipe()
        let appleScript = "do shell script \(appleScriptString(shellCommand)) with administrator privileges"

        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", appleScript]
        process.standardOutput = pipe
        process.standardError = pipe

        logStore.append("ADMIN RUN \(redacted(shellCommand))")
        try process.run()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let text = String(data: data, encoding: .utf8), !text.isEmpty {
            logStore.append(text.trimmingCharacters(in: .newlines))
        }

        process.waitUntilExit()
        logStore.append("ADMIN EXIT \(process.terminationStatus): \(redacted(shellCommand))")
        return process.terminationStatus
    }

    private func appleScriptString(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
    }

    private func redacted(_ value: String) -> String {
        value.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    private func display(_ command: VPNCommand) -> String {
        ([command.executable] + command.arguments).joined(separator: " ")
    }
}
