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

    func setHue(_ hue: Double) {
        self.hue = hue
        changed()
    }

    func setSaturationBrightness(saturation: Double, brightness: Double) {
        self.saturation = saturation
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

            SaturationBrightnessBox(model: model)
                .frame(height: 150)

            HStack(spacing: 12) {
                Circle()
                    .fill(Color(nsColor: model.color))
                    .overlay(Circle().strokeBorder(.primary.opacity(0.15)))
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                    .frame(width: 40, height: 40)
                    .onDrag { model.color.itemProvider }
                    .help("Drag this color into Saved Colors")
                HueSlider(model: model)
            }

            HStack(spacing: 8) {
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

/// Saturation left to right, brightness top to bottom, for the current hue.
private struct SaturationBrightnessBox: View {
    @ObservedObject var model: BorderColorModel

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                ZStack {
                    Color(hue: model.hue, saturation: 1, brightness: 1)
                    LinearGradient(colors: [.white, .white.opacity(0)], startPoint: .leading, endPoint: .trailing)
                    LinearGradient(colors: [.black.opacity(0), .black], startPoint: .top, endPoint: .bottom)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))

                Knob(color: Color(nsColor: model.color))
                    .position(x: model.saturation * size.width, y: (1 - model.brightness) * size.height)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                model.setSaturationBrightness(
                    saturation: (drag.location.x / size.width).clamped,
                    brightness: (1 - drag.location.y / size.height).clamped)
            })
        }
    }
}

private struct HueSlider: View {
    @ObservedObject var model: BorderColorModel
    private let knobSize: CGFloat = 20

    var body: some View {
        GeometryReader { geometry in
            let track = geometry.size.width - knobSize
            ZStack {
                Capsule()
                    .fill(LinearGradient(
                        colors: stride(from: 0, through: 1, by: 1.0 / 12).map { Color(hue: $0, saturation: 1, brightness: 1) },
                        startPoint: .leading, endPoint: .trailing))
                    .frame(height: 12)
                Knob(color: Color(hue: model.hue, saturation: 1, brightness: 1))
                    .position(x: knobSize / 2 + model.hue * track, y: geometry.size.height / 2)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                model.setHue(((drag.location.x - knobSize / 2) / track).clamped)
            })
        }
        .frame(height: knobSize)
    }
}

private struct Knob: View {
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .overlay(Circle().strokeBorder(.white, lineWidth: 3))
            .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
            .frame(width: 20, height: 20)
    }
}

private extension CGFloat {
    var clamped: CGFloat { Swift.min(Swift.max(self, 0), 1) }
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
