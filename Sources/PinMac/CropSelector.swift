import AppKit

/// A full-window overlay for choosing which part of a pinned window floats on top.
/// Drag to draw a selection, drag inside it to move it, then press Return.
@MainActor
final class CropSelector {
    enum Result {
        case crop(CGRect) // window points from its top-left
        case wholeWindow
        case cancelled
    }

    private var panel: NSPanel?

    /// `windowFrame` is in global CoreGraphics coordinates.
    func show(over windowFrame: CGRect, current: CGRect?, completion: @escaping (Result) -> Void) {
        close()
        let panel = KeyPanel(contentRect: windowFrame.flippedToAppKit, styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.transient, .ignoresCycle]

        let view = CropView(selection: current)
        view.onFinish = { [weak self] result in
            self?.close()
            completion(result)
        }
        panel.contentView = view
        self.panel = panel

        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(view)
    }

    private func close() {
        panel?.close()
        panel = nil
    }
}

/// Borderless panels can't become key by default, which they need for Return and Esc.
private final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private final class CropView: NSView {
    var onFinish: ((CropSelector.Result) -> Void)?

    private var selection: CGRect?
    private var dragStart: CGPoint?
    private var dragOrigin: CGRect?
    private static let minimumSize = CGSize(width: 60, height: 40)

    init(selection: CGRect?) {
        self.selection = selection
        super.init(frame: .zero)
        addSubview(toolbar)
    }

    required init?(coder: NSCoder) { fatalError() }

    // Top-left origin, matching the window points that crops are stored in.
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: Toolbar

    private lazy var toolbar: NSView = {
        let hint = NSTextField(labelWithString: "Drag to choose the part that stays on top")
        hint.textColor = .white
        hint.font = .systemFont(ofSize: 13, weight: .medium)

        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancel.keyEquivalent = "\u{1b}"
        let whole = NSButton(title: "Whole Window", target: self, action: #selector(useWholeWindow))
        let done = NSButton(title: "Done", target: self, action: #selector(done))
        done.keyEquivalent = "\r"
        done.bezelColor = .controlAccentColor

        let stack = NSStackView(views: [hint, cancel, whole, done])
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 14, bottom: 8, right: 8)
        stack.wantsLayer = true
        stack.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.75).cgColor
        stack.layer?.cornerRadius = 12
        stack.appearance = NSAppearance(named: .darkAqua) // light text on the dark bar
        return stack
    }()

    override func layout() {
        super.layout()
        let size = toolbar.fittingSize
        toolbar.frame = CGRect(x: (bounds.width - size.width) / 2, y: bounds.height - size.height - 16,
                               width: size.width, height: size.height)
    }

    @objc private func cancel() { onFinish?(.cancelled) }
    @objc private func useWholeWindow() { onFinish?(.wholeWindow) }

    @objc private func done() {
        if let selection, selection.width >= Self.minimumSize.width, selection.height >= Self.minimumSize.height {
            onFinish?(.crop(selection))
        } else {
            onFinish?(.wholeWindow)
        }
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: cancel()         // Esc
        case 36, 76: done()       // Return, Enter
        default: super.keyDown(with: event)
        }
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        // Dim everything except the selection.
        let dim = NSBezierPath(rect: bounds)
        if let selection {
            dim.append(NSBezierPath(roundedRect: selection, xRadius: 8, yRadius: 8))
            dim.windingRule = .evenOdd
        }
        NSColor.black.withAlphaComponent(0.45).setFill()
        dim.fill()

        guard let selection else { return }
        let outline = NSBezierPath(roundedRect: selection.insetBy(dx: -1, dy: -1), xRadius: 9, yRadius: 9)
        outline.lineWidth = 2
        NSColor.controlAccentColor.setStroke()
        outline.stroke()

        let size = "\(Int(selection.width)) × \(Int(selection.height))" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let textSize = size.size(withAttributes: attributes)
        let badge = CGRect(x: selection.minX, y: max(selection.minY - textSize.height - 10, 4),
                           width: textSize.width + 12, height: textSize.height + 6)
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: badge, xRadius: 5, yRadius: 5).fill()
        size.draw(at: CGPoint(x: badge.minX + 6, y: badge.minY + 3), withAttributes: attributes)
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        dragStart = point
        // Dragging inside the current selection moves it; anywhere else starts a new one.
        dragOrigin = selection?.contains(point) == true ? selection : nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else { return }
        let point = convert(event.locationInWindow, from: nil)
        if let origin = dragOrigin {
            var moved = origin.offsetBy(dx: point.x - start.x, dy: point.y - start.y)
            moved.origin.x = min(max(moved.minX, 0), bounds.width - moved.width)
            moved.origin.y = min(max(moved.minY, 0), bounds.height - moved.height)
            selection = moved
        } else {
            let clamped = CGPoint(x: min(max(point.x, 0), bounds.width), y: min(max(point.y, 0), bounds.height))
            selection = CGRect(x: min(start.x, clamped.x), y: min(start.y, clamped.y),
                               width: abs(clamped.x - start.x), height: abs(clamped.y - start.y))
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        dragStart = nil
        dragOrigin = nil
        if let selection, selection.width < 4 || selection.height < 4 { self.selection = nil }
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
        if let selection { addCursorRect(selection, cursor: .openHand) }
    }
}
