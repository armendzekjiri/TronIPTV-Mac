#!/usr/bin/env swift
// Renders the macOS app icon set from a square logo: the logo on a dark squircle, following Apple's icon grid
// (824 pt body on a 1024 pt canvas). Usage: scripts/make-icon.swift <logo.png> <AppIcon.appiconset dir> [out.icns]
import AppKit

let args = CommandLine.arguments
guard args.count >= 3, let logo = NSImage(contentsOfFile: args[1]) else {
    print("usage: make-icon.swift <logo.png> <AppIcon.appiconset> [AppIcon.icns]")
    exit(1)
}
let setDir = URL(fileURLWithPath: args[2])
try FileManager.default.createDirectory(at: setDir, withIntermediateDirectories: true)

func render(_ size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(size) / 1024
    let body = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let path = NSBezierPath(roundedRect: body, xRadius: 185 * s, yRadius: 185 * s)

    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = 20 * s
    shadow.shadowOffset = NSSize(width: 0, height: -10 * s)
    shadow.set()
    NSColor(calibratedRed: 0.09, green: 0.09, blue: 0.11, alpha: 1).setFill()
    path.fill()
    NSGraphicsContext.current?.restoreGraphicsState()

    NSGradient(colors: [NSColor(calibratedRed: 0.20, green: 0.20, blue: 0.24, alpha: 1),
                        NSColor(calibratedRed: 0.06, green: 0.06, blue: 0.08, alpha: 1)])!
        .draw(in: path, angle: -90)

    let inset: CGFloat = 150 * s
    NSGraphicsContext.current?.imageInterpolation = .high
    logo.draw(in: body.insetBy(dx: inset, dy: inset), from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

var images: [[String: String]] = []
for (point, scales) in [(16, [1, 2]), (32, [1, 2]), (128, [1, 2]), (256, [1, 2]), (512, [1, 2])] {
    for scale in scales {
        let name = "icon_\(point)x\(point)\(scale == 2 ? "@2x" : "").png"
        try render(point * scale).write(to: setDir.appendingPathComponent(name))
        images.append(["idiom": "mac", "size": "\(point)x\(point)", "scale": "\(scale)x", "filename": name])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: setDir.appendingPathComponent("Contents.json"))

if args.count >= 4 {
    let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
    try? FileManager.default.removeItem(at: iconset)
    try FileManager.default.copyItem(at: setDir, to: iconset)
    try? FileManager.default.removeItem(at: iconset.appendingPathComponent("Contents.json"))
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    p.arguments = ["-c", "icns", iconset.path, "-o", args[3]]
    try p.run()
    p.waitUntilExit()
}
print("Icon written to \(setDir.path)")
