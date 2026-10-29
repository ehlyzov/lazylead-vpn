import Foundation

public enum VPNState: Equatable {
    case disconnected
    case startingVM
    case preparing
    case waitingFor2FA
    case configuring
    case connected
    case disconnecting
    case error(String)

    public var label: String {
        switch self {
        case .disconnected:
            "Disconnected"
        case .startingVM:
            "Starting VM"
        case .preparing:
            "Preparing"
        case .waitingFor2FA:
            "Waiting for 2FA"
        case .configuring:
            "Configuring"
        case .connected:
            "Connected"
        case .disconnecting:
            "Disconnecting"
        case .error:
            "Error"
        }
    }

    public var menuTitle: String {
        "Lazylead VPN: \(label)"
    }

    public var canConnect: Bool {
        switch self {
        case .disconnected, .error:
            true
        default:
            false
        }
    }

    public var canDisconnect: Bool {
        switch self {
        case .disconnected, .disconnecting:
            false
        default:
            true
        }
    }

    public var errorMessage: String? {
        if case let .error(message) = self {
            message
        } else {
            nil
        }
    }

    public var usesActiveIcon: Bool {
        switch self {
        case .startingVM, .preparing, .waitingFor2FA, .configuring, .connected, .disconnecting:
            true
        case .disconnected, .error:
            false
        }
    }

    /// Reconcile Direct mode with the VM, including starts/stops outside this app.
    public func synchronizedDirectState(vmStatus: String?, networkHealthy: Bool) -> VPNState {
        switch self {
        case .startingVM, .preparing, .waitingFor2FA, .configuring, .disconnecting:
            return self
        default:
            break
        }
        switch vmStatus?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "stopped":
            return .disconnected
        case "running":
            return networkHealthy ? .connected : .error("Lima is running, but its direct0 default route could not be verified.")
        default:
            return .error("The Lima VM status could not be read.")
        }
    }
}
