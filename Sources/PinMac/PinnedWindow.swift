import AppKit

/// One pinned window: a floating live mirror that covers the real window
/// whenever something else is in front of it, plus an optional colored border.
@MainActor
final class PinnedWindow {
    static let borderWidth: CGFloat = 3

    let info: WindowInfo
    var onClick: (() -> Void)?

    private var frame: CGRect
    private let mirror: NSPanel
    private let mirrorView = MirrorView()
    private let border: NSPanel
    private let borderView = BorderView()
    private var stream: WindowStream!
    private var hasFrame = false
    private var needsCornerRadius = true

    var showsBorder: Bool {
        didSet { if !showsBorder { border.orderOut(nil) } }
    }

    init(info: WindowInfo, showsBorder: Bool) {
        self.info = info
        self.frame = info.frame
        self.showsBorder = showsBorder

        mirror = Self.makePanel()
        mirror.hasShadow = true
        mirror.contentView = mirrorView

        border = Self.makePanel()
        border.ignoresMouseEvents = true
        border.contentView = borderView

        stream = WindowStream(
            onFrame: { [weak self] surface in self?.show(surface) },
            onStop: { [weak self] in self?.hasFrame = false }
        )
        mirrorView.onMouseDown = { [weak self] in self?.onClick?() }
    }

    func start() async throws {
        try await stream.start(windowID: info.id, size: frame.size, scale: scale)
    }

    /// Called on every tick with the real window's latest position.
    func update(frame newFrame: CGRect, isFrontmost: Bool) {
        if newFrame.size != frame.size {
            stream.resize(to: newFrame.size, scale: scale)
            needsCornerRadius = true
        }
        frame = newFrame

        let appKitFrame = frame.flippedToAppKit
        if mirror.frame != appKitFrame {
            mirror.setFrame(appKitFrame, display: false)
        }

        // When the real window is already on top there's nothing to cover, and
        // hiding the mirror lets clicks reach the real window directly.
        if isFrontmost || !hasFrame {
            mirror.orderOut(nil)
        } else if !mirror.isVisible {
            mirror.orderFrontRegardless()
        }

        if showsBorder {
            let borderFrame = appKitFrame.insetBy(dx: -Self.borderWidth, dy: -Self.borderWidth)
            if border.frame != borderFrame { border.setFrame(borderFrame, display: true) }
            if !border.isVisible { border.orderFrontRegardless() }
        }
    }

    /// The window is minimized or on another Space.
    func hide() {
        mirror.orderOut(nil)
        border.orderOut(nil)
    }

    func close() {
        stream.stop()
        mirror.close()
        border.close()
    }

    private func show(_ surface: IOSurface) {
        hasFrame = true
        mirrorView.show(surface)
        if needsCornerRadius {
            needsCornerRadius = false
            if let radius = Self.cornerRadius(of: surface, pointWidth: frame.width) {
                borderView.cornerRadius = radius
            }
        }
    }

    private var scale: CGFloat {
        let appKitFrame = frame.flippedToAppKit
        let screen = NSScreen.screens.first { $0.frame.intersects(appKitFrame) } ?? NSScreen.main
        return screen?.backingScaleFactor ?? 2
    }

    private static func makePanel() -> NSPanel {
        // A non-activating panel can be clicked without making PinMac the active app.
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle]
        return panel
    }

    /// Measures the window's corner radius from the transparent pixels in the
    /// top-left corner of a captured frame, so the outline hugs the real shape.
    private static func cornerRadius(of surface: IOSurface, pointWidth: CGFloat) -> CGFloat? {
        surface.lock(options: .readOnly, seed: nil)
        defer { surface.unlock(options: .readOnly, seed: nil) }

        let pixels = surface.baseAddress.assumingMemoryBound(to: UInt8.self)
        let bytesPerRow = surface.bytesPerRow
        let limit = min(surface.width, surface.height) / 2

        // For a circle of radius r touching both edges, the edge crossing (x, y)
        // satisfies (r - x)² + (r - y)² = r², so r = x + y + √(2xy).
        var estimates: [CGFloat] = []
        for row in 0..<min(limit, 120) {
            var column = 0
            while column < limit, pixels[row * bytesPerRow + column * 4 + 3] == 0 { column += 1 }
            if column == 0 { break } // reached the straight edge
            let alpha = CGFloat(pixels[row * bytesPerRow + column * 4 + 3]) / 255
            let x = CGFloat(column) + 1 - alpha
            let y = CGFloat(row) + 0.5
            estimates.append(x + y + (2 * x * y).squareRoot())
        }
        guard !estimates.isEmpty, pointWidth > 0 else { return nil }
        let median = estimates.sorted()[estimates.count / 2]
        return median * pointWidth / CGFloat(surface.width)
    }
}

/// Shows the captured frames. Uses a layer-hosting view so the IOSurface from
/// ScreenCaptureKit can be handed straight to Core Animation without copying.
private final class MirrorView: NSView {
    var onMouseDown: (() -> Void)?

    init() {
        super.init(frame: .zero)
        layer = CALayer()
        layer?.contentsGravity = .resize
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(_ surface: IOSurface) {
        layer?.contents = surface
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onMouseDown?() }
}

private final class BorderView: NSView {
    /// The real window's corner radius; the outline sits just outside it.
    var cornerRadius: CGFloat = 12 {
        didSet { layer?.cornerRadius = cornerRadius + PinnedWindow.borderWidth }
    }

    init() {
        super.init(frame: .zero)
        layer = CALayer()
        layer?.borderWidth = PinnedWindow.borderWidth
        layer?.borderColor = NSColor.controlAccentColor.cgColor
        layer?.cornerRadius = cornerRadius + PinnedWindow.borderWidth
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }
}
