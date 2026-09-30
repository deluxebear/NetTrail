import Foundation

public enum HTTPHostParser {
    private static let methods = ["GET ", "POST ", "PUT ", "HEAD ", "DELETE ", "OPTIONS ", "PATCH ", "CONNECT ", "TRACE "]
    private static let longestMethod = methods.map(\.count).max()!

    public static func parse(_ data: Data) -> PeekResult {
        let prefix = String(decoding: data.prefix(longestMethod), as: UTF8.self)
        guard methods.contains(where: { prefix.hasPrefix($0) }) else {
            if data.count < longestMethod, methods.contains(where: { $0.hasPrefix(prefix) }) {
                return .needMore
            }
            return .notFound
        }
        let text = String(decoding: data, as: UTF8.self)
        let headerEnd = text.range(of: "\r\n\r\n")
        let headerText = headerEnd.map { String(text[..<$0.lowerBound]) } ?? text
        var lines = headerText.components(separatedBy: "\r\n").dropFirst()
        if headerEnd == nil {
            lines = lines.dropLast()   // last line may be cut mid-way
        }
        for line in lines where line.lowercased().hasPrefix("host:") {
            let value = line.dropFirst("host:".count).trimmingCharacters(in: .whitespaces)
            return HostNormalizer.normalizeDomain(stripPort(value)).map(PeekResult.found) ?? .notFound
        }
        return headerEnd == nil ? .needMore : .notFound
    }

    private static func stripPort(_ value: String) -> String {
        if value.hasPrefix("[") {
            return value.firstIndex(of: "]").map { String(value[...$0]) } ?? value
        }
        let parts = value.split(separator: ":", omittingEmptySubsequences: false)
        return parts.count == 2 ? String(parts[0]) : value
    }
}
