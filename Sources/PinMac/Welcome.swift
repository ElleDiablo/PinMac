import AppKit
import SwiftUI

/// State behind the welcome window. Polls the permissions so each row turns
/// green as soon as the user allows it in System Settings.
@MainActor
final class WelcomeModel: ObservableObject {
    @Published private(set) var screenRecording = Permissions.screenRecording
    @Published private(set) var accessibility = Permissions.accessibility
    @Published var shortcut = Shortcut.default
    @Published var cropShortcut = Shortcut.defaultResetCrop
    @Published var opacityShortcut = Shortcut.defaultOpacity

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

            VStack(alignment: .leading, spacing: 12) {
                TipRow(icon: "pin", keys: model.shortcut.displayString,
                       text: "Click any window, then press this to pin it on top. Press it again to unpin.")
                TipRow(icon: "crop", keys: model.cropShortcut.displayString,
                       text: "In a pinned window, press this to float just part of it, like a video. Press it again for the whole window.")
                TipRow(icon: "circle.lefthalf.filled", keys: model.opacityShortcut.displayString,
                       text: "Hover over a pinned window and press this to make it see-through while it floats.")
                TipRow(icon: "slider.horizontal.3", keys: nil,
                       text: "In the 📌 menu, each pinned window has more options, like click-through. Pick a border color under Border.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
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

private struct TipRow: View {
    let icon: String
    let keys: String?
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 4) {
                if let keys {
                    Text(keys)
                        .font(.system(.callout, design: .rounded).weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.08)))
                }
                Text(text)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
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

    func show(shortcut: Shortcut, cropShortcut: Shortcut, opacityShortcut: Shortcut) {
        model.shortcut = shortcut
        model.cropShortcut = cropShortcut
        model.opacityShortcut = opacityShortcut
        model.onDone = { [weak self] in self?.window?.close() }
        model.startWatching()

        if window == nil {
            let window = NSWindow.fixedSize(title: "Welcome to PinMac", rootView: WelcomeView(model: model))
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
