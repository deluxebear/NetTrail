import AppKit
import SwiftUI

struct AppIconView: View {
    let path: String?
    var size: CGFloat = 16

    var body: some View {
        Image(nsImage: icon)
            .resizable()
            .frame(width: size, height: size)
    }

    private var icon: NSImage {
        guard let path, FileManager.default.fileExists(atPath: path) else {
            return NSWorkspace.shared.icon(for: .unixExecutable)
        }
        return NSWorkspace.shared.icon(forFile: path)
    }
}
