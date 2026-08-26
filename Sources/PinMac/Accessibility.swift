import AppKit
import ApplicationServices

/// Private but long-stable API (used by Rectangle, AltTab, yabai…) that maps an
/// Accessibility window element to its window-server ID.
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

enum AXWindows {
    /// Finds the Accessibility element for a window-server window.
    static func element(windowID: CGWindowID, pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement]
        else { return nil }
        return windows.first { window in
            var id: CGWindowID = 0
            return _AXUIElementGetWindow(window, &id) == .success && id == windowID
        }
    }

    static func isMinimized(_ window: AXUIElement) -> Bool {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &value)
        return (value as? Bool) ?? false
    }
}

enum WindowRaiser {
    /// Brings a specific window of another app to the front.
    static func raise(windowID: CGWindowID, pid: pid_t) {
        let app = AXUIElementCreateApplication(pid)

        if let window = AXWindows.element(windowID: windowID, pid: pid) {
            AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        }

        // Setting "frontmost" through Accessibility works even though PinMac is
        // not the active app; NSRunningApplication.activate is the fallback.
        if AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue) != .success {
            NSRunningApplication(processIdentifier: pid)?.activate()
        }
    }
}

enum Permissions {
    static var screenRecording: Bool { CGPreflightScreenCaptureAccess() }
    static var accessibility: Bool { AXIsProcessTrusted() }

    /// Shows macOS's prompt that leads to the Accessibility settings.
    static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    static func openScreenRecordingSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    }

    static func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    private static func open(_ url: String) {
        if let url = URL(string: url) { NSWorkspace.shared.open(url) }
    }
}
