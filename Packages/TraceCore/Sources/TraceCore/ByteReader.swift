/// Bounds-checked big-endian reader. Every read returns nil instead of trapping.
struct ByteReader {
    let bytes: [UInt8]
    var offset: Int

    init(_ bytes: [UInt8], offset: Int = 0) {
        self.bytes = bytes
        self.offset = offset
    }

    var remaining: Int { bytes.count - offset }

    mutating func u8() -> UInt8? {
        guard remaining >= 1 else { return nil }
        defer { offset += 1 }
        return bytes[offset]
    }

    mutating func u16() -> UInt16? {
        guard remaining >= 2 else { return nil }
        defer { offset += 2 }
        return UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1])
    }

    mutating func u24() -> Int? {
        guard remaining >= 3 else { return nil }
        defer { offset += 3 }
        return Int(bytes[offset]) << 16 | Int(bytes[offset + 1]) << 8 | Int(bytes[offset + 2])
    }

    mutating func u32() -> UInt32? {
        guard remaining >= 4 else { return nil }
        defer { offset += 4 }
        return UInt32(bytes[offset]) << 24 | UInt32(bytes[offset + 1]) << 16
            | UInt32(bytes[offset + 2]) << 8 | UInt32(bytes[offset + 3])
    }

    mutating func take(_ count: Int) -> ArraySlice<UInt8>? {
        guard count >= 0, remaining >= count else { return nil }
        defer { offset += count }
        return bytes[offset..<offset + count]
    }

    mutating func skip(_ count: Int) -> Bool {
        take(count) != nil
    }
}
