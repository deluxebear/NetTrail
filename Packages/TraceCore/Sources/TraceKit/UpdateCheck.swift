import Foundation

/// A semantic-ish version such as `0.1.0` or `v0.2.0-rc.1`. A pre-release sorts before its release.
public struct AppVersion: Comparable, Equatable, Sendable {
    let core: [Int]
    let pre: [String]

    public init?(_ text: String) {
        var s = Substring(text.trimmingCharacters(in: .whitespaces))
        if s.hasPrefix("v") || s.hasPrefix("V") { s = s.dropFirst() }
        let halves = s.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard let head = halves.first else { return nil }
        let numbers = head.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !numbers.isEmpty, !numbers.contains(nil) else { return nil }
        core = numbers.compactMap { $0 }
        pre = halves.count > 1 ? halves[1].split(separator: ".").map(String.init) : []
    }

    public static func < (a: AppVersion, b: AppVersion) -> Bool {
        let n = max(a.core.count, b.core.count)
        for i in 0..<n {
            let x = i < a.core.count ? a.core[i] : 0
            let y = i < b.core.count ? b.core[i] : 0
            if x != y { return x < y }
        }
        if a.pre.isEmpty != b.pre.isEmpty { return !a.pre.isEmpty }   // pre-release < release
        for (x, y) in zip(a.pre, b.pre) where x != y {
            if let i = Int(x), let j = Int(y) { return i < j }
            return x < y
        }
        return a.pre.count < b.pre.count
    }
}

public struct AvailableUpdate: Equatable, Sendable {
    public let version: String
    public let url: URL
}

public enum UpdateCheck {
    private struct Release: Decodable {
        let tag_name: String
        let html_url: URL
        let draft: Bool?
        let prerelease: Bool?
    }

    /// The release described by GitHub's `releases/latest` JSON, if it is newer than `current`.
    public static func newerRelease(current: String, json: Data) -> AvailableUpdate? {
        guard let release = try? JSONDecoder().decode(Release.self, from: json),
              release.draft != true, release.prerelease != true,
              let latest = AppVersion(release.tag_name), let installed = AppVersion(current),
              latest > installed
        else { return nil }
        return AvailableUpdate(version: release.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV")),
                               url: release.html_url)
    }
}
