import AppKit

/// Finder and the permission card use the bundle icon. The status bar uses a
/// separately packed transparent rendering of that exact same artwork.
enum RazerIcon {
    static var appImage: NSImage {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        return NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
    }

    static func makeStatusItemImage(size: CGFloat = 18) -> NSImage {
        guard let url = Bundle.main.url(forResource: "StatusIcon", withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return appImage }
        image.size = NSSize(width: size, height: size)
        image.isTemplate = true
        return image
    }
}
