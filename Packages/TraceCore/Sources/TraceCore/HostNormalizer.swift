import Foundation

public enum HostNormalizer {
    private static let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-._")

    /// Lowercased DNS name without trailing dot, or nil for empty, invalid, or IP-literal input.
    public static func normalizeDomain(_ raw: String?) -> String? {
        guard let raw else { return nil }
        var name = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        while name.hasSuffix(".") { name.removeLast() }
        guard !name.isEmpty, name.utf8.count <= 253,
              !name.hasPrefix("."), !name.contains("..") else { return nil }
        guard name.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        guard IPAddressText.normalize(name) == nil else { return nil }
        return name
    }
}
