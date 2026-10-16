import Foundation
import LazyleadVPNCore

struct RoutingSnapshot {
    let date: Date
    let vmName: String
    let gateway: String
    let mode: String
    let vmStatus: String
    let guestDefault: String?
    let transmission: String?
    let dnsRules: [LimaDNSRule]
    let dnsServiceRunning: Bool?
    let cloudNetworks: [IPv4Network]?
    let table: RouteTable
    let tableAvailable: Bool
    let resolversAvailable: Bool

    var limaRoutes: [SystemRoute] { table.routes(via: gateway) }
    var cloudRouteCount: Int {
        limaRoutes.filter { route in cloudNetworks?.contains { $0.contains(route.network) } == true }.count
    }
}

final class RoutingInfoProvider {
    private let vmName: String
    private let gateway: String
    private let direct: Bool

    init(vmName: String, gateway: String, direct: Bool) {
        self.vmName = vmName
        self.gateway = gateway
        self.direct = direct
    }

    func snapshot() -> RoutingSnapshot {
        let output = run("/usr/sbin/netstat", ["-rn", "-f", "inet"])
        let table = RouteTable(output ?? "")
        let resolverDirectory = "/etc/resolver"
        let resolverNames = try? FileManager.default.contentsOfDirectory(atPath: resolverDirectory)
        let rules = (resolverNames ?? []).compactMap { name -> LimaDNSRule? in
            guard let text = try? String(contentsOfFile: resolverDirectory + "/" + name, encoding: .utf8) else { return nil }
            return LimaDNSRule.parse(text, filename: name, routes: table, gateway: gateway)
        }.sorted { $0.domain < $1.domain }
        let service = run("/bin/launchctl", ["print", "system/io.lazylead.gov-dns"])
        let dnsRunning = service.map { $0.contains("state = running") }
        let cloudText = try? String(contentsOfFile: "/opt/lazylead-direct/yandex-cloud-ipv4.txt", encoding: .utf8)
        let cloudNetworks = cloudText.map { $0.split(separator: "\n").compactMap { IPv4Network(String($0)) } }
        let limactl = ["/opt/homebrew/bin/limactl", "/usr/local/bin/limactl"].first {
            FileManager.default.isExecutableFile(atPath: $0)
        }
        var vmStatus = "Unavailable"
        var guest: [String: String] = [:]
        if let limactl, let list = run(limactl, ["list", "--format", "{{.Name}}\t{{.Status}}"]),
           let line = list.split(separator: "\n").first(where: { $0.split(separator: "\t").first.map(String.init) == vmName }) {
            vmStatus = line.split(separator: "\t").dropFirst().first.map(String.init) ?? "Unavailable"
            if vmStatus.lowercased() == "running" {
                let script = """
                import json, subprocess
                def read(args):
                    return subprocess.run(args, capture_output=True, text=True, timeout=3).stdout.strip()
                print(json.dumps({'default': read(['ip','-4','route','show','default']),
                                  'transmission': read(['systemctl','is-active','lazylead-transmission.service'])}))
                """
                if let json = run(limactl, ["shell", "--workdir", "/", vmName, "python3", "-c", script]),
                   let data = json.data(using: .utf8),
                   let values = try? JSONDecoder().decode([String: String].self, from: data) {
                    guest = values
                }
            }
        }
        return RoutingSnapshot(date: Date(), vmName: vmName, gateway: gateway,
                               mode: direct ? "Direct to provider" : "Check Point", vmStatus: vmStatus,
                               guestDefault: guest["default"], transmission: guest["transmission"],
                               dnsRules: rules, dnsServiceRunning: dnsRunning, cloudNetworks: cloudNetworks,
                               table: table, tableAvailable: output != nil, resolversAvailable: resolverNames != nil)
    }

    private func run(_ executable: String, _ arguments: [String]) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 6, execute: timeout)
        // Drain while the process runs: a large routing table can fill a pipe.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        timeout.cancel()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
