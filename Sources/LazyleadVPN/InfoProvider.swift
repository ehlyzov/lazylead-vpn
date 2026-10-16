import Foundation

struct InfoSnapshot {
    let appVersion: String
    let limactlPath: String
    let limactlVersion: String
    let vmName: String
    let vmStatus: String
    let limaInstanceDirectory: String
    let limaDiskPath: String
    let limaDiskSize: String
    let limaConfigPath: String
    let scriptsDirectory: String
    let privilegedScriptsDirectory: String
    let sudoersPath: String
    let sudoersStatus: String
    let logPath: String
    let routingTable: String
}

final class InfoProvider {
    private let vpnController: VPNController
    private let logStore: LogStore

    init(vpnController: VPNController, logStore: LogStore) {
        self.vpnController = vpnController
        self.logStore = logStore
    }

    func makeSnapshot() -> InfoSnapshot {
        let limactlPath = findExecutable("limactl") ?? "not found"
        let limactlVersion = run([limactlPath, "--version"]) ?? "not available"
        let vmName = vpnController.vmName
        let vmDetails = limaVMDetails(limactlPath: limactlPath, vmName: vmName)
        let instanceDirectory = vmDetails.directory
        let diskPath = "\(instanceDirectory)/disk"
        let diskSize = fileSize(atPath: diskPath)
        let configPath = "\(instanceDirectory)/lima.yaml"
        let sudoersPath = "/etc/sudoers.d/lazylead-vpn"
        let routingTable = run(["/usr/sbin/netstat", "-rn", "-f", "inet"]) ?? "Could not read routing table"

        return InfoSnapshot(
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "development",
            limactlPath: limactlPath,
            limactlVersion: limactlVersion,
            vmName: vmName,
            vmStatus: vmDetails.status,
            limaInstanceDirectory: instanceDirectory,
            limaDiskPath: diskPath,
            limaDiskSize: diskSize,
            limaConfigPath: configPath,
            scriptsDirectory: vpnController.projectDirectory,
            privilegedScriptsDirectory: "/usr/local/libexec/lazylead-vpn",
            sudoersPath: sudoersPath,
            sudoersStatus: FileManager.default.fileExists(atPath: sudoersPath) ? "installed" : "not installed",
            logPath: logStore.fileURL.path,
            routingTable: routingTable
        )
    }

    private func limaVMDetails(limactlPath: String, vmName: String) -> (status: String, directory: String) {
        let fallbackDirectory = "\(FileManager.default.homeDirectoryForCurrentUser.path)/.lima/\(vmName)"
        guard limactlPath != "not found",
              let output = run([limactlPath, "list", "--format", "{{.Name}}\t{{.Status}}\t{{.Dir}}"]) else {
            return ("not available", fallbackDirectory)
        }

        for line in output.split(separator: "\n") {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 3, fields[0] == vmName else {
                continue
            }
            return (fields[1], fields[2])
        }

        return ("not found", fallbackDirectory)
    }

    private func findExecutable(_ name: String) -> String? {
        let candidates = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)",
            "/bin/\(name)"
        ]

        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private func run(_ command: [String]) -> String? {
        guard let executable = command.first else {
            return nil
        }

        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = Array(command.dropFirst())
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func fileSize(atPath path: String) -> String {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attributes[.size] as? NSNumber else {
            return "not found"
        }

        let capacity = ByteCountFormatter.string(fromByteCount: size.int64Value, countStyle: .file)
        let used = allocatedSize(atPath: path)
        return "\(used) used / \(capacity) capacity"
    }

    private func allocatedSize(atPath path: String) -> String {
        guard let output = run(["/usr/bin/du", "-k", path]),
              let kilobytesText = output.split(whereSeparator: { $0 == " " || $0 == "\t" }).first,
              let kilobytes = Int64(kilobytesText) else {
            return "unknown"
        }

        return ByteCountFormatter.string(fromByteCount: kilobytes * 1024, countStyle: .file)
    }

}
