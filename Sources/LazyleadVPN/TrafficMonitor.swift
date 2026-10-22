import Foundation
import LazyleadVPNCore

struct TrafficViewState {
    let ledger: TrafficLedger?
    let update: TrafficUpdate?
    let message: String
    let available: Bool
}

/// Runs while the menu-bar app is open, independently of the routes window.
final class TrafficMonitor {
    private let vmName: String
    private let gateway: String
    private let direct: Bool
    private let queue = DispatchQueue(label: "LazyleadVPN.TrafficMonitor", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var ledger: TrafficLedger?
    private let storeURL: URL
    private var persistenceError: String?
    private(set) var state = TrafficViewState(ledger: nil, update: nil, message: "Reading traffic counters…", available: false)
    var onChange: ((TrafficViewState) -> Void)?

    init(vmName: String, gateway: String, direct: Bool) {
        self.vmName = vmName
        self.gateway = gateway
        self.direct = direct
        let identity = Data("\(vmName)|\(gateway)|\(direct)".utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "+", with: "-")
        storeURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Lazylead VPN/Traffic", isDirectory: true)
            .appendingPathComponent(identity + ".json")
        if FileManager.default.fileExists(atPath: storeURL.path) {
            do { ledger = try JSONDecoder().decode(TrafficLedger.self, from: Data(contentsOf: storeURL)) }
            catch { persistenceError = "Saved history could not be read; the original file is preserved. New totals are temporary." }
        }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 5)
        timer.setEventHandler { [weak self] in self?.collect() }
        self.timer = timer
        timer.resume()
    }

    deinit { timer?.cancel() }

    private func collect() {
        guard direct else {
            publish(update: nil, available: false, message: "Traffic accounting is available in Direct mode. Check Point routes remain available below.")
            return
        }
        guard let limactl = ["/opt/homebrew/bin/limactl", "/usr/local/bin/limactl"].first(where: {
            FileManager.default.isExecutableFile(atPath: $0)
        }) else {
            publish(update: nil, available: false, message: "Lima is not installed. Saved totals are retained.")
            return
        }
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: limactl)
        process.arguments = ["shell", "--workdir", "/", vmName, "python3", "-c", TrafficProbe.python, gateway]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() }
        catch {
            publish(update: nil, available: false, message: "VM unavailable. Saved totals are retained.")
            return
        }
        let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 4, execute: timeout)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        timeout.cancel()
        struct ProbeResult: Decodable {
            let uplink: TrafficReading
            let macLink: TrafficReading
        }
        guard process.terminationStatus == 0, let result = try? JSONDecoder().decode(ProbeResult.self, from: data) else {
            publish(update: nil, available: false, message: "Counters unavailable: VM stopped, unreachable, or direct0 is not the only default route. Saved totals are retained.")
            return
        }
        let sample = TrafficSample(date: Date(), uplink: result.uplink, macLink: result.macLink)
        let update: TrafficUpdate?
        if ledger == nil {
            ledger = TrafficLedger(baseline: sample)
            update = nil
        } else {
            update = ledger?.record(sample)
        }
        if persistenceError == nil {
            do {
                try FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try JSONEncoder().encode(ledger!).write(to: storeURL, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: storeURL.path)
            } catch { persistenceError = "History could not be saved. Totals are temporary until the app quits." }
        }
        publish(update: update, available: true, message: persistenceError ?? "Updated every 5 seconds while Lazylead VPN is open.")
    }

    private func publish(update: TrafficUpdate?, available: Bool, message: String) {
        let value = TrafficViewState(ledger: ledger, update: update, message: message, available: available)
        DispatchQueue.main.async { [weak self] in
            self?.state = value
            self?.onChange?(value)
        }
    }
}
