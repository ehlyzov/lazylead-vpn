import Foundation
import LazyleadVPNCore

struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ name: String) throws {
    if actual != expected {
        throw TestFailure(description: "\(name): expected \(expected), got \(actual)")
    }
}

func run() throws {
    let samlOutput = """
    For identity provider authentication, open the following URL in your browser:
    https://vpn.example.com/saml-vpn/spPortal/ServiceProviderTabs?realm=vpn.example.com&session=example-session
    """

    try expectEqual(
        SAMLURLParser.extract(from: samlOutput)?.absoluteString,
        "https://vpn.example.com/saml-vpn/spPortal/ServiceProviderTabs?realm=vpn.example.com&session=example-session",
        "SAML URL extraction"
    )

    try expectEqual(
        ShellQuoter.quote("/tmp/a b/it's.sh install"),
        "'/tmp/a b/it'\"'\"'s.sh install'",
        "shell single quote escaping"
    )

    let commands = VPNCommandFactory(
        projectDirectory: "/project",
        vmName: "lazylead-vpn",
        vmGateway: "192.168.64.2"
    )

    try expectEqual(commands.snxCommand().executable, "limactl", "snx executable")
    try expectEqual(commands.snxCommand().arguments, [
        "shell",
        "lazylead-vpn",
        "--",
        "sh",
        "-lc",
        "sudo snx-rs -c $HOME/.config/snx-rs/snx-rs.conf -m standalone -l debug"
    ], "snx arguments")

    try expectEqual(
        commands.installCorporateRoutesScript(),
        "'/project/host_corporate_routes.sh' install '192.168.64.2'",
        "corporate route script"
    )
    try expectEqual(
        commands.installCorporateRoutesAdminCommand(),
        VPNCommand(
            executable: "/usr/local/libexec/lazylead-vpn/host_corporate_routes.sh",
            arguments: ["install", "192.168.64.2"]
        ),
        "corporate route admin command"
    )
    try expectEqual(commands.gatewayProbeCommand().arguments.suffix(2), [
        "12",
        "https://vpn.example.com/clients/"
    ], "gateway probe command")

    // A lower-priority host/VPN default route must not become a silent fallback.
    let directProbe = commands.directNetworkProbeCommand().arguments.last!
    for (routes, expectedStatus) in [
        ("default via 192.168.1.1 dev direct0 metric 50", Int32(0)),
        ("default via 192.168.1.1 dev direct0 metric 50\ndefault via 192.168.5.2 dev eth0 metric 200", Int32(1)),
        ("default via 192.168.1.1 dev direct01", Int32(1)),
        ("", Int32(1))
    ] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "ip() { printf '%s' \"$TEST_ROUTES\"; }; " + directProbe]
        process.environment = ["PATH": "/usr/bin:/bin", "TEST_ROUTES": routes]
        try process.run()
        process.waitUntilExit()
        try expectEqual(process.terminationStatus, expectedStatus, "direct route validation: \(routes)")
    }

    try expectEqual(VPNState.connected.menuTitle, "Lazylead VPN: Connected", "connected state label")
    try expectEqual(VPNState.disconnected.usesActiveIcon, false, "disconnected inactive icon")
    try expectEqual(VPNState.waitingFor2FA.usesActiveIcon, true, "waiting active icon")
    try expectEqual(VPNState.connected.usesActiveIcon, true, "connected active icon")
    try runRoutingTests()
}

do {
    try run()
    print("LazyleadVPNCoreSelfTest passed")
} catch {
    fputs("LazyleadVPNCoreSelfTest failed: \(error)\n", stderr)
    exit(1)
}
