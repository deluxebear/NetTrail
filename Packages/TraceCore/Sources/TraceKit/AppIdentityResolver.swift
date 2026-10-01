import Foundation
import TraceCore

/// Maps a raw code identity to the app a user would recognize. Not thread-safe; use from one actor.
public final class AppIdentityResolver {
    private var cache: [String: ResolvedApp] = [:]

    public init() {}

    public func resolve(_ identity: AppIdentity) -> ResolvedApp {
        let cacheKey = identity.executablePath + "|" + (identity.signingID ?? "")
        if let hit = cache[cacheKey] { return hit }
        let resolved = Self.makeResolved(identity)
        if cache.count > 2000 { cache.removeAll() }
        cache[cacheKey] = resolved
        return resolved
    }

    static func makeResolved(_ identity: AppIdentity) -> ResolvedApp {
        if let appPath = outermostAppBundle(containing: identity.executablePath),
           let bundle = Bundle(path: appPath), let bundleID = bundle.bundleIdentifier {
            let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                ?? URL(fileURLWithPath: appPath).deletingPathExtension().lastPathComponent
            return ResolvedApp(key: bundleID, displayName: name, bundleID: bundleID, path: appPath, teamID: identity.teamID)
        }
        // Only reverse-DNS signing IDs name a product (`com.anthropic.claude-code` across versions); bare ones
        // like `node` are shared by unrelated installs, and ad-hoc ones (`git-remote-http-5555…`) change per build.
        let key = identity.signingID.flatMap { $0.contains(".") ? $0 : nil } ?? identity.executablePath
        return ResolvedApp(key: key,
                           displayName: toolName(forExecutableAt: identity.executablePath),
                           bundleID: identity.bundleID, path: identity.executablePath, teamID: identity.teamID)
    }

    private static let genericFolders: Set<String> = ["bin", "sbin", "libexec", "versions", "releases", "current"]

    /// The executable's file name, or for version-named binaries (e.g. `claude/versions/2.1.286`)
    /// the nearest folder that is neither a version nor a generic folder like `bin`.
    public static func toolName(forExecutableAt path: String) -> String {
        let components = path.split(separator: "/").map(String.init)
        guard let last = components.last else { return path }
        guard isVersion(last) else { return last }
        return components.dropLast().reversed()
            .first { !isVersion($0) && !genericFolders.contains($0.lowercased()) } ?? last
    }

    private static func isVersion(_ text: String) -> Bool {
        text.first?.isNumber == true && text.allSatisfy { $0.isNumber || $0 == "." || $0 == "-" }
    }

    /// Path of the first `.app` component in `path`, e.g. Slack.app for its helper apps.
    public static func outermostAppBundle(containing path: String) -> String? {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard let index = components.firstIndex(where: { $0.hasSuffix(".app") }) else { return nil }
        return components[...index].joined(separator: "/")
    }
}
