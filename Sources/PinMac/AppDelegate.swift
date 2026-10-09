import AppKit
import Carbon.HIToolbox
import ServiceManagement
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private let pins = PinManager()
    private var hotKeys: [ObjectIdentifier: HotKey] = [:]
    private let colorModel = BorderColorModel()
    private let pinShortcut = ShortcutModel(
        title: "Pin or Unpin", detail: "Pins or unpins the frontmost window.",
        storageKey: "shortcut", default: .default)
    private let resetCropShortcut = ShortcutModel(
        title: "Reset Crop", detail: "Shows cropped pinned windows whole again.",
        storageKey: "resetCropShortcut", default: .defaultResetCrop)
    private let welcome = WelcomeWindowController()
    private let about = AboutWindowController()
    private let cropSelector = CropSelector()
    private lazy var colorPopover = makePopover(BorderColorView(model: colorModel))
    private lazy var shortcutPopover = makePopover(ShortcutsView(models: [pinShortcut, resetCropShortcut]))

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        updateIcon()

        // Pinning defaults to ⌃⌘T, the Mac counterpart of PowerToys' Win+Ctrl+T.
        setUpShortcut(pinShortcut) { [weak self] in self?.pins.toggleFrontmost() }
        setUpShortcut(resetCropShortcut) { [weak self] in self?.resetCrop() }

        pins.onChange = { [weak self] in self?.updateIcon() }
        pins.onError = { [weak self] error in self?.showError(error) }
        colorModel.onChange = { [weak self] color in
            guard let self else { return }
            pins.borderColor = color
            if !pins.showsBorder { pins.showsBorder = true }
        }

        if WelcomeWindowController.shouldShowAtLaunch { showWelcome() }
    }

    private func setUpShortcut(_ model: ShortcutModel, action: @escaping @MainActor () -> Void) {
        let key = ObjectIdentifier(model)
        model.register = { [weak self] shortcut in
            guard let self else { return false }
            hotKeys[key] = nil // release the old shortcut first
            hotKeys[key] = HotKey(shortcut, action: action)
            return hotKeys[key] != nil
        }
        model.pause = { [weak self] in self?.hotKeys[key] = nil }
        model.onStartRecording = { [weak self] in
            // Only one row records at a time.
            for other in [self?.pinShortcut, self?.resetCropShortcut] where other !== model {
                other?.stopRecording()
            }
        }
        if model.register?(model.shortcut) != true {
            showError(ShortcutError.unavailable(model.shortcut))
        }
    }

    private func resetCrop() {
        // While choosing a crop, the shortcut picks "whole window" there too.
        if cropSelector.isShowing {
            cropSelector.finish(.wholeWindow)
        } else if !pins.resetCrops() {
            NSSound.beep()
        }
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

        menu.addItem(item("Pin / Unpin Frontmost Window", #selector(toggleFrontmost), shortcut: pinShortcut.shortcut))
        menu.addItem(item("Shortcuts…", #selector(showShortcutPopover)))

        let pinned = pins.pinnedWindows
        if !pinned.isEmpty {
            menu.addItem(.separator())
            menu.addItem(.sectionHeader(title: "Pinned"))
            for pin in pinned {
                let window = NSMenuItem(title: pin.info.displayName, action: nil, keyEquivalent: "")
                window.image = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: nil)
                window.submenu = pinMenu(for: pin)
                menu.addItem(window)
            }
            menu.addItem(item("Unpin All", #selector(unpinAll)))
        }

        if !Permissions.screenRecording || !Permissions.accessibility {
            menu.addItem(.separator())
            menu.addItem(item("⚠︎ Finish Setup…", #selector(showWelcome)))
        }

        menu.addItem(.separator())
        let border = NSMenuItem(title: "Border", action: nil, keyEquivalent: "")
        border.submenu = borderMenu()
        menu.addItem(border)
        let sounds = item("Play Sounds", #selector(toggleSounds))
        sounds.state = pins.playsSounds ? .on : .off
        menu.addItem(sounds)
        let login = item("Launch at Login", #selector(toggleLaunchAtLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        menu.addItem(item("Welcome Guide…", #selector(showWelcome)))
        menu.addItem(item("About PinMac", #selector(showAbout)))
        menu.addItem(item("Quit PinMac", #selector(quit)))
    }

    /// Per-window options for one pinned window.
    private func pinMenu(for pin: PinnedWindow) -> NSMenu {
        let menu = NSMenu()
        let id = pin.info.id

        menu.addItem(.sectionHeader(title: "Opacity While Floating"))
        for percent in [100, 80, 60, 40, 20] {
            let opacity = item("\(percent)%", #selector(setOpacity(_:)))
            opacity.representedObject = id
            opacity.tag = percent
            opacity.state = Int((pin.opacity * 100).rounded()) == percent ? .on : .off
            menu.addItem(opacity)
        }

        menu.addItem(.separator())
        let clickThrough = item("Click Through", #selector(toggleClickThrough(_:)))
        clickThrough.representedObject = id
        clickThrough.state = pin.isClickThrough ? .on : .off
        clickThrough.toolTip = "Clicks go to the windows underneath. Use Bring to Front to work in this window."
        menu.addItem(clickThrough)

        let crop = item(pin.crop == nil ? "Crop to Part of Window…" : "Change Crop…", #selector(cropWindow(_:)))
        crop.representedObject = id
        crop.toolTip = "Only the part you choose floats on top, e.g. just the video in a browser."
        menu.addItem(crop)
        if pin.crop != nil {
            let whole = item("Reset to Whole Window", #selector(uncropWindow(_:)), shortcut: resetCropShortcut.shortcut)
            whole.representedObject = id
            menu.addItem(whole)
        }

        menu.addItem(.separator())
        let raise = item("Bring to Front", #selector(raiseWindow(_:)))
        raise.representedObject = id
        menu.addItem(raise)
        let unpin = item("Unpin", #selector(unpinWindow(_:)))
        unpin.representedObject = id
        unpin.image = NSImage(systemSymbolName: "pin.slash", accessibilityDescription: nil)
        menu.addItem(unpin)
        return menu
    }

    private static let presetColors: [(String, NSColor)] = [
        ("Blue", .systemBlue), ("Purple", .systemPurple), ("Pink", .systemPink), ("Red", .systemRed),
        ("Orange", .systemOrange), ("Yellow", .systemYellow), ("Green", .systemGreen), ("Gray", .systemGray),
    ]

    private func borderMenu() -> NSMenu {
        let menu = NSMenu()
        let show = item("Show Border", #selector(toggleBorder))
        show.state = pins.showsBorder ? .on : .off
        menu.addItem(show)
        menu.addItem(.separator())

        let accent = item("Accent Color", #selector(chooseBorderColor(_:)))
        accent.image = swatch(.controlAccentColor)
        accent.state = pins.borderColor == nil ? .on : .off
        menu.addItem(accent)

        let current = pins.borderColor?.usingColorSpace(.sRGB)
        var matchedPreset = false
        for (name, color) in Self.presetColors {
            let preset = item(name, #selector(chooseBorderColor(_:)))
            preset.representedObject = color
            preset.image = swatch(color)
            if let current, current == color.usingColorSpace(.sRGB) {
                preset.state = .on
                matchedPreset = true
            }
            menu.addItem(preset)
        }

        menu.addItem(.separator())
        let custom = item("Custom Color…", #selector(showColorPopover))
        if let current, !matchedPreset {
            custom.state = .on
            custom.image = swatch(current)
        }
        menu.addItem(custom)
        return menu
    }

    private func swatch(_ color: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5)).fill()
            return true
        }
    }

    /// A menu item that shows a global shortcut next to it.
    private func item(_ title: String, _ action: Selector, shortcut: Shortcut) -> NSMenuItem {
        let item = item(shortcut.menuKeyEquivalent.isEmpty ? "\(title)  \(shortcut.displayString)" : title, action)
        item.keyEquivalent = shortcut.menuKeyEquivalent
        item.keyEquivalentModifierMask = shortcut.menuModifiers
        return item
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func toggleFrontmost() { pins.toggleFrontmost() }
    @objc private func unpinAll() { pins.unpinAll() }
    @objc private func toggleBorder() { pins.showsBorder.toggle() }
    @objc private func toggleSounds() { pins.playsSounds.toggle() }
    @objc private func showWelcome() { welcome.show(shortcut: pinShortcut.shortcut) }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func chooseBorderColor(_ sender: NSMenuItem) {
        pins.borderColor = sender.representedObject as? NSColor
        if !pins.showsBorder { pins.showsBorder = true }
    }

    @objc private func showColorPopover() {
        colorModel.load(pins.borderColor ?? .controlAccentColor)
        show(colorPopover)
    }

    @objc private func showShortcutPopover() {
        show(shortcutPopover)
    }

    // MARK: Popovers

    /// Popovers drop down from the menu-bar icon, so they're always easy to find.
    private func makePopover(_ view: some View) -> NSPopover {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.delegate = self
        let hosting = NSHostingController(rootView: view)
        hosting.sizingOptions = .preferredContentSize
        popover.contentViewController = hosting
        return popover
    }

    private func show(_ popover: NSPopover) {
        guard let button = statusItem.button else { return }
        // Activate so the popover can take typing, and wait for the menu to finish closing.
        NSApp.activate()
        DispatchQueue.main.async {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    func popoverDidClose(_ notification: Notification) {
        pinShortcut.stopRecording()
        resetCropShortcut.stopRecording()
    }

    @objc private func setOpacity(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? CGWindowID else { return }
        pins.pins[id]?.opacity = CGFloat(sender.tag) / 100
    }

    @objc private func toggleClickThrough(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? CGWindowID else { return }
        pins.pins[id]?.isClickThrough.toggle()
    }

    @objc private func cropWindow(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? CGWindowID else { return }
        // Bring the real window forward so you can see what you're selecting.
        pins.raise(id)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [self] in
            guard let pin = pins.pins[id] else { return }
            cropSelector.show(over: pin.windowFrame, current: pin.crop,
                              resetShortcut: resetCropShortcut.shortcut) { [weak self] result in
                guard let pin = self?.pins.pins[id] else { return }
                switch result {
                case .crop(let rect): pin.setCrop(rect)
                case .wholeWindow: pin.setCrop(nil)
                case .cancelled: break
                }
                self?.pins.raise(id)
            }
        }
    }

    @objc private func uncropWindow(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? CGWindowID else { return }
        pins.resetCrop(id)
    }

    @objc private func raiseWindow(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? CGWindowID { pins.raise(id) }
    }

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

    @objc private func showAbout() { about.show(shortcut: pinShortcut.shortcut) }

    private func showError(_ error: Error) {
        NSApp.activate()
        let alert = NSAlert(error: error)
        alert.runModal()
    }
}

enum ShortcutError: LocalizedError {
    case unavailable(Shortcut)

    var errorDescription: String? {
        switch self {
        case .unavailable(let shortcut):
            "\(shortcut.displayString) is already used by another app. Choose a different shortcut from the PinMac menu."
        }
    }
}
