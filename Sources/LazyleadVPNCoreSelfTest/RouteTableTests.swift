import Foundation
import LazyleadVPNCore

func runRoutingTests() throws {
    let table = RouteTable("""
    Routing tables
    Internet:
    Destination Gateway Flags Netif Expire
    default 192.168.1.1 UGScIg en0
    default link#26 UCSg utun5
    127 127.0.0.1 UCS lo0
    51.250/17 192.168.64.2 UGSc bridge101
    84.201.181.26 192.168.64.2 UGHS bridge101
    84.201.181.27 192.168.1.1 UGHS en0
    95.173.128.90 192.168.64.2 UGHSI bridge101
    203.0.113/24 192.168.64.2 UGHR bridge101
    invalid row should not parse
    """)
    let lima = table.routes(via: "192.168.64.2")
    try expectEqual(lima.map { $0.network.description }, ["51.250.0.0/17", "84.201.181.26", "95.173.128.90"], "only usable Lima routes")
    try expectEqual(table.defaultInterface, "utun5", "scoped physical default is not global default")
    try expectEqual(table.route(to: "51.250.33.235")?.gateway, "192.168.64.2", "abbreviated network covers host")
    try expectEqual(table.route(to: "84.201.181.27")?.gateway, "192.168.1.1", "specific non-Lima route is respected")
    try expectEqual(table.route(to: "95.173.128.90")?.interface, "utun5", "scoped route does not claim global lookup")
    try expectEqual(lima[0].matches("51.250.33.235"), true, "IP search finds covering prefix")
    try expectEqual(lima[0].matches("51.251.0.1"), false, "IP search respects mask")
    try expectEqual(lima[0].matches("51.250.0.0/16"), true, "CIDR search includes more-specific installed networks")
    try expectEqual(lima[0].matches("51.250.128.0/17"), false, "CIDR search excludes disjoint networks")
    try expectEqual(lima[0].matches("BRIDGE101"), true, "interface search")
    try expectEqual(lima[0].matches("192.168.64.2"), true, "gateway search")
    try expectEqual(IPv4Network("10")?.description, "10.0.0.0/8", "abbreviated classful network")
    try expectEqual(IPv4Network("default")?.contains(IPv4Network("255.255.255.255")!), true, "zero prefix has no shift overflow")
    for invalid in ["", "1.2.3.999", "::1", "1.2.3.4/33", "1.2.3.4/-1", "1..2", "1.2.3.4/", "example.com"] {
        try expectEqual(IPv4Network(invalid), nil, "reject malformed network: \(invalid)")
    }
    let legacy = RouteTable("Destination Gateway Flags Refs Use Netif Expire\n10/8 192.168.64.2 UGSc 0 0 bridge105\n")
    try expectEqual(legacy.routes.first?.interface, "bridge105", "Netif header position")
    let ru = LimaDNSRule.parse("domain ru\nnameserver 127.0.0.1\nport 1054\n", filename: "ru", routes: table, gateway: "192.168.64.2")
    try expectEqual(ru?.displayDomain, ".ru", "installed domain rule")
    let rf = LimaDNSRule.parse("nameserver 127.0.0.1\nport 1054 # comment\n", filename: "xn--p1ai", routes: table, gateway: "192.168.64.2")
    try expectEqual(rf?.displayDomain, ".рф", "IDN display")
    try expectEqual(LimaDNSRule.parse("nameserver 127.0.0.1\nport 53", filename: "ru", routes: table, gateway: "192.168.64.2"), nil, "unrelated loopback DNS excluded")
    try expectEqual(LimaDNSRule.parse("nameserver 127.0.0.1\nnameserver 8.8.8.8\nport 1054", filename: "ru", routes: table, gateway: "192.168.64.2"), nil, "mixed DNS cannot claim exclusive Lima routing")
    let corporate = LimaDNSRule.parse("nameserver 84.201.181.26", filename: "corp.example", routes: table, gateway: "192.168.64.2")
    try expectEqual(corporate?.usesLocalProxy, false, "corporate DNS routed through Lima")
}
