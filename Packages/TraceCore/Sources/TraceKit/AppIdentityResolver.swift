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
        return ResolvedApp(key: identity.signingID ?? identity.executablePath,
                           displayName: URL(fileURLWithPath: identity.executablePath).lastPathComponent,
                           bundleID: identity.bundleID, path: identity.executablePath, teamID: identity.teamID)
    }

    /// Path of the first `.app` component in `path`, e.g. Slack.app for its helper apps.
    public static func outermostAppBundle(containing path: String) -> String? {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard let index = components.firstIndex(where: { $0.hasSuffix(".app") }) else { return nil }
        return components[...index].joined(separator: "/")
    }
}
