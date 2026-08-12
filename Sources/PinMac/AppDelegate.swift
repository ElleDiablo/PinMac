import AppKit
import Carbon.HIToolbox
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let pins = PinManager()
    private var hotKey: HotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        updateIcon()

        // ⌃⌘T — the Mac counterpart of PowerToys' Win+Ctrl+T.
        hotKey = HotKey(keyCode: kVK_ANSI_T, modifiers: controlKey | cmdKey) { [weak self] in
            self?.pins.toggleFrontmost()
        }

        pins.onChange = { [weak self] in self?.updateIcon() }
        pins.onError = { [weak self] error in self?.showError(error) }

        Permissions.requestIfNeeded()
    }

    private func updateIcon() {
        let symbol = pins.pins.isEmpty ? "pin" : "pin.fill"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "PinMac")
        image?.isTemplate = true
        statusItem.button?.image = image
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let toggle = item("Pin / Unpin Frontmost Window", #selector(toggleFrontmost))
        toggle.keyEquivalent = "t"
        toggle.keyEquivalentModifierMask = [.control, .command]
        menu.addItem(toggle)

        let pinned = pins.pinnedWindows
        if !pinned.isEmpty {
            menu.addItem(.separator())
            menu.addItem(.sectionHeader(title: "Pinned — click to unpin"))
            for window in pinned {
                let unpin = item(window.displayName, #selector(unpinWindow(_:)))
                unpin.representedObject = window.id
                unpin.image = NSImage(systemSymbolName: "pin.slash", accessibilityDescription: nil)
                menu.addItem(unpin)
            }
            menu.addItem(item("Unpin All", #selector(unpinAll)))
        }

        if !Permissions.screenRecording || !Permissions.accessibility {
            menu.addItem(.separator())
            if !Permissions.screenRecording {
                menu.addItem(item("⚠︎ Allow Screen Recording…", #selector(openScreenRecording)))
            }
            if !Permissions.accessibility {
                menu.addItem(item("⚠︎ Allow Accessibility…", #selector(openAccessibility)))
            }
        }

        menu.addItem(.separator())
        let border = item("Show Border Around Pinned Windows", #selector(toggleBorder))
        border.state = pins.showsBorder ? .on : .off
        menu.addItem(border)
        let login = item("Launch at Login", #selector(toggleLaunchAtLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        menu.addItem(item("About PinMac", #selector(showAbout)))
        menu.addItem(item("Quit PinMac", #selector(quit)))
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func toggleFrontmost() { pins.toggleFrontmost() }
    @objc private func unpinAll() { pins.unpinAll() }
    @objc private func toggleBorder() { pins.showsBorder.toggle() }
    @objc private func openScreenRecording() { Permissions.openScreenRecordingSettings() }
    @objc private func openAccessibility() { Permissions.openAccessibilitySettings() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func unpinWindow(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? CGWindowID { pins.unpin(id) }
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            showError(error)
        }
    }

    @objc private func showAbout() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: NSAttributedString(string: "Keep any window on top.\nPress ⌃⌘T to pin or unpin the frontmost window."),
        ])
    }

    private func showError(_ error: Error) {
        NSApp.activate()
        let alert = NSAlert(error: error)
        alert.runModal()
    }
}
