import AppKit

@MainActor
final class PinManager {
    private(set) var pins: [CGWindowID: PinnedWindow] = [:]
    private var timer: Timer?

    /// Called whenever a window is pinned or unpinned.
    var onChange: (() -> Void)?
    var onError: ((Error) -> Void)?

    var showsBorder = UserDefaults.standard.object(forKey: "showsBorder") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(showsBorder, forKey: "showsBorder")
            pins.values.forEach { $0.showsBorder = showsBorder }
            tick()
        }
    }

    var playsSounds = UserDefaults.standard.object(forKey: "playsSounds") as? Bool ?? true {
        didSet { UserDefaults.standard.set(playsSounds, forKey: "playsSounds") }
    }

    /// nil means "follow the system accent color".
    var borderColor: NSColor? = PinManager.loadBorderColor() {
        didSet {
            PinManager.saveBorderColor(borderColor)
            pins.values.forEach { $0.borderColor = borderColor ?? .controlAccentColor }
        }
    }

    var pinnedWindows: [PinnedWindow] {
        pins.values.sorted { $0.info.displayName < $1.info.displayName }
    }

    func resetCrop(_ id: CGWindowID) {
        guard let pin = pins[id], pin.crop != nil else { return }
        pin.setCrop(nil)
        play("Pop")
    }

    /// Shows every cropped window whole again. Returns false if none were cropped.
    @discardableResult
    func resetAllCrops() -> Bool {
        let cropped = pins.values.filter { $0.crop != nil }
        guard !cropped.isEmpty else { return false }
        cropped.forEach { $0.setCrop(nil) }
        play("Pop")
        return true
    }

    /// The pinned window you're working in, if any.
    var frontmostPin: PinnedWindow? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let window = WindowList.onScreen().first(where: { $0.pid == pid })
        else { return nil }
        return pins[window.id]
    }

    func raise(_ id: CGWindowID) {
        guard let info = pins[id]?.info else { return }
        WindowRaiser.raise(windowID: info.id, pid: info.pid)
    }

    /// Pins the frontmost window of the active app, or unpins it if it's already pinned.
    func toggleFrontmost() {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let window = WindowList.onScreen().first(where: { $0.pid == app.processIdentifier })
        else {
            NSSound.beep()
            return
        }
        if pins[window.id] != nil {
            unpin(window.id)
        } else {
            pin(window)
        }
    }

    func pin(_ window: WindowInfo) {
        let pin = PinnedWindow(info: window)
        pin.showsBorder = showsBorder
        pin.borderColor = borderColor ?? .controlAccentColor
        pin.onClick = { WindowRaiser.raise(windowID: window.id, pid: window.pid) }
        pins[window.id] = pin
        startTimer()
        onChange?()
        play("Pop")

        Task {
            do {
                try await pin.start()
            } catch {
                remove(window.id)
                onError?(error)
            }
        }
    }

    func unpin(_ id: CGWindowID) {
        guard pins[id] != nil else { return }
        remove(id)
        play("Tink")
    }

    func unpinAll() {
        guard !pins.isEmpty else { return }
        pins.keys.forEach(remove)
        play("Tink")
    }

    /// Unpins without feedback, e.g. when the window closed on its own.
    private func remove(_ id: CGWindowID) {
        pins.removeValue(forKey: id)?.close()
        if pins.isEmpty { stopTimer() }
        onChange?()
    }

    /// Audible confirmation, like PowerToys' pin sound.
    private func play(_ sound: String) {
        guard playsSounds else { return }
        NSSound(named: sound)?.play()
    }

    // MARK: Tracking

    private func startTimer() {
        guard timer == nil else { tick(); return }
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        // .common keeps tracking alive while the status menu is open.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        tick()
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    /// Follows each pinned window and arranges PinMac's panels in the stacking
    /// order so pinned windows keep their order among themselves, above all others.
    private func tick() {
        let allWindows = WindowList.onScreen() // current Space, front to back, including PinMac's panels
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let windows = allWindows.filter { $0.pid != ownPID }

        // Pinned windows that aren't on this Space (e.g. the user switched to a
        // full-screen app) are shown as a mirror here, unless minimized or hidden.
        var elsewhere: [PinnedWindow] = []
        for (id, pin) in pins.sorted(by: { $0.key < $1.key }) where !windows.contains(where: { $0.id == id }) {
            guard let info = WindowList.info(for: id) else {
                remove(id) // closed, or its app quit
                continue
            }
            let isVisible = !pin.isMinimizedOrHidden
            pin.setCaptureNeeded(isVisible)
            if isVisible && pin.hasFrame {
                pin.setFrame(info.frame)
                pin.setMode(.mirror)
                elsewhere.append(pin)
            } else {
                pin.setMode(.hidden)
            }
        }

        // Pinned windows at the very top of the stack are already where they belong:
        // they only need their outline. Every pinned window below an unpinned one
        // gets a mirror, stacked just above the frontmost unpinned window.
        let topCount = windows.prefix { pins[$0.id] != nil }.count
        let anchor = windows.dropFirst(topCount).first

        // The desired order, front to back, of the top of the stack.
        var desired: [CGWindowID] = []
        var panels: [CGWindowID: PinnedWindow] = [:]
        func add(_ pin: PinnedWindow) {
            desired.append(pin.panelID)
            panels[pin.panelID] = pin
        }

        for window in windows.prefix(topCount) {
            guard let pin = pins[window.id] else { continue }
            pin.setFrame(window.frame)
            pin.setCaptureNeeded(false)
            pin.setMode(showsBorder ? .border : .hidden)
            if pin.mode != .hidden { add(pin) }
            desired.append(window.id)
        }
        elsewhere.forEach(add)
        for window in windows.dropFirst(topCount) {
            guard let pin = pins[window.id] else { continue }
            pin.setFrame(window.frame)
            pin.setCaptureNeeded(true)
            pin.setMode(pin.hasFrame ? .mirror : .hidden)
            if pin.mode != .hidden { add(pin) }
        }
        if let anchor { desired.append(anchor.id) }

        // Only reorder when something is out of place, working from the bottom up.
        let actual = allWindows.prefix(desired.count).map(\.id)
        guard actual != desired else { return }
        for index in desired.indices.reversed() {
            guard let pin = panels[desired[index]] else { continue }
            if index + 1 < desired.count {
                pin.order(above: desired[index + 1])
            } else if let window = desired[..<index].last(where: { panels[$0] == nil }) {
                pin.order(below: window)
            } else {
                pin.orderFront() // nothing else on this Space
            }
        }
    }

    // MARK: Border color

    private static func loadBorderColor() -> NSColor? {
        guard let rgb = UserDefaults.standard.array(forKey: "borderColor") as? [Double], rgb.count == 3 else { return nil }
        return NSColor(srgbRed: rgb[0], green: rgb[1], blue: rgb[2], alpha: 1)
    }

    private static func saveBorderColor(_ color: NSColor?) {
        guard let color = color?.usingColorSpace(.sRGB) else {
            UserDefaults.standard.removeObject(forKey: "borderColor")
            return
        }
        UserDefaults.standard.set([color.redComponent, color.greenComponent, color.blueComponent].map(Double.init), forKey: "borderColor")
    }
}
