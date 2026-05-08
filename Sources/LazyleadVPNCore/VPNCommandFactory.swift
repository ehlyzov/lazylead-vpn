import Foundation

public struct VPNCommand: Equatable {
    public let executable: String
    public let arguments: [String]
    public let workingDirectory: String?

    public init(executable: String, arguments: [String], workingDirectory: String? = nil) {
        self.executable = executable
        self.arguments = arguments
        self.workingDirectory = workingDirectory
    }
}

public struct VPNCommandFactory {
    public static let privilegedScriptsDirectory = "/usr/local/libexec/lazylead-vpn"

    public let projectDirectory: String
    public let vmName: String
    public let vmGateway: String
    public let limactl: String
    public let snxConfigPath: String
    public let gatewayProbeURL: String

    public init(
        projectDirectory: String,
        vmName: String = "lazylead-vpn",
        vmGateway: String = "192.168.64.2",
        limactl: String = "limactl",
        snxConfigPath: String = "$HOME/.config/snx-rs/snx-rs.conf",
        gatewayProbeURL: String = "https://vpn.example.com/clients/"
    ) {
        self.projectDirectory = projectDirectory
        self.vmName = vmName
        self.vmGateway = vmGateway
        self.limactl = limactl
        self.snxConfigPath = snxConfigPath
        self.gatewayProbeURL = gatewayProbeURL
    }

    public func startVMCommand() -> VPNCommand {
        VPNCommand(executable: limactl, arguments: ["start", vmName])
    }

    public func copyRouterCommand() -> VPNCommand {
        VPNCommand(
            executable: limactl,
            arguments: ["copy", "\(projectDirectory)/vm_corporate_router.sh", "\(vmName):/tmp/vm_corporate_router.sh"]
        )
    }

    public func chmodRouterCommand() -> VPNCommand {
        VPNCommand(executable: limactl, arguments: ["shell", vmName, "--", "chmod", "+x", "/tmp/vm_corporate_router.sh"])
    }

    public func snxCommand() -> VPNCommand {
        VPNCommand(
            executable: limactl,
            arguments: [
                "shell",
                vmName,
                "--",
                "sh",
                "-lc",
                "sudo snx-rs -c \(snxConfigPath) -m standalone -l debug"
            ]
        )
    }

    public func installVMRouterCommand() -> VPNCommand {
        VPNCommand(
            executable: limactl,
            arguments: ["shell", vmName, "--", "sudo", "/tmp/vm_corporate_router.sh", "install", "lima0", "snx-tun"]
        )
    }

    public func gatewayProbeCommand() -> VPNCommand {
        VPNCommand(
            executable: limactl,
            arguments: [
                "shell",
                vmName,
                "--",
                "curl",
                "-kIs",
                "--connect-timeout",
                "5",
                "--max-time",
                "12",
                gatewayProbeURL
            ]
        )
    }

    public func stopSNXCommand() -> VPNCommand {
        VPNCommand(executable: limactl, arguments: ["shell", vmName, "--", "sudo", "pkill", "-f", "snx-rs"])
    }

    public func installCheckpointRouteScript() -> String {
        "\(ShellQuoter.quote("\(projectDirectory)/host_checkpoint_gateway_route.sh")) install"
    }

    public func removeCheckpointRouteScript() -> String {
        "\(ShellQuoter.quote("\(projectDirectory)/host_checkpoint_gateway_route.sh")) remove"
    }

    public func installCorporateRoutesScript() -> String {
        "\(ShellQuoter.quote("\(projectDirectory)/host_corporate_routes.sh")) install \(ShellQuoter.quote(vmGateway))"
    }

    public func removeCorporateRoutesScript() -> String {
        "\(ShellQuoter.quote("\(projectDirectory)/host_corporate_routes.sh")) remove \(ShellQuoter.quote(vmGateway))"
    }

    public func installCheckpointRouteAdminCommand() -> VPNCommand {
        VPNCommand(executable: "\(Self.privilegedScriptsDirectory)/host_checkpoint_gateway_route.sh", arguments: ["install"])
    }

    public func removeCheckpointRouteAdminCommand() -> VPNCommand {
        VPNCommand(executable: "\(Self.privilegedScriptsDirectory)/host_checkpoint_gateway_route.sh", arguments: ["remove"])
    }

    public func installCorporateRoutesAdminCommand() -> VPNCommand {
        VPNCommand(executable: "\(Self.privilegedScriptsDirectory)/host_corporate_routes.sh", arguments: ["install", vmGateway])
    }

    public func removeCorporateRoutesAdminCommand() -> VPNCommand {
        VPNCommand(executable: "\(Self.privilegedScriptsDirectory)/host_corporate_routes.sh", arguments: ["remove", vmGateway])
    }
}
