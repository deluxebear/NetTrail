import Darwin
import Foundation
import Security
import TraceCore

/// Resolves audit tokens to code identities, cached per (pid, pid version). Thread-safe.
final class IdentityCache {
    private var cache: [String: AppIdentity] = [:]
    private let lock = NSLock()

    func identity(for token: Data?) -> AppIdentity {
        guard let token, token.count == MemoryLayout<audit_token_t>.size else { return .unknown }
        let audit = token.withUnsafeBytes { $0.loadUnaligned(as: audit_token_t.self) }
        let pid = pid_t(bitPattern: audit.val.5)
        let key = "\(pid):\(audit.val.7)"
        if let hit = lock.withLock({ cache[key] }) { return hit }
        let identity = Self.resolve(token: token, pid: pid)
        lock.withLock {
            if cache.count > 2000 { cache.removeAll() }
            cache[key] = identity
        }
        return identity
    }

    private static func resolve(token: Data, pid: pid_t) -> AppIdentity {
        var code: SecCode?
        let attributes = [kSecGuestAttributeAudit: token] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess, let code else {
            return AppIdentity(signingID: nil, teamID: nil, bundleID: nil,
                               executablePath: processPath(pid) ?? "unknown", pid: pid)
        }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else {
            return AppIdentity(signingID: nil, teamID: nil, bundleID: nil,
                               executablePath: processPath(pid) ?? "unknown", pid: pid)
        }
        var info: CFDictionary?
        SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info)
        let dict = info as? [String: Any] ?? [:]
        var url: CFURL?
        SecCodeCopyPath(staticCode, [], &url)
        let path = (url as URL?)?.path ?? processPath(pid) ?? "unknown"
        let plist = dict[kSecCodeInfoPList as String] as? [String: Any]
        return AppIdentity(signingID: dict[kSecCodeInfoIdentifier as String] as? String,
                           teamID: dict[kSecCodeInfoTeamIdentifier as String] as? String,
                           bundleID: plist?["CFBundleIdentifier"] as? String,
                           executablePath: path, pid: pid)
    }

    private static func processPath(_ pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
