// Renders the 1024×1024 app icon: PinMac's tilted pin on deep purple.
// Built together with Sources/PinMac/PinShape.swift so the app icon and the
// menu-bar icon share one pin. scripts/build.sh runs it when the icon is missing.
import AppKit

@main
struct MakeIcon {
    static let top = NSColor(srgbRed: 0x7E / 255, green: 0x5F / 255, blue: 0xD8 / 255, alpha: 1)    // #7E5FD8
    static let bottom = NSColor(srgbRed: 0x47 / 255, green: 0x28 / 255, blue: 0x9E / 255, alpha: 1) // #47289E

    static func main() throws {
        guard CommandLine.arguments.count > 1 else {
            print("Usage: make-icon <output.png>")
            exit(1)
        }

        let image = NSImage(size: NSSize(width: 1024, height: 1024), flipped: true) { rect in
            let background = NSBezierPath(roundedRect: rect.insetBy(dx: 100, dy: 100), xRadius: 185, yRadius: 185)
            NSGradient(starting: top, ending: bottom)!.draw(in: background, angle: 90)

            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.addPath(PinShape.tilted)
            context.setFillColor(.white)
            context.fillPath()
            return true
        }

        let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
        let png = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])!
        try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
    }
}
