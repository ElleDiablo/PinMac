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
    private var lastMove = Date.distantPast
    private var axElement: AXUIElement?

    private enum Capture { case idle, starting, running }
    private var capture = Capture.idle
    private var lastCaptureNeeded = Date.now
    private var lastCaptureFailure = Date.distantPast

    /// The panel's window-server ID, for ordering it relative to other windows.
    var panelID: CGWindowID { CGWindowID(panel.windowNumber) }

    var showsBorder: Bool {
        get { view.showsBorder }
        set { view.showsBorder = newValue }
    }

    var borderColor: NSColor {
        get { view.borderColor }
        set { view.borderColor = newValue }
    }

    /// How see-through the floating copy is while it covers other windows.
    /// The real window can't be made transparent, so this applies to the mirror.
    var opacity: CGFloat {
        get { view.mirrorOpacity }
        set { view.mirrorOpacity = newValue }
    }

    /// Minimized, or its app is hidden: nothing should be shown for it.
    var isMinimizedOrHidden: Bool {
        if NSRunningApplication(processIdentifier: info.pid)?.isHidden == true { return true }
        if axElement == nil { axElement = AXWindows.element(windowID: info.id, pid: info.pid) }
        return axElement.map(AXWindows.isMinimized) ?? false
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
        // Follow the user to every Space, including full-screen apps, but stay out
        // of Mission Control and App Exposé, where it would show as an empty window.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.contentView = view

        stream = WindowStream(
            onFrame: { [weak self] surface in self?.show(surface) },
            onStop: { [weak self] in self?.capture = .idle }
        )
        view.onMouseDown = { [weak self] in self?.onClick?() }
        updatePanelFrame()
    }

    /// The first capture, which also measures the window's corner radius.
    func start() async throws {
        capture = .starting
        do {
            try await stream.start(windowID: info.id, size: frame.size, scale: scale)
            capture = .running
        } catch {
            capture = .idle
            throw error
        }
    }

    /// Screen capture turns on macOS's purple recording indicator, so PinMac only
    /// captures while the window is covered. The last frame is kept, so the
    /// mirror can appear instantly and turn live a moment later.
    func setCaptureNeeded(_ needed: Bool) {
        if needed {
            lastCaptureNeeded = .now
            guard capture == .idle, Date.now.timeIntervalSince(lastCaptureFailure) > 2 else { return }
            capture = .starting
            Task {
                do {
                    try await stream.start(windowID: info.id, size: frame.size, scale: scale)
                    capture = .running
                } catch {
                    capture = .idle
                    lastCaptureFailure = .now
                }
            }
        } else if capture == .running, !needsCornerRadius, Date.now.timeIntervalSince(lastCaptureNeeded) > 1 {
            // The short grace period avoids restarting when clicking back and forth.
            stream.stop()
            capture = .idle
        }
    }

    /// Follows the real window's latest position and size. The outline can't
    /// keep up with a window being dragged, so it hides until the window settles.
    func setFrame(_ newFrame: CGRect) {
        guard newFrame != frame else {
            if view.isMoving, Date.now.timeIntervalSince(lastMove) > 0.15 { view.isMoving = false }
            return
        }
        if newFrame.size != frame.size {
            stream.resize(to: newFrame.size, scale: scale)
            needsCornerRadius = true
        }
        frame = newFrame
        lastMove = .now
        view.isMoving = true
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

    /// Places the panel directly above or below another window in the stacking order.
    func order(above windowID: CGWindowID) {
        panel.order(.above, relativeTo: Int(windowID))
    }

    func order(below windowID: CGWindowID) {
        panel.order(.below, relativeTo: Int(windowID))
    }

    func orderFront() {
        panel.orderFrontRegardless()
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
        didSet { updateBorderVisibility() }
    }

    var isMoving = false {
        didSet { updateBorderVisibility() }
    }

    var borderColor = NSColor.controlAccentColor {
        didSet { borderLayer.borderColor = borderColor.cgColor }
    }

    var mirrorOpacity: CGFloat = 1 {
        didSet { mirrorLayer.opacity = Float(mirrorOpacity) }
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
        borderLayer.borderColor = borderColor.cgColor
        borderLayer.cornerRadius = cornerRadius + PinnedWindow.borderWidth
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(_ surface: IOSurface) {
        mirrorLayer.contents = surface
    }

    private func updateBorderVisibility() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        borderLayer.isHidden = !showsBorder || isMoving
        CATransaction.commit()
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
