import AppKit
import SwiftUI

struct AppIconView: View {
    /// Lists re-render on every data refresh; icon lookups hit the disk, so keep them per path.
    private static let cache = NSCache<NSString, NSImage>()

    let path: String?
    var size: CGFloat = 16

    var body: some View {
        Image(nsImage: icon)
            .resizable()
            .frame(width: size, height: size)
    }

    private var icon: NSImage {
        let key = (path ?? "") as NSString
        if let cached = Self.cache.object(forKey: key) { return cached }
        let image: NSImage
        if let path, FileManager.default.fileExists(atPath: path) {
            image = NSWorkspace.shared.icon(forFile: path)
        } else {
            image = NSWorkspace.shared.icon(for: .unixExecutable)
        }
        Self.cache.setObject(image, forKey: key)
        return image
    }
}
