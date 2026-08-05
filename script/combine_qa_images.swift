import AppKit
import Foundation

guard CommandLine.arguments.count == 4,
      let source = NSImage(contentsOfFile: CommandLine.arguments[1]),
      let implementation = NSImage(contentsOfFile: CommandLine.arguments[2]) else {
    FileHandle.standardError.write(Data("usage: combine_qa_images source implementation output\n".utf8))
    exit(2)
}

let width: CGFloat = 1_500
let labelHeight: CGFloat = 38
let implementationHeight = implementation.size.height * width / implementation.size.width
let canvasSize = NSSize(
    width: width,
    height: source.size.height + implementationHeight + labelHeight * 2
)
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(canvasSize.width),
    pixelsHigh: Int(canvasSize.height),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: Int(canvasSize.width) * 4,
    bitsPerPixel: 32
), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    exit(3)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
NSColor.black.setFill()
NSRect(origin: .zero, size: canvasSize).fill()

implementation.draw(
    in: NSRect(x: 0, y: labelHeight, width: width, height: implementationHeight),
    from: .zero,
    operation: .copy,
    fraction: 1
)
source.draw(
    in: NSRect(x: 0, y: implementationHeight + labelHeight * 2, width: width, height: source.size.height),
    from: .zero,
    operation: .copy,
    fraction: 1
)

let attributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.monospacedSystemFont(ofSize: 15, weight: .semibold),
    .foregroundColor: NSColor.white
]
NSAttributedString(string: "IMPLEMENTATION — 1120 × 380 pt @2x", attributes: attributes)
    .draw(at: NSPoint(x: 16, y: 10))
NSAttributedString(string: "SOURCE VISUAL TARGET — 1500 × 1060 px", attributes: attributes)
    .draw(at: NSPoint(x: 16, y: implementationHeight + labelHeight + 10))

context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    exit(4)
}
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[3]), options: .atomic)
