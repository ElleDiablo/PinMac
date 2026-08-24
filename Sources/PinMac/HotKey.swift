import Carbon.HIToolbox

/// A system-wide keyboard shortcut. Carbon's RegisterEventHotKey is still the
/// simplest way to do this on macOS and, unlike event taps, needs no permission.
final class HotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: @MainActor () -> Void

    /// Returns nil if the shortcut can't be registered (e.g. another app owns it).
    init?(_ shortcut: Shortcut, action: @escaping @MainActor () -> Void) {
        self.action = action

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let userData = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let hotKey = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
            MainActor.assumeIsolated { hotKey.action() }
            return noErr
        }, 1, &eventType, userData, &handlerRef)

        let id = EventHotKeyID(signature: OSType(0x504E_4D43), id: 1) // "PNMC"
        let status = RegisterEventHotKey(UInt32(shortcut.keyCode), UInt32(shortcut.modifiers), id,
                                         GetApplicationEventTarget(), 0, &hotKeyRef)
        if status != noErr { return nil }
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
