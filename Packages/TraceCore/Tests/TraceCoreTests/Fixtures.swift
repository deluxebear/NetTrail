import Foundation

extension Data {
    init(hex: String) {
        var bytes: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            bytes.append(UInt8(hex[index..<next], radix: 16)!)
            index = next
        }
        self.init(bytes)
    }
}

func be16(_ value: Int) -> [UInt8] { [UInt8((value >> 8) & 0xff), UInt8(value & 0xff)] }
func be24(_ value: Int) -> [UInt8] { [UInt8((value >> 16) & 0xff), UInt8((value >> 8) & 0xff), UInt8(value & 0xff)] }

/// Minimal TLS 1.2-style ClientHello record with the given extensions, in order.
func clientHello(extensions: [(type: Int, data: [UInt8])]) -> Data {
    var body: [UInt8] = [0x03, 0x03] + Array(repeating: 0xAB, count: 32)
    body += [0x00]                       // session id length
    body += be16(2) + [0x13, 0x01]       // cipher suites
    body += [0x01, 0x00]                 // compression methods
    var ext: [UInt8] = []
    for e in extensions { ext += be16(e.type) + be16(e.data.count) + e.data }
    body += be16(ext.count) + ext
    let handshake: [UInt8] = [0x01] + be24(body.count) + body
    return Data([0x16, 0x03, 0x01] + be16(handshake.count) + handshake)
}

func sniExtension(_ host: String) -> (type: Int, data: [UInt8]) {
    let name = Array(host.utf8)
    let entry: [UInt8] = [0x00] + be16(name.count) + name
    return (0x0000, be16(entry.count) + entry)
}

/// ClientHello captured from `curl https://www.example.com` (curl 8.7.1, LibreSSL).
let curlClientHelloHex = "16030101400100013c0303e61c0b8ec8671925ed00e35df27a4be2ff5a8803e06dc2e9132cf22bc6a9410d202dd698e3caf7126b98c2013147a45ad03342c5230c8dd4e090ec4ed536e0d1e40062130313021301cca9cca8ccaac030c02cc028c024c014c00a009f006b0039ff8500c400880081009d003d003500c00084c02fc02bc027c023c013c009009e0067003300be0045009c003c002f00ba0041c011c00700050004c012c0080016000a00ff01000091002b0009080304030303020301003300260024001d0020e4a83158e10a9a0bb34917d9b749b90dad284e9d80c06eab9db5ddd12fe9480500000014001200000f7777772e6578616d706c652e636f6d000b00020100000a000a0008001d001700180019000d00180016080606010603080505010503080404010403020102030010000e000c02683208687474702f312e31"

/// Random bytes for fuzz-style tests.
func randomBytes(count: Int) -> [UInt8] {
    (0..<count).map { _ in UInt8.random(in: 0...255) }
}
