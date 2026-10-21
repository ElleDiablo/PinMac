import AppKit

/// A small, brief label shown over a window, like the volume overlay, for
/// feedback when a shortcut changes something you can't see right away.
@MainActor
enum HUD {
    /// One label per window, keyed by its window ID.
    private static var panels: [CGWindowID: NSPanel] = [:]

    static func show(_ title: String, detail: String? = nil, over frame: NSRect, for id: CGWindowID) {
        panels[id]?.close() // pressing again replaces the label

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        titleLabel.alignment = .center
        titleLabel.textColor = .white
        var views: [NSView] = [titleLabel]
        if let detail {
            let detailLabel = NSTextField(labelWithString: detail)
            detailLabel.font = .systemFont(ofSize: 12)
            detailLabel.textColor = NSColor.white.withAlphaComponent(0.7)
            detailLabel.alignment = .center
            views.append(detailLabel)
        }
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 22, bottom: 14, right: 22)

        let background = NSVisualEffectView()
        background.material = .hudWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 14
        background.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            stack.topAnchor.constraint(equalTo: background.topAnchor),
            stack.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ])

        let size = stack.fittingSize
        let panel = NSPanel(contentRect: NSRect(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2,
                                                width: size.width, height: size.height),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        panel.contentView = background
        panel.appearance = NSAppearance(named: .darkAqua) // a dark label in light and dark mode
        panel.orderFrontRegardless()
        panels[id] = panel

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            guard panels[id] === panel else { return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.25
                panel.animator().alphaValue = 0
            }, completionHandler: {
                MainActor.assumeIsolated {
                    panel.close()
                    if panels[id] === panel { panels[id] = nil }
                }
            })
        }
    }
}
