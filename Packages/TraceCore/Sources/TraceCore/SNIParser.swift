import Foundation

public enum SNIParser {
    private enum Outcome {
        case host(String)
        case noSNI
        case truncated
        case malformed
    }

    public static func parse(_ data: Data) -> PeekResult {
        let bytes = [UInt8](data)
        guard let first = bytes.first else { return .needMore }
        guard first == 0x16 else { return .notFound }
        guard bytes.count >= 5 else { return bytes.count >= 2 && bytes[1] != 0x03 ? .notFound : .needMore }
        guard bytes[1] == 0x03 else { return .notFound }
        let recordLength = Int(bytes[3]) << 8 | Int(bytes[4])
        let recordComplete = bytes.count >= 5 + recordLength
        var reader = ByteReader(bytes, offset: 5)
        switch parseClientHello(&reader) {
        case .host(let raw):
            return HostNormalizer.normalizeDomain(raw).map(PeekResult.found) ?? .notFound
        case .truncated:
            return recordComplete ? .notFound : .needMore
        case .noSNI, .malformed:
            return .notFound
        }
    }

    private static func parseClientHello(_ r: inout ByteReader) -> Outcome {
        guard let type = r.u8() else { return .truncated }
        guard type == 0x01 else { return .malformed }
        guard r.u24() != nil, r.skip(2 + 32) else { return .truncated }
        guard let sessionLength = r.u8(), r.skip(Int(sessionLength)) else { return .truncated }
        guard let suitesLength = r.u16(), r.skip(Int(suitesLength)) else { return .truncated }
        guard let compressionLength = r.u8(), r.skip(Int(compressionLength)) else { return .truncated }
        guard let extensionsLength = r.u16() else { return .truncated }
        let extensionsEnd = r.offset + Int(extensionsLength)
        while r.offset + 4 <= extensionsEnd {
            guard let extType = r.u16(), let extLength = r.u16() else { return .truncated }
            guard extType == 0x0000 else {
                guard r.skip(Int(extLength)) else { return .truncated }
                continue
            }
            guard let listLength = r.u16() else { return .truncated }
            let listEnd = r.offset + Int(listLength)
            while r.offset + 3 <= listEnd {
                guard let nameType = r.u8(), let nameLength = r.u16(),
                      let name = r.take(Int(nameLength)) else { return .truncated }
                if nameType == 0 {
                    return .host(String(decoding: name, as: UTF8.self))
                }
            }
            return .noSNI
        }
        return r.offset >= extensionsEnd ? .noSNI : .truncated
    }
}
