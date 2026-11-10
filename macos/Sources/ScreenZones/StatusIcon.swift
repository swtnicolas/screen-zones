import AppKit

@MainActor
enum StatusIcon {
    static let active = make(filled: true)
    static let idle = make(filled: false)

    private static func make(filled: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            let primary = NSColor(srgbRed: 0.22, green: 0.42, blue: 0.82, alpha: 1)
            let secondary = NSColor(srgbRed: 0.486, green: 0.486, blue: 0.502, alpha: 1)
            let tiles = [
                (NSRect(x: 1.5, y: 2, width: 7, height: 14), primary),
                (NSRect(x: 10, y: 2, width: 6.5, height: 6.25), secondary),
                (NSRect(x: 10, y: 9.75, width: 6.5, height: 6.25), secondary),
            ]
            for (rect, color) in tiles {
                if filled {
                    color.setFill()
                    NSBezierPath(roundedRect: rect, xRadius: 1.6, yRadius: 1.6).fill()
                } else {
                    let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.6, dy: 0.6), xRadius: 1.2, yRadius: 1.2)
                    path.lineWidth = 1.2
                    secondary.setStroke()
                    path.stroke()
                }
            }
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = "ScreenZones"
        return image
    }
}
