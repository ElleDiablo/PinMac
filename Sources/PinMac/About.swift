import AppKit
import SwiftUI

enum AppInfo {
    static let repository = URL(string: "https://github.com/ElleDiablo/PinMac")!
    static let issues = URL(string: "https://github.com/ElleDiablo/PinMac/issues")!
    static let releases = URL(string: "https://github.com/ElleDiablo/PinMac/releases")!

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
}

struct AboutView: View {
    /// What each shortcut does, in menu order, e.g. ("Pin or unpin", ⌃⌘T).
    let shortcuts: [(action: String, shortcut: Shortcut)]

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .shadow(color: .black.opacity(0.15), radius: 6, y: 3)

            Text("PinMac")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .padding(.top, 10)
            Text("Version \(AppInfo.version)")
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(.top, 2)

            Text("Keep any window on top — inspired by\nthe Always On Top tool in Microsoft PowerToys.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.top, 14)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                ForEach(shortcuts, id: \.action) { item in
                    GridRow {
                        Text(item.shortcut.displayString)
                            .font(.system(.body, design: .rounded).weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.08)))
                            .gridColumnAlignment(.trailing)
                        Text(item.action)
                    }
                }
            }
            .padding(.top, 16)

            HStack(spacing: 10) {
                LinkButton(title: "GitHub", icon: "chevron.left.forwardslash.chevron.right", url: AppInfo.repository)
                LinkButton(title: "Report Bug", icon: "ladybug", url: AppInfo.issues)
                LinkButton(title: "Releases", icon: "arrow.down.circle", url: AppInfo.releases)
            }
            .padding(.top, 20)

            Divider().padding(.vertical, 18)

            Text("Free and open source under the MIT License.\nMade by ElleDiablo.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .padding(.bottom, 22)
        .frame(width: 400)
    }
}

private struct LinkButton: View {
    let title: String
    let icon: String
    let url: URL

    var body: some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            Label(title, systemImage: icon)
                .frame(maxWidth: .infinity)
        }
        .controlSize(.large)
        .help(url.absoluteString)
    }
}

@MainActor
final class AboutWindowController {
    private var window: NSWindow?

    func show(shortcuts: [(action: String, shortcut: Shortcut)]) {
        // Rebuilt each time so the shortcuts shown are always current.
        window?.close()
        let window = NSWindow.fixedSize(title: "About PinMac", rootView: AboutView(shortcuts: shortcuts))
        self.window = window
        NSApp.activate()
        window.center()
        window.makeKeyAndOrderFront(nil)
    }
}
