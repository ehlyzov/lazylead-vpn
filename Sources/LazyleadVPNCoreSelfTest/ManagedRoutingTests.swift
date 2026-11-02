import Foundation
import LazyleadVPNCore

func runManagedRoutingTests() throws {
    try expectEqual(try RoutingRuleKind.domain.normalize("*.Пример.РФ."), "xn--e1afmkfd.xn--p1ai", "Normalize IDN rule")
    try expectEqual(try RoutingRuleKind.domain.normalize(".RU"), "ru", "Normalize TLD")
    try expectEqual(try RoutingRuleKind.network.normalize("8.8.8.9/24"), "8.8.8.0/24", "Canonical public prefix")
    for (kind, value) in [(RoutingRuleKind.domain, "https://x.com"), (.domain, "x.com/route"),
                           (.domain, "8.8.8.8"), (.domain, "bad;command.com"), (.network, "0.0.0.0/0"),
                           (.network, "172.0.0.0/8"), (.network, "192.168.64.2"), (.network, "8.8"), (.network, "::1")] {
        var rejected = false
        do { _ = try kind.normalize(value) } catch { rejected = true }
        try expectEqual(rejected, true, "Reject unsafe or invalid routing destination: \(value)")
    }
    let rules = ManagedRoutingRules(domains: ["ru", "vkvideo.cloud"], networks: ["8.8.8.0/24"])
    let restored = try JSONDecoder().decode(ManagedRoutingRules.self, from: JSONEncoder().encode(rules))
    try expectEqual(restored.networks, rules.networks, "Routing preferences JSON compatibility")
}
