import AppKit

/// One pinned window. PinMac shows a single panel for it, used in one of two ways:
/// - `.border`: just the colored outline, placed directly above the real window.
/// - `.mirror`: a live copy of the window (plus outline) that covers it while
///   unpinned windows are in front of the real one.
@MainActor
final class PinnedWindow {
    enum Mode { case hidden, border, mirror }

    static let borderWidth: CGFloat = 3

    let info: WindowInfo
    var onClick: (() -> Void)?

    /// Whether a captured frame has arrived, so the panel can act as a mirror.
    private(set) var hasFrame = false
    private(set) var mode = Mode.hidden

    private var frame: CGRect
    private let panel: NSPanel
    private let view = PinView()
    private var stream: WindowStream!
    private var needsCornerRadius = true

    /// The panel's window-server ID, for ordering it relative to other windows.
    var panelID: CGWindowID { CGWindowID(panel.windowNumber) }

    var showsBorder: Bool {
        get { view.showsBorder }
        set { view.showsBorder = newValue }
    }

    init(info: WindowInfo) {
        self.info = info
        self.frame = info.frame

        // A non-activating panel can be clicked without making PinMac the active app.
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = view

        stream = WindowStream(
            onFrame: { [weak self] surface in self?.show(surface) },
            onStop: { [weak self] in self?.hasFrame = false }
        )
        view.onMouseDown = { [weak self] in self?.onClick?() }
        updatePanelFrame()
    }

    func start() async throws {
        try await stream.start(windowID: info.id, size: frame.size, scale: scale)
    }

    /// Follows the real window's latest position and size.
    func setFrame(_ newFrame: CGRect) {
        guard newFrame != frame else { return }
        if newFrame.size != frame.size {
            stream.resize(to: newFrame.size, scale: scale)
            needsCornerRadius = true
        }
        frame = newFrame
        updatePanelFrame()
    }

    func setMode(_ newMode: Mode) {
        guard newMode != mode else { return }
        mode = newMode
        view.showsMirror = newMode == .mirror
        // The outline alone shouldn't block clicks on the real window beneath it.
        panel.ignoresMouseEvents = newMode != .mirror
        panel.hasShadow = newMode == .mirror
        if newMode == .hidden { panel.orderOut(nil) }
    }

    /// Places the panel directly above another window in the stacking order.
    func order(above windowID: CGWindowID) {
        panel.order(.above, relativeTo: Int(windowID))
    }

    func close() {
        stream.stop()
        panel.close()
    }

    private func show(_ surface: IOSurface) {
        hasFrame = true
        view.show(surface)
        if needsCornerRadius {
            needsCornerRadius = false
            if let radius = Self.cornerRadius(of: surface, pointWidth: frame.width) {
                view.cornerRadius = radius
            }
        }
    }

    private func updatePanelFrame() {
        let outer = frame.flippedToAppKit.insetBy(dx: -Self.borderWidth, dy: -Self.borderWidth)
        if panel.frame != outer { panel.setFrame(outer, display: true) }
    }

    private var scale: CGFloat {
        let appKitFrame = frame.flippedToAppKit
        let screen = NSScreen.screens.first { $0.frame.intersects(appKitFrame) } ?? NSScreen.main
        return screen?.backingScaleFactor ?? 2
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

/// Layer-hosting view: the IOSurface from ScreenCaptureKit is handed straight
/// to Core Animation without copying.
private final class PinView: NSView {
    var onMouseDown: (() -> Void)?

    private let mirrorLayer = CALayer()
    private let borderLayer = CALayer()

    var showsMirror = false {
        didSet { mirrorLayer.isHidden = !showsMirror }
    }

    var showsBorder = true {
        didSet { borderLayer.isHidden = !showsBorder }
    }

    /// The real window's corner radius; the outline sits just outside it.
    var cornerRadius: CGFloat = 12 {
        didSet { borderLayer.cornerRadius = cornerRadius + PinnedWindow.borderWidth }
    }

    init() {
        super.init(frame: .zero)
        let root = CALayer()
        root.addSublayer(mirrorLayer)
        root.addSublayer(borderLayer)
        layer = root
        wantsLayer = true

        mirrorLayer.contentsGravity = .resize
        mirrorLayer.isHidden = true
        borderLayer.borderWidth = PinnedWindow.borderWidth
        borderLayer.borderColor = NSColor.controlAccentColor.cgColor
        borderLayer.cornerRadius = cornerRadius + PinnedWindow.borderWidth
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(_ surface: IOSurface) {
        mirrorLayer.contents = surface
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        borderLayer.frame = bounds
        mirrorLayer.frame = bounds.insetBy(dx: PinnedWindow.borderWidth, dy: PinnedWindow.borderWidth)
        CATransaction.commit()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onMouseDown?() }
}
