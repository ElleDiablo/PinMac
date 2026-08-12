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

    var pinnedWindows: [WindowInfo] {
        pins.values.map(\.info).sorted { $0.displayName < $1.displayName }
    }

    /// Pins the frontmost window of the active app, or unpins it if it's already pinned.
    func toggleFrontmost() {
        guard let app = NSWorkspace.shared.frontmostApplication,
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
        let pin = PinnedWindow(info: window, showsBorder: showsBorder)
        pin.onClick = { WindowRaiser.raise(windowID: window.id, pid: window.pid) }
        pins[window.id] = pin
        startTimer()
        onChange?()

        Task {
            do {
                try await pin.start()
            } catch {
                unpin(window.id)
                onError?(error)
            }
        }
    }

    func unpin(_ id: CGWindowID) {
        pins.removeValue(forKey: id)?.close()
        if pins.isEmpty { stopTimer() }
        onChange?()
    }

    func unpinAll() {
        pins.keys.forEach(unpin)
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

    /// Follows each pinned window and decides whether its mirror needs to show.
    private func tick() {
        let windows = WindowList.onScreen()
        let frontmostID = windows.first?.id

        for (id, pin) in pins {
            if let window = windows.first(where: { $0.id == id }) {
                pin.update(frame: window.frame, isFrontmost: id == frontmostID)
            } else if WindowList.exists(id) {
                pin.hide()
            } else {
                unpin(id) // closed, or its app quit
            }
        }
    }
}
