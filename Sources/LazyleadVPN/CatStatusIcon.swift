import AppKit

enum CatStatusIcon {
    static func makeImage(active: Bool) -> NSImage {
        let size = NSSize(width: 24, height: 22)
        let image = NSImage(size: size)

        image.lockFocus()

        if active {
            NSColor(calibratedRed: 0.03, green: 0.04, blue: 0.04, alpha: 1).setFill()
            let background = NSBezierPath(roundedRect: NSRect(x: 1, y: 2, width: 22, height: 18), xRadius: 5, yRadius: 5)
            background.fill()
            let activeGreen = NSColor(calibratedRed: 201 / 255, green: 253 / 255, blue: 133 / 255, alpha: 0.88)
            let shadow = NSShadow()
            shadow.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.38)
            shadow.shadowOffset = NSSize(width: 0, height: -0.5)
            shadow.shadowBlurRadius = 1.6
            NSGraphicsContext.saveGraphicsState()
            shadow.set()
            activeGreen.setStroke()
            activeGreen.setFill()
        } else {
            NSColor.black.setStroke()
            NSColor.black.setFill()
        }

        let stroke = NSBezierPath()
        stroke.lineWidth = active ? 1.55 : 1.7
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

        if active {
            NSBezierPath(ovalIn: NSRect(x: 14.7, y: 10.4, width: 1.9, height: 1.9)).fill()
        } else {
            let wink = NSBezierPath()
            wink.lineWidth = 1.5
            wink.lineCapStyle = .round
            wink.move(to: NSPoint(x: 13.7, y: 11.2))
            wink.line(to: NSPoint(x: 16.1, y: 11.9))
            wink.stroke()
        }

        let mouth = NSBezierPath()
        mouth.lineWidth = active ? 1.1 : 1.2
        mouth.lineCapStyle = .round
        if active {
            mouth.move(to: NSPoint(x: 9.2, y: 8.5))
            mouth.curve(to: NSPoint(x: 14.8, y: 8.5), controlPoint1: NSPoint(x: 10.4, y: 6.6), controlPoint2: NSPoint(x: 13.6, y: 6.6))
        } else {
            mouth.move(to: NSPoint(x: 9.4, y: 8.6))
            mouth.curve(to: NSPoint(x: 14.6, y: 8.6), controlPoint1: NSPoint(x: 10.5, y: 7.0), controlPoint2: NSPoint(x: 13.5, y: 7.0))
        }
        mouth.stroke()

        if active {
            NSGraphicsContext.restoreGraphicsState()
        }
        image.unlockFocus()
        image.isTemplate = !active

        return image
    }
}
