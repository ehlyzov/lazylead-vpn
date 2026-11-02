import Foundation

public struct ManagedRoutingRules: Codable {
    public var version: Int
    public var domains: [String]
    public var networks: [String]

    public init(version: Int = 1, domains: [String] = [], networks: [String] = []) {
        self.version = version
        self.domains = domains
        self.networks = networks
    }
}

public enum RoutingRuleKind: String, CaseIterable {
    case domain, network
    public var title: String { self == .domain ? "Domain" : "IPv4 address / network" }

    public func normalize(_ input: String) throws -> String {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        func invalid(_ message: String) -> NSError {
            NSError(domain: "LazyleadVPN.RoutingRule", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
        if self == .network {
            let address = value.split(separator: "/", omittingEmptySubsequences: false).first ?? ""
            guard address.split(separator: ".", omittingEmptySubsequences: false).count == 4,
                  let parsed = IPv4Network(value) else {
                throw invalid("Enter a complete IPv4 address or CIDR, such as 8.8.8.8 or 8.8.8.0/24.")
            }
            let protected = ["0/8", "10/8", "100.64/10", "127/8", "169.254/16", "172.16/12",
                             "192.0.0/24", "192.0.2/24", "192.168/16", "198.18/15", "198.51.100/24",
                             "203.0.113/24", "224/4", "240/4"].compactMap(IPv4Network.init)
            guard !protected.contains(where: { $0.contains(parsed) || parsed.contains($0) }) else {
                throw invalid("Only public IPv4 destinations are supported. Local and default routes are protected.")
            }
            return parsed.description
        }
        var name = value.lowercased()
        if name.hasPrefix("*.") { name.removeFirst(2) }
        name = name.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard !name.contains(where: { $0.isWhitespace }), !name.contains(":"), !name.contains("/"),
              let host = URL(string: "https://" + name)?.host, host.count <= 253 else {
            throw invalid("Enter a domain without a URL, port, or path, such as example.com or .ru.")
        }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard !labels.isEmpty, labels.allSatisfy({ label in
            !label.isEmpty && label.count <= 63 && label.first != "-" && label.last != "-" &&
            label.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
        }), labels.last?.allSatisfy({ $0.isNumber }) == false else {
            throw invalid("Enter a valid domain, such as example.com or .ru.")
        }
        return host.lowercased()
    }
}
