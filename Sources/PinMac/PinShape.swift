import AppKit

/// PinMac's own pushpin, used for both the app icon and the menu-bar icon.
/// (Apple's SF Symbols may not be used in app icons or logos, so the brand
/// mark is drawn here instead.)
enum PinShape {
    /// The pin tilted 45° to the right, as one outline, in a 1024×1024 canvas
    /// with the origin at the top-left.
    static let tilted: CGPath = {
        var transform = CGAffineTransform(translationX: 512, y: 512)
            .rotated(by: .pi / 4) // y points down, so this turns it clockwise
            .scaledBy(x: 0.86, y: 0.86)
            .translatedBy(x: -512, y: -530) // the upright pin's center
        let rotated = upright.copy(using: &transform) ?? upright
        // Center the tilted pin's bounds in the canvas.
        let bounds = rotated.boundingBoxOfPath
        var center = CGAffineTransform(translationX: 512 - bounds.midX, y: 512 - bounds.midY)
        return rotated.copy(using: &center) ?? rotated
    }()

    /// The upright pin: cap, neck and bell, and needle, merged into one shape
    /// so it can be stroked as a clean outline.
    static let upright: CGPath = {
        let cap = CGPath(roundedRect: CGRect(x: 352, y: 228, width: 320, height: 74),
                         cornerWidth: 37, cornerHeight: 37, transform: nil)

        let body = CGMutablePath()
        body.move(to: CGPoint(x: 420, y: 290))
        body.addLine(to: CGPoint(x: 604, y: 290))
        body.addLine(to: CGPoint(x: 590, y: 452))
        body.addCurve(to: CGPoint(x: 712, y: 600), control1: CGPoint(x: 662, y: 480), control2: CGPoint(x: 712, y: 540))
        body.addCurve(to: CGPoint(x: 680, y: 640), control1: CGPoint(x: 712, y: 626), control2: CGPoint(x: 700, y: 640))
        body.addLine(to: CGPoint(x: 344, y: 640))
        body.addCurve(to: CGPoint(x: 312, y: 600), control1: CGPoint(x: 324, y: 640), control2: CGPoint(x: 312, y: 626))
        body.addCurve(to: CGPoint(x: 434, y: 452), control1: CGPoint(x: 312, y: 540), control2: CGPoint(x: 362, y: 480))
        body.closeSubpath()

        let needle = CGMutablePath()
        needle.move(to: CGPoint(x: 488, y: 630))
        needle.addLine(to: CGPoint(x: 536, y: 630))
        needle.addLine(to: CGPoint(x: 518, y: 820))
        needle.addCurve(to: CGPoint(x: 506, y: 820), control1: CGPoint(x: 515, y: 832), control2: CGPoint(x: 509, y: 832))
        needle.closeSubpath()

        return cap.union(body).union(needle)
    }()

    /// A menu-bar icon: filled when something is pinned, an outline otherwise.
    /// Template images are tinted by macOS to match light and dark menu bars.
    static func menuBarImage(filled: Bool, size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            // Fit the tilted pin's bounds into the image, leaving room for the stroke.
            let bounds = tilted.boundingBoxOfPath
            let inset: CGFloat = filled ? 0.5 : 1.2
            let scale = (rect.width - inset * 2) / max(bounds.width, bounds.height)
            context.translateBy(x: rect.midX, y: rect.midY)
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: -bounds.midX, y: -bounds.midY)
            context.addPath(tilted)
            if filled {
                context.setFillColor(.black)
                context.fillPath()
            } else {
                context.setStrokeColor(.black)
                context.setLineWidth(1.4 / scale)
                context.setLineJoin(.round)
                context.strokePath()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "PinMac"
        return image
    }
}
