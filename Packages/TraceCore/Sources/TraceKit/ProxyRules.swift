import Darwin
import Foundation

public enum ProxyRuleFormat: String, CaseIterable, Identifiable, Sendable {
    case clash, surge, singBox, plain

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .clash: "Clash / Mihomo"
        case .surge: "Surge / Loon"
        case .singBox: "sing-box"
        case .plain: "纯列表"
        }
    }
}

/// Turns the hosts an app contacted into proxy rules: LAN addresses are dropped and
/// domains collapse to their main domain, matched with DOMAIN-SUFFIX.
public enum ProxyRules {
    public static func render(_ hosts: [String], as format: ProxyRuleFormat) -> String {
        var domains = Set<String>(), ipv4 = Set<String>(), ipv6 = Set<String>()
        for host in hosts where !host.isEmpty && !isLocal(host) {
            if parseIPv4(host) != nil {
                ipv4.insert(host)
            } else if parseIPv6(host) != nil {
                ipv6.insert(host)
            } else {
                domains.insert(mainDomain(host))
            }
        }
        let domainList = domains.sorted(), v4List = ipv4.sorted(), v6List = ipv6.sorted()
        let rules = domainList.map { "DOMAIN-SUFFIX,\($0)" }
            + v4List.map { "IP-CIDR,\($0)/32,no-resolve" }
            + v6List.map { "IP-CIDR6,\($0)/128,no-resolve" }
        switch format {
        case .clash: return rules.isEmpty ? "" : (["payload:"] + rules.map { "  - \($0)" }).joined(separator: "\n")
        case .surge: return rules.joined(separator: "\n")
        case .singBox: return singBoxRuleSet(domains: domainList, cidrs: v4List.map { "\($0)/32" } + v6List.map { "\($0)/128" })
        case .plain: return (domainList + v4List + v6List).joined(separator: "\n")
        }
    }

    /// A source-format rule set (`sing-box rule-set compile` input, or a `local`/`remote` rule set).
    private static func singBoxRuleSet(domains: [String], cidrs: [String]) -> String {
        guard !domains.isEmpty || !cidrs.isEmpty else { return "" }
        var rule: [String: [String]] = [:]
        if !domains.isEmpty { rule["domain_suffix"] = domains }
        if !cidrs.isEmpty { rule["ip_cidr"] = cidrs }
        let ruleSet: [String: Any] = ["version": 2, "rules": [rule]]
        let data = try? JSONSerialization.data(withJSONObject: ruleSet,
                                               options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    /// The registrable domain, e.g. `api.anthropic.com` → `anthropic.com`, `www.bbc.co.uk` → `bbc.co.uk`.
    public static func mainDomain(_ host: String) -> String {
        let labels = normalized(host).split(separator: ".")
        guard labels.count > 2 else { return labels.joined(separator: ".") }
        let lastTwo = labels.suffix(2).joined(separator: ".")
        return labels.suffix(multiLabelSuffixes.contains(lastTwo) ? 3 : 2).joined(separator: ".")
    }

    /// Loopback, private, link-local, CGNAT, multicast and mDNS/home names: traffic that never goes through a proxy.
    public static func isLocal(_ host: String) -> Bool {
        let host = normalized(host)
        if let v4 = parseIPv4(host) { return isLocalIPv4(v4) }
        if let v6 = parseIPv6(host) {
            if v6[0..<10].allSatisfy({ $0 == 0 }) && v6[10] == 0xff && v6[11] == 0xff {
                return isLocalIPv4(Array(v6[12..<16]))
            }
            return v6.allSatisfy { $0 == 0 }                         // ::
                || (v6[0..<15].allSatisfy { $0 == 0 } && v6[15] == 1) // ::1
                || (v6[0] == 0xfe && v6[1] & 0xc0 == 0x80)            // fe80::/10
                || v6[0] & 0xfe == 0xfc                               // fc00::/7
                || v6[0] == 0xff                                      // ff00::/8
        }
        return host == "localhost" || localNameSuffixes.contains { host.hasSuffix($0) }
    }

    private static func isLocalIPv4(_ b: [UInt8]) -> Bool {
        b[0] == 0 || b[0] == 10 || b[0] == 127 || b[0] >= 224
            || (b[0] == 169 && b[1] == 254)
            || (b[0] == 172 && b[1] & 0xf0 == 16)
            || (b[0] == 192 && b[1] == 168)
            || (b[0] == 100 && b[1] & 0xc0 == 64)
    }

    private static func normalized(_ host: String) -> String {
        var host = host.lowercased()
        if host.hasSuffix(".") { host.removeLast() }
        if let zone = host.firstIndex(of: "%") { host = String(host[..<zone]) }
        return host
    }

    private static func parseIPv4(_ host: String) -> [UInt8]? {
        var addr = in_addr()
        guard inet_pton(AF_INET, host, &addr) == 1 else { return nil }
        return withUnsafeBytes(of: addr) { Array($0) }
    }

    private static func parseIPv6(_ host: String) -> [UInt8]? {
        var addr = in6_addr()
        guard inet_pton(AF_INET6, normalized(host), &addr) == 1 else { return nil }
        return withUnsafeBytes(of: addr) { Array($0) }
    }

    private static let localNameSuffixes = [".local", ".localhost", ".lan", ".home.arpa", ".internal"]

    /// Common two-label public suffixes; a full public suffix list is not worth shipping for rule export.
    private static let multiLabelSuffixes: Set<String> = [
        "com.cn", "net.cn", "org.cn", "gov.cn", "edu.cn", "ac.cn",
        "com.hk", "net.hk", "org.hk", "com.tw", "net.tw", "org.tw", "idv.tw", "com.mo",
        "co.jp", "ne.jp", "or.jp", "ac.jp", "go.jp", "co.kr", "or.kr",
        "co.uk", "org.uk", "ac.uk", "gov.uk", "me.uk",
        "com.au", "net.au", "org.au", "co.nz", "com.sg", "com.my", "com.ph", "com.vn", "co.th",
        "co.id", "co.in", "com.br", "com.mx", "com.ar", "com.tr", "co.za", "com.ru",
    ]
}
