import Foundation
import LazyleadVPNCore

func runTrafficAccountingTests() throws {
    func sample(_ seconds: Double, _ received: UInt64, _ sent: UInt64,
                epoch: String = "boot-a:4", linkReceived: UInt64 = 100, linkSent: UInt64 = 50) -> TrafficSample {
        TrafficSample(date: Date(timeIntervalSince1970: seconds),
                      uplink: TrafficReading(epoch: epoch, interface: "direct0", bytes: TrafficBytes(received: received, sent: sent)),
                      macLink: TrafficReading(epoch: epoch + ":link", interface: "lima0", bytes: TrafficBytes(received: linkReceived, sent: linkSent)))
    }
    var ledger = TrafficLedger(baseline: sample(100, 9_000_000, 2_000_000))
    try expectEqual(ledger.uplink.received, 0, "Do not charge bytes from before tracking began")
    let update = ledger.record(sample(105, 9_001_000, 2_000_500, linkReceived: 300, linkSent: 75))
    try expectEqual(ledger.uplink, TrafficBytes(received: 1000, sent: 500), "Both uplink directions")
    try expectEqual(ledger.macLink, TrafficBytes(received: 200, sent: 25), "Keep overlapping Mac link separate")
    try expectEqual(update.uplinkRate?.received, 200, "Rate is bytes per second")
    try expectEqual(update.macLinkRate?.sent, 5, "Mac-link rate")

    // A save/relaunch must retain the baseline, then recover counter growth while closed.
    var restored = try JSONDecoder().decode(TrafficLedger.self, from: JSONEncoder().encode(ledger))
    try expectEqual(restored, ledger, "History survives Codable persistence")
    let gap = restored.record(sample(200, 9_101_000, 2_010_500, linkReceived: 500, linkSent: 95))
    try expectEqual(restored.uplink.received, 101_000, "Recover same-interface traffic across a sampling gap")
    try expectEqual(gap.uplinkRate, nil, "Long-gap average is not a live speed")
    try expectEqual(restored.started, ledger.started, "Tracking start survives relaunch")
    let before = restored
    _ = restored.record(sample(199, 100_000_000, 100_000_000))
    try expectEqual(restored, before, "Ignore out-of-order samples")

    // Boot/interface identity must detect a restart even when the new counter is larger.
    let restart = restored.record(sample(205, 10_000_000, 3_000_000, epoch: "boot-b:4", linkReceived: 800, linkSent: 150))
    try expectEqual(restored.uplink.received, 10_101_000, "New boot has its own zero origin")
    try expectEqual(restored.discontinuities, 1, "Mark potential unobserved traffic at restart")
    try expectEqual(restart.uplinkRate, nil, "No rate across reboot")
    _ = restored.record(sample(210, 50, 3_000_100, epoch: "boot-b:4", linkReceived: 850, linkSent: 160))
    try expectEqual(restored.uplink.received, 10_101_050, "Counter regression never underflows")
    try expectEqual(restored.uplink.sent, 3_010_600, "Do not double-count the direction that did not reset")
    try expectEqual(restored.discontinuities, 2, "Counter reset is visible")
    _ = restored.record(sample(215, 75, 25, epoch: "boot-b:9", linkReceived: 10, linkSent: 5))
    try expectEqual(restored.uplink.received, 10_101_125, "Interface replacement within a boot")

    var large = TrafficLedger(baseline: sample(100, 0, 0))
    _ = large.record(sample(105, UInt64.max, UInt64.max))
    _ = large.record(sample(110, 10, 10, epoch: "other"))
    try expectEqual(large.uplink.received, UInt64.max, "Overflow saturates rather than crashes")

    try testTrafficProbe()
}

private func testTrafficProbe() throws {
    // Execute the actual guest probe with OS reads mocked; never change the host network.
    let setup = """
    import json, sys
    from unittest.mock import patch
    class FakePath:
        def __init__(self, name): self.name = str(name)
        def __truediv__(self, name): return FakePath(self.name + '/' + name)
        def read_text(self):
            if self.name.endswith('boot_id'): return 'boot-id'
            if self.name.endswith('ifindex'): return '4' if '/direct0/' in self.name else '3'
            if self.name.endswith('rx_bytes'): return '1000' if '/direct0/' in self.name else '20'
            if self.name.endswith('tx_bytes'): return '200' if '/direct0/' in self.name else '400'
            raise AssertionError(self.name)
    routes = json.loads(sys.argv[2])
    def output(args, **kwargs):
        if 'route' in args: return json.dumps(routes)
        return json.dumps([{'ifname':'lima0','addr_info':[{'local':'192.168.64.2'}]}])
    patch('pathlib.Path', FakePath).start()
    patch('subprocess.check_output', output).start()
    """
    func run(_ routes: String) throws -> (Int32, Data) {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-c", setup + "\n" + TrafficProbe.python, "192.168.64.2", routes]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, output)
    }
    let success = try run("[{\"dev\":\"direct0\"}]")
    try expectEqual(success.0, 0, "Direct-only probe succeeds")
    struct Probe: Decodable { let uplink: TrafficReading; let macLink: TrafficReading }
    let result = try JSONDecoder().decode(Probe.self, from: success.1)
    try expectEqual(result.uplink.bytes, TrafficBytes(received: 1000, sent: 200), "Read external interface bytes")
    try expectEqual(result.macLink.bytes, TrafficBytes(received: 400, sent: 20), "Reverse guest-facing link for Mac download/upload")
    try expectEqual(result.uplink.epoch, "boot-id:4", "Interface epoch includes boot and index")
    for routes in ["[]", "[{\"dev\":\"eth0\"}]", "[{\"dev\":\"direct0\"},{\"dev\":\"eth0\"}]"] {
        let failure = try run(routes)
        try expectEqual(failure.0 == 0, false, "Never label a host fallback as direct traffic")
    }
}
