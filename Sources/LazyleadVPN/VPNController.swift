import AppKit
import Foundation
import LazyleadVPNCore

final class VPNController {
    private let logStore: LogStore
    private let commandRunner: CommandRunner
    private let adminRunner: AdminScriptRunner
    private let commands: VPNCommandFactory
    private let queue = DispatchQueue(label: "LazyleadVPN.VPNController")
    private var snxProcess: Process?
    private var sawTunnelConnected = false
    private var sawTunnelInterface = false
    private var isFinalizingConnection = false
    private var healthTimer: DispatchSourceTimer?

    let projectDirectory: String
    let vmName: String
    let vmGateway: String
    let bootstrapProbeIP: String
    let corporateProbeIP: String
    let samlBrowserApp: String?
    var onStateChange: ((VPNState) -> Void)?
    var onSAMLURLChange: (() -> Void)?
    private(set) var lastSAMLURL: URL?

    private(set) var state: VPNState = .disconnected {
        didSet {
            logStore.append("STATE \(state.label)")
            onStateChange?(state)
        }
    }

    init(logStore: LogStore) {
        self.logStore = logStore
        self.commandRunner = CommandRunner(logStore: logStore)
        self.adminRunner = AdminScriptRunner(logStore: logStore)

        let resolvedProjectDirectory = Self.resolveProjectDirectory()
        let environment = ProcessInfo.processInfo.environment
        let resolvedVMName = environment["LAZYLEAD_VM_NAME"].flatMap { $0.isEmpty ? nil : $0 } ?? "lazylead-vpn"
        let resolvedVMGateway = environment["LAZYLEAD_VM_GATEWAY"].flatMap { $0.isEmpty ? nil : $0 } ?? "192.168.64.2"
        let resolvedSNXConfigPath = environment["LAZYLEAD_SNX_CONFIG_PATH"].flatMap { $0.isEmpty ? nil : $0 } ?? "$HOME/.config/snx-rs/snx-rs.conf"
        let resolvedGatewayProbeURL = environment["LAZYLEAD_GATEWAY_PROBE_URL"].flatMap { $0.isEmpty ? nil : $0 } ?? "https://vpn.example.com/clients/"
        let resolvedBootstrapProbeIP = environment["LAZYLEAD_BOOTSTRAP_PROBE_IP"].flatMap { $0.isEmpty ? nil : $0 } ?? "203.0.113.10"
        let resolvedCorporateProbeIP = environment["LAZYLEAD_CORPORATE_PROBE_IP"].flatMap { $0.isEmpty ? nil : $0 } ?? "10.0.0.1"
        let resolvedSAMLBrowserApp = environment["LAZYLEAD_SAML_BROWSER_APP"].flatMap { $0.isEmpty ? nil : $0 }

        self.projectDirectory = resolvedProjectDirectory
        self.vmName = resolvedVMName
        self.vmGateway = resolvedVMGateway
        self.bootstrapProbeIP = resolvedBootstrapProbeIP
        self.corporateProbeIP = resolvedCorporateProbeIP
        self.samlBrowserApp = resolvedSAMLBrowserApp
        self.commands = VPNCommandFactory(
            projectDirectory: resolvedProjectDirectory,
            vmName: resolvedVMName,
            vmGateway: resolvedVMGateway,
            snxConfigPath: resolvedSNXConfigPath,
            gatewayProbeURL: resolvedGatewayProbeURL
        )
        logStore.append("PROJECT \(resolvedProjectDirectory)")
        startHealthTimer()
    }

    private static func resolveProjectDirectory() -> String {
        let fileManager = FileManager.default

        if let environmentPath = ProcessInfo.processInfo.environment["LAZYLEAD_VPN_HOME"], !environmentPath.isEmpty {
            return environmentPath
        }

        if let bundledScripts = Bundle.main.resourceURL?.appendingPathComponent("scripts", isDirectory: true).path,
           fileManager.fileExists(atPath: "\(bundledScripts)/host_corporate_routes.sh") {
            return bundledScripts
        }

        let currentPath = fileManager.currentDirectoryPath
        if fileManager.fileExists(atPath: "\(currentPath)/host_corporate_routes.sh") {
            return currentPath
        }

        return currentPath
    }

    func connect() {
        queue.async { [weak self] in
            guard let self else { return }
            guard self.state.canConnect else { return }

            self.sawTunnelConnected = false
            self.sawTunnelInterface = false
            self.isFinalizingConnection = false
            self.lastSAMLURL = nil
            self.onSAMLURLChange?()
            self.setState(.startingVM)

            do {
                try self.ensureLimactlExists()
                try self.runFinite(self.commands.startVMCommand())
                self.setState(.preparing)
                try self.runFinite(self.commands.copyRouterCommand())
                try self.runFinite(self.commands.chmodRouterCommand())
                try self.runAdmin(
                    self.commands.installCheckpointRouteAdminCommand(),
                    fallbackShellCommand: self.commands.installCheckpointRouteScript()
                )
                try self.waitForGatewayReachability()
                self.setState(.waitingFor2FA)
                self.startSNX()
            } catch {
                self.setState(.error(error.localizedDescription))
            }
        }
    }

    func disconnect() {
        queue.async { [weak self] in
            guard let self else { return }
            guard self.state.canDisconnect || self.snxProcess != nil else { return }

            self.setState(.disconnecting)
            self.snxProcess?.terminate()
            self.snxProcess = nil

            _ = try? self.commandRunner.run(self.commands.stopSNXCommand())
            _ = try? self.adminRunner.run(
                self.commands.removeCorporateRoutesAdminCommand(),
                fallbackShellCommand: self.commands.removeCorporateRoutesScript()
            )
            self.logStore.append("Keeping Check Point bootstrap routes installed")
            self.setState(.disconnected)
        }
    }

    func openLastSAMLURL() {
        guard let lastSAMLURL else {
            return
        }

        logStore.append("SAML URL reopened from menu")
        openSAMLURL(lastSAMLURL)
    }

    private func startSNX() {
        do {
            snxProcess = try commandRunner.start(commands.snxCommand(), output: { [weak self] text in
                self?.queue.async {
                    self?.handleSNXOutput(text)
                }
            }, onExit: { [weak self] status in
                self?.queue.async {
                    guard let self else { return }
                    self.snxProcess = nil
                    if case .disconnecting = self.state {
                        return
                    }
                    if case .disconnected = self.state {
                        return
                    }
                    self.setState(.error("snx-rs exited with status \(status)"))
                }
            })
        } catch {
            setState(.error(error.localizedDescription))
        }
    }

    private func handleSNXOutput(_ text: String) {
        if let url = SAMLURLParser.extract(from: text) {
            lastSAMLURL = url
            onSAMLURLChange?()
            logStore.append("SAML URL parsed and opened")
            DispatchQueue.main.async {
                self.openSAMLURL(url)
            }
        }

        if text.contains("Tunnel connected") {
            sawTunnelConnected = true
        }

        if text.contains("Interface: snx-tun") {
            sawTunnelInterface = true
        }

        if sawTunnelConnected && sawTunnelInterface && !isFinalizingConnection {
            isFinalizingConnection = true
            queue.async { [weak self] in
                self?.finishConnection()
            }
        }
    }

    private func finishConnection() {
        setState(.configuring)

        do {
            try runFinite(commands.installVMRouterCommand())
            try runAdmin(
                commands.installCorporateRoutesAdminCommand(),
                fallbackShellCommand: commands.installCorporateRoutesScript()
            )
            setState(.connected)
        } catch {
            setState(.error(error.localizedDescription))
        }
    }

    private func waitForGatewayReachability() throws {
        var lastError = "gateway probe was not attempted"

        for attempt in 1...5 {
            let result = try commandRunner.output(commands.gatewayProbeCommand())
            if result.status == 0 {
                logStore.append("Gateway probe OK on attempt \(attempt)")
                return
            }

            lastError = result.text.isEmpty ? "gateway probe exited with \(result.status)" : result.text
            logStore.append("Gateway probe failed on attempt \(attempt): \(lastError)")

            try runAdmin(
                commands.installCheckpointRouteAdminCommand(),
                fallbackShellCommand: commands.installCheckpointRouteScript()
            )
            Thread.sleep(forTimeInterval: 2)
        }

        throw NSError(
            domain: "LazyleadVPN.GatewayProbe",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Check Point gateway is not reachable from Lima after route repair: \(lastError)"]
        )
    }

    private func runFinite(_ command: VPNCommand) throws {
        let status = try commandRunner.run(command)
        if status != 0 {
            throw NSError(
                domain: "LazyleadVPN.Command",
                code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "Command failed with status \(status): \(command.executable)"]
            )
        }
    }

    private func runAdmin(_ command: VPNCommand, fallbackShellCommand: String) throws {
        let status = try adminRunner.run(command, fallbackShellCommand: fallbackShellCommand)
        if status != 0 {
            throw NSError(
                domain: "LazyleadVPN.AdminCommand",
                code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "Administrator command failed or was cancelled"]
            )
        }
    }

    private func setState(_ newState: VPNState) {
        state = newState
    }

    private func startHealthTimer() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 10, repeating: 30)
        timer.setEventHandler { [weak self] in
            self?.repairRoutesIfNeeded()
        }
        timer.resume()
        healthTimer = timer
    }

    private func repairRoutesIfNeeded() {
        if !bootstrapRoutesLookHealthy() {
            logStore.append("Repairing Check Point bootstrap routes after health check")
            _ = try? adminRunner.run(
                commands.installCheckpointRouteAdminCommand(),
                fallbackShellCommand: commands.installCheckpointRouteScript()
            )
        }

        if state == .connected, !corporateRoutesLookHealthy() {
            logStore.append("Repairing corporate routes after health check")
            _ = try? adminRunner.run(
                commands.installCorporateRoutesAdminCommand(),
                fallbackShellCommand: commands.installCorporateRoutesScript()
            )
        }
    }

    private func bootstrapRoutesLookHealthy() -> Bool {
        guard let output = shellOutput(["/sbin/route", "-n", "get", bootstrapProbeIP]) else {
            return false
        }

        return output.contains("interface: en0")
    }

    private func corporateRoutesLookHealthy() -> Bool {
        guard let output = shellOutput(["/sbin/route", "-n", "get", corporateProbeIP]) else {
            return false
        }

        return output.contains("gateway: \(vmGateway)")
    }

    private func shellOutput(_ command: [String]) -> String? {
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

        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }

    private func openSAMLURL(_ url: URL) {
        guard let samlBrowserApp else {
            NSWorkspace.shared.open(url)
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", samlBrowserApp, url.absoluteString]

        do {
            try process.run()
            logStore.append("SAML URL opened with \(samlBrowserApp)")
        } catch {
            logStore.append("Failed to open SAML URL with \(samlBrowserApp); falling back to default browser")
            NSWorkspace.shared.open(url)
        }
    }

    private func ensureLimactlExists() throws {
        let candidates = [
            "/opt/homebrew/bin/limactl",
            "/usr/local/bin/limactl",
            "/usr/bin/limactl",
            "/bin/limactl"
        ]

        if candidates.contains(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return
        }

        throw NSError(
            domain: "LazyleadVPN.Dependency",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Lima is not installed. Install Homebrew and Lima, or reinstall Lazylead VPN with Homebrew available."]
        )
    }
}
