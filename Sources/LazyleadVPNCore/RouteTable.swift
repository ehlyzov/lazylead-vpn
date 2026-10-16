import Foundation

public struct IPv4Network: Equatable, Hashable {
    public let address: UInt32
    public let prefixLength: Int

    public init?(_ text: String) {
        let value = text == "default" ? "0.0.0.0/0" : text
        let pieces = value.split(separator: "/", omittingEmptySubsequences: false)
        guard !pieces.isEmpty, pieces.count <= 2 else { return nil }
        let octets = pieces[0].split(separator: ".", omittingEmptySubsequences: false)
        guard (1...4).contains(octets.count) else { return nil }
        var address: UInt32 = 0
        for index in 0..<4 {
            let part = index < octets.count ? String(octets[index]) : "0"
            guard !part.isEmpty, part.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let byte = UInt32(part), byte <= 255 else { return nil }
            address = (address << 8) | byte
        }
        let prefix: Int
        if pieces.count == 2 {
            guard let parsed = Int(pieces[1]), (0...32).contains(parsed) else { return nil }
            prefix = parsed
        } else {
            prefix = octets.count * 8
        }
        self.prefixLength = prefix
        self.address = address & Self.mask(prefix)
    }

    private static func mask(_ prefix: Int) -> UInt32 {
        prefix == 0 ? 0 : UInt32.max << (32 - prefix)
    }

    public var description: String {
        let ip = [24, 16, 8, 0].map { String((address >> $0) & 255) }.joined(separator: ".")
        return prefixLength == 32 ? ip : "\(ip)/\(prefixLength)"
    }

    public func contains(_ other: IPv4Network) -> Bool {
        prefixLength <= other.prefixLength && (other.address & Self.mask(prefixLength)) == address
    }
}

public struct SystemRoute: Equatable {
    public let network: IPv4Network
    public let gateway: String
    public let interface: String
    public let flags: String
    public var isScoped: Bool { flags.contains("I") }
    public var isUsable: Bool { flags.contains("U") && !flags.contains("R") && !flags.contains("B") }

    public func matches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty { return true }
        if query == gateway { return true }
        if let network = IPv4Network(query) { return self.network.contains(network) || network.contains(self.network) }
        return "\(network.description) \(gateway) \(interface) \(isScoped ? "scoped" : "global")"
            .localizedCaseInsensitiveContains(query)
    }
}

public struct RouteTable {
    public let routes: [SystemRoute]

    public init(_ output: String) {
        var interfaceColumn = 3
        var entries: [SystemRoute] = []
        for line in output.split(separator: "\n") {
            let fields = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            if fields.first == "Destination", let index = fields.firstIndex(of: "Netif") {
                interfaceColumn = index
                continue
            }
            guard fields.count > max(2, interfaceColumn), let network = IPv4Network(fields[0]) else { continue }
            entries.append(SystemRoute(network: network, gateway: fields[1], interface: fields[interfaceColumn], flags: fields[2]))
        }
        routes = entries
    }

    public func routes(via gateway: String) -> [SystemRoute] {
        routes.filter { $0.gateway == gateway && $0.isUsable }.sorted {
            if $0.network.address != $1.network.address { return $0.network.address < $1.network.address }
            if $0.network.prefixLength != $1.network.prefixLength { return $0.network.prefixLength < $1.network.prefixLength }
            return $0.interface < $1.interface
        }
    }

    public var defaultInterface: String? {
        routes.first { $0.network.prefixLength == 0 && !$0.isScoped && $0.isUsable }?.interface
    }

    public func route(to address: String) -> SystemRoute? {
        guard let host = IPv4Network(address), host.prefixLength == 32 else { return nil }
        return routes.filter { !$0.isScoped && $0.isUsable && $0.network.contains(host) }
            .max { $0.network.prefixLength < $1.network.prefixLength }
    }
}

public struct LimaDNSRule: Equatable {
    public let domain: String
    public let usesLocalProxy: Bool
    public var displayDomain: String { domain == "xn--p1ai" ? ".рф" : "." + domain }

    public static func parse(_ text: String, filename: String, routes: RouteTable, gateway: String) -> LimaDNSRule? {
        var domain = filename
        var servers: [String] = []
        var port = "53"
        for line in text.split(separator: "\n") {
            let content = line.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0]
            let parts = content.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            guard parts.count >= 2 else { continue }
            switch parts[0].lowercased() {
            case "domain": domain = parts[1]
            case "nameserver": servers.append(parts[1])
            case "port": port = parts[1]
            default: break
            }
        }
        let local = servers.contains("127.0.0.1") && port == "1054"
        // Multiple resolvers may fall back to any configured server. Do not
        // describe a mixed direct/Lima resolver as exclusively using Lima.
        let throughVM = !servers.isEmpty && servers.allSatisfy {
            $0 == gateway || routes.route(to: $0)?.gateway == gateway
        }
        guard (local && servers.allSatisfy { $0 == "127.0.0.1" }) || throughVM else { return nil }
        return LimaDNSRule(domain: domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")), usesLocalProxy: local)
    }
}
