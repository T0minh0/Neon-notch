import AppKit
import Foundation

guard CommandLine.arguments.count == 3,
      let image = NSImage(contentsOfFile: CommandLine.arguments[1]) else {
    exit(2)
}

let canvas = NSImage(size: image.size)
canvas.lockFocus()
NSColor.black.setFill()
NSRect(origin: .zero, size: image.size).fill()
image.draw(
    in: NSRect(origin: .zero, size: image.size),
    from: .zero,
    operation: .sourceOver,
    fraction: 1
)
canvas.unlockFocus()

guard let tiff = canvas.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    exit(3)
}
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[2]), options: .atomic)
