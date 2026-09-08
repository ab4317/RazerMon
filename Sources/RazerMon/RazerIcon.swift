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
              let source = NSImage(contentsOf: url),
              let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int(size * 2),
                pixelsHigh: Int(size * 2),
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
              ),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return appImage }

        // Decode and rasterize the status icon before assigning it to the
        // status item. This avoids AppKit briefly displaying the lazy-loaded
        // source at its intrinsic size while the app is launching.
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: size * 2, height: size * 2).fill()
        source.draw(in: NSRect(x: 0, y: 0, width: size * 2, height: size * 2))
        NSGraphicsContext.restoreGraphicsState()

        bitmap.size = NSSize(width: size, height: size)
        let image = NSImage(size: bitmap.size)
        image.addRepresentation(bitmap)
        image.isTemplate = true
        return image
    }
}
