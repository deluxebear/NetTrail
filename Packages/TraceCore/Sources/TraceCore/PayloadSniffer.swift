import Foundation

public enum PayloadSniffer {
    public static let maxPeekBytes = 4096

    public static func sniff(_ data: Data) -> SniffResult {
        guard let first = data.first else { return .needMore }
        if first == 0x16 {
            return map(SNIParser.parse(data), source: .sni)
        }
        return map(HTTPHostParser.parse(data), source: .httpHost)
    }

    private static func map(_ result: PeekResult, source: HostSource) -> SniffResult {
        switch result {
        case .found(let host): return .found(host: host, source: source)
        case .needMore: return .needMore
        case .notFound: return .notFound
        }
    }
}
