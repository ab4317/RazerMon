import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("usage: make-dmg-background.swift OUTPUT.png\n", stderr)
    exit(2)
}

let width = 660
let height = 420
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: width,
    pixelsHigh: height,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
), let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fputs("unable to create background bitmap\n", stderr)
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphicsContext

NSColor(calibratedWhite: 0.95, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: width, height: height).fill()

let context = graphicsContext.cgContext
context.setStrokeColor(NSColor(calibratedWhite: 0.56, alpha: 1).cgColor)
context.setLineWidth(4)
context.setLineCap(.round)
context.setLineJoin(.round)
context.move(to: CGPoint(x: 295, y: 215))
context.addLine(to: CGPoint(x: 365, y: 215))
context.move(to: CGPoint(x: 350, y: 230))
context.addLine(to: CGPoint(x: 365, y: 215))
context.addLine(to: CGPoint(x: 350, y: 200))
context.strokePath()

NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("unable to encode background PNG\n", stderr)
    exit(1)
}
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]), options: .atomic)
