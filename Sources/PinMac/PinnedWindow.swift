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
    private var stream: WindowStream!
    private var hasFrame = false

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
        border.contentView = BorderView()

        stream = WindowStream(
            onFrame: { [weak self] surface in
                self?.hasFrame = true
                self?.mirrorView.show(surface)
            },
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
    init() {
        super.init(frame: .zero)
        layer = CALayer()
        layer?.borderWidth = PinnedWindow.borderWidth
        layer?.borderColor = NSColor.controlAccentColor.cgColor
        layer?.cornerRadius = 14
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }
}
