import Darwin
import Foundation
import Security
import TraceCore

/// Resolves audit tokens to code identities and launch origins, cached per (pid, pid version). Thread-safe.
final class IdentityCache {
    struct Source {
        let identity: AppIdentity
        let origin: ProcessOrigin?
    }

    private var cache: [String: Source] = [:]
    private let lock = NSLock()

    func source(for token: Data?) -> Source {
        guard let token, token.count == MemoryLayout<audit_token_t>.size else { return Source(identity: .unknown, origin: nil) }
        let audit = token.withUnsafeBytes { $0.loadUnaligned(as: audit_token_t.self) }
        let pid = pid_t(bitPattern: audit.val.5)
        let key = "\(pid):\(audit.val.7)"
        if let hit = lock.withLock({ cache[key] }) { return hit }
        let source = Source(identity: Self.resolve(token: token, pid: pid), origin: ProcessInspector.origin(pid: pid))
        lock.withLock {
            if cache.count > 2000 { cache.removeAll() }
            cache[key] = source
        }
        return source
    }

    private static func resolve(token: Data, pid: pid_t) -> AppIdentity {
        var code: SecCode?
        let attributes = [kSecGuestAttributeAudit: token] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess, let code else {
            return kernelIdentity(pid)
        }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else {
            return kernelIdentity(pid)
        }
        var info: CFDictionary?
        SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info)
        let dict = info as? [String: Any] ?? [:]
        var url: CFURL?
        SecCodeCopyPath(staticCode, [], &url)
        let path = (url as URL?)?.path ?? ProcessInspector.executablePath(pid) ?? "unknown"
        let plist = dict[kSecCodeInfoPList as String] as? [String: Any]
        guard let signingID = dict[kSecCodeInfoIdentifier as String] as? String else {
            // Reading signing info opens the executable, which the sandbox denies outside a few
            // system locations; the kernel's copy of the identity works everywhere.
            let kernel = ProcessInspector.signingIdentity(pid: pid)
            return AppIdentity(signingID: kernel.signingID, teamID: kernel.teamID, bundleID: nil,
                               executablePath: path, pid: pid)
        }
        return AppIdentity(signingID: signingID,
                           teamID: dict[kSecCodeInfoTeamIdentifier as String] as? String,
                           bundleID: plist?["CFBundleIdentifier"] as? String,
                           executablePath: path, pid: pid)
    }

    private static func kernelIdentity(_ pid: pid_t) -> AppIdentity {
        let kernel = ProcessInspector.signingIdentity(pid: pid)
        return AppIdentity(signingID: kernel.signingID, teamID: kernel.teamID, bundleID: nil,
                           executablePath: ProcessInspector.executablePath(pid) ?? "unknown", pid: pid)
    }
}
