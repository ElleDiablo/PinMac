import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// State behind the border color popover: the color being edited (as HSB, so
/// the wheel doesn't jump around) and the user's saved colors.
@MainActor
final class BorderColorModel: ObservableObject {
    @Published private(set) var hue: Double = 0.6
    @Published private(set) var saturation: Double = 0.8
    @Published private(set) var brightness: Double = 1
    @Published var hexText = ""
    @Published private(set) var saved: [String] = UserDefaults.standard.stringArray(forKey: "savedColors") ?? []
    @Published var isEditing = false
    @Published var isDropTargeted = false

    /// Called with every change, so pinned borders update live.
    var onChange: ((NSColor) -> Void)?

    var color: NSColor {
        NSColor(colorSpace: .sRGB, hue: hue, saturation: saturation, brightness: brightness, alpha: 1)
    }

    /// Loads a color without reporting it as a change (e.g. when the popover opens).
    func load(_ color: NSColor) {
        guard let rgb = color.usingColorSpace(.sRGB) else { return }
        hue = rgb.hueComponent
        saturation = rgb.saturationComponent
        brightness = rgb.brightnessComponent
        hexText = rgb.hexString
    }

    func select(_ color: NSColor) {
        load(color)
        onChange?(self.color)
    }

    func setWheel(hue: Double, saturation: Double) {
        self.hue = hue
        self.saturation = saturation
        changed()
    }

    func setBrightness(_ brightness: Double) {
        self.brightness = brightness
        changed()
    }

    /// Applies typed or pasted text as soon as it's a valid hex color.
    func setHexText(_ text: String) {
        hexText = text
        guard let color = NSColor(hex: text)?.usingColorSpace(.sRGB) else { return }
        hue = color.hueComponent
        saturation = color.saturationComponent
        brightness = color.brightnessComponent
        onChange?(self.color)
    }

    func save(_ color: NSColor) {
        guard let hex = color.usingColorSpace(.sRGB)?.hexString, !saved.contains(hex) else { return }
        saved.append(hex)
        persist()
    }

    func remove(_ hex: String) {
        saved.removeAll { $0 == hex }
        if saved.isEmpty { isEditing = false }
        persist()
    }

    private func changed() {
        hexText = color.hexString
        onChange?(color)
    }

    private func persist() {
        UserDefaults.standard.set(saved, forKey: "savedColors")
    }
}

struct BorderColorView: View {
    @ObservedObject var model: BorderColorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Border Color").font(.headline)

            ColorWheel(model: model)
                .frame(width: 180, height: 180)
                .frame(maxWidth: .infinity)

            HStack(spacing: 6) {
                Image(systemName: "sun.min").foregroundStyle(.secondary)
                Slider(value: Binding(get: { model.brightness }, set: model.setBrightness), in: 0...1)
                Image(systemName: "sun.max").foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: model.color))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.primary.opacity(0.2)))
                    .frame(width: 34, height: 24)
                    .onDrag { model.color.itemProvider }
                    .help("Drag this color into Saved Colors")
                TextField("#RRGGBB", text: Binding(get: { model.hexText }, set: model.setHexText))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .help("Type or paste a hex color, like #FF8800")
                Button { model.save(model.color) } label: { Image(systemName: "plus") }
                    .help("Save this color")
            }

            Divider()

            HStack {
                Text("Saved Colors").font(.subheadline.weight(.semibold))
                Spacer()
                if !model.saved.isEmpty {
                    Button(model.isEditing ? "Done" : "Edit") { model.isEditing.toggle() }
                        .buttonStyle(.link)
                }
            }
            savedColors
        }
        .padding(16)
        .frame(width: 260)
    }

    private var savedColors: some View {
        VStack(spacing: 8) {
            if !model.saved.isEmpty {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(24), spacing: 8), count: 6), spacing: 8) {
                    ForEach(model.saved, id: \.self) { hex in
                        swatch(hex)
                    }
                }
            }
            Text(model.isEditing ? "Click a color to remove it" : "Drag and drop colors here")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 56)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .foregroundStyle(model.isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.5))
        }
        .onDrop(of: [.nsColor, .plainText], isTargeted: $model.isDropTargeted, perform: drop)
    }

    private func swatch(_ hex: String) -> some View {
        let color = NSColor(hex: hex) ?? .gray
        return Circle()
            .fill(Color(nsColor: color))
            .overlay(Circle().strokeBorder(.primary.opacity(0.2)))
            .frame(width: 24, height: 24)
            .overlay(alignment: .topTrailing) {
                if model.isEditing {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .red)
                        .offset(x: 5, y: -5)
                }
            }
            .contentShape(Circle())
            .onTapGesture {
                if model.isEditing { model.remove(hex) } else { model.select(color) }
            }
            .help(model.isEditing ? "Remove \(hex)" : hex)
    }

    /// Accepts colors dragged from PinMac or other apps, or hex text.
    private func drop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.nsColor.identifier) {
                _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.nsColor.identifier) { data, _ in
                    guard let data, let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data)
                    else { return }
                    DispatchQueue.main.async { model.save(color) }
                }
            } else if provider.canLoadObject(ofClass: NSString.self) {
                _ = provider.loadObject(ofClass: NSString.self) { text, _ in
                    guard let text = text as? String, let color = NSColor(hex: text) else { return }
                    DispatchQueue.main.async { model.save(color) }
                }
            }
        }
        return true
    }
}

/// Hue around the circle, saturation from the center out.
private struct ColorWheel: View {
    @ObservedObject var model: BorderColorModel

    var body: some View {
        GeometryReader { geometry in
            let radius = min(geometry.size.width, geometry.size.height) / 2
            let angle = model.hue * 2 * .pi
            ZStack {
                Circle().fill(AngularGradient(
                    colors: stride(from: 0, through: 1, by: 1.0 / 12).map { Color(hue: $0, saturation: 1, brightness: 1) },
                    center: .center))
                Circle().fill(RadialGradient(colors: [.white, .white.opacity(0)], center: .center,
                                             startRadius: 0, endRadius: radius))
                Circle().fill(Color.black.opacity(1 - model.brightness))
                Circle()
                    .strokeBorder(.white, lineWidth: 2.5)
                    .shadow(color: .black.opacity(0.4), radius: 1.5)
                    .frame(width: 16, height: 16)
                    .position(x: radius + cos(angle) * model.saturation * radius,
                              y: radius + sin(angle) * model.saturation * radius)
            }
            .contentShape(Circle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                let dx = drag.location.x - radius
                let dy = drag.location.y - radius
                var hue = atan2(dy, dx) / (2 * .pi)
                if hue < 0 { hue += 1 }
                model.setWheel(hue: hue, saturation: min(1, (dx * dx + dy * dy).squareRoot() / radius))
            })
        }
    }
}

extension UTType {
    /// The pasteboard type AppKit uses for dragged colors.
    static let nsColor = UTType(importedAs: "com.apple.cocoa.pasteboard.color")
}

extension NSColor {
    /// Parses "#RGB", "#RRGGBB", with or without "#" and surrounding spaces.
    convenience init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        if text.count == 3 { text = text.map { "\($0)\($0)" }.joined() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                  green: CGFloat((value >> 8) & 0xFF) / 255,
                  blue: CGFloat(value & 0xFF) / 255,
                  alpha: 1)
    }

    /// For dragging: AppKit's color type (for other Mac apps) plus hex text.
    var itemProvider: NSItemProvider {
        let provider = NSItemProvider(object: hexString as NSString)
        let data = try? NSKeyedArchiver.archivedData(withRootObject: self, requiringSecureCoding: true)
        provider.registerDataRepresentation(forTypeIdentifier: UTType.nsColor.identifier, visibility: .all) { completion in
            completion(data, nil)
            return nil
        }
        return provider
    }

    /// "#RRGGBB" in sRGB.
    var hexString: String {
        guard let rgb = usingColorSpace(.sRGB) else { return "#000000" }
        func byte(_ component: CGFloat) -> Int { Int((min(max(component, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(rgb.redComponent), byte(rgb.greenComponent), byte(rgb.blueComponent))
    }
}
