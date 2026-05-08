#!/usr/bin/env swift
import AppKit
import Foundation

let fileManager = FileManager.default
let rootURL = URL(fileURLWithPath: fileManager.currentDirectoryPath)
let buildURL = rootURL.appendingPathComponent("build", isDirectory: true)
let iconsetURL = buildURL.appendingPathComponent("AppIcon.iconset", isDirectory: true)
let icnsURL = buildURL.appendingPathComponent("AppIcon.icns")

try fileManager.createDirectory(at: buildURL, withIntermediateDirectories: true)
try? fileManager.removeItem(at: iconsetURL)
try? fileManager.removeItem(at: icnsURL)
try fileManager.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

func drawInactiveCat(in rect: NSRect) {
    let baseWidth: CGFloat = 24
    let baseHeight: CGFloat = 22
    let scale = min(rect.width / baseWidth, rect.height / baseHeight)
    let origin = NSPoint(
        x: rect.midX - (baseWidth * scale / 2),
        y: rect.midY - (baseHeight * scale / 2)
    )

    NSGraphicsContext.saveGraphicsState()
    let transform = NSAffineTransform()
    transform.translateX(by: origin.x, yBy: origin.y)
    transform.scale(by: scale)
    transform.concat()

    NSColor.black.setStroke()
    NSColor.black.setFill()

    let stroke = NSBezierPath()
    stroke.lineWidth = 1.7
    stroke.lineCapStyle = .round
    stroke.lineJoinStyle = .round

    stroke.move(to: NSPoint(x: 5.5, y: 11.5))
    stroke.line(to: NSPoint(x: 7.8, y: 17.5))
    stroke.line(to: NSPoint(x: 11.1, y: 14.7))
    stroke.line(to: NSPoint(x: 13.0, y: 14.7))
    stroke.line(to: NSPoint(x: 16.2, y: 17.5))
    stroke.line(to: NSPoint(x: 18.5, y: 11.5))
    stroke.curve(to: NSPoint(x: 12.0, y: 4.9), controlPoint1: NSPoint(x: 19.1, y: 7.8), controlPoint2: NSPoint(x: 16.1, y: 4.9))
    stroke.curve(to: NSPoint(x: 5.5, y: 11.5), controlPoint1: NSPoint(x: 7.9, y: 4.9), controlPoint2: NSPoint(x: 4.9, y: 7.8))
    stroke.stroke()

    NSBezierPath(ovalIn: NSRect(x: 8.4, y: 10.4, width: 1.9, height: 1.9)).fill()

    let wink = NSBezierPath()
    wink.lineWidth = 1.5
    wink.lineCapStyle = .round
    wink.move(to: NSPoint(x: 13.7, y: 11.2))
    wink.line(to: NSPoint(x: 16.1, y: 11.9))
    wink.stroke()

    let mouth = NSBezierPath()
    mouth.lineWidth = 1.2
    mouth.lineCapStyle = .round
    mouth.move(to: NSPoint(x: 9.4, y: 8.6))
    mouth.curve(to: NSPoint(x: 14.6, y: 8.6), controlPoint1: NSPoint(x: 10.5, y: 7.0), controlPoint2: NSPoint(x: 13.5, y: 7.0))
    mouth.stroke()

    NSGraphicsContext.restoreGraphicsState()
}

func makeIcon(pixelSize: Int) throws -> Data {
    let size = NSSize(width: pixelSize, height: pixelSize)
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw NSError(domain: "LazyleadVPNIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create icon bitmap"])
    }
    bitmap.size = size

    guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw NSError(domain: "LazyleadVPNIcon", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create graphics context"])
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.shouldAntialias = true

    NSColor.clear.setFill()
    NSRect(origin: .zero, size: size).fill()

    let backgroundRect = NSRect(
        x: CGFloat(pixelSize) * 0.08,
        y: CGFloat(pixelSize) * 0.08,
        width: CGFloat(pixelSize) * 0.84,
        height: CGFloat(pixelSize) * 0.84
    )
    let radius = CGFloat(pixelSize) * 0.18
    NSColor(calibratedWhite: 0.94, alpha: 1).setFill()
    NSBezierPath(roundedRect: backgroundRect, xRadius: radius, yRadius: radius).fill()
    NSColor(calibratedWhite: 0.78, alpha: 1).setStroke()
    let border = NSBezierPath(roundedRect: backgroundRect.insetBy(dx: CGFloat(pixelSize) * 0.01, dy: CGFloat(pixelSize) * 0.01), xRadius: radius, yRadius: radius)
    border.lineWidth = max(1, CGFloat(pixelSize) * 0.012)
    border.stroke()

    let catRect = backgroundRect.insetBy(dx: CGFloat(pixelSize) * 0.12, dy: CGFloat(pixelSize) * 0.15)
    drawInactiveCat(in: catRect)

    NSGraphicsContext.restoreGraphicsState()

    guard
        let png = bitmap.representation(using: .png, properties: [:])
    else {
        throw NSError(domain: "LazyleadVPNIcon", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to render icon PNG"])
    }

    return png
}

let entries: [(base: Int, scale: Int)] = [
    (16, 1), (16, 2),
    (32, 1), (32, 2),
    (128, 1), (128, 2),
    (256, 1), (256, 2),
    (512, 1), (512, 2),
]

for entry in entries {
    let pixelSize = entry.base * entry.scale
    let suffix = entry.scale == 1 ? "" : "@\(entry.scale)x"
    let filename = "icon_\(entry.base)x\(entry.base)\(suffix).png"
    let data = try makeIcon(pixelSize: pixelSize)
    try data.write(to: iconsetURL.appendingPathComponent(filename))
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetURL.path, "-o", icnsURL.path]
try process.run()
process.waitUntilExit()

if process.terminationStatus != 0 {
    throw NSError(domain: "LazyleadVPNIcon", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "iconutil failed"])
}
