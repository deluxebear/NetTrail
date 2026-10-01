import Testing
@testable import TraceKit

@Suite struct ProxyRulesTests {
    @Test func collapsesDomainsToTheirMainDomain() {
        #expect(ProxyRules.mainDomain("api.anthropic.com") == "anthropic.com")
        #expect(ProxyRules.mainDomain("a.b.c.example.org.") == "example.org")
        #expect(ProxyRules.mainDomain("www.bbc.co.uk") == "bbc.co.uk")
        #expect(ProxyRules.mainDomain("img.alicdn.com.cn") == "alicdn.com.cn")
        #expect(ProxyRules.mainDomain("Claude.AI") == "claude.ai")
        #expect(ProxyRules.mainDomain("localhost") == "localhost")
    }

    @Test(arguments: ["10.0.0.1", "172.16.5.4", "172.31.255.255", "192.168.50.26", "127.0.0.1",
                      "169.254.1.1", "100.64.0.1", "224.0.0.251", "255.255.255.255", "0.0.0.0",
                      "::1", "::", "fe80::1462:b109:6aa3:b476", "fe80::1%en0", "fd12:3456::1", "ff02::fb",
                      "::ffff:192.168.1.1", "printer.local", "router.lan", "nas.home.arpa", "localhost"])
    func treatsLocalAddressesAsLocal(_ host: String) {
        #expect(ProxyRules.isLocal(host))
    }

    @Test(arguments: ["34.160.81.0", "172.32.0.1", "8.8.8.8", "2606:4700::1111", "api.anthropic.com"])
    func treatsPublicAddressesAsRemote(_ host: String) {
        #expect(!ProxyRules.isLocal(host))
    }

    let hosts = ["api.anthropic.com", "claude.ai", "statsig.anthropic.com", "192.168.50.26",
                 "34.160.81.0", "fe80::1", "2606:4700::1111", "printer.local", ""]

    @Test func rendersClashRuleProvider() {
        #expect(ProxyRules.render(hosts, as: .clash) == """
        payload:
          - DOMAIN-SUFFIX,anthropic.com
          - DOMAIN-SUFFIX,claude.ai
          - IP-CIDR,34.160.81.0/32,no-resolve
          - IP-CIDR6,2606:4700::1111/128,no-resolve
        """)
    }

    @Test func rendersSurgeRuleSet() {
        #expect(ProxyRules.render(hosts, as: .surge) == """
        DOMAIN-SUFFIX,anthropic.com
        DOMAIN-SUFFIX,claude.ai
        IP-CIDR,34.160.81.0/32,no-resolve
        IP-CIDR6,2606:4700::1111/128,no-resolve
        """)
    }

    @Test func rendersSingBoxRuleSet() {
        #expect(ProxyRules.render(hosts, as: .singBox) == """
        {
          "rules" : [
            {
              "domain_suffix" : [
                "anthropic.com",
                "claude.ai"
              ],
              "ip_cidr" : [
                "34.160.81.0/32",
                "2606:4700::1111/128"
              ]
            }
          ],
          "version" : 2
        }
        """)
    }

    @Test func rendersPlainList() {
        #expect(ProxyRules.render(hosts, as: .plain) == """
        anthropic.com
        claude.ai
        34.160.81.0
        2606:4700::1111
        """)
    }

    @Test func rendersNothingWhenEverythingIsLocal() {
        for format in ProxyRuleFormat.allCases {
            #expect(ProxyRules.render(["192.168.1.1", "fe80::1"], as: format).isEmpty)
        }
    }
}
