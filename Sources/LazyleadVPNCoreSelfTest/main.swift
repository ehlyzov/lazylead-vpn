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

    try expectEqual(VPNState.connected.menuTitle, "Lazylead VPN: Connected", "connected state label")
    try expectEqual(VPNState.disconnected.usesActiveIcon, false, "disconnected inactive icon")
    try expectEqual(VPNState.waitingFor2FA.usesActiveIcon, true, "waiting active icon")
    try expectEqual(VPNState.connected.usesActiveIcon, true, "connected active icon")
}

do {
    try run()
    print("LazyleadVPNCoreSelfTest passed")
} catch {
    fputs("LazyleadVPNCoreSelfTest failed: \(error)\n", stderr)
    exit(1)
}
