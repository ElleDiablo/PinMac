// Renders the 1024×1024 app icon. Usage: swift scripts/make-icon.swift out.png
import AppKit

let size = 1024.0
let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
    let inset = rect.insetBy(dx: 100, dy: 100)
    let background = NSBezierPath(roundedRect: inset, xRadius: 185, yRadius: 185)
    NSGradient(starting: NSColor(red: 0.36, green: 0.55, blue: 1.0, alpha: 1),
               ending: NSColor(red: 0.20, green: 0.25, blue: 0.85, alpha: 1))!
        .draw(in: background, angle: -90)

    let config = NSImage.SymbolConfiguration(pointSize: 480, weight: .semibold)
        .applying(.init(paletteColors: [.white]))
    if let pin = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let pinRect = NSRect(x: rect.midX - pin.size.width / 2, y: rect.midY - pin.size.height / 2,
                             width: pin.size.width, height: pin.size.height)
        pin.draw(in: pinRect)
    }
    return true
}

let rep = NSBitmapImageRep(cgImage: image.cgImage(forProposedRect: nil, context: nil, hints: nil)!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
