import AppKit
import SwiftUI

/// State behind the welcome window. Polls the permissions so each row turns
/// green as soon as the user allows it in System Settings.
@MainActor
final class WelcomeModel: ObservableObject {
    @Published private(set) var screenRecording = Permissions.screenRecording
    @Published private(set) var accessibility = Permissions.accessibility
    @Published var shortcut = Shortcut.default

    var onDone: (() -> Void)?
    private var timer: Timer?

    var isComplete: Bool { screenRecording && accessibility }

    func startWatching() {
        refresh()
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stopWatching() {
        timer?.invalidate()
        timer = nil
    }

    func allowScreenRecording() {
        // The first request shows macOS's own prompt; after that, only Settings can change it.
        if Self.firstRequest("screenRecording") {
            CGRequestScreenCaptureAccess()
        } else {
            Permissions.openScreenRecordingSettings()
        }
    }

    func allowAccessibility() {
        if Self.firstRequest("accessibility") {
            Permissions.requestAccessibility()
        } else {
            Permissions.openAccessibilitySettings()
        }
    }

    /// macOS only applies Screen Recording after the app restarts.
    func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    private func refresh() {
        if screenRecording != Permissions.screenRecording { screenRecording.toggle() }
        if accessibility != Permissions.accessibility { accessibility.toggle() }
    }

    private static func firstRequest(_ name: String) -> Bool {
        let key = "requested.\(name)"
        defer { UserDefaults.standard.set(true, forKey: key) }
        return !UserDefaults.standard.bool(forKey: key)
    }
}

struct WelcomeView: View {
    @ObservedObject var model: WelcomeModel

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 72, height: 72)
                Text("Welcome to PinMac").font(.title2.weight(.semibold))
                Text("Keep any window on top of the others.")
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Image(systemName: "keyboard").font(.title3).foregroundStyle(.secondary)
                Text("Click any window, then press **\(model.shortcut.displayString)** to pin it. Press it again to unpin.")
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))

            VStack(alignment: .leading, spacing: 14) {
                Text("PinMac needs two permissions").font(.headline)
                PermissionRow(
                    icon: "rectangle.dashed.badge.record",
                    title: "Screen Recording",
                    detail: "Shows a live copy of a pinned window while other windows cover it. Nothing is saved or sent anywhere.",
                    isAllowed: model.screenRecording,
                    allow: model.allowScreenRecording)
                if !model.screenRecording {
                    HStack(spacing: 4) {
                        Text("Already allowed it?").foregroundStyle(.secondary)
                        Button("Reopen PinMac", action: model.relaunch).buttonStyle(.link)
                    }
                    .font(.caption)
                    .padding(.leading, 38)
                }
                PermissionRow(
                    icon: "accessibility",
                    title: "Accessibility",
                    detail: "Brings the real window to the front when you click a pinned window.",
                    isAllowed: model.accessibility,
                    allow: model.allowAccessibility)
            }

            HStack {
                Text("You can find PinMac in the menu bar under the 📌 icon.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(model.isComplete ? "Get Started" : "Later") { model.onDone?() }
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
            }
        }
        .padding(24)
        .frame(width: 440)
    }
}

private struct PermissionRow: View {
    let icon: String
    let title: String
    let detail: String
    let isAllowed: Bool
    let allow: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium))
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if isAllowed {
                Label("Allowed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.callout.weight(.medium))
            } else {
                Button("Allow…", action: allow)
            }
        }
    }
}

/// Hosts the welcome view in a regular window.
@MainActor
final class WelcomeWindowController: NSObject, NSWindowDelegate {
    let model = WelcomeModel()
    private var window: NSWindow?

    func show(shortcut: Shortcut) {
        model.shortcut = shortcut
        model.onDone = { [weak self] in self?.window?.close() }
        model.startWatching()

        if window == nil {
            // A fixed size: letting SwiftUI and the window resize each other can
            // loop until AppKit throws ("more Update Constraints passes than views").
            let hosting = NSHostingView(rootView: WelcomeView(model: model))
            let size = hosting.fittingSize // measure before turning off size reporting
            hosting.sizingOptions = []
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.contentView = hosting
            window.title = "Welcome to PinMac"
            window.isReleasedWhenClosed = false
            window.delegate = self
            self.window = window
        }
        NSApp.activate()
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        model.stopWatching()
        UserDefaults.standard.set(true, forKey: "hasSeenWelcome")
    }

    static var shouldShowAtLaunch: Bool {
        !UserDefaults.standard.bool(forKey: "hasSeenWelcome") || !Permissions.screenRecording || !Permissions.accessibility
    }
}
