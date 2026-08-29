import AppKit
import SwiftUI

extension NSWindow {
    /// A fixed-size window showing a SwiftUI view. The size is measured once:
    /// letting SwiftUI and the window resize each other can loop until AppKit
    /// throws ("more Update Constraints passes than views").
    static func fixedSize(title: String, rootView: some View) -> NSWindow {
        let hosting = NSHostingView(rootView: rootView)
        let size = hosting.fittingSize // measure before turning off size reporting
        hosting.sizingOptions = []
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.contentView = hosting
        window.title = title
        window.isReleasedWhenClosed = false
        return window
    }
}
