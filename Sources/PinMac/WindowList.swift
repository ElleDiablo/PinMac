import AppKit

/// A snapshot of one on-screen window, as reported by the window server.
struct WindowInfo {
    let id: CGWindowID
    let pid: pid_t
    /// Global CoreGraphics coordinates: origin at the top-left of the main display.
    let frame: CGRect
    let title: String
    let appName: String

    var displayName: String { title.isEmpty ? appName : "\(appName) — \(title)" }
}

enum WindowList {
    /// Normal app windows on the current Space, ordered front to back.
    /// PinMac's own windows are excluded.
    static func onScreen() -> [WindowInfo] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return list.compactMap(WindowInfo.init).filter { $0.pid != ownPID }
    }

    /// Looks up a window even when it's not on screen (minimized or on another
    /// Space). Returns nil once the window has closed.
    static func info(for id: CGWindowID) -> WindowInfo? {
        let list = CGWindowListCopyWindowInfo(.optionIncludingWindow, id) as? [[String: Any]]
        return list?.first.flatMap(WindowInfo.init)
    }
}

private extension WindowInfo {
    init?(_ dict: [String: Any]) {
        guard
            let id = dict[kCGWindowNumber as String] as? CGWindowID,
            let pid = dict[kCGWindowOwnerPID as String] as? pid_t,
            let layer = dict[kCGWindowLayer as String] as? Int, layer == 0,
            let boundsDict = dict[kCGWindowBounds as String] as? NSDictionary,
            let frame = CGRect(dictionaryRepresentation: boundsDict),
            frame.width >= 40, frame.height >= 40
        else { return nil }
        // Some apps keep invisible helper windows around; skip them.
        if let alpha = dict[kCGWindowAlpha as String] as? Double, alpha <= 0 { return nil }

        self.id = id
        self.pid = pid
        self.frame = frame
        self.title = dict[kCGWindowName as String] as? String ?? ""
        self.appName = dict[kCGWindowOwnerName as String] as? String ?? "Window"
    }
}

extension CGRect {
    /// Converts CoreGraphics global coordinates (top-left origin) to
    /// AppKit screen coordinates (bottom-left origin of the main display).
    var flippedToAppKit: NSRect {
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        return NSRect(x: minX, y: mainHeight - maxY, width: width, height: height)
    }
}
